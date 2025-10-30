---@diagnostic disable: lowercase-global


local helper = require("shared.helper")
local de_umlaute = helper.de_umlaute

local Log = require("shared.helper_log")
local log = Log.log

local helper_inventory = require("shared.helper_inventory")
local byAllNick = helper_inventory.byAllNick

require("shared.items.items[-LANGUAGE-]")


--------------------------------------------------------------------------------
-- Basisklasse: FactoryStack
--------------------------------------------------------------------------------

---@class FactoryStack
---@field itemClass MyItem|nil
---@field amountStation integer
---@field amountContainer integer
---@field maxAmountStation integer
---@field maxAmountContainer integer
local FactoryStack = {}
FactoryStack.__index = FactoryStack

--- Generischer Basiskonstruktor:
---@generic T : FactoryStack
---@param self T
---@param o table|nil
---@return T
function FactoryStack:new(o)
    o                    = o or {}
    -- Standard-Properties
    o.itemClass          = o.itemClass or nil
    o.amountStation      = o.amountStation or 0
    o.amountContainer    = o.amountContainer or 0
    o.maxAmountStation   = o.maxAmountStation or 0
    o.maxAmountContainer = o.maxAmountContainer or 0
    return setmetatable(o, self)
end

-- Platzhalter-Implementierungen (werden in Subklassen überschrieben)
---@return boolean
function FactoryStack:isInput() return false end

---@return boolean
function FactoryStack:isOutput() return false end

--------------------------------------------------------------------------------
-- Subklasse: Input
--------------------------------------------------------------------------------
---@class Input : FactoryStack
local Input = setmetatable({ __name = "Input" }, FactoryStack)
Input.__index = Input

---@param o table|nil
---@return Input
function Input:new(o)
    o = o or {}
    ---@cast o Input
    return FactoryStack.new(self, o) -- ruft Eltern-Constructor
end

---@return boolean
function Input:isInput() return true end

---@return boolean
function Input:isOutput() return false end

--------------------------------------------------------------------------------
-- Subklasse: Output
--------------------------------------------------------------------------------
---@class Output : FactoryStack
local Output = setmetatable({ __name = "Output" }, FactoryStack)
Output.__index = Output

---@param o table|nil
---@return Output
function Output:new(o)
    o = o or {}
    ---@cast o Output
    return FactoryStack.new(self, o)
end

---@return boolean
function Output:isInput() return false end

---@return boolean
function Output:isOutput() return true end

--[[ USAGE
local a = Input:new{ itemClass="IronPlate", amountStation=120, amountContainer=800 }
local b = Output:new{ itemClass="Screw", amountStation=300, amountContainer=1500 }

print(a, a:isInput(), a:isOutput())   -- Input{...}   true  false
print(b, b:isInput(), b:isOutput())   -- Output{...}  false true]]

--- Factory Info

--------------------------------------------------------------------------------
-- FactoryInfo
--------------------------------------------------------------------------------
---@class FactoryInfo
---@field fName string|nil
---@field fCoreNetworkCard string|nil
---@field fType MyItem | nil
---@field inputs  table<string, Input>   -- key: Itemname
---@field outputs table<string, Output>  -- key: Itemname
local FactoryInfo = {
    __name = "FactoryInfo",
    fName = nil,
    fType = nil,
    fCoreNetworkCard = nil,
    inputs = {},
    outputs = {}
}

---@param o table|nil
---@return FactoryInfo
function FactoryInfo:new(o)
    o                  = o or {}
    o.fName            = o.fName or nil
    o.fType            = o.fType or nil
    o.fCoreNetworkCard = o.fCoreNetworkCard or nil
    o.inputs           = o.inputs or {} -- ← NEU (sonst shared!)
    o.outputs          = o.outputs or {}
    o.__name           = "FactoryInfo"
    self.__index       = self
    return setmetatable(o, self)
end

---@param name string
function FactoryInfo:setName(name)
    self.fName = name
end

---@param type MyItem
function FactoryInfo:setType(type)
    self.fType = type
end

---@param coreNetworkCard string
function FactoryInfo:setCoreNetworkCard(coreNetworkCard)
    self.fCoreNetworkCard = coreNetworkCard
end

--- Merge eines eintreffenden FactoryInfo-Snapshots in diese Instanz.
---@param factory FactoryInfo
function FactoryInfo:update(factory)
    -- Outputs zuerst, dann Inputs (Reihenfolge beliebig, semantisch getrennt)
    for _, outStack in pairs(factory.outputs) do
        ---@cast outStack Output
        self:updateOutput(outStack)
    end
    for _, inStack in pairs(factory.inputs) do
        ---@cast inStack Input
        self:updateInput(inStack)
    end
end

--- Einzelnen Output-Stack aktualisieren/setzen.
---@param output Output
function FactoryInfo:updateOutput(output)
    if self.outputs[output.itemClass.name] == nil then
        self.outputs[output.itemClass.name] = output
    else
        self.outputs[output.itemClass.name].amountStation = output.amountStation
        self.outputs[output.itemClass.name].amountContainer = output.amountContainer
        self.outputs[output.itemClass.name].maxAmountStation = output.maxAmountStation
        self.outputs[output.itemClass.name].maxAmountContainer = output.maxAmountContainer
    end
end

--- Einzelnen Input-Stack aktualisieren/setzen.
---@param input Input
function FactoryInfo:updateInput(input)
    if self.inputs[input.itemClass.name] == nil then
        self.inputs[input.itemClass.name] = input
    else
        self.inputs[input.itemClass.name].amountStation = input.amountStation
        self.inputs[input.itemClass.name].amountContainer = input.amountContainer
    end
end

---@param factory FactoryInfo|nil
---@return boolean
function FactoryInfo:check(factory)
    if not factory then
        log(3, "Factory is nil")
        return false
    end

    local id = factory.fCoreNetworkCard
    if not id then
        log(3, "Factory has no CoreNetworkCardId")
        return false
    end

    local name = factory.fName
    if not name then
        log(3, "Factory has no Name")
        return false
    end

    return true
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen (Namensbildung → deine Komponenten-Suche)
--------------------------------------------------------------------------------

---@param factoryName string
---@param itemStack FactoryStack
---@return any  -- Komponentensuche/Proxy (abhängig von deiner byAllNick)
local function containerByFactoryStack(factoryName, itemStack)
    local nick = "Container "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(factoryName)
    end

    return byAllNick(nick)
end

---@param factoryName string
---@param itemStack FactoryStack
---@return any
local function trainstationByFactoryStack(factoryName, itemStack)
    local nick = "Trainstation "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(factoryName)
    end
    return byAllNick(nick)
end

---@param factoryName string
---@param itemStack FactoryStack
---@return Build_RailroadBlockSignal_C
local function trainsignalByFactoryStack(factoryName, itemStack)
    local nick = "Trainsignal "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(factoryName)
    end
    return byAllNick(nick)
end


-- Modul-Export ----------------------------------------------------------------
return {
    FactoryStack               = FactoryStack,
    Input                      = Input,
    Output                     = Output,
    FactoryInfo                = FactoryInfo,
    containerByFactoryStack    = containerByFactoryStack,
    trainstationByFactoryStack = trainstationByFactoryStack,
    trainsignalByFactoryStack  = trainsignalByFactoryStack,
}
