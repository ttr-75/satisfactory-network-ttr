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

local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        log(4, tb)
        return tb
    end
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

-- Maskiert alle Lua-Pattern-Sonderzeichen in einem Literal
local function escape_lua_pattern(s)
    return (s:gsub("(%W)", "%%%1")) -- alles, was nicht %w ist, mit % escapen
end

-- Ersetzt EXAKT die Zeichenkette "[-LANGUAGE-].lua" durch z.B. "de.lua"
local function replace_language_chunk(str, replacement)
    local literal = "[-LANGUAGE-].lua"
    replacement = "_" .. replacement .. ".lua"
    local pattern = escape_lua_pattern(literal)

    -- Falls replacement '%' enthalten könnte, für gsub-Replacement escapen:
    replacement = replacement:gsub("%%", "%%%%")

    return (str:gsub(pattern, replacement))
end

---@diagnostic disable: lowercase-global


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

    self.fsio  = FileIO.new { root = "/srv" }

    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end
        if cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            self:onGetEEPROM(from, tostring(programName or ""))
        end
    end)

    return self
end

--=== Prototyp-Methoden =======================================================

--- Antwortet auf GET_EEPROM mit dem angeforderten Code.
---@param fromId string
---@param programName string
function CodeDispatchServer:onGetEEPROM(fromId, programName)
    local fallback = [[
        print("Invalid Net-Boot-Program: Program not found!")
        event.pull(5)
        computer.reset()
    ]]
    log(1, ('CodeDispatchServer: request "%s" from "%s"'):format(programName, tostring(fromId)))

    local ok, code = pcall(function()
        local ok, content, err = self.fsio:readAllText(programName)
        if not ok then
            log(3, "Failed to read " .. programName, err)
            return
        end
        content = replace_language_chunk(content, TTR_FIN_Config.language)
        content:gsub("[-LANGUAGE-].lua", "_" .. TTR_FIN_Config.language)
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
        future.run()
    end
end

local filename = "config.lua"
local ok, data, err = fsio:readAllText(filename)
if not ok then
    log(4, "Failed to read " .. filename, err)
    return
end
local contentFn = load(data)
xpcall(contentFn, _traceback("ServerStart"), "Failed to excecute " .. filename)


log(2, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
log(0, "Laguage set to " .. TTR_FIN_Config.language)

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()
CodeDispatchServer:run()
