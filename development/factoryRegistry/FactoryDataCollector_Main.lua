---@diagnostic disable: lowercase-global

local helper = require("shared.helper")
local string_contains = helper.string_contains
local now_ms = helper.now_ms
local sleep_ms = helper.sleep_ms
local pj = helper.pj

local log = require("shared.helper_log").log

require("factoryRegistry.basics")
Helper_inv = require("shared.helper_inventory")
local FI = require("factoryRegistry.FactoryInfo")
local NetworkAdapter = require("net.NetworkAdapter")

local JSON = require("shared.serializer")


local MyItemList = require("shared.items.items[-LANGUAGE-]")
local MyItem     = require("shared.items.items_basics").MyItem

local C          = require("shared.items.items_basics").MyItemConst

--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------
local LOG_TAG = "FactoryDataCollector"

---@class FactoryDataCollector : NetworkAdapter
---@field myFactoryInfo FactoryInfo|nil
---@field registered boolean
---@field stationMin integer
local FactoryDataCollector = setmetatable({}, { __index = NetworkAdapter })
FactoryDataCollector.__index = FactoryDataCollector

---@param opts table|nil
---@return boolean, FactoryDataCollector|nil, table|nil
function FactoryDataCollector.new(opts)
    assert(NetworkAdapter, LOG_TAG .. ".new: NetworkAdapter not loaded")
    opts                     = opts or {}
    local self               = NetworkAdapter.new(FactoryDataCollector, opts)
    self.name                = NET_NAME_FACTORY_REGISTRY_CLIENT
    self.port                = NET_PORT_FACTORY_REGISTRY
    self.ver                 = 1
    self.myFactoryInfo       = opts.factoryInfo or nil
    self.registered          = false
    self.stationMin          = opts.stationMin or 0
    self._initOpts           = opts -- für spätere Re-Registrierung
    self._fatal, self._error = nil, nil

    if not self.net then
        log(4, LOG_TAG .. ".new: no NIC available (self.net == nil)")
        return false, nil, { code = "NO_NIC", message = "no network card available" }
    end

    log(1, LOG_TAG, (".new: port=%s name=%s ver=%s nic=%s")
        :format(tostring(self.port), tostring(self.name), tostring(self.ver), tostring(self.net.id or self.net)))


    --------------------------------------------------------------------------
    -- Netzwerk-Handler registrieren
    --------------------------------------------------------------------------
    -- Netzwerk-Handler registrieren (unverändert)
    self:registerWith(function(from, port, cmd, a, b)
        log(0, LOG_TAG, (" from=%s cmd=%s"):format(tostring(from), tostring(cmd)))
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
            log(2, LOG_TAG .. ": unknown cmd: " .. tostring(cmd))
        end
    end)

    -- Sofortige Registrierung (Broadcast) – niemals fail-hard
    if self.myFactoryInfo then
        local factoryName = tostring(self.myFactoryInfo.fName or "")
        if factoryName == "" then
            log(3, "FactoryDataCollector.register: cannot broadcast – myFactoryInfo.fName is empty")
        else
            log(1, ("FactoryDataCollector.register: broadcasting '%s' name='%s' on port %d")
                :format(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, factoryName, self.port))
            self:broadcast(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, factoryName)
        end
    else
        log(1, "FactoryDataCollector.register: FactoryInfo not set, try name()")
        if opts.fName and tostring(opts.fName) ~= "" then
            log(1, ("FactoryDataCollector.register: found name='%s'"):format(opts.fName))
            self.myFactoryInfo = FI.FactoryInfo:new { fName = opts.fName }
            self:broadcast(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, opts.fName)
        else
            log(2, "FactoryDataCollector.register: no myFactoryInfo and no fName; skipping initial broadcast")
        end
    end

    return true, self, nil
end

--- Einheitliche Fehler-API -----------------------------------------------

function FactoryDataCollector:fail(msg, code)
    self._fatal = true
    self._error = { code = code or "FATAL", message = tostring(msg) }
    log(4, ("FDC.fail[%s]: %s"):format(self._error.code, self._error.message))
    return false, self._error
end

function FactoryDataCollector:isFatal()
    return self._fatal == true
end

function FactoryDataCollector:getError()
    return self._error
end

--- Best-effort Close: gibt Ports frei (NetHub:unregister wird aus dem Adapter gerufen)
function FactoryDataCollector:close(reason)
    pcall(function() NetworkAdapter.close(self, reason or "client-close") end)
end

--------------------------------------------------------------------------
-- HOOKS
--------------------------------------------------------------------------

--- ACK nach Registrierung
---@param fromId string
function FactoryDataCollector:onRegisterAck(fromId)
    -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
    log(1, "Client: Registration ACK from " .. tostring(fromId) .. " Build FactoryInfo now.")
    self.myFactoryInfo:setCoreNetworkCard(self.net.id)
    self:performUpdate()
    self.registered = true
end

