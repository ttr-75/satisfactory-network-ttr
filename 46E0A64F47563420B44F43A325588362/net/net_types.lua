---@meta
---@diagnostic disable: lowercase-global

-- Gemeinsame Aliase (nur für die IDE, haben keine Runtime-Wirkung)
---@alias NIC        any          -- FN NetworkCard Component-Proxy
---@alias NetPort    integer
---@alias NetName    string
---@alias NetVersion integer
---@alias NetCommand string

--- Signatur eines Netzwerk-Handlers (NetHub ruft so auf)
---@alias NetHandler fun(fromId: string, port: NetPort, cmd: NetCommand, a: any, b: any, c: any, d: any): any
