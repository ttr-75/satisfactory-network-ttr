


----------------------------------------------------------------
-- FileIO (FicsIt Network kompatibel)
-- - Auto-Mount von /dev/* auf self.root (Default: "/srv")
-- - exists / isFile / isDir / list / mkdir / rm
-- - readAllText / readAllBinary / writeText / appendText / writeBinary
-- - copy / move / tryRead*
----------------------------------------------------------------

FileIO = {}
FileIO.__index = FileIO

-- ==== interne Helfer ====

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

-- NEU: echtes dirname
local function _dirname(p)
    p = tostring(p or "")
    -- trailing slashes weg
    p = p:gsub("/+$", "")
    -- alles bis vor dem letzten / behalten
    local dir = p:match("^(.*)/[^/]*$") or ""
    if dir == "" then return "/" end
    return dir
end

-- Elternordner des ZIEL-Dateipfads sicherstellen
local function _ensure_parent_dir(filePath)
    local dir = _dirname(filePath)
    if dir and not filesystem.exists(dir) then
        filesystem.createDir(dir) -- FN: createDir
    end
end


-- isDir kann unterschiedlich heißen; wir nehmen isDir, fallback isDirectory
local _isDirFn = filesystem.isDir or filesystem.isDirectory

-- ==== Konstruktor ====

-- opts.root       : Mountpunkt (Default "/srv")
-- opts.chunk      : Lesepuffer (Default 64*1024)
-- opts.autoMount  : true/false (Default true)
-- opts.searchFile : optionaler Dateiname zur Verifikation nach Mount
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

-- ==== Mount-Logik ====

function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

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

-- ==== public helpers ====

function FileIO:abs(rel) return _join(self.root, rel) end

function FileIO:getMountedDevice() return self._mountedDev end -- "/dev/XYZ" oder nil

function FileIO:getMountedId() return self._mountedId end      -- "XYZ" oder nil

-- ==== Abfragen ====

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
    if not filesystem.exists(p) then return false end
    if _isDirFn then
        return _isDirFn(p)
    end
    -- Fallback (falls weder isDir noch isDirectory existiert):
    -- Heuristik: ein Pfad ist "Dir", wenn children nicht fehlschlägt.
    local ok = pcall(function() return filesystem.children(p) end)
    return ok
end

function FileIO:list(rel)
    self:ensureMounted()
    local p = self:abs(rel or "")
    if not filesystem.exists(p) then return {} end
    return filesystem.children(p) or {}
end

-- ==== Erstellen / Löschen ====

function FileIO:mkdir(rel)
    self:ensureMounted()
    filesystem.createDir(self:abs(rel))
end

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

-- ==== Lesen/Schreiben ====

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

function FileIO:writeText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "w")
    assert(f, "FileIO: kann Datei nicht öffnen (w): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:appendText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "a")
    assert(f, "FileIO: kann Datei nicht öffnen (a): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:writeBinary(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "wb")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    f:write(bytes or "")
    f:close()
end

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

-- ==== Utilities ====

function FileIO:copy(srcRel, dstRel)
    local src = self:readAllBinary(srcRel)
    self:writeBinary(dstRel, src)
end

function FileIO:move(srcRel, dstRel)
    self:copy(srcRel, dstRel)
    self:rm(srcRel)
end

function FileIO:tryReadText(rel)
    local ok, res = pcall(function() return self:readAllText(rel) end)
    if ok then return res end
    return nil, res
end

function FileIO:tryReadBinary(rel)
    local ok, res = pcall(function() return self:readAllBinary(rel) end)
    if ok then return res end
    return nil, res
end
