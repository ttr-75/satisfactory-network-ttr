local names = {
    "fabricRegistry/basics.lua",
    "fabricRegistry/FabricRegistry.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------
FabricRegistryServer = setmetatable({}, { __index = NetworkAdapter })
FabricRegistryServer.__index = FabricRegistryServer

function FabricRegistryServer.new(opts)
    local self = NetworkAdapter:new(opts)
    self.name = NET_NAME_FABRIC_REGISTRY_SERVER
    self.port = NET_PORT_FABRIC_REGISTRY
    self.ver = 1
    self = setmetatable(self, FabricRegistryServer)
    self.reg = FabricRegistry:new() -- eigene, leere Registry für diesen Server
    self.last = 0

    -- deine bestehende Registry-Struktur weiter verwenden:
    --self.reg = {} -- id -> { name=..., fromId=..., ts=... }  (ODER ersetze durch dein FabricRegistry-Objekt)
    -- === HOOKS: hier deine Original-Logik einfügen ===
    function self:onRegister(fromId, fName)
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

    -- function self:onRegistryReset(fromId)
    --    -- KEEP: wie du beim Reset verfahren willst (Registry leeren, etc.)
    --    self:clearRegistry()
    --     log(0, "Server: registry cleared (by " .. tostring(fromId) .. ")")
    -- optional Clients informieren, damit sie neu registrieren:
    --     self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    -- end

    -- function self:onGetFabricUpdate(fromId, payloadA, payloadB)
    -- KEEP: wenn der Client Updates anfragt → antworte mit deinen Daten
    -- Beispiel: self:send(fromId, NET_CMD_UPDATE_FABRIC, <dein JSON/String/…>)
    --end

    function self:onUpdateFabric(fromId, fabricInfoS)
        -- KEEP: falls Client etwas am Server aktualisiert
        log(0, ('Net-FabricRegistryServer: Received Update from "%s"'):format(fromId))
        local J = JSON.new { indent = 2, sort_keys = true }
        local o = J:decode(fabricInfoS)
        --print(arg1)
        --local id = o.fCoreNetworkCard
        self:getRegistry():update(o)
    end

    self:registerWith(function(from, port, cmd, a, b)
        if port == self.port and cmd == NET_CMD_FABRIC_REGISTER then
            self:onRegister(from, a)
        elseif port == self.port and cmd == NET_CMD_UPDATE_FABRIC then
            self:onUpdateFabric(from, a)
            -- elseif port == self.port and cmd == NET_CMD_RESET_ALL then
            --     self:onGetFabricUpdate(fromId, a, b)
        end
    end)


    return self
end

function FabricRegistryServer:callForUpdates(fabricInfo)
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.reg:checkMinimum(fabricInfo) then
            local fromId = fabricInfo.fCoreNetworkCard
            local name = fabricInfo.fName
            log(0, "Net-FabricRegistryServer: Send UpdateRequest for " .. name)
            self.net:send(fromId, self.port, NET_CMD_GET_FABRIC_UPDATE)
        else
        end
    end
end

function FabricRegistryServer:clearRegistry()
    -- KEEP: falls du eine eigene Registry-Klasse hast, ruf hier deren clear/reset
    --self.reg = FabricRegistry:new()
end

function FabricRegistryServer:broadcastRegistryReset()
    self:clearRegistry()
    self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    log(2, "Server: broadcast registry reset")
end

-- ===== ÖFFENTLICH: Zugriff auf die Registry =====
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
