---@diagnostic disable: lowercase-global

local names = {
    "factoryRegistry/basics.lua",
    "factoryRegistry/FactoryInfo.lua",
    "factoryRegistry/FactoryRegistry.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------

---@class FactoryRegistryServer : NetworkAdapter
---@field reg FactoryRegistry
---@field last integer
FactoryRegistryServer = setmetatable({}, { __index = NetworkAdapter })
FactoryRegistryServer.__index = FactoryRegistryServer

---@param opts table|nil
---@return FactoryRegistryServer
function FactoryRegistryServer.new(opts)
    local self = NetworkAdapter.new(FactoryRegistryServer, opts)
    self.name = NET_NAME_FACTORY_REGISTRY_SERVER
    self.port = NET_PORT_FACTORY_REGISTRY
    self.ver = 1


    ---@type FactoryRegistry
    self.reg = FactoryRegistry:new() -- eigene, leere Registry für diesen Server
    ---@type integer
    self.last = 0


    -- Netzwerk-Handler für diesen Port registrieren
    self:registerWith(function(from, port, cmd, a, b)
        if port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY then
            self:onRegister(from, a)
            -- elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_UPDATE_FACTORY_IN_REGISTRY then
            --    self:onUpdateFactory(from, a)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_SHUT_DOWN_DUBLICATE_FACTORYREGISTRY then
            log(4, "UPSI....... I thought I'll be alone thx '" .. from .. "'")
            log(4, " ... Shutting down now")
            computer.stop()
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY then
            if from == self.net.id then
                log(0, "It's me, Mario")
            else
                log(4, "There is a second FactoryRsistry started: Now send kill signal to " .. from)
                self:send(from, NET_CMD_FACTORY_REGISTRY_SHUT_DOWN_DUBLICATE_FACTORYREGISTRY)
            end
            -- self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS then
            log(0, "Request for Address of " .. (a or "unknown"))
            if a then
                local fi = self.reg:getByName(a)
                if not fi then
                    log(4, "FactoryRegistryServer.getAddress:There is no factory called " .. a)
                    self:send(from, NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS_NO_FACTORY)
                else
                    log(0,
                        "FactoryRegistryServer.getAddress: Send address of " ..
                        a .. "'" .. fi.fCoreNetworkCard .. "' to " .. from)
                    self:send(from, NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS, fi.fCoreNetworkCard)
                end
            else
                log(4, "FactoryRegistryServer.getAddress: The name must been set " .. from)
            end
            -- self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE then
        else
            -- Unerwartete Kommandos sichtbar machen
            log(2, "FRC.rx: unknown cmd: " .. tostring(cmd))
        end
    end)

    -- Initial: Registry leeren und allen Clients Reset signalisieren
    self:broadcastRegistryReset()

    return self
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- Wird aufgerufen, wenn ein Client sich registriert.
---@param fromId string
---@param fName string
function FactoryRegistryServer:onRegister(fromId, fName)
    -- KEEP: Original-Server-Logik beim Register (FactoryInfo anlegen, speichern, …)
    local name = tostring(fName or "?")

    local fInfo = FactoryInfo:new()
    fInfo:setName(fName)
    fInfo:setCoreNetworkCard(fromId)
    self.reg:add(fInfo)
    -- ACK an den Absender zurück
    log(1, ('Server: Registered "%s" from %s'):format(fName, tostring(fromId)))
    self:send(fromId, NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY_ACK)
end

--[[
function FactoryRegistryServer:callForUpdates(factoryInfo)
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.reg:checkMinimum(factoryInfo) then
            local fromId = factoryInfo.fCoreNetworkCard
            local name = factoryInfo.fName
            log(0, "Net-FactoryRegistryServer: Send UpdateRequest for " .. name)
            self.net:send(fromId, self.port, NET_CMD_CALL_FACTORYS_FOR_UPDATES)
        else
        end
    end
end]]

function FactoryRegistryServer:clearRegistry()
    -- KEEP: falls du eine eigene Registry-Klasse hast, ruf hier deren clear/reset
    --self.reg = FactoryRegistry:new()
end

--- Registry-Reset broadcasten (und ggf. lokal leeren).
function FactoryRegistryServer:broadcastRegistryReset()
    self:clearRegistry()
    self:broadcast(NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY)
    log(2, "Server: broadcast registry reset")
end

-- ===== ÖFFENTLICH: Zugriff auf die Registry =====
--- Öffentliche API: Registry holen.
---@return FactoryRegistry
function FactoryRegistryServer:getRegistry()
    return self.reg
end

--[[
-- Server
local srv = FactoryRegistryServer.new{ port = 11 }
srv:initNetworkt()
srv:initRegisterListener()

-- Client
local cli = FactoryRegistryClient.new{ port = 11 }
cli:initNetworkt()
cli:initRegisterListener()
cli:register("Mehrzweckgeruest")

-- Loop
while true do
  event.pull(0.1)
  if not cli.registered then cli:register("Mehrzweckgeruest") end
end]]
