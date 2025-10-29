---@diagnostic disable: lowercase-global

local names = {
    "shared/helper.lua",
    "shared/items.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- Basisklasse: FabricStack
--------------------------------------------------------------------------------

---@class FabricStack
---@field itemClass MyItem|nil
---@field amountStation integer
---@field amountContainer integer
---@field maxAmountStation integer
---@field maxAmountContainer integer
FabricStack = {}
FabricStack.__index = FabricStack

--- Generischer Basiskonstruktor:
---@generic T : FabricStack
---@param self T
---@param o table|nil
---@return T
function FabricStack:new(o)
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
function FabricStack:isInput() return false end

---@return boolean
function FabricStack:isOutput() return false end

--------------------------------------------------------------------------------
-- Subklasse: Input
--------------------------------------------------------------------------------
---@class Input : FabricStack
Input = setmetatable({ __name = "Input" }, FabricStack)
Input.__index = Input

---@param o table|nil
---@return Input
function Input:new(o)
    o = o or {}
    ---@cast o Input
    return FabricStack.new(self, o) -- ruft Eltern-Constructor
end

---@return boolean
function Input:isInput() return true end

---@return boolean
function Input:isOutput() return false end

--------------------------------------------------------------------------------
-- Subklasse: Output
--------------------------------------------------------------------------------
---@class Output : FabricStack
Output = setmetatable({ __name = "Output" }, FabricStack)
Output.__index = Output

---@param o table|nil
---@return Output
function Output:new(o)
    o = o or {}
    ---@cast o Output
    return FabricStack.new(self, o)
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

--- Fabric Info

--------------------------------------------------------------------------------
-- FabricInfo
--------------------------------------------------------------------------------
---@class FabricInfo
---@field fName string|nil
---@field fCoreNetworkCard string|nil
---@field fType MyItem | nil
---@field inputs  table<string, Input>   -- key: Itemname
---@field outputs table<string, Output>  -- key: Itemname
FabricInfo = {
    __name = "FabricInfo",
    fName = nil,
    fType = nil,
    fCoreNetworkCard = nil,
    inputs = {},
    outputs = {}
}

---@param o table|nil
---@return FabricInfo
function FabricInfo:new(o)
    o                  = o or {}
    o.fName            = o.fName or nil
    o.fType            = o.fType or nil
    o.fCoreNetworkCard = o.fCoreNetworkCard or nil
    o.inputs           = o.inputs or {} -- ← NEU (sonst shared!)
    o.outputs          = o.outputs or {}
    o.__name           = "FabricInfo"
    self.__index       = self
    return setmetatable(o, self)
end

---@param name string
function FabricInfo:setName(name)
    self.fName = name
end

---@param type MyItem
function FabricInfo:setType(type)
    self.fType = type
end

---@param coreNetworkCard string
function FabricInfo:setCoreNetworkCard(coreNetworkCard)
    self.fCoreNetworkCard = coreNetworkCard
end

--- Merge eines eintreffenden FabricInfo-Snapshots in diese Instanz.
---@param fabric FabricInfo
function FabricInfo:update(fabric)
    -- Outputs zuerst, dann Inputs (Reihenfolge beliebig, semantisch getrennt)
    for _, outStack in pairs(fabric.outputs) do
        ---@cast outStack Output
        self:updateOutput(outStack)
    end
    for _, inStack in pairs(fabric.inputs) do
        ---@cast inStack Input
        self:updateInput(inStack)
    end
end

--- Einzelnen Output-Stack aktualisieren/setzen.
---@param output Output
function FabricInfo:updateOutput(output)
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
function FabricInfo:updateInput(input)
    if self.inputs[input.itemClass.name] == nil then
        self.inputs[input.itemClass.name] = input
    else
        self.inputs[input.itemClass.name].amountStation = input.amountStation
        self.inputs[input.itemClass.name].amountContainer = input.amountContainer
    end
end

---@param fabric FabricInfo|nil
---@return boolean
function FabricInfo:check(fabric)
    if not fabric then
        log(3, "Fabric is nil")
        return false
    end

    local id = fabric.fCoreNetworkCard
    if not id then
        log(3, "Fabric has no CoreNetworkCardId")
        return false
    end

    local name = fabric.fName
    if not name then
        log(3, "Fabric has no Name")
        return false
    end

    return true
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen (Namensbildung → deine Komponenten-Suche)
--------------------------------------------------------------------------------

---@param fabricName string
---@param itemStack FabricStack
---@return any  -- Komponentensuche/Proxy (abhängig von deiner byAllNick)
function containerByFabricStack(fabricName, itemStack)
    local nick = "Container "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(fabricName)
    end

    return byAllNick(nick)
end

---@param fabricName string
---@param itemStack FabricStack
---@return any
function trainstationByFabricStack(fabricName, itemStack)
    local nick = "Trainstation "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(fabricName)
    end
    return byAllNick(nick)
end

---@param fabricName string
---@param itemStack FabricStack
---@return Build_RailroadBlockSignal_C
function trainsignalByFabricStack(fabricName, itemStack)
    local nick = "Trainsignal "

    if itemStack:isOutput() then
        nick = nick .. de_umlaute(itemStack.itemClass.name)
    else
        nick = nick .. de_umlaute(itemStack.itemClass.name) .. "2" .. de_umlaute(fabricName)
    end
    return byAllNick(nick)
end
