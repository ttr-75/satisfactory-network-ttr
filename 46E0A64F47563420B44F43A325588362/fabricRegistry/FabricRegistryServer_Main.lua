---@diagnostic disable: lowercase-global

local names = {
    "fabricRegistry/basics.lua",
    "fabricRegistry/FabricInfo.lua",
    "fabricRegistry/FabricRegistry.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------

---@class FabricRegistryServer : NetworkAdapter
---@field reg FabricRegistry
---@field last integer
FabricRegistryServer = setmetatable({}, { __index = NetworkAdapter })
FabricRegistryServer.__index = FabricRegistryServer

---@param opts table|nil
---@return FabricRegistryServer
function FabricRegistryServer.new(opts)
    local self = NetworkAdapter.new(FabricRegistryServer, opts)
    self.name = NET_NAME_FABRIC_REGISTRY_SERVER
    self.port = NET_PORT_FABRIC_REGISTRY
    self.ver = 1


    ---@type FabricRegistry
    self.reg = FabricRegistry:new() -- eigene, leere Registry für diesen Server
    ---@type integer
    self.last = 0


    -- Netzwerk-Handler für diesen Port registrieren
    self:registerWith(function(from, port, cmd, a, b)
        if port == self.port and cmd == NET_CMD_FABRIC_REGISTER then
            self:onRegister(from, a)
        elseif port == self.port and cmd == NET_CMD_UPDATE_FABRIC_IN_REGISTRY then
            self:onUpdateFabric(from, a)
        elseif port == self.port and cmd == NET_CMD_SHUT_DOWN_DUBLICATE_FABRICREGISTRY then
            log(4, "UPSI....... I thought I'll be alone thx '" .. from .. "'")
            log(4, " ... Shutting down now")
            computer.stop()
        elseif port == self.port and cmd == NET_CMD_RESET_FABRICREGISTRY then
            if from == self.net.id then
                log(0, "It's me, Mario")
            else
                log(4, "There is a second FabricRsistry started: Now send kill signal to " .. from)
                self:send(from, NET_CMD_SHUT_DOWN_DUBLICATE_FABRICREGISTRY)
            end
            -- self:onRegistryReset(from)
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
function FabricRegistryServer:onRegister(fromId, fName)
    -- KEEP: Original-Server-Logik beim Register (FabricInfo anlegen, speichern, …)
    local name = tostring(fName or "?")

    local fInfo = FabricInfo:new()
    fInfo:setName(fName)
    fInfo:setCoreNetworkCard(fromId)
    self.reg:add(fInfo)
    -- ACK an den Absender zurück
    log(1, ('Server: Registered "%s" from %s'):format(fName, tostring(fromId)))
    self:send(fromId, NET_CMD_FABRIC_REGISTER_ACK)
end

--- Client schickt ein Update seiner FabricInfo (als JSON).
---@param fromId string
---@param fabricInfoS string
function FabricRegistryServer:onUpdateFabric(fromId, fabricInfoS)
    -- KEEP: falls Client etwas am Server aktualisiert
    log(0, ('Net-FabricRegistryServer: Received Update from "%s"'):format(fromId))
    local J = JSON.new { indent = 2, sort_keys = true }
    local o = J:decode(fabricInfoS)
    --print(arg1)
    --local id = o.fCoreNetworkCard
    ---@cast o FabricInfo
    self.reg:update(o)
end

--- Fragt zyklisch (1/s) alle bekannten Fabriken nach Updates.
function FabricRegistryServer:callForUpdates()
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        local fabrics = self.reg:getAll()
        for name2, fabric in pairs(fabrics) do
            if self.reg:checkMinimum(fabric) then
                local fromId = fabric.fCoreNetworkCard or ""
                local name = fabric.fName
                log(0, "Net-FabricRegistryServer: Send UpdateRequest for " .. name)
                self:send(fromId, NET_CMD_CALL_FABRICS_FOR_UPDATES)
            else
            end
        end
    end
end

--[[
function FabricRegistryServer:callForUpdates(fabricInfo)
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.reg:checkMinimum(fabricInfo) then
            local fromId = fabricInfo.fCoreNetworkCard
            local name = fabricInfo.fName
            log(0, "Net-FabricRegistryServer: Send UpdateRequest for " .. name)
            self.net:send(fromId, self.port, NET_CMD_CALL_FABRICS_FOR_UPDATES)
        else
        end
    end
end]]

function FabricRegistryServer:clearRegistry()
    -- KEEP: falls du eine eigene Registry-Klasse hast, ruf hier deren clear/reset
    --self.reg = FabricRegistry:new()
end

--- Registry-Reset broadcasten (und ggf. lokal leeren).
function FabricRegistryServer:broadcastRegistryReset()
    self:clearRegistry()
    self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    log(2, "Server: broadcast registry reset")
end

-- ===== ÖFFENTLICH: Zugriff auf die Registry =====
--- Öffentliche API: Registry holen.
---@return FabricRegistry
function FabricRegistryServer:getRegistry()
    return self.reg
end

--[[
-- Server
local srv = FabricRegistryServer.new{ port = 11 }
srv:initNetworkt()
srv:initRegisterListener()

-- Client
local cli = FabricRegistryClient.new{ port = 11 }
cli:initNetworkt()
cli:initRegisterListener()
cli:register("Mehrzweckgeruest")

-- Loop
while true do
  event.pull(0.1)
  if not cli.registered then cli:register("Mehrzweckgeruest") end
end]]
