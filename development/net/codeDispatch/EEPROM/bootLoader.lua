---gpt ignore
---@diagnostic disable: duplicate-doc-field, duplicate-set-field, redefined-local, lowercase-global


-- Set Loglevel globaly in config.lua or here localy
--LOG_MIN = 0

-- Set Start script
local name = nil

----------------------------------------------------------------
-- Custom Input
----------------------------------------------------------------

yourInput = nil


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
    if level >= (LOG_MIN or TTR_FIN_Config and TTR_FIN_Config.LOG_LEVEL or 0) then
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
    if not self.nic then
        return false, { code = "NO_NIC", message = "NetHub: keine NIC gefunden" }
    end
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

--- Hebt die Registrierung eines Ports auf und schließt ihn auf der NIC.
---@param port NetPort
---@param name NetName|nil   -- optional zur Plausibilitätsprüfung
---@param ver  NetVersion|nil -- optional zur Plausibilitätsprüfung
---@return boolean, table|nil -- true, nil bei Erfolg; andernfalls false/nil, {code=, message=}
function NetHub:unregister(port, name, ver)
    if type(port) ~= "number" then
        return false, { code = "BAD_PORT", message = "NetHub.unregister: port must be number" }
    end
    local svc = self.services[port]
    if not svc then
        return false, { code = "NOT_FOUND", message = ("no service registered on port %s"):format(tostring(port)) }
    end

    -- optionale Plausibilitätschecks (nur wenn name/ver übergeben wurden)
    if name ~= nil and svc.name ~= name then
        return false, {
            code = "NAME_MISMATCH",
            message = ("service name mismatch on port %s (have=%s, want=%s)")
                :format(port, tostring(svc.name), tostring(name))
        }
    end
    if ver ~= nil and svc.ver ~= ver then
        return false, {
            code = "VER_MISMATCH",
            message = ("service version mismatch on port %s (have=%s, want=%s)")
                :format(port, tostring(svc.ver), tostring(ver))
        }
    end

    -- Port schließen (try-catch, falls NIC fehlt/geschlossen)
    pcall(function()
        if self.nic and self.nic.close then
            self.nic:close(port)
        end
    end)

    self.services[port] = nil
    log(0, ("NetHub: unregistered port %s"):format(tostring(port)))

    -- Wenn keine Services mehr registriert: Listener sauber abbauen
    if next(self.services) == nil then
        if self.listenerId and event.removeListener then
            pcall(function() event.removeListener(self.listenerId) end)
        end
        self.listenerId = nil
        log(0, "NetHub: no services remaining; listener stopped")
    end

    return true
end

--- Beendet den Listener und leert die Service-Tabelle, schließt alle Ports.
function NetHub:close()
    -- Listener abbauen
    if self.listenerId and event.removeListener then
        pcall(function() event.removeListener(self.listenerId) end)
    end
    self.listenerId = nil

    -- Alle Ports schließen (best-effort)
    if self.nic and self.nic.close then
        for port, _ in pairs(self.services) do
            pcall(function() self.nic:close(port) end)
        end
    end

    self.services = {}
    log(0, "NetHub: closed")
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
-- Konstruktor: Instanz kann Methoden vom Child *und* vom NetworkAdapter finden
function NetworkAdapter:new(opts)
    local class = self
    local o     = setmetatable({}, {
        __index = function(_, k)
            local v = class[k]
            if v ~= nil then return v end
            return NetworkAdapter[k]
        end
    })
    o.port      = (opts and opts.port) or NET_PORT_DEFAULT
    o.name      = (opts and opts.name) or "NetworkAdapter"
    o.ver       = (opts and opts.ver) or 1
    o.net       = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
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

--- Einheitliches Fehlerobjekt
---@param code string @Kurzcode
---@param message string @Beschreibung
function NetworkAdapter:error(code, message)
    return { code = code, message = message }
end

--- Prüft, ob eine NIC vorhanden ist (statt später zu crashen)
---@return boolean, table|nil
function NetworkAdapter:ensureNet()
    if self.net then return true end
    return false, self:error("NO_NIC", "No network card (self.net == nil)")
end

--- “Weiche” Variante von send()
---@param toId string
---@param cmd NetCommand
---@return boolean, table|nil
function NetworkAdapter:trySend(toId, cmd, ...)
    local ok, err = self:ensureNet()
    if not ok then return false, err end

    local args = table.pack(...)
    local sOK, sErr = pcall(function()
        self.net:send(self.port and toId, self.port, cmd, table.unpack(args, 1, args.n))
        --                      ^ optional: sanity-checks kannst du weglassen
    end)
    if not sOK then return false, self:error("SEND_FAIL", tostring(sErr)) end
    return true
