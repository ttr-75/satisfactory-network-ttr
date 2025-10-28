---@diagnostic disable: duplicate-doc-field, duplicate-set-field, redefined-local, lowercase-global


----------------------------------------------------------------
-- helper.lua – Kleine Helferlein für Logging
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------

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
-- helper_safe_listern.lua –  Events
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------


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
        computer.log(4, tb)
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
    assert(self.nic, "NetHub: keine NIC gefunden")
    event.listen(self.nic)

    local f = event.filter { event = "NetworkMessage" }
    self.listenerId = event.registerListener(f, _wrap("NetHub.Dispatch",
        ---@param _ev string
        ---@param _nic any
        ---@param fromId string
        ---@param port NetPort
        ---@param cmd NetCommand
        ---@param a any
        ---@param b any
        ---@param c any
        ---@param d any
        function(_, _, fromId, port, cmd, a, b, c, d)
            local svc = self.services[port]
            if not svc then return end
            -- delegate to per-port wrapped handler (already safe-wrapped in :register)
            return svc._wrapped(fromId, port, cmd, a, b, c, d)
        end))

    computer.log(0, "NetHub: ready")
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

-- Standardport (aus deiner Originaldatei)
---@type integer
NET_PORT_DEFAULT       = 8

--------------------------------------------------------------------------------
-- NetworkAdapter – Typ-Annotationen (EmmyLua/LuaLS)
-- Hinweis: Diese Datei verändert KEIN Laufzeitverhalten – nur Kommentare.
-- Erwartet, dass NetHub global verfügbar ist (mit NetHub:register/init).
--------------------------------------------------------------------------------

---@class NetworkAdapter
---@field port NetPort
---@field name NetName
---@field ver  NetVersion
---@field net  NIC
NetworkAdapter         = {}
NetworkAdapter.__index = NetworkAdapter

---@class NetworkAdapterOpts
---@field port NetPort|nil
---@field name NetName|nil
---@field ver  NetVersion|nil
---@field nic  NIC|nil

---@generic T: NetworkAdapter
---@param self T
---@param opts NetworkAdapterOpts|nil
---@return T
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

-- Erwartete globale Konstante (nur Typ-Hinweis; keine Zuweisung hier):
---@type NetPort
NET_PORT_DEFAULT = NET_PORT_DEFAULT



-------------------------------------------------------------------------------
--- CodeDispatchClient
-------------------------------------------------------------------------------

---@class CodeDispatchClient : NetworkAdapter
---@field requestCompleted table<string, boolean>
---@field loadingRegistry  string[]
---@field codes            table<string, function>
---@field codeOrder        string[]
---@field _onReset         fun()|nil
local CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

-- ===== Lokale Utilities (nur Datei-intern) ===================================

local function split_on_finished(content)
    assert(type(content) == "string", "content must be string")
    local marker = "CodeDispatchClient:finished()"
    local s, e = string.find(content, marker, 1, true)
    if not s then return nil, content end
    return string.sub(content, 1, s - 1), string.sub(content, e + 1)
end

local function indexOfIn(a, value)
    for i = 1, #a do if a[i] == value then return i end end
    return nil
end

local function removeFrom(a, value)
    local i = indexOfIn(a, value)
    if i then
        table.remove(a, i); return true
    end
    return false
end

local function insertAt(a, i, v)
    local n = #a
    if i == nil then i = n + 1 end
    if i < 1 then i = 1 end
    if i > n + 1 then i = n + 1 end
    table.insert(a, i, v)
    return i
end

-- ===== Konstruktor ===========================================================

---@param opts table|nil
---@return CodeDispatchClient
function CodeDispatchClient.new(opts)
    local self            = NetworkAdapter.new(CodeDispatchClient, opts)
    self.name             = NET_NAME_CODE_DISPATCH_CLIENT
    self.port             = NET_PORT_CODE_DISPATCH
    self.ver              = 1

    self.requestCompleted = {}
    self.loadingRegistry  = {}
    self.codes            = {}
    self.codeOrder        = {}
    self._onReset         = nil

    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end

        if cmd == NET_CMD_CODE_DISPATCH_SET_EEPROM then
            log(0, ('CDC: got code for "%s" from "%s"'):format(tostring(programName), tostring(from)))
            self:onSetEEPROM(tostring(programName or ""), tostring(code or ""))
        elseif cmd == NET_CMD_CODE_DISPATCH_RESET_ALL then
            log(2, ('CDC: received resetAll from "%s"'):format(tostring(from)))
            if self._onReset then
                local ok, err = pcall(self._onReset)
                if not ok then log(3, "CDC: reset handler error: " .. tostring(err)) end
            end
            computer.reset()
        end
    end)

    return self
