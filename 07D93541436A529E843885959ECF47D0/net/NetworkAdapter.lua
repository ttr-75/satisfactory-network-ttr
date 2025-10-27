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
