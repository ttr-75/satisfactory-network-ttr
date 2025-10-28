---@diagnostic disable: lowercase-global

local names = {
    "fabricRegistry/basics.lua",
    "fabricRegistry/FabricInfo.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()


--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

---@class FabricRegistryClient : NetworkAdapter
---@field myFabricInfo FabricInfo|nil
---@field registered boolean
FabricRegistryClient = setmetatable({}, { __index = NetworkAdapter })
FabricRegistryClient.__index = FabricRegistryClient

---@param opts table|nil
---@return FabricRegistryClient
function FabricRegistryClient.new(opts)
    assert(NetworkAdapter, "FabricRegistryClient.new: NetworkAdapter not loaded")
    local self        = NetworkAdapter.new(FabricRegistryClient, opts)
    self.name         = NET_NAME_FABRIC_REGISTRY_CLIENT
    self.port         = NET_PORT_FABRIC_REGISTRY
    self.ver          = 1
    ---@type FabricInfo|nil
    self.myFabricInfo = opts and opts.fabricInfo or nil
    self.registered   = false

    -- NIC MUSS existieren (sonst kann nichts gesendet/gehört werden)
    assert(self.net, "FabricRegistryClient.new: no NIC available (self.net == nil)")

    -- Initial-Log
    log(1, ("FRC.new: port=%s name=%s ver=%s nic=%s")
        :format(tostring(self.port), tostring(self.name), tostring(self.ver), tostring(self.net.id or self.net)))

    --------------------------------------------------------------------------
    -- Netzwerk-Handler registrieren
    --------------------------------------------------------------------------
    self:registerWith(function(from, port, cmd, a, b)
        -- Eingehendes Paket protokollieren (Low-Noise → Level 1)
        log(0, ("FRC.rx: from=%s cmd=%s"):format(tostring(from), tostring(cmd)))

        if port == self.port and cmd == NET_CMD_FABRIC_REGISTER_ACK then
            self:onRegisterAck(from)
        elseif port == self.port and cmd == NET_CMD_RESET_FABRICREGISTRY then
            self:onRegistryReset(from)
        elseif port == self.port and cmd == NET_CMD_CALL_FABRICS_FOR_UPDATES then
            self:onGetFabricUpdate(from, a, b)
        else
            -- Unerwartete Kommandos sichtbar machen
            log(2, "FRC.rx: unknown cmd: " .. tostring(cmd))
        end
    end)


    --------------------------------------------------------------------------
    -- Sofortige Registrierung (Broadcast)
    -- - Kein return false mehr; nur Logs, damit der Aufrufer immer ein Objekt hat
    --------------------------------------------------------------------------
    if self.myFabricInfo then
        -- Sanity-Check: sieht es aus wie eine FabricInfo?
        assert(type(self.myFabricInfo.setCoreNetworkCard) == "function",
            "FabricRegistryClient.new: myFabricInfo does not look like a FabricInfo (missing setCoreNetworkCard)")

        local fabricName = tostring(self.myFabricInfo.fName or "")
        if fabricName == "" then
            log(3, "FRC.register: cannot broadcast – myFabricInfo.fName is empty")
        else
            log(1, ("FRC.register: broadcasting '%s' name='%s' on port %d")
                :format(NET_CMD_FABRIC_REGISTER, fabricName, self.port))
            self:broadcast(NET_CMD_FABRIC_REGISTER, fabricName)
        end
    else
        -- Kein harter Fehler: Client kann später myFabricInfo setzen & erneut registrieren
        log(2, "FRC.register: myFabricInfo not provided; will skip initial broadcast")
    end

    return self
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- ACK nach Registrierung
---@param fromId string
function FabricRegistryClient:onRegisterAck(fromId)
    -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
    log(1, "Client: Registration ACK from " .. tostring(fromId) .. " Build FabricInfo now.")
    self.myFabricInfo:setCoreNetworkCard(self.net.id)
    self:performUpdate()
    self.registered = true
end

--- Server hat Registry zurückgesetzt
---@param fromId string
function FabricRegistryClient:onRegistryReset(fromId)
    -- KEEP: deine bisherige Logik beim Registry-Reset (früher: computer.reset())
    log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
    self.registered = false
    computer.reset()
end

--- Server fordert ein Update an
---@param fromId string
---@param payloadA any
---@param payloadB any
function FabricRegistryClient:onGetFabricUpdate(fromId, payloadA, payloadB)
    log(0, "Net-FabricRegistryClient:: Received update request  from  \"" .. fromId .. "\"")

    self:performUpdate()

    local J = JSON.new { indent = 2, sort_keys = true }
    local serialized = J:encode(self.myFabricInfo)
    self:send(fromId, NET_CMD_UPDATE_FABRIC_IN_REGISTRY, serialized)
    log(0, "Net-FabricRegistryClient::update send to  \"" .. fromId .. "\"")
end

-- statt: function performUpdate() ... end
function FabricRegistryClient:performUpdate()
    local comp = component.findComponent(classes.Manufacturer)
    if #comp > 0 then
        local manufacturer = component.proxy(comp[1])
        local recipe = manufacturer:getRecipe()

        if recipe ~= nil then
            local products = recipe:getProducts()
            for _, product in pairs(products) do
                local p = product
                local item = MyItemList:get_by_Name(p.type.name)
                item.max = p.type.max
                local output = Output:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 3000,
                    maxAmountContainer = 3000
                }

                -- Container
                local containers = containerByFabricStack(self.myFabricInfo.fName, output)

                local maxSlotsC = 0
                local totalsC = {}
                local typesC = {}


                for _, container in pairs(containers) do
                    maxSlotsC = maxSlotsC + getMaxSlotsForContainer(container)
                    totalsC, typesC = readInventory(container, totalsC, typesC)
                    --print(container.nick)
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
                local trainstations = trainstationByFabricStack(self.myFabricInfo.fName, output)


                local maxSlotsS = 0
                local totalsS = {}
                local typesS = {}


                for _, trainstation in pairs(trainstations) do
                    local platforms = trainstation:getAllConnectedPlatforms()
                    log(0, "# platforms:" .. tostring(#platforms))



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
                    --maxStackS = (t and t.max) or 0
                    counterS = counterS + cnt

                    local tht = (t and t.name) or ("Type#" .. tostring(key))
                    --log(3, de_umlaute(MyItemList:get_by_Name(tht).name) .. t.description .. cnt)
                end

                local _maxAmountTainstation = maxSlotsS * maxStackS

                output = Output:new {
                    itemClass          = item,
                    amountStation      = counterS,
                    amountContainer    = counterC,
                    maxAmountStation   = _maxAmountTainstation,
                    maxAmountContainer = _maxAmountContainer
                }

                self.myFabricInfo:updateOutput(output) -- <– korrektes Feld
                --pj(self.myFabricInfo)
            end
            for _, ingredient in pairs(recipe:getIngredients()) do
                local item = MyItemList:get_by_Name(ingredient.type.name)
                item.max = ingredient.type.max
                local input = Input:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 3000,
                    maxAmountContainer = 3000
                }


                -- Container
                local containers = containerByFabricStack(self.myFabricInfo.fName, input)

                local maxSlotsC = 0
                local totalsC = {}
                local typesC = {}


                for _, container in pairs(containers) do
                    maxSlotsC = maxSlotsC + getMaxSlotsForContainer(container)
                    totalsC, typesC = readInventory(container, totalsC, typesC)
                    --print(container.nick)
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
                local trainstations = trainstationByFabricStack(self.myFabricInfo.fName, input)


                local maxSlotsS = 0
                local totalsS = {}
                local typesS = {}


                for _, trainstation in pairs(trainstations) do
                    local platforms = trainstation:getAllConnectedPlatforms()
                    log(0, "# platforms:" .. tostring(#platforms))



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

                input = Input:new {
                    itemClass          = item,
                    amountStation      = counterS,
                    amountContainer    = counterC,
                    maxAmountStation   = _maxAmountTainstation,
                    maxAmountContainer = _maxAmountContainer
                }

                self.myFabricInfo:updateInput(input) -- <– korrektes Feld
            end
        end
    end
end
