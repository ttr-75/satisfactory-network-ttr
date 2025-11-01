---@diagnostic disable: lowercase-global


-- Standardport (aus deiner Originaldatei)
---@type integer
NET_PORT_DEFAULT       = 8

--------------------------------------------------------------------------------
-- NetworkAdapter – Typ-Annotationen (EmmyLua/LuaLS)
-- Hinweis: Diese Datei verändert KEIN Laufzeitverhalten – nur Kommentare.
-- Erwartet, dass NetHub global verfügbar ist (mit NetHub:register/init).
--------------------------------------------------------------------------------

---@class NetworkAdapter
local NetworkAdapter   = {}
NetworkAdapter.__index = NetworkAdapter

---@class NetworkAdapterOpts
---@generic T: NetworkAdapter
---@param self T
---@param opts NetworkAdapterOpts|nil
---@return T
function NetworkAdapter:new(opts)
    local class = self
    local o = setmetatable({}, {
        __index = function(_, k)
            local v = class[k]
            if v ~= nil then return v end
            return NetworkAdapter[k]
        end
    })
    o.port = (opts and opts.port) or NET_PORT_DEFAULT
    o.name = (opts and opts.name) or "NetworkAdapter"
    o.ver  = (opts and opts.ver)  or 1
    o.net  = (opts and opts.nic)  or computer.getPCIDevices(classes.NetworkCard)[1]
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

-- Erwartete globale Konstante (nur Typ-Hinweis; keine Zuweisung hier):
---@type NetPort
NET_PORT_DEFAULT = NET_PORT_DEFAULT

return NetworkAdapter
