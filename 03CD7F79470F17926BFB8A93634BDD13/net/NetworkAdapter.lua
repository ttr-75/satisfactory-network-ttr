---@diagnostic disable: lowercase-global


-- Standardport (aus deiner Originaldatei)
---@type integer
NET_PORT_DEFAULT       = 8

--------------------------------------------------------------------------------
-- NetworkAdapter – dünne Convenience-Schicht um NetHub/nic
-- (Nur Typisierung/Kommentare; Verhalten bleibt unverändert)
--------------------------------------------------------------------------------

---@alias NIC any  -- FN-Component-Proxy der NetworkCard

---@class NetworkAdapter
---@field port integer
---@field name string
---@field ver  integer
---@field net  NIC
NetworkAdapter         = {}
NetworkAdapter.__index = NetworkAdapter

---@class NetworkAdapterOpts
---@field port integer|nil
---@field name string|nil
---@field ver  integer|nil
---@field nic  NIC|nil

---@param opts NetworkAdapterOpts|nil
---@return NetworkAdapter
function NetworkAdapter:new(opts)
    local self = setmetatable({}, NetworkAdapter)
    self.port  = (opts and opts.port) or NET_PORT_DEFAULT
    self.name  = (opts and opts.name) or "NetworkAdapter"
    self.ver   = (opts and opts.ver) or 1
    self.net   = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    return self
end

--- Registriert einen Paket-Handler bei NetHub auf self.port/self.name/self.ver
---@param fn fun(fromId:string, port:integer, cmd:string, a:any, b:any, c:any, d:any)
function NetworkAdapter:registerWith(fn)
    NetHub:register(self.port, self.name, self.ver, fn)
end

--- Direktnachricht an bestimmte NIC
---@param toId string
---@param cmd string
---@param ... any
function NetworkAdapter:send(toId, cmd, ...)
    self.net:send(toId, self.port, cmd, ...)
end

--- Broadcast auf dem Adapter-Port
---@param cmd string
---@param ... any
function NetworkAdapter:broadcast(cmd, ...)
    self.net:broadcast(self.port, cmd, ...)
end
