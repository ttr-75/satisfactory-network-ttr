---@diagnostic disable: lowercase-global


local names = {
    "shared/helper_log.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

---@diagnostic disable: lowercase-global

----------------------------------------------------------------
-- FileIO (FicsIt Network kompatibel)
-- - Auto-Mount von /dev/* auf self.root (Default: "/srv")
-- - Konsistente Rückgaben: ok, result|nil, err
-- - exists / isFile / isDir / list / mkdir / rm
-- - readAllText / readAllBinary / writeText / appendText / writeBinary(/Array)
-- - copy / move / tryRead*
----------------------------------------------------------------

--------------------------------
-- FileIO-Klasse
--------------------------------

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

--- Absoluten Pfad unterhalb von root bilden.
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
    p = p:gsub("/+$", "")                     -- trailing "/" entfernen
    local dir = p:match("^(.*)/[^/]*$") or "" -- alles vor letztem "/"
    if dir == "" then return "/" end
    return dir
end

--- Stellt sicher, dass das Elternverzeichnis des Zieldateipfades existiert.
---@param filePath string
local function _ensure_parent_dir(filePath)
    local dir = _dirname(filePath)
    if dir and not filesystem.exists(dir) then
        filesystem.createDir(dir, true) -- FIN-API: createDir
    end
end

-- isDir kann je nach FIN-Version anders heißen
local _isDirFn = filesystem.isDir or filesystem.isDirectory

--- Einheitliche Fehlerformatierung + Log
---@param where string  -- z.B. "readAllText"
---@param path  string
---@param msg   any
---@return string
local function _err(where, path, msg)
    local s = string.format("FileIO.%s(%s): %s", where, path, tostring(msg))
    log(3, s) -- error
    return s
end

--- Safe open: ok, file|nil, err
---@param path string
---@param mode string
---@return boolean, any|nil, string|nil
local function _safe_open(path, mode)
    local ok, f = pcall(function() return filesystem.open(path, mode) end)
    if not ok or not f then
        local msg = (ok and "open returned nil") or tostring(f)
        return false, nil, _err("open(" .. tostring(mode) .. ")", path, msg)
    end
    return true, f, nil
end

--- Safe call Wrapper: ok, result|nil, err
---@param where string
---@param path string
---@param fn fun():any
---@return boolean, any|nil, string|nil
local function _pcall(where, path, fn)
    local ok, res = pcall(fn)
    if not ok then
        return false, nil, _err(where, path, res)
    end
    return true, res, nil
end

-- ==== Konstruktor ============================================================

--- Erzeugt eine neue FileIO-Instanz.
---@param opts {root?:string, chunk?:integer, autoMount?:boolean, searchFile?:string}|nil
---@return FileIO
function FileIO.new(opts)
    local self       = setmetatable({}, FileIO)
    self.root        = (opts and opts.root) or "/srv"
    self.readChunk   = (opts and opts.chunk) or (64 * 1024)
    self.autoMount   = (opts and opts.autoMount ~= false) -- Default: true
    self.searchFile  = (opts and opts.searchFile) or nil

    self._mounted    = false
    self._mountedDev = nil -- z. B. "/dev/XYZ"
    self._mountedId  = nil -- z. B. "XYZ"
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
    -- /dev initialisieren (FIN)
    pcall(function() filesystem.initFileSystem("/dev") end)

    local devs = filesystem.children("/dev") or {}
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        local okMnt = pcall(function() filesystem.mount(drive, self.root) end)
        if okMnt then
            -- gemountetes Device merken
            self._mountedDev = drive
            self._mountedId  = tostring(drive):match("^/dev/(.+)$")

            if not self.searchFile then
                return true
            else
                local testPath = _join(self.root, self.searchFile)
                if filesystem.exists(testPath) then
                    return true
                else
                    -- nicht der richtige Datenträger → wieder auswerfen
                    pcall(function() filesystem.unmount(drive) end)
                    self._mountedDev, self._mountedId = nil, nil
                end
            end
        end
    end
    return false
end

--- Stellt sicher, dass root bereit/montiert ist (führt ggf. Auto-Mount aus).
---@return boolean, nil|nil, string|nil
function FileIO:ensureMounted()
    if self._mounted then return true end
    if self:_rootLooksReady() then
        self._mounted = true
        log(1, "FileIO: root ready:", self.root)
        return true
    end
    if not self.autoMount then
        return false, nil, _err("ensureMounted", self.root, "root not ready and autoMount=false")
    end
    local ok = self:_tryMount()
    self._mounted = ok and self:_rootLooksReady() or false
    if not self._mounted then
        return false, nil, _err("ensureMounted", self.root, "could not mount any /dev/*")
    end
    log(1, "FileIO: mounted on", self.root, "device:", self._mountedDev or "?")
    return true
end

-- ==== public helpers =========================================================

--- Absoluten Pfad unterhalb von root bilden.
---@param rel string
---@return string
function FileIO:abs(rel) return _join(self.root, rel) end

--- Liefert das zuletzt gemountete Device (z. B. "/dev/XYZ"), falls bekannt.
---@return string|nil
function FileIO:getMountedDevice() return self._mountedDev end

--- Liefert die ID des gemounteten Devices (z. B. "XYZ"), falls bekannt.
---@return string|nil
function FileIO:getMountedId() return self._mountedId end

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

--- Erzeugt ein Verzeichnis (rekursiv, sofern von FIN so gehandhabt).
---@param rel string
---@return boolean, nil|nil, string|nil
function FileIO:mkdir(rel)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    local okMk, _, e = _pcall("mkdir", p, function() return filesystem.createDir(p, true) end)
    if not okMk then return false, nil, e end
    log(1, "FileIO.mkdir OK:", p)
    return true
end

--- Entfernt Datei oder (rekursiv=true) Verzeichnis inkl. Inhalt.
---@param rel string
---@param rekursiv boolean|nil
---@return boolean, nil|nil, string|nil
function FileIO:rm(rel, rekursiv)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    rekursiv = rekursiv or true

    if rekursiv and self:isDir(rel) then
        for _, name in ipairs(filesystem.children(p) or {}) do
            local okRm, _, eRm = self:rm(_sanitize(rel) .. "/" .. name, true)
            if not okRm then return false, nil, eRm end
        end
    end

    local okDel, _, eDel = _pcall("rm", p, function() return filesystem.remove(p, rekursiv) end)
    if not okDel then return false, nil, eDel end
    log(1, "FileIO.rm OK:", p)
    return true
end

-- ==== Lesen/Schreiben ========================================================

--- Liest Textdatei komplett (UTF-8/ASCII).
---@param rel string
---@return boolean, string|nil, string|nil
function FileIO:readAllText(rel)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)

    local okOpen, f, e = _safe_open(p, "r")
    if not okOpen then return false, nil, e end

    local buf = ""
    while true do
        local okRead, chunk, er = _pcall("readAllText/read", p, function() return f:read(self.readChunk) end)
        if not okRead then
            f:close(); return false, nil, er
        end
        if not chunk then break end
        buf = buf .. chunk
    end

    f:close()
    return true, buf, nil
end

--- Liest Binärdatei komplett als String (Bytes).
---@param rel string
---@return boolean, string|nil, string|nil
function FileIO:readAllBinary(rel)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)

    local okOpen, f, e = _safe_open(p, "rb")
    if not okOpen then return false, nil, e end

    local buf = ""
    while true do
        local okRead, chunk, er = _pcall("readAllBinary/read", p, function() return f:read(self.readChunk) end)
        if not okRead then
            f:close(); return false, nil, er
        end
        if not chunk then break end
        buf = buf .. chunk
    end

    f:close()
    return true, buf, nil
end

--- Schreibt Text (überschreibt Datei, erzeugt Elternordner bei Bedarf).
---@param rel string
---@param text any
---@return boolean, nil|nil, string|nil
function FileIO:writeText(rel, text)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    _ensure_parent_dir(p)

    local okOpen, f, e = _safe_open(p, "w")
    if not okOpen then return false, nil, e end

    local okWrite, _, ew = _pcall("writeText/write", p, function() f:write(tostring(text or "")) end)
    f:close()
    if not okWrite then return false, nil, ew end

    log(1, "FileIO.writeText OK:", p)
    return true
end

--- Hängt Text an (erzeugt Elternordner bei Bedarf).
---@param rel string
---@param text any
---@return boolean, nil|nil, string|nil
function FileIO:appendText(rel, text)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    _ensure_parent_dir(p)

    local okOpen, f, e = _safe_open(p, "a")
    if not okOpen then return false, nil, e end

    local okWrite, _, ew = _pcall("appendText/write", p, function() f:write(tostring(text or "")) end)
    f:close()
    if not okWrite then return false, nil, ew end

    log(1, "FileIO.appendText OK:", p)
    return true
end

--- Schreibt Binärdaten (String-Bytes), erzeugt Elternordner bei Bedarf.
---@param rel string
---@param bytes string|nil
---@return boolean, nil|nil, string|nil
function FileIO:writeBinary(rel, bytes)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    _ensure_parent_dir(p)

    local okOpen, f, e = _safe_open(p, "wb")
    if not okOpen then return false, nil, e end

    local okWrite, _, ew = _pcall("writeBinary/write", p, function() f:write(bytes or "") end)
    f:close()
    if not okWrite then return false, nil, ew end

    log(1, ("FileIO.writeBinary OK: %s (%d bytes)"):format(p, bytes and #bytes or 0))
    return true
end

--- Schreibt eine Liste von Byte-Strings nacheinander (z. B. chunkweise).
---@param rel string
---@param bytes string[]
---@return boolean, nil|nil, string|nil
function FileIO:writeBinaryArray(rel, bytes)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)
    _ensure_parent_dir(p)

    local okOpen, f, e = _safe_open(p, "wb")
    if not okOpen then return false, nil, e end

    for i = 1, #bytes do
        local okWrite, _, ew = _pcall("writeBinaryArray/write", p, function() f:write(bytes[i] or "") end)
        if not okWrite then
            f:close(); return false, nil, ew
        end
    end

    f:close()
    log(1, ("FileIO.writeBinaryArray OK: %s (%d chunks)"):format(p, #bytes))
    return true
end

-- ==== Utilities ==============================================================

--- Kopiert Datei (binär).
---@param srcRel string
---@param dstRel string
---@return boolean, nil|nil, string|nil
function FileIO:copy(srcRel, dstRel)
    local okR, data, eR = self:readAllBinary(srcRel)
    if not okR then return false, nil, eR end
    local okW, _, eW = self:writeBinary(dstRel, data)
    if not okW then return false, nil, eW end
    log(1, "FileIO.copy OK:", self:abs(srcRel), "->", self:abs(dstRel))
    return true
end

--- Verschiebt Datei (kopieren + löschen).
---@param srcRel string
---@param dstRel string
---@return boolean, nil|nil, string|nil
function FileIO:move(srcRel, dstRel)
    local okC, _, eC = self:copy(srcRel, dstRel)
    if not okC then return false, nil, eC end
    local okD, _, eD = self:rm(srcRel)
    if not okD then return false, nil, eD end
    log(1, "FileIO.move OK:", self:abs(srcRel), "->", self:abs(dstRel))
    return true
end

--- Wie readAllText, aber Fehler → nil + Fehlermeldung (komfortabel für Call-Sites).
---@param rel string
---@return string|nil, string|nil
function FileIO:tryReadText(rel)
    local ok, res, err = self:readAllText(rel)
    if ok then return res, nil end
    return nil, err
end

--- Wie readAllBinary, aber Fehler → nil + Fehlermeldung.
---@param rel string
---@return string|nil, string|nil
function FileIO:tryReadBinary(rel)
    local ok, res, err = self:readAllBinary(rel)
    if ok then return res, nil end
    return nil, err
end
