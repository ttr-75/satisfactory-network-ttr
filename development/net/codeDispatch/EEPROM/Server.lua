---gpt ignore
--------------------------------------------------------------------------------
-- Konstanten (wie in deiner Originaldatei)
--------------------------------------------------------------------------------
NET_PORT_CODE_DISPATCH             = 8
NET_NAME_CODE_DISPATCH_CLIENT      = "CodeDispatchClient"
NET_NAME_CODE_DISPATCH_SERVER      = "CodeDispatchServer"

--NET_CMD_CODE_DISPATCH_SET_EEPROM = "CodeDispatchClient.setEEPROM"
--NET_CMD_CODE_DISPATCH_GET_EEPROM = "CodeDispatchClient.getEEPROM"
--NET_CMD_CODE_DISPATCH_RESET_ALL      = "CodeDispatchClient.resetAll"

NET_CMD_CODE_DISPATCH_SET_EEPROM   = "setEEPROM"
NET_CMD_CODE_DISPATCH_GET_EEPROM   = "getEEPROM"
NET_CMD_CODE_DISPATCH_RESET_ALL    = "resetAll"
NET_CMD_CODE_DISPATCH_RESET_SERVER = "resetServer"


local function _to_strings(tbl)
    local out = {}
    for i = 1, #tbl do out[i] = tostring(tbl[i]) end
    return out
end

local function log(level, ...)
    if level >= (LOG_MIN or TTR_FIN_Config and TTR_FIN_Config.LOG_LEVEL or 0) then
        local parts = _to_strings({ ... }) -- robust bei Zahlen, Booleans, Tabellen (tostring)
        computer.log(level, table.concat(parts, " "))
    end
end

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



-------------------------------
-- Listener-Debug-Helfer
-------------------------------
-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        log(4, tb)
        return tb
    end
end

-- safe_listener(tag, fn): verpackt fn in xpcall, sodass Fehler nicht „leise“ bleiben.
local function safe_listener(tag, fn)
    assert(type(fn) == "function", "safe_listener needs a function")
    return function(...)
        local ok, res = xpcall(fn, _traceback(tag), ...)
        return res
    end
end


-------------------------------------------------------
--- NetHub
-------------------------------------------------------

--- Ein Dienst-Eintrag in NetHub.services
---@class NetServiceEntry
---@field handler  NetHandler
---@field _wrapped NetHandler
---@field name     NetName|nil
---@field ver      NetVersion

--- NetHub-Singleton
---@class NetHubClass
---@field nic NIC|nil
---@field listenerId any|nil
---@field services table<NetPort, NetServiceEntry>
NetHub = {
    nic = nil,
    listenerId = nil,
    services = {}, -- [port] = { handler=fn, name="MEDIA", ver=1 }
}

-- fallback wrapper if safe_listener isn't loaded
---@param tag string
---@return fun(err:any):string
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        log(4, tb)
        return tb
    end
end

---@param tag string
---@param fn  NetHandler
---@return NetHandler
local function _wrap(tag, fn)
    if type(safe_listener) == "function" then
        return safe_listener(tag, fn)
    end
    return function(...)
        local ok, res = xpcall(fn, _traceback(tag), ...)
        return res
    end
end

--- Initialisiert den Hub (einmalig), hört auf NetworkMessage und verteilt pro Port.
---@param nic NIC|nil  -- optional explizite NIC; sonst erste gefundene
function NetHub:init(nic)
    if self.listenerId then return end
    self.nic = nic or computer.getPCIDevices(classes.NetworkCard)[1]
    if not self.nic then
        return false, { code = "NO_NIC", message = "NetHub: keine NIC gefunden" }
    end
    event.listen(self.nic)

    local f = event.filter { event = "NetworkMessage" }
    self.listenerId = event.registerListener(f, _wrap("NetHub.Dispatch",
        ---@param fromId string
        ---@param port NetPort
        ---@param cmd NetCommand
        ---@param a any
        ---@param b any
        function(_, _, fromId, port, cmd, a, b)
            local svc = self.services[port]
            if not svc then return end
            -- delegate to per-port wrapped handler (already safe-wrapped in :register)
            return svc._wrapped(fromId, port, cmd, a, b)
        end))

    log(0, "NetHub: ready")
end

--- Registriert einen Handler für Port/Name/Version; öffnet den Port auf der NIC.
---@param port NetPort
---@param name NetName|nil
---@param ver  NetVersion|nil
---@param handler NetHandler
function NetHub:register(port, name, ver, handler)
    assert(type(port) == "number" and handler, "NetHub.register: ungültig")
    local wrapped = _wrap("NetHub." .. tostring(name or port), handler)
    self.services[port] = { handler = handler, _wrapped = wrapped, name = name, ver = ver or 1 }
    self.nic:open(port) -- Port EINMAL hier öffnen
end

--- Beendet den Listener und leert die Service-Tabelle.
function NetHub:close()
    if self.listenerId and event.removeListener then event.removeListener(self.listenerId) end
    self.listenerId = nil
    self.services = {}
end

function NetHub:unregister(port, name, ver)
    if type(port) ~= "number" then
        return false, { code = "BAD_PORT", message = "NetHub.unregister: port must be number" }
    end
    local svc = self.services[port]
    if not svc then
        return false, { code = "NOT_FOUND", message = ("no service on port %s"):format(port) }
    end
    if name and svc.name ~= name then
        return false, { code = "NAME_MISMATCH", message = "service name mismatch" }
    end
    if ver and svc.ver ~= ver then
        return false, { code = "VER_MISMATCH", message = "service version mismatch" }
    end
    pcall(function() if self.nic and self.nic.close then self.nic:close(port) end end)
    self.services[port] = nil
    if next(self.services) == nil then
        if self.listenerId and event.removeListener then pcall(function() event.removeListener(self.listenerId) end) end
        self.listenerId = nil
    end
    return true
