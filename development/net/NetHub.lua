---@diagnostic disable: lowercase-global

local Helper_log = require("shared.helper_log")
local log = Helper_log.log

local helper_safe_listern = require("shared.helper_safe_listener")
local safe_listener = helper_safe_listern.safe_listener

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
