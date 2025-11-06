-- local name = "net.codeDispatch.starter.resetServer"


require("config")
require("net.codeDispatch.basics")
require("net.NetworkAdapter")
local log = require("shared.helper_log").log

CodeDispatchRestartServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchRestartServer.__index = CodeDispatchRestartServer

---@param opts table|nil
---@return CodeDispatchRestartServer
function CodeDispatchRestartServer.new(opts)
    -- generischer Basiskonstruktor → sofort ein CodeDispatchServer-Objekt
    local self = NetworkAdapter.new(CodeDispatchRestartServer, opts)
    self.name  = NET_NAME_CODE_DISPATCH_SERVER
    self.port  = NET_PORT_CODE_DISPATCH
    self.ver   = 1

    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)

    end)

    log(2, "CodeDispatchRestartServer: broadcasting resetServer command")
    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_SERVER)

    return self
end

local c = CodeDispatchRestartServer.new()

