---@diagnostic disable: lowercase-global



local names = {
    "shared/helperlua",
    "shared/helper_comments.lua",
    "net/NetworkAdapter.lua",
    "net/NetHub.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------

---@class CodeDispatchServer : NetworkAdapter
---@field fsio FileIO
local CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

---@param opts table|nil
---@return CodeDispatchServer
function CodeDispatchServer.new(opts)
    -- generischer Basiskonstruktor → sofort ein CodeDispatchServer-Objekt
    local self = NetworkAdapter.new(CodeDispatchServer, opts)
    self.name  = NET_NAME_CODE_DISPATCH_SERVER
    self.port  = NET_PORT_CODE_DISPATCH
    self.ver   = 1

    self.fsio  = FileIO.new { root = "/srv" }
    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end
        if cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            self:onGetEEPROM(from, tostring(programName or ""))
        end
    end)

    return self
end

--=== Prototyp-Methoden =======================================================

--- Antwortet auf GET_EEPROM mit dem angeforderten Code.
---@param fromId string
---@param programName string
function CodeDispatchServer:onGetEEPROM(fromId, programName)
    local fallback = [[
        print("Invalid Net-Boot-Program: Program not found!")
        event.pull(5)
        computer.reset()
    ]]

    local ok, code = pcall(function()
        return strip_lua_comments_and_blank(self.fsio:readAllText(programName))
    end)

    local payload = (ok and code) or fallback
    log(1, ('CodeDispatchServer: request "%s" from "%s"'):format(programName, tostring(fromId)))
    self:send(fromId, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, payload)
end

--- Optionale Lauf-Schleife.
---@param timeout number|nil
function CodeDispatchServer:run()
    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_ALL)
    log(1, "CodeDispatchServer: broadcast resetAll")
    while true do
        future.run()
    end
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()

CodeDispatchServer:run(0.25)