end

local FileIO = {}
FileIO.__index = FileIO

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

function FileIO:abs(rel) return _join(self.root, rel) end

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

function FileIO:ensureMounted()
    if self._mounted and self:_rootLooksReady() then
        if not self.searchFile or filesystem.exists(_join(self.root, self.searchFile)) then
            return true
        end
        -- falsch gemountet → neu versuchen
        pcall(function() if self._mountedDev then filesystem.unmount(self._mountedDev) end end)
        self._mounted, self._mountedDev, self._mountedId = false, nil, nil
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

function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

local fsio = FileIO.new { root = "/srv" }

local ok, data, err = fsio:readAllText("config.lua")
if not ok then
    log(4, "Failed to read config.lua", err)
    return
end
local contentFn = load(data)
xpcall(contentFn, _traceback("ServerStart"), "Failed to excecute config.lua")

-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------



-- Standardport (aus deiner Originaldatei)
---@type integer
NET_PORT_DEFAULT       = 8

--------------------------------------------------------------------------------
-- NetworkAdapter – Typ-Annotationen (EmmyLua/LuaLS)
-- Hinweis: Diese Datei verändert KEIN Laufzeitverhalten – nur Kommentare.
-- Erwartet, dass NetHub global verfügbar ist (mit NetHub:register/init).
--------------------------------------------------------------------------------

local NetworkAdapter   = {}
NetworkAdapter.__index = NetworkAdapter



function NetworkAdapter:new(opts)
    local o = setmetatable({}, self)
    o.port  = (opts and opts.port) or NET_PORT_DEFAULT
    o.name  = (opts and opts.name) or "NetworkAdapter"
    o.ver   = (opts and opts.ver) or 1
    o.net   = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    return o
end

--- Registriert einen Paket-Handler beim NetHub auf self.port/self.name/self.ver.
--- Der Handler wird bei eingehenden NetworkMessage-Paketen auf diesem Port aufgerufen.
---@param fn NetHandler
function NetworkAdapter:registerWith(fn)
    NetHub:register(self.port, self.name, self.ver, fn)
end

--- Sendet eine Direktnachricht an eine Ziel-NIC.
---@param toId string
---@param cmd NetCommand
---@param ... any
function NetworkAdapter:send(toId, cmd, ...)
    self.net:send(toId, self.port, cmd, ...)
end

--- Broadcastet eine Nachricht auf diesem Adapter-Port.
---@param cmd NetCommand
---@param ... any
function NetworkAdapter:broadcast(cmd, ...)
    self.net:broadcast(self.port, cmd, ...)
end

function NetworkAdapter:close(reason)
    if NetHub and NetHub.unregister then
        pcall(NetHub.unregister, NetHub, self.port, self.name, self.ver)
    end
end

---@class CodeDispatchServer : NetworkAdapter
---@field fsio FileIO
CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

---@param opts table|nil
---@return CodeDispatchServer
function CodeDispatchServer.new(opts)
    -- generischer Basiskonstruktor → sofort ein CodeDispatchServer-Objekt
    local self = NetworkAdapter.new(CodeDispatchServer, opts)
    self.name  = NET_NAME_CODE_DISPATCH_SERVER
    self.port  = NET_PORT_CODE_DISPATCH
    self.ver   = 1

    self.fsio  = opts and opts.fsio or FileIO.new { root = "/srv" }

    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end
        if cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            self:onGetEEPROM(from, tostring(programName or ""))
        elseif cmd == NET_CMD_CODE_DISPATCH_RESET_SERVER then
            self:onResetServer(from)
        end
    end)

    return self
end

function CodeDispatchServer:onResetServer(fromId)
    log(3, ('CodeDispatchServer: resetServer request from "%s"'):format(tostring(fromId)))
    computer.reset()
end

--=== Prototyp-Methoden =======================================================

--- Antwortet auf GET_EEPROM mit dem angeforderten Code.
---@param fromId string
---@param programName string
function CodeDispatchServer:onGetEEPROM(fromId, programName)
    local fallback = [[
        print("Invalid Net-Boot-Program: Program not found!")
        event.pull(5)
    ]]
    log(1, ('CodeDispatchServer: request "%s" from "%s"'):format(programName, tostring(fromId)))

    local ok, code = pcall(function()
        local ok, content, err = self.fsio:readAllText(programName)
        if not ok then
            log(3, "Failed to read " .. programName, err)
            return
        end
        -- content = replace_language_chunk(content, TTR_FIN_Config.language)
        -- content:gsub("[-LANGUAGE-].lua", "_" .. TTR_FIN_Config.language)
        return content
    end)
    if ok == false then
        log(3, ('CodeDispatchServer: Unable to load "%s" sending fallback'):format(programName))
    end
    local payload = (ok and code) or fallback
    self:send(fromId, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, payload)
end

function CodeDispatchServer:run()
    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_ALL)
    log(1, "CodeDispatchServer: broadcast resetAll")
    while true do
        local ok = xpcall(function() future.run() end, _traceback("CDS.loop"))
        if not ok then event.pull(0.2) end
    end
end

--function CodeDispatchServer:run()
--    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_ALL)
--    log(1, "CodeDispatchServer: broadcast resetAll")
--   while true do
--        future.run()
--   end
--end

log(2, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
log(0, "Laguage set to " .. TTR_FIN_Config.language)

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new { fsio = fsio }
CodeDispatchServer:run()
