NET_CMD_RESET_ALL = "resetAll"

--[[ Net-Boot Server ]] --

-- Configuration
local netBootPort = 8
local netBootPrograms = {}
netBootPrograms["station2.lua"] = [[]]
netBootPrograms["test2.lua"] = [[]]
netBootPrograms["helper.lua"] = [[]]
netBootPrograms["items.lua"] = [[]]
netBootPrograms["graphics.lua"] = [[]]
netBootPrograms["fabricBillboard.lua"] = [[]]
netBootPrograms["serializer.lua"] = [[]]
netBootPrograms["fabricInfo.lua"] = [[]]
netBootPrograms["fabricRegistry.lua"] = [[]]
netBootPrograms["fabricDashboard.lua"] = [[]]
----netBootPrograms["testFolder/testFile.lua"] = [[]]
--netBootPrograms["testFolder/testFile2.lua"] = [[]]

bootloader2 = {
    --init = nil,
    --port = 8,
    srv = "/srv",
    storageMounted = false,
}

local fs = filesystem

function bootloader2:mountStorage(searchFile)
    if self.storageMounted then
        return
    end

    fs.initFileSystem("/dev")

    local devs = fs.children("/dev")
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        fs.mount(drive, self.srv)
        if searchFile == nil or self:programExists(searchFile) then
            self.storageMounted = true
            return true
        end
        fs.unmount(drive)
    end

    return false
end

function bootloader2:programExists(name)
    local path = filesystem.path(self.srv, name)
    return filesystem.exists(path) and filesystem.isFile(path)
end

function bootloader2:loadFromStorage(name)
    if not self.storageMounted then
        self:mountStorage()
    end

    if not self:programExists(name) then
        return nil
    end

    fd = fs.open("/srv/" .. name, "r")
    content = ""
    while true do
        chunk = fd:read(1024)
        if chunk == nil or #chunk == 0 then
            break
        end
        content = content .. chunk
    end
    return content
end

function bootloader2:loadCode(name)
    local content = netBootPrograms[name]

    if is_longer_than(content, 10) then
        computer.log(1, "Loading " .. name .. " from cache")
        return content
    end
    --computer.log(1, content)
    if not self.storageMounted then
        computer.log(0, "Mounting storage")
        self:mountStorage()
    end


    if self.storageMounted then
        log(1, "Loading " .. name .. " from storage")
        content = self:loadFromStorage(name)
    else
        log(2, "No storage available")
        return nil
    end

    if not content then
        --return("Net-Boot: Failed to Start: No Network Card available!")
        --    computer.log(0, "Loading " .. name .. " from net boot")
        --    content = self:loadFromNetBoot(name)
    end
    netBootPrograms[name] = content
    return content
end


local netBootFallbackProgram = [[
    print("Invalid Net-Boot-Program: Program not found!")
    event.pull(5)
    computer.reset()
]]

-- Setup Network
local net = computer.getPCIDevices(classes.NetworkCard)[1]
if not net then
    error("Failed to start Net-Boot-Server: No network card found!")
end
net:open(netBootPort)
event.listen(net)

-- Reset all  Programs
    net:broadcast(netBootPort, NET_CMD_RESET_ALL)
    print("Broadcasted reset for All Netdevices")


-- Serve Net-Boot
while true do
    local e, _, s, p, cmd, arg1 = event.pull()
    if e == "NetworkMessage" and p == netBootPort then
        if cmd == "getEEPROM" then
            print("Program Request for \"" .. arg1 .. "\" from \"" .. s .. "\"")
            local code = bootloader2:loadCode(arg1) or netBootFallbackProgram; --netBootPrograms[arg1] or netBootFallbackProgram
            net:send(s, netBootPort, "setEEPROM", arg1, code)
        end
    end
end