--- Server hat Registry zurückgesetzt
---@param fromId string
function FactoryDataCollector:onRegistryReset(fromId)
    log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
    self.registered = false
    local name = (self.myFactoryInfo and self.myFactoryInfo.fName)
        or (self._initOpts and self._initOpts.fName)
        or ""
    if name ~= "" then
        log(1, ("FactoryDataCollector.register(re): broadcasting '%s' name='%s'")
            :format(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, name))
        self:broadcast(NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY, name)
    else
        -- Wenn wir nicht mal den Namen kennen, fatal markieren → Starter re-init
        self:fail("registry reset without factory name; cannot re-register", "REG_RESET")
    end
end

--- Server fordert ein Update an
---@param fromId string
---@param fName string
function FactoryDataCollector:onGetFactoryUpdate(fromId, fName)
    log(0, "Net-FactoryDataCollector:: Received update request  from  \"" .. fromId .. "\"")

    self:performUpdate()

    if fName and self.myFactoryInfo and fName == self.myFactoryInfo.fName then
        local J = JSON.new { indent = 2, sort_keys = true }
        local serialized = J:encode(self.myFactoryInfo)
        self:send(fromId, NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_UPDATE, serialized)
        log(0, "Net-FactoryDataCollector::update send to  \"" .. fromId .. "\"")
    else
        log(4,
            "Net-FactoryDataCollector::requested update name does not match requested=\"" ..
            fName .. "\" localFactopry=\"" .. (self.myFactoryInfo and self.myFactoryInfo.fName or "unknown") .. "\"")
    end
end

--- Statt der alten: function FactoryDataCollector:performUpdate() ... end
function FactoryDataCollector:performUpdate()
    local ok, manufacturer, err = FI.manufacturerByFactoryName(self.myFactoryInfo.fName)
    if not ok then
        local ok2, miner, err2 = FI.minerByFactoryName(self.myFactoryInfo.fName)
        if not ok2 then
            log(3, "FactoryDataCollector: No Manufacturer or Miner found for Factory '"
                .. tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err) .. tostring(err2))
            self:fail("no Manufacturer or Miner found for '" .. tostring(self.myFactoryInfo.fName) .. "'",
                "NO_FACTORY_OBJECT")
            return false
        end
        self:performMinerUpdate(miner)
    else
        self:performManufactureUpdate(manufacturer)
    end
    return true
end

