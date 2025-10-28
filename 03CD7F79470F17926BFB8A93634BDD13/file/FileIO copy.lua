----------------------------------------------------------------
-- FileIO.lua – kleine Dateihilfe (instanzbasiert)
-- Features:
--   - Root-Verzeichnis (Chroot-ähnlich) zur Sicherheit
--   - exists/isFile/isDir/list/mkdir/rm
--   - readAllText/readAllBinary (ganze Datei -> String)
--   - writeText/appendText/writeBinary
--   - copy/move
--   - sichere Pfad-Join + Sanitizing (kein '..')
----------------------------------------------------------------
----------------------------------------------------------------
-- FileIO.lua – Dateihilfe mit Auto-Mount
-- Features:
--   - Root-Verzeichnis (Default "/srv")
--   - Auto-Mount: durchsucht /dev und mountet das erste Device auf root
--   - Optionaler Such-File zur Verifikation (opts.searchFile)
--   - exists/isFile/isDir/list/mkdir/rm
--   - readAllText/readAllBinary, writeText/appendText/writeBinary
--   - copy/move, tryRead*
----------------------------------------------------------------

FileIO = {}
FileIO.__index = FileIO

-- interne Helfer --------------------------------------------------------------

local function _sanitize(rel)
    rel = tostring(rel or "")
    rel = rel:gsub("^/*", "")
    assert(not rel:find("%.%.", 1, true), "FileIO: Pfad darf kein '..' enthalten")
    return rel
end

local function _join(root, rel)
    rel = _sanitize(rel)
    if root == "/" then return "/" .. rel end
    if root:sub(-1) == "/" then return root .. rel end
    return root .. "/" .. rel
end

local function _ensure_dir(path)
    local dir = filesystem.path(path)
    if dir and not filesystem.exists(dir) then
        filesystem.createDir(dir, true)
    end
end

-- Konstruktor -----------------------------------------------------------------
-- opts.root       : Mountpunkt/Root (Default "/srv")
-- opts.chunk      : Lesepuffer (Default 64*1024)
-- opts.autoMount  : true/false (Default true)
-- opts.searchFile : optionaler Dateiname, der nach Mount existieren soll
function FileIO.new(opts)
    local self       = setmetatable({}, FileIO)
    self.root        = (opts and opts.root) or "/srv"
    self.readChunk   = (opts and opts.chunk) or (64 * 1024)
    self.autoMount   = (opts and opts.autoMount ~= false)
    self.searchFile  = (opts and opts.searchFile) or nil
    self._mounted    = false
    self._mountedDev = nil -- z.B. "/dev/123ABC"
    self._mountedId  = nil -- z.B. "123ABC"
    assert(type(self.root) == "string", "FileIO: root muss string sein")
    return self
end

-- Mount-Logik -----------------------------------------------------------------

-- Prüft, ob root „benutzbar“ wirkt (existiert + lesbar).
function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    -- kleiner Zugriffstest: children kann leer sein, ist aber ok
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

-- Versucht, ein /dev/* Device auf self.root zu mounten.
-- Wenn searchFile gesetzt ist, wird nur akzeptiert, wenn Datei existiert.
function FileIO:_tryMount()
    -- /dev initialisieren (idempotent)
    pcall(function() filesystem.initFileSystem("/dev") end)

    local devs = filesystem.children("/dev") or {}
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        -- mounten
        local ok = pcall(function() filesystem.mount(drive, self.root) end)
        if ok then
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

-- Stellt sicher, dass root gemountet ist (einmalig).
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

-- Pfad-Helfer (öffentlich)
function FileIO:abs(rel) return _join(self.root, rel) end

-- Abfragen --------------------------------------------------------------------
function FileIO:getMountedDevice() -- gibt z.B. "/dev/123ABC" oder nil
    return self._mountedDev
end

function FileIO:getMountedId() -- nur die ID, z.B. "123ABC" oder nil
    return self._mountedId
end

function FileIO:exists(rel)
    self:ensureMounted()
    return filesystem.exists(self:abs(rel))
end

function FileIO:isFile(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    return filesystem.exists(p) and filesystem.isFile(p)
end

function FileIO:isDir(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    return filesystem.exists(p) and filesystem.isDirectory(p)
end

function FileIO:list(rel)
    self:ensureMounted()
    local p = self:abs(rel or "")
    if not filesystem.exists(p) then return {} end
    return filesystem.children(p) or {}
end

-- Erstellen / Löschen ---------------------------------------------------------

function FileIO:mkdir(rel)
    self:ensureMounted()
    _ensure_dir(self:abs(rel))
end

function FileIO:rm(rel, rekursiv)
    self:ensureMounted()
    local p = self:abs(rel)
    if rekursiv and filesystem.isDirectory(p) then
        for _, name in ipairs(filesystem.children(p) or {}) do
            self:rm(_sanitize(rel) .. "/" .. name, true)
        end
    end
    filesystem.remove(p)
end

-- Lesen -----------------------------------------------------------------------

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

-- Schreiben -------------------------------------------------------------------

function FileIO:writeText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_dir(p)
    local f = filesystem.open(p, "w")
    assert(f, "FileIO: kann Datei nicht öffnen (w): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:appendText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_dir(p)
    local f = filesystem.open(rel, "a")
    assert(f, "FileIO: kann Datei nicht öffnen (a): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:writeBinary(rel, bytes)
    self:ensureMounted()
    --local p = self:abs(rel)
    --_ensure_dir(p)
    local f = filesystem.open(rel, "w")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    f:write(bytes or "")
    f:close()
end

-- Utilities -------------------------------------------------------------------

function FileIO:copy(srcRel, dstRel)
    self:ensureMounted()
    local src = self:readAllBinary(srcRel)
    self:writeBinary(dstRel, src)
end

function FileIO:move(srcRel, dstRel)
    self:ensureMounted()
    self:copy(srcRel, dstRel)
    self:rm(srcRel)
end

function FileIO:tryReadText(rel)
    self:ensureMounted()
    local ok, res = pcall(function() return self:readAllText(rel) end)
    if ok then return res end
    return nil, res
end

function FileIO:tryReadBinary(rel)
    self:ensureMounted()
    local ok, res = pcall(function() return self:readAllBinary(rel) end)
    if ok then return res end
    return nil, res
end
