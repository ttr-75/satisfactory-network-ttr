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


-------------------------------
-- Listener-Debug-Helfer
-------------------------------
-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        computer.log(4, tb)
        return tb
    end
end

-- safe_listener(tag, fn): verpackt fn in xpcall, sodass Fehler nicht „leise“ bleiben.
function safe_listener(tag, fn)
    assert(type(fn) == "function", "safe_listener needs a function")
    return function(...)
        local ok, res = xpcall(fn, _traceback(tag), ...)
        return res
    end
end

-- hübsches Argument-Logging
function fmt_args(...)
    local t = table.pack(...)
    for i = 1, t.n do t[i] = tostring(t[i]) end
    return table.concat(t, ", ")
end

-------------------------------------------------------
--- NetHub
-------------------------------------------------------


NetHub = {
    nic = nil,
    listenerId = nil,
    services = {}, -- [port] = { handler=fn, name="MEDIA", ver=1 }
}


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

function NetworkAdapter:send(toId, cmd, ...)
    self.net:send(toId, self.port, cmd, ...)
end

function NetworkAdapter:broadcast(cmd, ...)
    self.net:broadcast(self.port, cmd, ...)
end

-------------------------------------------------------------------------------
--- CodeDispatchClient
-------------------------------------------------------------------------------

CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

function CodeDispatchClient.new(opts)
    local self = NetworkAdapter:new(opts)
    self.name = NET_NAME_CODE_DISPATCH_CLIENT
    self.port = NET_PORT_CODE_DISPATCH
    self.ver = 1
    self.requestCompleted = {}
    self.loadingRegistry = {}
    self.codes = {}
    self.codeOrder = {}
    self = setmetatable(self, CodeDispatchClient)


    local function existsInRegistry(name)
        for _, n in pairs(self.loadingRegistry) do
            if n == name then
                return true
            end
        end
        return false
    end

    local function insertAt(a, i, v)
        local n = #a
        if i == nil then i = n + 1 end
        if i < 1 then i = 1 end
        if i > n + 1 then i = n + 1 end
        table.insert(a, i, v) -- nutzt die eingebaute Verschiebung
        return i
    end

    local function indexOfIn(a, value)
        for i = 1, #a do
            if a[i] == value then return i end
        end
        return nil
    end

    local function removeFrom(a, value)
        local i = indexOfIn(a, value)
        if i then
            table.remove(a, i); return true
        end
        return false
    end


    -- Private functions--
    local function split_on_finished(content)
        assert(type(content) == "string", "content muss String sein")
        local marker = "CodeDispatchClient:finished()"
        local s, e = string.find(content, marker, 1, true) -- plain match
        if not s then
            return nil, content
        end
        local before = string.sub(content, 1, s - 1)
        local after  = string.sub(content, e + 1)
        return before, after
    end

    local function parseModule(name, content)
        if not content then
            log(3, "CodeDispatchClient:Could not load " .. name .. ": Not found.")
            return nil
        end


        local register, content = split_on_finished(content)

        if (register ~= nil) then
            log(1, "CodeDispatchClient:Parsing loaded register " .. name)
            local code, err = load(register)
            if not code then
                log(4, "Failed to parse register " .. name .. ": " .. tostring(err))
            end

            if not code then
                computer.log(4, "CodeDispatchClient:Failed to load module register " .. name)
                return
            end
            log(1, "CodeDispatchClient:Starting Registration " .. name)
            local ok, err = pcall(code)
            if not ok then
                log(4, err)
            end
        end


        log(1, "CodeDispatchClient:Parsing loaded content " .. name)
        local code, err = load(content)
        if not code then
            log(4, "Failed to parse " .. name .. ": " .. tostring(err))
        end

        if not code then
            computer.log(4, "CodeDispatchClient:Failed to load module " .. name)
            return
        end
        log(1, "CodeDispatchClient:Save for Procedure " .. name)
        self.codes[name] = code
        self.requestCompleted[name] = true
    end

    function self:onSetEEPROM(programName, code)
        parseModule(programName, code)
    end

    self:registerWith(function(from, port, cmd, programName, code)
        if port == self.port and cmd == NET_CMD_CODE_DISPATCH_SET_EEPROM then
            log(0, ('CodeDispatchClient: Got code for "%s" from "%s"'):format(programName, from))
            self:onSetEEPROM(programName, code)
        elseif port == self.port and cmd == NET_CMD_CODE_DISPATCH_RESET_ALL then
            log(2, ('CodeDispatchClient: Received reset command from "%s"'):format(from))
            if self._onReset ~= nil then
                log(1, "CodeDispatchClient: Call Reset Callback")
                local ok, err = pcall(self._onReset)
                if not ok then log(3, "Reset handler error: " .. tostring(err)) end
            end
            computer.reset()
        end
    end)

    local function loadModule(name)
        if self.requestCompleted[name] then
            log(2, ('CodeDispatchClient: Already loaded "%s"'):format(name))
            return
        end
        self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, name)
        log(0, ('CodeDispatchClient: Broadcast-Requesting "%s on port %s"'):format(name, self.port))
        self.requestCompleted[name] = false
    end

    -- Dummy Funktion
    function self:finished()

    end

    function self:loadAndWait()
        if #self.loadingRegistry == 0 then
            self:callAllLoadedFiles()
            return false
        end
        local next = self.loadingRegistry[1]

        while removeFrom(self.loadingRegistry, next) do

        end


        loadModule(next)

        while self.requestCompleted[next] == false do
            future.run()
        end

        self:loadAndWait()
    end

    function self:callAllLoadedFiles()
        for i = 1, #self.codeOrder do
            local name = self.codeOrder[i]
            log(1, "CodeDispatchClient:Running Code: " .. name)
            local ok, err = pcall(self.codes[name])
            if not ok then
                log(4, err)
            end
        end
        self.codeOrder = {}
        self.codes = {}
    end

    local function register(name)
        if self.requestCompleted[name] == nil then
            if existsInRegistry(name) == false then
                log(0, "Neu Registiert:  " .. name)
                insertAt(self.loadingRegistry, 1, name)
                insertAt(self.codeOrder, 1, name)
            else
                log(0, "Nochmals Registiert:  " .. name)
                while removeFrom(self.loadingRegistry, name) do
                    -- Delete all
                end
                insertAt(self.loadingRegistry, 1, name)
            end
            while removeFrom(self.codeOrder, name) do
                -- Delete all
            end
            insertAt(self.codeOrder, 1, name)
        end
    end

    function self:registerForLoading(names)
        local n = #names
        local out = {}
        for i = 1, n do
            out[i] = names[n - i + 1]
        end

        for i = 1, #out do
            register(out[i])
        end
    end

    return self
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchClient = CodeDispatchClient.new()




names = {}
CodeDispatchClient:registerForLoading(names)

CodeDispatchClient:loadAndWait()
