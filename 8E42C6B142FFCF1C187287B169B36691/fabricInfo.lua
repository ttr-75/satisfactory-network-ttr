--------------------------------------------------------------------------------
-- Basisklasse: FabricStack
--------------------------------------------------------------------------------
FabricStack = {}
FabricStack.__index = FabricStack

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
function FabricStack:isInput() return false end

function FabricStack:isOutput() return false end

-- Optional: hübsches tostring (nur für Debug)
function FabricStack:__tostring()
    return string.format(
        "%s{itemClass=%s, station=%s, container=%s}",
        rawget(self, "__name") or "FabricStack",
        tostring(self.itemClass),
        tostring(self.amountStation),
        tostring(self.amountContainer)
    )
end

--------------------------------------------------------------------------------
-- Subklasse: Input
--------------------------------------------------------------------------------
Input = setmetatable({ __name = "Input" }, FabricStack)
Input.__index = Input

function Input:new(o)
    o = o or {}
    return FabricStack.new(self, o) -- ruft Eltern-Constructor
end

function Input:isInput() return true end

function Input:isOutput() return false end

--------------------------------------------------------------------------------
-- Subklasse: Output
--------------------------------------------------------------------------------
Output = setmetatable({ __name = "Output" }, FabricStack)
Output.__index = Output

function Output:new(o)
    o = o or {}
    return FabricStack.new(self, o)
end

function Output:isInput() return false end

function Output:isOutput() return true end

--[[ USAGE
local a = Input:new{ itemClass="IronPlate", amountStation=120, amountContainer=800 }
local b = Output:new{ itemClass="Screw", amountStation=300, amountContainer=1500 }

print(a, a:isInput(), a:isOutput())   -- Input{...}   true  false
print(b, b:isInput(), b:isOutput())   -- Output{...}  false true]]

--- Fabric Info


FabricInfo = {
    __name = "FabricInfo",
    fName = nil,
    fType = nil,
    fCoreNetworkCard = nil,
    inputs = {},
    outputs = {}
}


function FabricInfo:new(o)
    o                  = o or {}
    o.fName            = o.fName or nil
    o.fType            = o.fType or nil
    o.fCoreNetworkCard = o.fCoreNetworkCard or nil
    o.inputs           = o.inputs or {} -- ← NEU (sonst shared!)
    o.outputs          = o.outputs or {}
    self.__index       = self
    return setmetatable(o, self)
end

function FabricInfo:setName(name)
    self.fName = name
end

function FabricInfo:setType(type)
    self.fType = type
end

function FabricInfo:setCoreNetworkCard(coreNetworkCard)
    self.fCoreNetworkCard = coreNetworkCard
end

function FabricInfo:update(fabric)
    for _, output in pairs(fabric.outputs) do
        self:updateOutput(output)
    end
    for _, input in pairs(fabric.inputs) do
        self:updateInput(input)
    end
end

function FabricInfo:updateOutput(output)
    local J = JSON.new { indent = 2, sort_keys = true }
    local s = J:encode(output)
    --print(s)
    if self.outputs[output.itemClass.name] == nil then
        self.outputs[output.itemClass.name] = output
    else
        self.outputs[output.itemClass.name].amountStation = output.amountStation
        self.outputs[output.itemClass.name].amountContainer = output.amountContainer
        self.outputs[output.itemClass.name].maxAmountStation = output.maxAmountStation
        self.outputs[output.itemClass.name].maxAmountContainer = output.maxAmountContainer
    end
    --local J = JSON.new { indent = 2, sort_keys = true }
    --local s2 = J:encode(self)
    --print(s2)
end

function FabricInfo:updateInput(input)
    local J = JSON.new { indent = 2, sort_keys = true }
    local s = J:encode(input)
    --print(s)
    if self.inputs[input.itemClass.name] == nil then
        self.inputs[input.itemClass.name] = input
    else
        self.inputs[input.itemClass.name].amountStation = input.amountStation
        self.inputs[input.itemClass.name].amountContainer = input.amountContainer
    end
    --local J = JSON.new { indent = 2, sort_keys = true }
    --local s2 = J:encode(self)
    --print(s2)
end

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
