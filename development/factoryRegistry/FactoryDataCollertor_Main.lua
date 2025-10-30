---@diagnostic disable: lowercase-global

local helper = require("shared.helper")
local string_contains = helper.string_contains
local now_ms = helper.now_ms

require("factoryRegistry.basics")
Helper_inv = require("shared.helper_inventory")
local FI = require("factoryRegistry.FactoryInfo")
local NetworkAdapter = require("net.NetworkAdapter")

local JSON = require("shared.serializer")

--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

---@class FactoryDataCollertor : NetworkAdapter
---@field myFactoryInfo FactoryInfo|nil
---@field registered boolean
---@field stationMin integer
local FactoryDataCollertor = setmetatable({}, { __index = NetworkAdapter })
FactoryDataCollertor.__index = FactoryDataCollertor

---@param opts table|nil
---@return FactoryDataCollertor
function FactoryDataCollertor.new(opts)
    assert(NetworkAdapter, "FactoryRegistryClient.new: NetworkAdapter not loaded")
    opts               = opts or {}
    local self         = NetworkAdapter.new(FactoryDataCollertor, opts)
    self.name          = NET_NAME_FACTORY_REGISTRY_CLIENT
    self.port          = NET_PORT_FACTORY_REGISTRY
    self.ver           = 1
    ---@type FactoryInfo|nil
    self.myFactoryInfo = opts and opts.factoryInfo or nil
    self.registered    = false
    self.stationMin    = opts and opts.stationMin or 0

    -- NIC MUSS existieren (sonst kann nichts gesendet/gehört werden)
    assert(self.net, "FactoryRegistryClient.new: no NIC available (self.net == nil)")

    -- Initial-Log
    log(1, ("FRC.new: port=%s name=%s ver=%s nic=%s")
        :format(tostring(self.port), tostring(self.name), tostring(self.ver), tostring(self.net.id or self.net)))

    --------------------------------------------------------------------------
    -- Netzwerk-Handler registrieren
    --------------------------------------------------------------------------
    self:registerWith(function(from, port, cmd, a, b)
        -- Eingehendes Paket protokollieren (Low-Noise → Level 1)
        log(0, ("FRC.rx: from=%s cmd=%s"):format(tostring(from), tostring(cmd)))

        if port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY_ACK then
            self:onRegisterAck(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY then
            self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE then
            self:onGetFactoryUpdate(from, a)
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY then
            -- Nothing just catch
        elseif port == self.port and cmd == NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS then
            -- Nothing just catch
        else
            -- Unerwartete Kommandos sichtbar machen
            log(2, "FRC.rx: unknown cmd: " .. tostring(cmd))
        end
    end)

    --------------------------------------------------------------------------
    -- Sofortige Registrierung (Broadcast)
    -- - Kein return false mehr; nur Logs, damit der Aufrufer immer ein Objekt hat
    --------------------------------------------------------------------------
    if self.myFactoryInfo then
        -- Sanity-Check: sieht es aus wie eine FactoryInfo?
        assert(type(self.myFactoryInfo.setCoreNetworkCard) == "function",
            "FactoryRegistryClient.new: myFactoryInfo does not look like a FactoryInfo (missing setCoreNetworkCard)")

        local factoryName = tostring(self.myFactoryInfo.fName or "")
        if factoryName == "" then
            log(3, "FRC.register: cannot broadcast – myFactoryInfo.fName is empty")
        else
            log(1, ("FRC.register: broadcasting '%s' name='%s' on port %d")
                :format(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, factoryName, self.port))
            self:broadcast(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, factoryName)
        end
    else
        log(1, "FRC.register: FactoryInfo not set try name")

        if opts.fName then
            log(1, ("FRC.register: found name='%s'"):format(opts.fName))
            self.myFactoryInfo = FI.FactoryInfo:new { fName = opts.fName }
            self:broadcast(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, opts.fName)
        else
            -- Kein harter Fehler: Client kann später myFactoryInfo setzen & erneut registrieren
            log(2, "FRC.register: myFactoryInfo not provided; will skip initial broadcast")
        end
    end

    return self
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- ACK nach Registrierung
---@param fromId string
function FactoryDataCollertor:onRegisterAck(fromId)
    -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
    log(1, "Client: Registration ACK from " .. tostring(fromId) .. " Build FactoryInfo now.")
    self.myFactoryInfo:setCoreNetworkCard(self.net.id)
    self:performUpdate()
    self.registered = true
end

--- Server hat Registry zurückgesetzt
---@param fromId string
function FactoryDataCollertor:onRegistryReset(fromId)
    -- KEEP: deine bisherige Logik beim Registry-Reset (früher: computer.reset())
    log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
    self.registered = false
    computer.reset()
end

--- Server fordert ein Update an
---@param fromId string
---@param fName string
function FactoryDataCollertor:onGetFactoryUpdate(fromId, fName)
    log(0, "Net-FactoryRegistryClient:: Received update request  from  \"" .. fromId .. "\"")

    self:performUpdate()

    if fName and self.myFactoryInfo and fName == self.myFactoryInfo.fName then
        local J = JSON.new { indent = 2, sort_keys = true }
        local serialized = J:encode(self.myFactoryInfo)
        self:send(fromId, NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_UPDATE, serialized)
        log(0, "Net-FactoryRegistryClient::update send to  \"" .. fromId .. "\"")
    else
        log(4,
            "Net-FactoryRegistryClient::requested update name does not match requested=\"" ..
            fName .. "\" localFactopry=\"" .. (self.myFactoryInfo and self.myFactoryInfo.fName or "unknown") .. "\"")
    end
end

--- Statt der alten: function FactoryDataCollertor:performUpdate() ... end
function FactoryDataCollertor:performUpdate()
    local manufacturer = FI.manufacturerByFactoryName(self.myFactoryInfo.fName)
    if not manufacturer then
        local miner = FI.minerByFactoryName(self.myFactoryInfo.fName)
        if not miner then
            log(3,
                "FactoryDataCollertor: No Manufacturer or Miner found for Factory '" ..
                tostring(self.myFactoryInfo.fName) .. "'")
            return
        end
        self:performMinerUpdate(miner)
    else
        self:performManufactureUpdate(manufacturer)
    end
end

---comment
---@param miner FGBuildableResourceExtractor
function FactoryDataCollertor:performMinerUpdate(miner)
    if not miner then
        log(3, "FactoryDataCollertor: No Miner provided for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "'")
        return
    end


end

---comment
---@param manufacturer Manufacturer
function FactoryDataCollertor:performManufactureUpdate(manufacturer)
    -- 1) Manufacturer holen (früh & robust raus, wenn keiner da)
    if not manufacturer then
        log(3, "FactoryDataCollertor: No Manufacturer provided for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "'")
        return
        
        self.myFactoryInfo.fType = MyItem.ASSEMBLER

    end

    -- 2) Typ bestimmen (nur, wenn verfügbar)
    local mTypeName = (manufacturer:getType() and manufacturer:getType().name) or ""
    if string_contains(mTypeName, MyItem.ASSEMBLER.name, false) then
        self.myFactoryInfo.fType = MyItem.ASSEMBLER
    else
        log(2, ('Net-FactoryRegistryClient::Unknown Manufacturer Type "%s"'):format(mTypeName))
    end

    -- 3) Rezept ziehen (wenn keins: Ende)
    local recipe = manufacturer:getRecipe()
    if recipe == nil then return end

    ---------------------------------------------------------------------------
    -- 4) PRODUCTS (Outputs)
    ---------------------------------------------------------------------------
    local products = recipe:getProducts() or {}
    for _, product in pairs(products) do
        local ptype = product and product.type
        local itemName = ptype and ptype.name
        local maxStack = ptype and ptype.max or 0

        if itemName then
            local item = MyItemList:get_by_Name(itemName)
            if item then
                item.max           = maxStack

                -- Vor-Objekt nur zur Zielbestimmung (Container/Stations-Finder nutzt itemClass)
                local probeOutput  = FI.Output:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 0,
                    maxAmountContainer = 0
                }

                -- Container summieren
                local containers   = FI.containerByFactoryStack(self.myFactoryInfo.fName, probeOutput) or {}
                local cCount, cMax = Helper_inv.sumContainers(containers, item.max)

                -- Trainstations summieren
                local stations     = FI.trainstationByFactoryStack(self.myFactoryInfo.fName, probeOutput) or {}
                local sCount, sMax = Helper_inv.sumTrainstations(stations, item.max)

                -- Finales Output-Objekt
                local output       = FI.Output:new {
                    itemClass          = item,
                    amountStation      = sCount,
                    amountContainer    = cCount,
                    maxAmountStation   = sMax,
                    maxAmountContainer = cMax
                }
                self.myFactoryInfo:updateOutput(output)
            end
            -- wenn item nil ist, einfach diesen Eintrag überspringen (kein break!)
        end
    end

    ---------------------------------------------------------------------------
    -- 5) INGREDIENTS (Inputs)
    ---------------------------------------------------------------------------
    local ingredients = recipe:getIngredients() or {}
    for _, ing in pairs(ingredients) do
        local itype = ing and ing.type
        local itemName = itype and itype.name
        local maxStack = itype and itype.max or 0

        if itemName then
            local item = MyItemList:get_by_Name(itemName)
            if item then
                item.max           = maxStack

                local probeInput   = FI.Input:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 0,
                    maxAmountContainer = 0
                }

                local containers   = FI.containerByFactoryStack(self.myFactoryInfo.fName, probeInput) or {}
                local cCount, cMax = Helper_inv.sumContainers(containers, item.max)

                local stations     = FI.trainstationByFactoryStack(self.myFactoryInfo.fName, probeInput) or {}
                local sCount, sMax = Helper_inv.sumTrainstations(stations, item.max)

                local input        = FI.Input:new {
                    itemClass          = item,
                    amountStation      = sCount,
                    amountContainer    = cCount,
                    maxAmountStation   = sMax,
                    maxAmountContainer = cMax
                }
                self.myFactoryInfo:updateInput(input)
            end
        end
    end
end

--- Server hat Registry zurückgesetzt
function FactoryDataCollertor:checkTrainsignals()
    local t = now_ms()
    if not self.last then
        self.last = 0
    end
    if t - self.last >= 1000 then
        self.last = t

        for _, input in pairs(self.myFactoryInfo.inputs) do
            local signal = FI.trainsignalByFactoryStack(self.myFactoryInfo.fName, input)[1]
            local block = signal:getObservedBlock()
            if input.amountStation <= self.stationMin then
                if block.isPathBlock then
                    block.isPathBlock = false
                    log(0, "Switching Signal " .. signal.nick .. " to green")
                end
            else
                if not block.isPathBlock then
                    log(0, "Switching Signal " .. signal.nick .. " to red")
                    block.isPathBlock = true
                end
            end
        end
    end
end

--- Server hat Registry zurückgesetzt
function FactoryDataCollertor:run()
    while true do
        self:checkTrainsignals()
        future.run()
    end
end

return FactoryDataCollertor
