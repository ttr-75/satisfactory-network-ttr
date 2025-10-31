---@diagnostic disable: lowercase-global

local NetworkAdapter = require("net.NetworkAdapter")
local FileIO = require("file.FileIO")


-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------




---@class CodeDispatchServer : NetworkAdapter
---@field fsio FileIO
CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

---@param opts table|nil
---@return CodeDispatchServer
function CodeDispatchServer.new(opts)
    -- generischer Basiskonstruktor → sofort ein CodeDispatchServer-Objekt
    local self = NetworkAdapter.new(CodeDispatchServer, opts)
    self.name  = NET_NAME_CODE_DISPATCH_SERVER
    self.port  = NET_PORT_CODE_DISPATCH
    self.ver   = 1

    self.fsio  = opts and opts.fsio or FileIO.new { root = "/srv" }

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
    log(1, ('CodeDispatchServer: request "%s" from "%s"'):format(programName, tostring(fromId)))

    local ok, code = pcall(function()
        local ok, content, err = self.fsio:readAllText(programName)
        if not ok then
            log(3, "Failed to read " .. programName, err)
            return
        end
       -- content = replace_language_chunk(content, TTR_FIN_Config.language)
       -- content:gsub("[-LANGUAGE-].lua", "_" .. TTR_FIN_Config.language)
        return content
    end)
    if ok == false then
        log(3, ('CodeDispatchServer: Unable to load "%s" sending fallback'):format(programName))
    end
    local payload = (ok and code) or fallback
    self:send(fromId, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, payload)
end

--- Optionale Lauf-Schleife.
function CodeDispatchServer:run()
    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_ALL)
    log(1, "CodeDispatchServer: broadcast resetAll")
    while true do
        future.run()
    end
end

