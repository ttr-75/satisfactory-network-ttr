LOG_MIN = 1


-------------------------------
-- Logging
-------------------------------
-- Hinweis: LOG_MIN sollte global gesetzt sein (z. B. 0=Info, 1=Info+, 2=Warn, 3=Error, 4=Fatal)
-- Alte Version nutzte table.concat({ ... }, " "), was crasht, wenn ... Nicht-Strings enthält. (fix)
local function _to_strings(tbl)
    local out = {}
    for i = 1, #tbl do out[i] = tostring(tbl[i]) end
    return out
end

function log(level, ...)
    if level >= (LOG_MIN or 0) then
        local parts = _to_strings({ ... }) -- robust bei Zahlen, Booleans, Tabellen (tostring)
        computer.log(level, table.concat(parts, " "))
    end
end

--------------------------------------------------------------------------------
-- Konstanten (wie in deiner Originaldatei)
--------------------------------------------------------------------------------
NET_PORT_CODE_DISPATCH           = 8
NET_NAME_CODE_DISPATCH_CLIENT    = "CodeDispatchClient"
NET_NAME_CODE_DISPATCH_SERVER    = "CodeDispatchServer"

--NET_CMD_CODE_DISPATCH_SET_EEPROM = "CodeDispatchClient.setEEPROM"
--NET_CMD_CODE_DISPATCH_GET_EEPROM = "CodeDispatchClient.getEEPROM"
--NET_CMD_CODE_DISPATCH_RESET_ALL      = "CodeDispatchClient.resetAll"

NET_CMD_CODE_DISPATCH_SET_EEPROM = "setEEPROM"
NET_CMD_CODE_DISPATCH_GET_EEPROM = "getEEPROM"
NET_CMD_CODE_DISPATCH_RESET_ALL  = "resetAll"
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

FileIO                           = {}
FileIO.__index                   = FileIO

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
        filesystem.makeDirectory(dir)
    end
end

-- Konstruktor -----------------------------------------------------------------
-- opts.root       : Mountpunkt/Root (Default "/srv")
-- opts.chunk      : Lesepuffer (Default 64*1024)
-- opts.autoMount  : true/false (Default true)
-- opts.searchFile : optionaler Dateiname, der nach Mount existieren soll
function FileIO.new(opts)
    local self      = setmetatable({}, FileIO)
    self.root       = (opts and opts.root) or "/srv"
    self.readChunk  = (opts and opts.chunk) or (64 * 1024)
    self.autoMount  = (opts and opts.autoMount ~= false)
    self.searchFile = (opts and opts.searchFile) or nil
    self._mounted   = false
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
            -- optional verifizieren
            if not self.searchFile then
                return true
            else
                local testPath = _join(self.root, self.searchFile)
                if filesystem.exists(testPath) then
                    return true
                else
                    -- wieder unmounten, wenn nicht passend
                    pcall(function() filesystem.unmount(drive) end)
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
    filesystem.makeDirectory(self:abs(rel))
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
    local f = filesystem.open(p, "a")
    assert(f, "FileIO: kann Datei nicht öffnen (a): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:writeBinary(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_dir(p)
    local f = filesystem.open(p, "wb")
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

-------------------------------------------------------
--- NetHub
-------------------------------------------------------


NetHub = {
    nic = nil,
    listenerId = nil,
    services = {}, -- [port] = { handler=fn, name="MEDIA", ver=1 }
}

-- fallback wrapper if safe_listener isn't loaded
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        computer.log(4, tb)
        return tb
    end
end
local function _wrap(tag, fn)
    if type(safe_listener) == "function" then
        return safe_listener(tag, fn)
    end
    return function(...)
        local ok, res = xpcall(fn, _traceback(tag), ...)
        return res
    end
end

function NetHub:init(nic)
    if self.listenerId then return end
    self.nic = nic or computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.nic, "NetHub: keine NIC gefunden")
    event.listen(self.nic)

    local f = event.filter { event = "NetworkMessage" }
    self.listenerId = event.registerListener(f, _wrap("NetHub.Dispatch", function(_, _, fromId, port, cmd, a, b, c, d)
        local svc = self.services[port]
        if not svc then return end
        -- delegate to per-port wrapped handler (already safe-wrapped in :register)
        return svc._wrapped(fromId, port, cmd, a, b, c, d)
    end))

    computer.log(0, "NetHub: ready")
end

function NetHub:register(port, name, ver, handler)
    assert(type(port) == "number" and handler, "NetHub.register: ungültig")
    local wrapped = _wrap("NetHub." .. tostring(name or port), handler)
    self.services[port] = { handler = handler, _wrapped = wrapped, name = name, ver = ver or 1 }
    self.nic:open(port) -- Port EINMAL hier öffnen
end

function NetHub:close()
    if self.listenerId and event.removeListener then event.removeListener(self.listenerId) end
    self.listenerId = nil
    self.services = {}
end

--------------------------------------------------------------------------------
-- NetwordAdapter
--------------------------------------------------------------------------------

NET_PORT_DEFAULT = 8


NetworkAdapter         = {}
NetworkAdapter.__index = NetworkAdapter

function NetworkAdapter:new(opts)
    local self = setmetatable({}, NetworkAdapter)
    self.port  = (opts and opts.port) or NET_PORT_DEFAULT
    self.name  = (opts and opts.name) or "NetworkAdapter"
    self.ver   = (opts and opts.ver) or 1
    self.net   = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    return self
end

function NetworkAdapter:registerWith(fn)
    NetHub:register(self.port, self.name, self.ver, fn)
end

-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------


CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

function CodeDispatchServer.new(opts)
    local self = NetworkAdapter:new(opts)
    self.name = NET_NAME_CODE_DISPATCH_SERVER
    self.port = NET_PORT_CODE_DISPATCH
    self.ver = 1

    self.fsio = FileIO.new { root = "/srv" }
    self = setmetatable(self, CodeDispatchServer)

    local netBootFallbackProgram = [[
    print("Invalid Net-Boot-Program: Program not found!")
    event.pull(5)
    computer.reset()
]]

    local function loadCode(programName)
        return self.fsio:readAllText(programName)
    end


    self:registerWith(function(from, port, cmd, programName, code)
        if port == self.port and cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            print("Program Request for \"" .. programName .. "\" from \"" .. from .. "\"")
            local code = loadCode(programName) or netBootFallbackProgram;
            self.net:send(from, self.port, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, code)
        end
    end)


    function self:run(timeout)
        while true do
            future.run(timeout)
        end
    end

    return self
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()

CodeDispatchServer:run(0.25)