end

-- ===== Prototyp-Methoden =====================================================

--- Optionaler Reset-Callback.
---@param fn fun()|nil
function CodeDispatchClient:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

--- Verarbeitet eingehenden Code, splittet ggf. Registrierung/Rest, speichert „Rest“.
---@param programName string
---@param content string
function CodeDispatchClient:onSetEEPROM(programName, content)
    if content == "" then
        log(3, "CDC:onSetEEPROM: empty content for " .. programName)
        self.requestCompleted[programName] = true
        return
    end

    local register, rest = split_on_finished(content)
    if register ~= nil then
        log(1, "CDC: parse register " .. programName)
        local regFn, err = load(register)
        if not regFn then
            log(4, "CDC: register parse error " .. tostring(err))
        else
            local ok, perr = pcall(regFn)
            if not ok then log(4, perr) end
        end
    else
        rest = content
    end

    log(1, "CDC: parse content " .. programName)
    local codeFn, err2 = load(rest)
    if not codeFn then
        log(4, "CDC: content parse error " .. tostring(err2))
        self.requestCompleted[programName] = true
        return
    end

    self.codes[programName]            = codeFn
    self.requestCompleted[programName] = true
end

--- Interner Lader (einzelnes Modul anfordern).
---@param name string
function CodeDispatchClient:loadModule(name)
    if self.requestCompleted[name] then
        log(2, ('CDC: already loaded "%s"'):format(name))
        return
    end
    self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, name)
    log(0, ('CDC: broadcast GET_EEPROM "%s" on port %s'):format(name, self.port))
    self.requestCompleted[name] = false
end

--- Marker-Funktion (wird serverseitig erkannt).
function CodeDispatchClient:finished() end

--- Lädt registrierte Module nacheinander und wartet auf deren Empfang.
function CodeDispatchClient:loadAndWait()
    if #self.loadingRegistry == 0 then
        self:callAllLoadedFiles()
        return false
    end

    local nextName = self.loadingRegistry[1]
    while removeFrom(self.loadingRegistry, nextName) do end

    self:loadModule(nextName)
    while self.requestCompleted[nextName] == false do
        future.run()
    end

    self:loadAndWait()
end

--- Führt alle empfangenen Module in definierter Reihenfolge aus.
function CodeDispatchClient:callAllLoadedFiles()
    for i = 1, #self.codeOrder do
        local name = self.codeOrder[i]
        log(1, "CDC: run " .. name)
        local ok, err = pcall(self.codes[name])
        if not ok then log(4, err) end
    end
    self.codeOrder = {}
    self.codes     = {}
end

--- Fügt Namen in die Lade-Registrierung ein (dedupliziert, stabilisiert Reihenfolge).
---@param names string[]
function CodeDispatchClient:registerForLoading(names)
    -- invertierte Reihenfolge beibehalten (wie bei dir)
    local n = #names
    local out = {}
    for i = 1, n do out[i] = names[n - i + 1] end

    for i = 1, #out do
        local name = out[i]
        if self.requestCompleted[name] == nil then
            if indexOfIn(self.loadingRegistry, name) == nil then
                insertAt(self.loadingRegistry, 1, name)
                insertAt(self.codeOrder, 1, name)
                log(0, "CDC: registered " .. name)
            else
                while removeFrom(self.loadingRegistry, name) do end
                insertAt(self.loadingRegistry, 1, name)
                while removeFrom(self.codeOrder, name) do end
                insertAt(self.codeOrder, 1, name)
                log(0, "CDC: re-ordered " .. name)
            end
        end
    end
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchClient = CodeDispatchClient.new()




names = {}
CodeDispatchClient:registerForLoading(names)

CodeDispatchClient:loadAndWait()
