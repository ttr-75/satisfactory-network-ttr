MyClient = {
    port = 8,
    netBootInitDone = false,
}

function MyClient:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function MyClient:initNetBoot()
    if self.netBootInitDone then
        return
    end
    self.net = computer.getPCIDevices(classes.NetworkCard)[1]
    if not self.net then
        error("Net-Boot: Failed to Start: No Network Card available!")
    end
    self.net:open(self.port)
    event.listen(self.net)

    -- Wrap event.pull() and filter Net-Boot messages
   --[[local og_event_pull = event.pull
    function event.pull(timeout)
        local args = { og_event_pull(timeout) }
        local e, _, s, p, cmd, programName = table.unpack(args)
        if e == "NetworkMessage" and p == self.port then
            if cmd == "reset" and programName == self.init then
                computer.log(2, "Net-Boot: Received reset command from Server \"" .. s .. "\"")
                if netBootReset then
                    pcall(netBootReset)
                end
                computer.reset()
            end
        end
        return table.unpack(args)
    end]] 

    self.netBootInitDone = true
end

function MyClient:loadFromNetBoot(name)
    if not self.netBootInitDone then
        self:initNetBoot()
    end
    self.net:broadcast(self.port, "getEEPROM", name)
    local program = nil
    while program == nil do
        local e, _, s, p, cmd, programName, code = event.pull(30)
        if e == "NetworkMessage" and p == self.port and cmd == "setEEPROM" and programName == name then
            print("Net-Boot: Got Code for Program \"" .. name .. "\" from Server \"" .. s .. "\"")
            return code
        elseif e == nil then
            computer.log(3, "Net-Boot: Request Timeout reached! Retry...")
            break
        end
    end
    return nil
end

function MyClient:loadCode(name)
    local content = nil

    if not content then
        computer.log(0, "Loading " .. name .. " from net boot")
        content = self:loadFromNetBoot(name)
    end

    return content
end

function MyClient:parseModule(name)
    local content = self:loadCode(name)
    if content then
        computer.log(0, "Parsing loaded content")
        local code, error = load(content)
        if not code then
            computer.log(4, "Failed to parse " .. name .. ": " .. tostring(error))
            event.pull(2)
            computer.reset()
        end
        return code
    else
        computer.log(3, "Could not load " .. name .. ": Not found.")
        return nil
    end
end

function MyClient:loadModule(name)
    computer.log(0, "Loading " .. name .. " through the bootloader")
    local code = self:parseModule(name)
    if code then
        -- We don't really expect this to return
        computer.log(0, "Starting " .. name)
        local success, error = pcall(code)
        if not success then
            computer.log(3, error)
            event.pull(2)
            computer.reset()
        end
    else
        computer.log(4, "Failed to load module " .. name)
    end
end

function MyClient:close()
    self.net:close()
end

c = MyClient:new()