end

--- “Weiche” Variante von broadcast()
---@param cmd NetCommand
---@return boolean, table|nil
function NetworkAdapter:tryBroadcast(cmd, ...)
    local ok, err = self:ensureNet()
    if not ok then return false, err end

    local args = table.pack(...)
    local bOK, bErr = pcall(function()
        self.net:broadcast(self.port, cmd, table.unpack(args, 1, args.n))
    end)
    if not bOK then return false, self:error("BCAST_FAIL", tostring(bErr)) end
    return true
end

--- Adapter schliessen (optional)
function NetworkAdapter:close(reason)
    self._closed = reason or true
    if NetHub and NetHub.unregister then
        pcall(function() NetHub:unregister(self.port, self.name, self.ver) end)
    end
end

function NetworkAdapter:isClosed()
    return self._closed and true or false
end

---@diagnostic disable: lowercase-global

-------------------------------------------------------------------------------
--- CodeDispatchClient – mit in-Memory `require`,
-------------------------------------------------------------------------------

---@class CodeDispatchClient : NetworkAdapter
---@field requestCompleted table<string, boolean>   -- Name -> ob Code empfangen/geparsed
---@field loadingRegistry  string[]                 -- Warteschlange der anzufordernden Dateien
---@field codes            table<string, string>    -- Name -> (Rest-)Code als String
---@field codeOrder        string[]                 -- Ausführungsreihenfolge (wie gehabt)
---@field modules          table<string, any>       -- Name -> ausgewertetes Modul (Cache)
---@field loading          table<string, boolean>   -- Name -> "wird gerade geladen" (Zyklus-Schutz)
---@field _onReset         (fun()|nil)              -- optionaler Reset-Callback
CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

-- ========= Konstruktor =======================================================

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

    -- Neu für require:
    self.modules          = {}
    self.loading          = {}
    self.startLog         = false

    self._onReset         = nil

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
            event.pull(math.random() * 5000)
            computer.reset()
        end
    end)

    return self
end

-- ========= Utilities =========================================================
--- mark client fatal + store error (uniform shape)
function CodeDispatchClient:fail(msg, code)
    self._fatal = true
    self._error = { code = code or "FATAL", message = tostring(msg) }
    log(4, ("CDC.fail[%s]: %s"):format(self._error.code, self._error.message))
    return nil
end

function CodeDispatchClient:isFatal()
    return self._fatal == true
end

function CodeDispatchClient:getError()
    return self._error
end

--- best-effort close (uses NetworkAdapter:close -> NetHub:unregister)
function CodeDispatchClient:close(reason)
    pcall(function() NetworkAdapter.close(self, reason or "client-close") end)
end

---@param name string
---@return boolean
function CodeDispatchClient:existsInRegistry(name)
    for _, n in pairs(self.loadingRegistry) do
        if n == name then return true end
    end
    return false
end

---@param a string[]
---@param value string
---@return integer|nil
function CodeDispatchClient:indexOfIn(a, value)
    for i = 1, #a do if a[i] == value then return i end end
    return nil
end

---@param a string[]
---@param value string
---@return boolean
function CodeDispatchClient:removeFrom(a, value)
    local i = self:indexOfIn(a, value)
    if i then
        table.remove(a, i); return true
    end
    return false
end

---@param a string[]
---@param i integer|nil
---@param v string
---@return integer
function CodeDispatchClient:insertAt(a, i, v)
    local n = #a
    if i == nil then i = n + 1 end
    if i < 1 then i = 1 end
    if i > n + 1 then i = n + 1 end
    table.insert(a, i, v)
    return i
end

