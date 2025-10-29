---@diagnostic disable: lowercase-global

local names = {
    "factoryRegistry/basics.lua",
    "factoryRegistry/FactoryInfo.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()


--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

---@class FarbricDashboardClient : NetworkAdapter
---@field myFactoryInfo FactoryInfo|nil
---@field registered boolean
---@field stationMin integer
FarbricDashboardClient = setmetatable({}, { __index = NetworkAdapter })
FarbricDashboardClient.__index = FarbricDashboardClient

---@param opts table|nil
---@return FarbricDashboardClient
function FarbricDashboardClient.new(opts)
    assert(NetworkAdapter, "FarbricDashboardClient.new: NetworkAdapter not loaded")
    opts               = opts or {}
    local self         = NetworkAdapter.new(FarbricDashboardClient, opts)
    self.name          = NET_NAME_FACTORY_REGISTRY_CLIENT
    self.port          = NET_PORT_FACTORY_REGISTRY
    self.ver           = 1
    ---@type FactoryInfo|nil
    self.myFactoryInfo = opts and opts.factoryInfo or nil
    ---@type integer
    self.last          = 0


    -- NIC MUSS existieren (sonst kann nichts gesendet/gehört werden)
    assert(self.net, "FarbricDashboardClient.new: no NIC available (self.net == nil)")

    -- Initial-Log
    log(1, ("FRC.new: port=%s name=%s ver=%s nic=%s")
        :format(tostring(self.port), tostring(self.name), tostring(self.ver), tostring(self.net.id or self.net)))

    --------------------------------------------------------------------------
    -- Netzwerk-Handler registrieren
    --------------------------------------------------------------------------
    self:registerWith(function(from, port, cmd, a, b)
        -- Eingehendes Paket protokollieren (Low-Noise → Level 1)
        log(0, ("FRC.rx: from=%s cmd=%s"):format(tostring(from), tostring(cmd)))

        if port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS then
            self:onResponseFactoryAddress(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY then
            self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_UPDATE then
            self:onUpdateFactory(from, a, b)
        else
            -- Unerwartete Kommandos sichtbar machen
            log(2, "FRC.rx: unknown cmd: " .. tostring(cmd))
        end
    end)

    if opts.fName then
        self:setFactoryInfo(opts.fName)
    else
        -- Harter Fehler: Client kann später myFactoryInfo setzen & erneut registrieren
        log(4, "FRC.register: myFactoryInfo not provided; will skip initial broadcast")
        computer.stop()
    end

    return self
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- ACK nach Registrierung
---@param fromId string
function FarbricDashboardClient:onResponseFactoryAddress(fromId)
    -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
    log(1, "FarbricDashboardClient: Got Address '" .. tostring(fromId) .. "' for Factory " .. self.myFactoryInfo.fName)
    self.myFactoryInfo:setCoreNetworkCard(self.net.id)
end

--- Server hat Registry zurückgesetzt
---@param fromId string
function FarbricDashboardClient:onRegistryReset(fromId)
    -- KEEP: deine bisherige Logik beim Registry-Reset (früher: computer.reset())
    log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
    self.registered = false
    computer.reset()
end

---@param factoryName string
function FarbricDashboardClient:setFactoryInfo(factoryName)
    self.myFactoryInfo = FactoryInfo:new({ fName = factoryName })
    self:broadcast(NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS, factoryName)
end

--- Server hat Registry zurückgesetzt
function FarbricDashboardClient:run()
    while true do
        self:callForUpdate()
        future.run()
    end
end

--- Client schickt ein Update seiner FactoryInfo (als JSON).
---@param fromId string
---@param factoryInfoS string
function FarbricDashboardClient:onUpdateFactory(fromId, factoryInfoS)
    -- KEEP: falls Client etwas am Server aktualisiert
    log(0, ('Net-FarbricDashboardClient: Received Update from "%s"'):format(fromId))
    local J = JSON.new { indent = 2, sort_keys = true }
    local o = J:decode(factoryInfoS)
    --print(arg1)
    --local id = o.fCoreNetworkCard
    ---@cast o FactoryInfo
    self.myFactoryInfo:update(o)
end

--- Fragt zyklisch (1/s) alle bekannten Fabriken nach Updates.
function FarbricDashboardClient:callForUpdate()
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.myFactoryInfo:check(self.myFactoryInfo) then
            local fromId = self.myFactoryInfo.fCoreNetworkCard or ""
            local name = self.myFactoryInfo.fName
            log(0, "Net-FarbricDashboardClient: Send UpdateRequest for " .. name)
            self:send(fromId, NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE, name)
        else
        end
    end
end
