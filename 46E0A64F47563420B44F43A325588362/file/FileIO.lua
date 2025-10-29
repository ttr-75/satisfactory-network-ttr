---@diagnostic disable: lowercase-global


local names = {
    "shared/helper_log.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()


----------------------------------------------------------------
-- FileIO (FicsIt Network kompatibel)
-- - Auto-Mount von /dev/* auf self.root (Default: "/srv")
-- - exists / isFile / isDir / list / mkdir / rm
-- - readAllText / readAllBinary / writeText / appendText / writeBinary
-- - copy / move / tryRead*
----------------------------------------------------------------
-- Hinweis: Diese Datei ist rein Lua/FIN-API-basiert und ändert die
-- ursprüngliche Logik nicht – es kommen nur Anmerkungen/Kommentare dazu.
----------------------------------------------------------------

---@class FileIO
---@field root string              -- Mountpunkt (i. d. R. "/srv")
---@field readChunk integer        -- Lese-Chunkgröße in Bytes
---@field autoMount boolean        -- true = bei Bedarf /dev automatisch mounten
---@field searchFile string|nil    -- optional: Datei, die nach Mount existieren muss
---@field _mounted boolean         -- interner Status: Root bereit/gemountet
---@field _mountedDev string|nil   -- z. B. "/dev/XYZ"
---@field _mountedId string|nil    -- z. B. "XYZ"
FileIO = {}
FileIO.__index = FileIO

-- ==== interne Helfer =========================================================

--- Entfernt führende Slashes und verbietet ".." in relativen Pfaden.
---@param rel any
---@return string
local function _sanitize(rel)
    rel = tostring(rel or "")
    rel = rel:gsub("^/*", "")
    assert(not rel:find("%.%.", 1, true), "FileIO: Pfad darf kein '..' enthalten")
    return rel
end

--- Baut einen absoluten Pfad unterhalb von root.
---@param root string
---@param rel string
---@return string
local function _join(root, rel)
    rel = _sanitize(rel)
    if root == "/" then return "/" .. rel end
    if root:sub(-1) == "/" then return root .. rel end
    return root .. "/" .. rel
end


--- Liefert das Elternverzeichnis eines Pfades (echtes dirname).
---@param p any
---@return string
local function _dirname(p)
    p = tostring(p or "")
    -- trailing slashes weg
    p = p:gsub("/+$", "")
    -- alles bis vor dem letzten / behalten
    local dir = p:match("^(.*)/[^/]*$") or ""
    if dir == "" then return "/" end
    return dir
end

--- Stellt sicher, dass das Elternverzeichnis des Zieldateipfades existiert.
---@param filePath string
local function _ensure_parent_dir(filePath)
    local dir = _dirname(filePath)
    if dir and not filesystem.exists(dir) then
        filesystem.createDir(dir) -- FN: createDir
    end
end


-- isDir kann je nach FIN-Version anders heißen
local _isDirFn = filesystem.isDir or filesystem.isDirectory

-- ==== Konstruktor ============================================================

--- Erzeugt eine neue FileIO-Instanz.
---@param opts {root?:string, chunk?:integer, autoMount?:boolean, searchFile?:string}|nil
---@return FileIO
function FileIO.new(opts)
    local self       = setmetatable({}, FileIO)
    self.root        = (opts and opts.root) or "/srv"
    self.readChunk   = (opts and opts.chunk) or (64 * 1024)
    self.autoMount   = (opts and opts.autoMount ~= false)
    self.searchFile  = (opts and opts.searchFile) or nil

    self._mounted    = false
    self._mountedDev = nil -- z.B. "/dev/XYZ"
    self._mountedId  = nil -- z.B. "XYZ"
    return self
end

-- ==== Mount-Logik ============================================================

--- Prüft heuristisch, ob root bereits „benutzbar“ ist (existiert + children abrufbar).
---@return boolean
function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

--- Versucht, irgendein /dev/* auf root zu mounten (optional verifiziert via searchFile).
---@return boolean
function FileIO:_tryMount()
    -- /dev initialisieren (FN)
    pcall(function() filesystem.initFileSystem("/dev") end)

    local devs = filesystem.children("/dev") or {}
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        local ok = pcall(function() filesystem.mount(drive, self.root) end)
        if ok then
            -- Merken, welches Device wir gemountet haben
            self._mountedDev = drive
            self._mountedId  = tostring(drive):match("^/dev/(.+)$")

            if not self.searchFile then
                return true
            else
                local testPath = _join(self.root, self.searchFile)
                if filesystem.exists(testPath) then
                    return true
                else
                    pcall(function() filesystem.unmount(drive) end)
                    self._mountedDev, self._mountedId = nil, nil
                end
            end
        end
    end
    return false
end

--- Stellt sicher, dass root bereit/montiert ist (führt ggf. Auto-Mount aus).
---@return boolean mounted
function FileIO:ensureMounted()
    if self._mounted then return true end
    if self:_rootLooksReady() then
        self._mounted = true
        return true
    end
    if not self.autoMount then return false end
    local ok = self:_tryMount()
    self._mounted = ok and self:_rootLooksReady() or false
    return self._mounted
end

-- ==== public helpers =========================================================

--- Absoluten Pfad unterhalb von root bilden.
---@param rel string
---@return string
function FileIO:abs(rel) return _join(self.root, rel) end

--- Liefert das zuletzt gemountete Device (z. B. "/dev/XYZ"), falls bekannt.
---@return string|nil
function FileIO:getMountedDevice() return self._mountedDev end -- "/dev/XYZ" oder nil

--- Liefert die ID des gemounteten Devices (z. B. "XYZ"), falls bekannt.
---@return string|nil
function FileIO:getMountedId() return self._mountedId end -- "XYZ" oder nil

-- ==== Abfragen ===============================================================

--- true, wenn die relative Ressource existiert.
---@param rel string
---@return boolean
function FileIO:exists(rel)
    self:ensureMounted()
    return filesystem.exists(self:abs(rel))
end

--- true, wenn die relative Ressource eine Datei ist.
---@param rel string
---@return boolean
function FileIO:isFile(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    return filesystem.exists(p) and filesystem.isFile(p)
end

--- true, wenn die relative Ressource ein Verzeichnis ist.
---@param rel string
---@return boolean
function FileIO:isDir(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    if not filesystem.exists(p) then return false end
    if _isDirFn then
        return _isDirFn(p)
    end
    -- Fallback (falls weder isDir noch isDirectory existiert):
    -- Heuristik: ein Pfad ist "Dir", wenn children nicht fehlschlägt.
    local ok = pcall(function() return filesystem.children(p) end)
    return ok
end

--- Listet Kinder eines Verzeichnisses (oder {} wenn nicht existent).
---@param rel string|nil
---@return string[]
function FileIO:list(rel)
    self:ensureMounted()
    local p = self:abs(rel or "")
    if not filesystem.exists(p) then return {} end
    return filesystem.children(p) or {}
end

-- ==== Erstellen / Löschen ====================================================

--- Erzeugt ein Verzeichnis (rekursiv, falls FIN das so handhabt).
---@param rel string
function FileIO:mkdir(rel)
    self:ensureMounted()
    filesystem.createDir(self:abs(rel))
end

--- Entfernt Datei oder (rekursiv=true) Verzeichnis inkl. Inhalt.
---@param rel string
---@param rekursiv boolean|nil
function FileIO:rm(rel, rekursiv)
    self:ensureMounted()
    local p = self:abs(rel)
    if rekursiv and ((_isDirFn and _isDirFn(p)) or (not _isDirFn and filesystem.exists(p))) then
        for _, name in ipairs(filesystem.children(p) or {}) do
            self:rm(_sanitize(rel) .. "/" .. name, true)
        end
    end
    filesystem.remove(p)
end

-- ==== Lesen/Schreiben ========================================================

--- Liest Textdatei komplett (UTF-8/ASCII), wirft assert auf Fehler.
---@param rel string
---@return string
function FileIO:readAllText(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    local f = filesystem.open(p, "r")
    assert(f, "FileIO: kann Datei nicht öffnen (r): " .. p)
    local buf, chunk = "", nil
    repeat
        chunk = f:read(self.readChunk)
        if chunk then buf = buf .. chunk end
    until not chunk
    f:close()
    return buf
end

--- Liest Binärdatei komplett als String (Bytes).
---@param rel string
---@return string
function FileIO:readAllBinary(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    local f = filesystem.open(p, "rb")
    assert(f, "FileIO: kann Datei nicht öffnen (rb): " .. p)
    local buf, chunk = "", nil
    repeat
        chunk = f:read(self.readChunk)
        if chunk then buf = buf .. chunk end
    until not chunk
    f:close()
    return buf
end

--- Schreibt Text (überschreibt Datei, erzeugt Elternordner bei Bedarf).
---@param rel string
---@param text any
function FileIO:writeText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "w")
    assert(f, "FileIO: kann Datei nicht öffnen (w): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

--- Hängt Text an (erzeugt Elternordner bei Bedarf).
---@param rel string
---@param text any
function FileIO:appendText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "a")
    assert(f, "FileIO: kann Datei nicht öffnen (a): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

--- Schreibt Binärdaten (String-Bytes), erzeugt Elternordner bei Bedarf.
---@param rel string
---@param bytes string|nil
function FileIO:writeBinary(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "wb")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    f:write(bytes or "")
    f:close()
end

--- Schreibt eine Liste von Byte-Strings nacheinander (z. B. chunkweise).
---@param rel string
---@param bytes string[]
function FileIO:writeBinaryArray(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "wb")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    for i = 1, #bytes do
        f:write(bytes[i] or "")
    end
    f:close()
end

-- ==== Utilities ==============================================================

--- Kopiert Datei (binär).
---@param srcRel string
---@param dstRel string
function FileIO:copy(srcRel, dstRel)
    local src = self:readAllBinary(srcRel)
    self:writeBinary(dstRel, src)
end

--- Verschiebt Datei (kopieren + löschen).
---@param srcRel string
---@param dstRel string
function FileIO:move(srcRel, dstRel)
    self:copy(srcRel, dstRel)
    self:rm(srcRel)
end

--- Wie readAllText, aber Fehler → nil + Fehlermeldung.
---@param rel string
---@return string|nil, any
function FileIO:tryReadText(rel)
    local ok, res = pcall(function() return self:readAllText(rel) end)
    if ok then return res end
    return nil, res
end

--- Wie readAllBinary, aber Fehler → nil + Fehlermeldung.
---@param rel string
---@return string|nil, any
function FileIO:tryReadBinary(rel)
    local ok, res = pcall(function() return self:readAllBinary(rel) end)
    if ok then return res end
    return nil, res
end
