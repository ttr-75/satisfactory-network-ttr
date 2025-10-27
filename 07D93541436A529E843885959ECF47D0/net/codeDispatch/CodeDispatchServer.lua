-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------


CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

function CodeDispatchServer.new(opts)
    local self = NetworkAdapter:new(opts)
    self.name = NET_NAME_CODE_DISPATCH_SERVER
    self.port = NET_PORT_CODE_DISPATCH
    self.ver = 1

    self.fsio = FileIO.new { root = "/srv" }
    self = setmetatable(self, CodeDispatchServer)

    local netBootFallbackProgram = [[
    print("Invalid Net-Boot-Program: Program not found!")
    event.pull(5)
    computer.reset()
]]

    local function loadCode(programName)
        return self.fsio:readAllText(programName)
    end

    -- Private functions--
    self:registerWith(function(from, port, cmd, programName, code)
        if port == self.port and cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            log(1, "Program Request for \"" .. programName .. "\" from \"" .. from .. "\"")
            local code = loadCode(programName) or netBootFallbackProgram; --netBootPrograms[arg1] or netBootFallbackProgram
            self.net:send(from, self.port, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, code)
        end
    end)

    function self:run(timeout)
        while true do
            event.pull(timeout)
        end
    end

    return self
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()


--[[
CodeDispatchClient:loadModule("helper.lua")
CodeDispatchClient:loadModule("serializer.lua")
CodeDispatchClient:loadModule("testFolder/testFile.lua")

while not CodeDispatchClient:ready() do
	future.run()
end
]]