---comment
---@param miner FGBuildableResourceExtractor |nil
function FactoryDataCollector:performMinerUpdate(miner)
    if not miner then
        log(3, "FactoryDataCollector: No Miner provided for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "'")
        return
    end

    self.myFactoryInfo.fType = C.MINER_MK_1
    local maxStack = 0;
    local itemName = nil
    for name, output in pairs(self.myFactoryInfo.outputs) do
        itemName = output.itemClass and output.itemClass.name
        maxStack = output.itemClass and output.itemClass.max or 0
    end
    if itemName == nil then
        log(0,
            "FactoryDataCollector: Trying to determine mined item for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "' via Miner Inventories")
        local minedItem = Helper_inv.readMinedItemStack(miner, 30)
        if minedItem then
            log(0,
                "FactoryDataCollector: Determined mined item for Factory '" ..
                tostring(self.myFactoryInfo.fName) .. "' via Miner Inventories: " ..
                ---@diagnostic disable-next-line: undefined-field
                tostring((minedItem and minedItem.item and minedItem.item.type.name) or "Unknown"))
            ---@diagnostic disable-next-line: undefined-field
            itemName = (minedItem and minedItem.item and minedItem.item.type and minedItem.item.type.name) or "Unknown"
            ---@diagnostic disable-next-line: undefined-field
            maxStack = (minedItem and minedItem.item and minedItem.item.type and minedItem.item.type.max) or 0
        end
    end

    if itemName == nil then
        log(2, "FactoryDataCollector: Could not determine mined item for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "'")
        return
    end

    local item = MyItemList:get_by_Name(itemName)
    if item then
        if maxStack > 0 then
            item.max = maxStack
        end
        -- Output-Objekt
        local probeOutput = FI.Output:new {
            itemClass          = item,
            amountStation      = 0,
            amountContainer    = 0,
            maxAmountStation   = 0,
            maxAmountContainer = 0
        }


        -- Container summieren
        local ok, containers, err = FI.containersByFactoryStack(self.myFactoryInfo.fName, probeOutput)
        local cCount, cMax = 0, 0
        if not ok then
            log(3,
                "FactoryDataCollector: Error finding Containers for Factory '" ..
                tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err))
        else
            cCount, cMax = Helper_inv.sumContainers(containers, item.max)
        end

        -- Trainstations summieren
        local ok2, stations, err2 = FI.trainstationsByFactoryStack(self.myFactoryInfo.fName, probeOutput)
        local sCount, sMax = 0, 0
        if not ok2 then
            log(3,
                "FactoryDataCollector: Error finding Trainstations for Factory '" ..
                tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err2))
        else
            sCount, sMax = Helper_inv.sumTrainstations(stations, item.max)
        end

        -- Finales Output-Objekt
        local output = FI.Output:new {
            itemClass          = item,
            amountStation      = sCount,
            amountContainer    = cCount,
            maxAmountStation   = sMax,
            maxAmountContainer = cMax
        }

        self.myFactoryInfo:updateOutput(output)
    end
end

---comment
---@param manufacturer Manufacturer|nil
function FactoryDataCollector:performManufactureUpdate(manufacturer)
    -- 1) Manufacturer holen (früh & robust raus, wenn keiner da)
    if not manufacturer then
        log(3, "FactoryDataCollector: No Manufacturer provided for Factory '" ..
            tostring(self.myFactoryInfo.fName) .. "'")
        return
    end

    -- 2) Typ bestimmen (nur, wenn verfügbar)
    local mTypeName = (manufacturer:getType() and manufacturer:getType().name) or ""
    if string_contains(mTypeName, "Assembler", false) then
        self.myFactoryInfo.fType = C.ASSEMBLER
    elseif string_contains(mTypeName, "Smelter", false) then
        self.myFactoryInfo.fType = C.SMELTER
    elseif string_contains(mTypeName, "Foundry", false) then
        self.myFactoryInfo.fType = C.FOUNDRY
    elseif string_contains(mTypeName, "Constructor", false) then
        self.myFactoryInfo.fType = C.CONSTRUCTOR
    else
        log(2, ('Net-FactoryDataCollector::Unknown Manufacturer Type "%s"'):format(mTypeName))
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
                item.max                  = maxStack

                -- Vor-Objekt nur zur Zielbestimmung (Container/Stations-Finder nutzt itemClass)
                local probeOutput         = FI.Output:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 0,
                    maxAmountContainer = 0
                }

                -- Container summieren
                local ok, containers, err = FI.containersByFactoryStack(self.myFactoryInfo.fName, probeOutput)
                local cCount, cMax        = 0, 0
                if not ok then
                    log(3,
                        "FactoryDataCollector: Error finding Containers for Factory '" ..
                        tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err))
                else
                    cCount, cMax = Helper_inv.sumContainers(containers, item.max)
                end

                -- Trainstations summieren
                local ok2, stations, err2 = FI.trainstationsByFactoryStack(self.myFactoryInfo.fName, probeOutput)
                local sCount, sMax = 0, 0
                if not ok2 then
                    log(3,
                        "FactoryDataCollector: Error finding Trainstations for Factory '" ..
                        tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err2))
                else
                    sCount, sMax = Helper_inv.sumTrainstations(stations, item.max)
                end

                -- Finales Output-Objekt
                local output = FI.Output:new {
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
                item.max                  = maxStack

                local probeInput          = FI.Input:new {
                    itemClass          = item,
                    amountStation      = 0,
                    amountContainer    = 0,
                    maxAmountStation   = 0,
                    maxAmountContainer = 0
                }

                -- Container summieren
                local ok, containers, err = FI.containersByFactoryStack(self.myFactoryInfo.fName, probeInput)
                local cCount, cMax        = 0, 0
                if not ok then
                    log(3,
                        "FactoryDataCollector: Error finding Containers for Factory '" ..
                        tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err))
                else
                    cCount, cMax = Helper_inv.sumContainers(containers, item.max)
                end

                -- Trainstations summieren
                local ok2, stations, err2 = FI.trainstationsByFactoryStack(self.myFactoryInfo.fName, probeInput)
                local sCount, sMax = 0, 0
                if not ok2 then
                    log(3,
                        "FactoryDataCollector: Error finding Trainstations for Factory '" ..
                        tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err2))
                else
                    sCount, sMax = Helper_inv.sumTrainstations(stations, item.max)
                end

                local input = FI.Input:new {
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
   -- pj(self.myFactoryInfo)
end

--- Server hat Registry zurückgesetzt
function FactoryDataCollector:checkTrainsignals()
    local t = now_ms()
    self.last = self.last or 0
    if t - self.last < 1000 then return true end
    self.last = t

    for _, input in pairs(self.myFactoryInfo.inputs or {}) do
        local ok, signal, err = FI.trainsignalByFactoryStack(self.myFactoryInfo.fName, input)
        if not ok then
            log(0, "FactoryDataCollector: Error finding Trainsignal for Factory '"
                .. tostring(self.myFactoryInfo.fName) .. "': " .. tostring(err))
            return false
        end
        if not signal then
            log(0, "FactoryDataCollector: No Trainsignal found for Factory '"
                .. tostring(self.myFactoryInfo.fName) .. "' and Input Item '"
                .. tostring(input.itemClass and input.itemClass.name) .. "'")
            return false
        end
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
    -- Debug: bei Bedarf aktiv lassen
    -- pj(self.myFactoryInfo)
    return true
end

return FactoryDataCollector