--- Wandelt beliebige require-Schreibweise in eine kanonische Form um:
---  "shared.helper"        -> "shared/helper.lua"
---  "shared/helper"        -> "shared/helper.lua"
---  "shared/helper.lua"    -> "shared/helper.lua"
---@param name string
---@return string
local function _canon(name)
    local s = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return s end

    -- Windows-Backslashes tolerieren
    s = s:gsub("\\", "/")

    -- Falls bereits Slash-Pfade genutzt werden:
    if s:find("/", 1, true) then
        if not s:match("%.lua$") then
            s = s .. ".lua"
        end
        return s
    end

    -- Dot-Notation ohne Slash
    if s:match("%.lua$") then
        -- ".lua" wegschneiden, NUR davor Punkte -> Slashes
        local base = s:sub(1, #s - 4) -- alles vor ".lua"
        base = base:gsub("%.", "/")   -- Punkte zu Slashes
        return base .. ".lua"
    else
        -- Keine Endung -> Punkte zu Slashes, dann ".lua" anhängen
        return (s:gsub("%.", "/")) .. ".lua"
    end
end

-- Maskiert alle Lua-Pattern-Sonderzeichen in einem Literal
local function escape_lua_pattern(s)
    return (s:gsub("(%W)", "%%%1")) -- alles, was nicht %w ist, mit % escapen
end

local function replace_language_chunk(content, language)
    local literal = "[-LANGUAGE-]"
    language = "_" .. language .. ""
    local pattern = escape_lua_pattern(literal)

    -- Falls language '%' enthalten könnte, für gsub-Replacement escapen:
    language = language:gsub("%%", "%%%%")
    return (content:gsub(pattern, language))
end

-- ========= Öffentliche API ===================================================

---@param fn fun()|nil
function CodeDispatchClient:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

---@param programName string
---@param content string
function CodeDispatchClient:onSetEEPROM(programName, content)
    self:parseModule(programName, content)
end

--- Parst Register-Teil (optional) und speichert den ausführbaren Rest **als String**.
---@param name string
---@param content string|nil
function CodeDispatchClient:parseModule(name, content)
    local key = _canon(name)
    if not content then
        log(3, "CodeDispatchClient:Could not load " .. tostring(key) .. ": Not found.")
        return
    end

    -- WICHTIG: String speichern, nicht (nur) Funktion – wir brauchen eine eigene Env für require.
    self.codes[key]            = tostring(content or "")
    self.requestCompleted[key] = true
    log(1, "CDC: stored chunk for " .. tostring(key))
end

--- Fordert ein einzelnes Modul an (wenn noch nicht empfangen).
---@param name string
function CodeDispatchClient:loadModule(name)
    local key = _canon(name)
    if self.requestCompleted[key] then
        log(2, ('CDC: already loaded "%s"'):format(key))
        return
    end
    self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, key)
    log(0, ('CDC: broadcast GET_EEPROM "%s" on port %s'):format(key, self.port))
    self.requestCompleted[key] = false
end

--- Lädt registrierte Module nacheinander und wartet auf deren Empfang (wie gehabt).
---@return boolean|nil false wenn sofort alles ausgeführt wurde
function CodeDispatchClient:loadAndWait()
    if #self.loadingRegistry == 0 then
        self:callAllLoadedFiles()
        return false
    end

    local nextName = self.loadingRegistry[1]
    while self:removeFrom(self.loadingRegistry, nextName) do end

    self:loadModule(nextName)
    while self.requestCompleted[nextName] == false do
        future.run()
    end

    self:loadAndWait()
end

--- Führt alle gespeicherten Module in definierter Reihenfolge aus
--- (jetzt via _require, damit Rückgabewerte/Namespaces landen).
function CodeDispatchClient:callAllLoadedFiles()
    for i = 1, #self.codeOrder do
        local name = self.codeOrder[i]
        log(1, "CDC: run " .. tostring(name))
        local ok, err = pcall(function() self:_require(name) end)
        if not ok then log(4, err) end
    end
    self.codeOrder = {}
    self.codes     = {}
end

--- Interner Registrierer (wie zuvor).
---@param name string
function CodeDispatchClient:_register(name)
    local key = _canon(name)
    if self.requestCompleted[key] == nil then
        if not self:existsInRegistry(key) then
            log(0, "CDC: register " .. tostring(key))
            self:insertAt(self.loadingRegistry, 1, key)
            self:insertAt(self.codeOrder, 1, key)
        else
            log(0, "CDC: re-register " .. tostring(key))
            while self:removeFrom(self.loadingRegistry, key) do end
            self:insertAt(self.loadingRegistry, 1, key)
        end
        while self:removeFrom(self.codeOrder, key) do end
        self:insertAt(self.codeOrder, 1, key)
    end
end

---@param names string[]
function CodeDispatchClient:registerForLoading(names)
    local n, out = #names, {}
    for i = 1, n do out[i] = names[n - i + 1] end -- reverse
    for i = 1, #out do self:_register(out[i]) end
end

