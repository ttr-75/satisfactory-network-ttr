-- NetHub.lua – EIN Listener, viele Services
NetHub = {
    nic = nil,
    listenerId = nil,
    services = {}, -- services[port] = { handler = fn, name="MEDIA", ver=1 }
}

function NetHub:init(nic)
    if self.listenerId then return end
    self.nic = nic or computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.nic, "NetHub: keine NIC gefunden")
    event.listen(self.nic)
    local f = event.filter { event = "NetworkMessage" }
    self.listenerId = event.registerListener(f, function(_, _, fromId, port, cmd, a, b, c, d)
        local svc = self.services[port]
        if not svc then return end
        local ok, err = pcall(svc.handler, fromId, port, cmd, a, b, c, d)
        if not ok then computer.log(4, "NetHub[" .. (svc.name or port) .. "] error: " .. tostring(err)) end
    end)
    computer.log(0, "NetHub: ready")
end

function NetHub:register(port, name, ver, handler)
    assert(type(port) == "number" and handler, "NetHub.register: ungültig")
    self.services[port] = { handler = handler, name = name, ver = ver or 1 }
    self.nic:open(port) -- Port EINMAL hier öffnen
end

function NetHub:close()
    if self.listenerId and event.removeListener then event.removeListener(self.listenerId) end
    self.listenerId = nil
    self.services = {}
end
