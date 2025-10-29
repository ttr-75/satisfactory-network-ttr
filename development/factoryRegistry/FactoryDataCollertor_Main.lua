---@diagnostic disable: lowercase-global

require("factoryRegistry/basics.lua")
local FI = require("factoryRegistry/FactoryInfo.lua")
local NetworkAdapter = require("net/NetworkAdapter.lua")
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

-- statt: function performUpdate() ... end
function FactoryDataCollertor:performUpdate()
    local comp = component.findComponent(classes.Manufacturer)
    if #comp > 0 then
        local manufacturer = component.proxy(comp[1])
        ---@cast manufacturer Manufacturer
        if not manufacturer then return end

        local recipe = manufacturer:getRecipe()

        if string_contains(manufacturer:getType().name, MyItem.ASSEMBLER.name, false) then
            self.myFactoryInfo.fType = MyItem.ASSEMBLER
        else
            log(2, "Net-FactoryRegistryClient::Unknown Manufacturer Type \"" .. manufacturer:getType().name .. "\"")
        end


        if recipe ~= nil then
            local products = recipe:getProducts()
            for _, product in pairs(products) do
                local p = product
                local item = MyItemList:get_by_Name(p.type.name)
                if item == nil then
                    break
                end
                item.max = p.type.max
                local output = FI.Output:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 3000,
                    maxAmountContainer = 3000
                }

                -- Container
                local containers = FI.containerByFactoryStack(self.myFactoryInfo.fName, output)

                local maxSlotsC = 0
                local totalsC = {}
                local typesC = {}


                for _, container in pairs(containers) do
                    maxSlotsC = maxSlotsC + getMaxSlotsForContainer(container)
                    totalsC, typesC = readInventory(container, totalsC, typesC)
                end

                local counterC = 0
                local maxStackC = item.max
                for key, cnt in pairs(totalsC) do
                    local t = typesC[key]
                    --local name = (t and t.name) or ("Type#" .. tostring(key))
                    -- maxStackC = (t and t.max) or 0
                    counterC = counterC + cnt

                    local tht = (t and t.name) or ("Type#" .. tostring(key))
                    --log(3, de_umlaute(MyItemList:get_by_Name(tht).name) .. t.description .. cnt)
                end

                local _maxAmountContainer = maxSlotsC * maxStackC

                --Station
                local trainstations = FI.trainstationByFactoryStack(self.myFactoryInfo.fName, output)


                local maxSlotsS = 0
                local totalsS = {}
                local typesS = {}


                for _, trainstation in pairs(trainstations) do
                    local platforms = trainstation:getAllConnectedPlatforms()

                    for _, platform in pairs(platforms) do
                        totalsS, typesS = readInventory(platform, totalsS, typesS)
                        maxSlotsS = maxSlotsS + getMaxSlotsForContainer(platform)
                    end
                end

                local counterS = 0
                local maxStackS = item.max
                for key, cnt in pairs(totalsS) do
                    local t = typesS[key]
                    --local name = (t and t.name) or ("Type#" .. tostring(key))
                    --maxStackS = (t and t.max) or 0
                    counterS = counterS + cnt

                    local tht = (t and t.name) or ("Type#" .. tostring(key))
                    --log(3, de_umlaute(MyItemList:get_by_Name(tht).name) .. t.description .. cnt)
                end

                local _maxAmountTainstation = maxSlotsS * maxStackS

                output = FI.Output:new {
                    itemClass          = item,
                    amountStation      = counterS,
                    amountContainer    = counterC,
                    maxAmountStation   = _maxAmountTainstation,
                    maxAmountContainer = _maxAmountContainer
                }

                self.myFactoryInfo:updateOutput(output) -- <– korrektes Feld
                --pj(self.myFactoryInfo)
            end
            for _, ingredient in pairs(recipe:getIngredients()) do
                local item = MyItemList:get_by_Name(ingredient.type.name)
                if item == nil then
                    break
                end


                item.max = ingredient.type.max
                local input = FI.Input:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 3000,
                    maxAmountContainer = 3000
                }


                -- Container
                local containers = FI.containerByFactoryStack(self.myFactoryInfo.fName, input)

                local maxSlotsC = 0
                local totalsC = {}
                local typesC = {}


                for _, container in pairs(containers) do
                    maxSlotsC = maxSlotsC + getMaxSlotsForContainer(container)
                    totalsC, typesC = readInventory(container, totalsC, typesC)
                end

                local counterC = 0
                local maxStackC = item.max
                for key, cnt in pairs(totalsC) do
                    local t = typesC[key]
                    --local name = (t and t.name) or ("Type#" .. tostring(key))
                    --maxStackC = (t and t.max) or 0
                    counterC = counterC + cnt

                    local tht = (t and t.name) or ("Type#" .. tostring(key))
                    --log(3, de_umlaute(MyItemList:get_by_Name(tht).name) .. t.description .. cnt)
                end

                local _maxAmountContainer = maxSlotsC * maxStackC




                --Station
                local trainstations = FI.trainstationByFactoryStack(self.myFactoryInfo.fName, input)


                local maxSlotsS = 0
                local totalsS = {}
                local typesS = {}


                for _, trainstation in pairs(trainstations) do
                    local platforms = trainstation:getAllConnectedPlatforms()

                    for _, platform in pairs(platforms) do
                        totalsS, typesS = readInventory(platform, totalsS, typesS)
                        maxSlotsS = maxSlotsS + getMaxSlotsForContainer(platform)
                    end
                    --print(container.nick)
                end

                local counterS = 0
                local maxStackS = item.max
                for key, cnt in pairs(totalsS) do
                    local t = typesS[key]
                    --local name = (t and t.name) or ("Type#" .. tostring(key))
                    -- maxStackS = (t and t.max) or 0
                    counterS = counterS + cnt

                    local tht = (t and t.name) or ("Type#" .. tostring(key))
                    --log(3, de_umlaute(MyItemList:get_by_Name(tht).name) .. t.description .. cnt)
                end

                local _maxAmountTainstation = maxSlotsS * maxStackS

                input = FI.Input:new {
                    itemClass          = item,
                    amountStation      = counterS,
                    amountContainer    = counterC,
                    maxAmountStation   = _maxAmountTainstation,
                    maxAmountContainer = _maxAmountContainer
                }

                self.myFactoryInfo:updateInput(input) -- <– korrektes Feld
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
