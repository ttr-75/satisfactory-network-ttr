---@diagnostic disable: lowercase-global
local Logger = require("shared.helper_log")
log = Logger.log

local helper = require("shared.helper")
local sleep_s = helper.sleep_s
local now_ms = helper.now_ms
local byNick = helper.byNick


require("factoryRegistry.basics")
local NetworkAdapter = require("net.NetworkAdapter")
local FI = require("factoryRegistry.FactoryInfo")
local FactoryDashboard = require("factoryRegistry.FactoryDashboard_UI")

local JSON = require("shared.serializer")

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

---@class FarbricDashboardClient : NetworkAdapter
---@field myFactoryInfo FactoryInfo|nil
---@field registered boolean
---@field stationMin integer
---@field scr ScreenProxy|nil
---@field gpu GPUProxy|nil
---@field last integer
---@field dash FactoryDashboard
local FactoryDashboardClient = setmetatable({}, { __index = NetworkAdapter })
FactoryDashboardClient.__index = FactoryDashboardClient

---@param opts table|nil
---@return FarbricDashboardClient
function FactoryDashboardClient.new(opts)
    assert(NetworkAdapter, "FarbricDashboardClient.new: NetworkAdapter not loaded")
    opts               = opts or {}
    local self         = NetworkAdapter.new(FactoryDashboardClient, opts)
    self.name          = NET_NAME_FACTORY_REGISTRY_CLIENT
    self.port          = NET_PORT_FACTORY_REGISTRY
    self.gpu           = nil
    self.scr           = nil
    self.ver           = 1
    self.dash          = FactoryDashboard.new {}
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
            self:onResponseFactoryAddress(a)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS_NO_FACTORY then
            self:onResponseFactoryAddress(nil)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY then
            self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_UPDATE then
            self:onUpdateFactory(from, a)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS then
            -- Ignore: Server should not send this to Client
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE then
            -- Ignore: Server should not send this to Client
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY then
            -- Ignore: Server should not send this to Client
        else
            -- Unerwartete Kommandos sichtbar machen
            log(2, "FRC.rx: unknown cmd: " .. tostring(cmd))
        end
    end)


    ---@diagnostic disable-next-line: undefined-field, assign-type-mismatch
    self.gpu = computer.getPCIDevices(classes.GPU_T2_C)[1]
    if opts.scrName then
        local ok, value, err = byNick("miner iron north")
        if not ok then error(err) end
        if not value then
            log(4, "FactoryDashboardClient.new: Screen '" .. tostring(opts.scrName) .. "' not found")
        else
        ---@diagnostic disable-next-line: assign-type-mismatch
            self.scr = byNick(opts.scrName)
        end
    end

    if opts.fName then
        self:setFactoryInfo(opts.fName)
    else
        -- Harter Fehler: Client kann später myFactoryInfo setzen & erneut registrieren
        log(4, "FRC.register: myFactoryInfo not provided; will skip initial broadcast")
        computer.stop()
    end

    local dash = FactoryDashboard.new {}
    self.dash:init(self.gpu, self.scr)

    return self
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- ACK nach Registrierung
---@param fromId string | nil
function FactoryDashboardClient:onResponseFactoryAddress(fromId)
    -- Limitiere Aufrufe auf max. 5
    self._responseAttempts = (self._responseAttempts or 0) + 1
    if self._responseAttempts >= 5 then
        log(4,
            ("FarbricDashboardClient: onResponseFactoryAddress called more than 5 times; ignoring (attempt %d)"):format(
                self._responseAttempts))
        computer.stop()
        return
    end

    if not fromId then
        sleep_s(5)
        log(4,
            "FarbricDashboardClient: There is no factory with name " ..
            tostring(self.myFactoryInfo and self.myFactoryInfo.fName or "<unknown>") ..
            " registered on the FactoryRegistryServer... Retry (" .. self._responseAttempts .. "/5)")
        if self._responseAttempts < 5 and self.myFactoryInfo then
            self:broadcast(NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS, self.myFactoryInfo.fName)
        end
        return
    end

    -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
    log(1,
        "FarbricDashboardClient: Got Address '" ..
        tostring(fromId) .. "' for Factory " .. tostring(self.myFactoryInfo and self.myFactoryInfo.fName or "<unknown>"))
    self.myFactoryInfo:setCoreNetworkCard(fromId)
end

--- Server hat Registry zurückgesetzt
---@param fromId string
function FactoryDashboardClient:onRegistryReset(fromId)
    -- KEEP: deine bisherige Logik beim Registry-Reset (früher: computer.reset())
    log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
    self.registered = false
    computer.reset()
end

---@param factoryName string
function FactoryDashboardClient:setFactoryInfo(factoryName)
    self.myFactoryInfo = FI.FactoryInfo:new({ fName = factoryName })
    self:broadcast(NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS, factoryName)
end

--- Server hat Registry zurückgesetzt
function FactoryDashboardClient:run()
    while true do
        self:callForUpdate()
        future.run()
    end
end

--- Client schickt ein Update seiner FactoryInfo (als JSON).
---@param fromId string
---@param factoryInfoS string
function FactoryDashboardClient:onUpdateFactory(fromId, factoryInfoS)
    -- KEEP: falls Client etwas am Server aktualisiert
    log(0, ('Net-FarbricDashboardClient: Received Update from "%s"'):format(fromId))
    local J = JSON.new { indent = 2, sort_keys = true }
    local o = J:decode(factoryInfoS)
    --print(arg1)
    --local id = o.fCoreNetworkCard
    ---@cast o FactoryInfo
    self.myFactoryInfo:update(o)
    self.dash:setFromFactoryInfo(self.myFactoryInfo)
    self.dash:paint()
end

--- Fragt zyklisch (1/s) alle bekannten Fabriken nach Updates.
function FactoryDashboardClient:callForUpdate()
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.myFactoryInfo:check(self.myFactoryInfo) then
            local fromId = self.myFactoryInfo.fCoreNetworkCard or ""
            local name = self.myFactoryInfo.fName
            log(0, "Net-FarbricDashboardClient: Send UpdateRequest for " .. name .. " to " .. fromId)
            self:send(fromId, NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE, name)
        else
        end


        -- ggf. myFactoryInfo:update(...) → dann erneut mappen:
        -- dash:setFromFactoryInfo(myFactoryInfo)
    end
end

return FactoryDashboardClient