--- Komfort: ein Modul registrieren und direkt laden
---@param name string
function CodeDispatchClient:startClient(name)
    assert(name, "CodeDispatchClient:startClient(name): name can not be nil")
    self:registerForLoading({ name })
    self:loadAndWait()
end

-- ========= In-Memory `require` ==============================================

--- Führt ein Modul (String) in eigener Env mit lokalem `require` aus und cached das Ergebnis.
---@param name string
---@return any module
function CodeDispatchClient:_executeModule(name)
    local key = _canon(name)
    local chunk = self.codes[key]
    if not chunk then
        error("CDC: no code for module " .. tostring(key))
    end

    if self.loading[key] then
        error("CDC: cyclic require: " .. tostring(key))
    end
    self.loading[key] = true

    local env = setmetatable({
        require = function(dep) return self:_require(dep) end,
        exports = {}, -- Fallback, falls Modul nichts returned
    }, { __index = _G, __newindex = _G })

    -- TODO Staabiler machen: Language-Chunks ersetzen
    if TTR_FIN_Config and TTR_FIN_Config.language then
        chunk = replace_language_chunk(chunk, TTR_FIN_Config.language)
    end

    local fn, perr = load(chunk, key, "t", env)
    if not fn then
        self.loading[key] = nil
        log(4, "CDC: load env error for " .. tostring(key) .. ": " .. tostring(perr))
        return self:fail("module load error: " .. tostring(perr), "MODULE_LOAD")
    end

    local ok, ret = xpcall(fn, debug.traceback)
    self.loading[key] = nil
    if not ok then
        log(4, "CDC: runtime error in " .. tostring(key) .. ": " .. tostring(ret))
        return self:fail("module runtime error: " .. tostring(ret), "MODULE_RUNTIME")
    end
    local mod = (ret ~= nil) and ret or (next(env.exports) and env.exports) or true
    self.modules[key] = mod


    if TTR_FIN_Config and self.startLog ~= true then
        log(2, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
        log(0, "Laguage set to " .. TTR_FIN_Config.language)
        self.startLog = true
    end

    return mod
end

--- In-Memory-Require mit Nachladen/Warten/Cache
---@param name string
---@return any module
function CodeDispatchClient:_require(name)
    local key = _canon(name)
    if self.modules[key] ~= nil then
        return self.modules[key]
    end

    -- Code bereits vorhanden?
    if not self.codes[key] then
        -- Nachfordern & warten – das erlaubt require() *innerhalb* von Modulen
        self:loadModule(key)
        while self.requestCompleted[key] == false do
            future.run()
        end
        if not self.codes[key] then
            error("require('" .. tostring(key) .. "'): no code after fetch")
        end
    end

    return self:_executeModule(key)
end

--------------------------------------------------------------------------------
--- Starter-Skript
--- ---------------------------------------------------------------------------
local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchClient = CodeDispatchClient.new()

local START_TARGET = name or "test/test.lua"

local function start_with_retry()
    local attempt = 0
    while true do
        attempt = attempt + 1

        -- fresh client per attempt to ensure clean state
        CodeDispatchClient = CodeDispatchClient.new()

        local started_ok, start_err = xpcall(function()
            CodeDispatchClient:startClient(START_TARGET)
        end, debug.traceback)

        if started_ok then
            log(0, ("Bootloader: started '%s' successfully after %d attempt(s)")
                :format(START_TARGET, attempt))

            -- supervise: as long as client isn't fatal, keep idling here
            while true do
                event.pull(0.5)
                if CodeDispatchClient:isFatal() then
                    local e = CodeDispatchClient:getError()
                    log(4, ("Bootloader: client went fatal [%s] %s – reinitializing")
                        :format(e and e.code or "?", e and e.message or "unknown"))

                    -- best-effort close; unregisters adapter + cleans ports
                    pcall(function() CodeDispatchClient:close("fatal") end)

                    -- break to outer while → new attempt
                    event.pull(5.0)
                    break
                end
            end
        else
            -- initial start failed (e.g., immediate syntax error) → retry after delay
            log(3, ("Bootloader: start of '%s' failed (attempt %d): %s")
                :format(START_TARGET, attempt, tostring(start_err)))
            event.pull(5.0)
        end
        -- on loop continue: we try again with a fresh instance
    end
end

event.pull(math.random(5000)/1000)

start_with_retry()

log(2, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
log(0, "Laguage set to " .. TTR_FIN_Config.language)
