---@diagnostic disable: lowercase-global


local helper = require("shared.helper")
local de_umlaute = helper.de_umlaute
local byAllNick = helper.byAllNick
local is_str = helper.is_str

local log = require("shared.helper_log").log




local MyItemList = require("shared.items.items[-LANGUAGE-]")
local MyItem     = require("shared.items.items_basics").MyItem


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
    self.fType = factory.fType or self.fType
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
---@param prefix string
---@param factoryName string|nil
---@param itemStack any|nil
---@return boolean, string|nil, string|nil  -- ok, nickOrNil, err
local function _make_nick(prefix, factoryName, itemStack)
    -- de_umlaute darf fehlen; dann Fallback = identity
    local _de = type(de_umlaute) == "function" and de_umlaute or function(x) return x end

    if not is_str(prefix) or prefix == "" then
        return false, nil, "nick: prefix must be non-empty string"
    end

    -- 3 Modi:
    -- A) nur factoryName  -> "<prefix> <factoryName>"
    -- B) itemStack-Output -> "<prefix> <itemName>"
    -- C) itemStack-Input  -> "<prefix> <itemName>2<factoryName>"

    if itemStack == nil then
        if not is_str(factoryName) or factoryName == "" then
            return false, nil, "nick: factoryName must be non-empty string"
        end
        return true, (prefix .. " " .. _de(factoryName)), nil
    end

    -- itemStack-Variante
    local ok_isOutput = (type(itemStack) == "table") and (type(itemStack.isOutput) == "function")
    local ok_itemClass = (type(itemStack) == "table")
        and (type(itemStack.itemClass) == "table")
        and is_str(itemStack.itemClass.name)

    if not ok_isOutput then
        return false, nil, "nick: itemStack.isOutput() missing"
    end
    if not ok_itemClass then
        return false, nil, "nick: itemStack.itemClass.name missing"
    end

    local itemName = _de(itemStack.itemClass.name)
    if itemStack:isOutput() then
        return true, (prefix .. " " .. itemName), nil
    else
        if not is_str(factoryName) or factoryName == "" then
            return false, nil, "nick: factoryName required for non-output stacks"
        end
        return true, (prefix .. " " .. itemName .. "2" .. _de(factoryName)), nil
    end
end

--- Ruft byAllNick mit Kontext-Fehlermeldungen auf
---@param ctx string
---@param nick string
---@return boolean, table[]|nil, string|nil
local function _find_all_by_nick(ctx, nick)
    local ok, comps, err = byAllNick(nick)
    if not ok then
        return false, nil, string.format("%s: byAllNick(%q) failed: %s", ctx, nick, _to_str(err))
    end
    -- ok=true; comps kann {} sein (kein Treffer) – das ist absichtlich KEIN Fehler
    return true, comps, nil
end

--- Optional: „erster Treffer“-Helfer mit sauberem Fehler bei 0 Treffern
---@param ctx string
---@param nick string
---@return boolean, table|nil, string|nil
local function _find_one_by_nick_or_err(ctx, nick)
    local ok, comps, err = _find_all_by_nick(ctx, nick)
    if not ok then return false, nil, err end
    if #comps == 0 then
        return false, nil, string.format("%s: no component found for nick %q", ctx, nick)
    end
---@diagnostic disable-next-line: need-check-nil
    return true, comps[1], nil
end

--------------------------------------------------------------------------------
-- Wrapper: Manufacturer / Miner / Container / Trainstation / Trainsignal
-- Rückgabe überall: ok:boolean, result:table[]|table|nil, err:string|nil
--  - *_All...  : alle Treffer ({} bei 0 Treffern, ok=true)
--  - *_One...  : genau ein erster Treffer; 0 Treffer => ok=false + err
--------------------------------------------------------------------------------

---@param factoryName string
---@return boolean, Manufacturer[]|nil, string|nil
local function manufacturersByFactoryName(factoryName)
    local ok, nick, e = _make_nick("Manufacturer", factoryName, nil)
    if not ok then return false, nil, "manufacturersByFactoryName: " .. e end
---@diagnostic disable-next-line:  param-type-mismatch
    return _find_all_by_nick("manufacturersByFactoryName", nick)
end

---@param factoryName string
---@return boolean, Manufacturer|nil, string|nil
local function manufacturerByFactoryName(factoryName)
    local ok, nick, e = _make_nick("Manufacturer", factoryName, nil)
    if not ok then return false, nil, "manufacturerByFactoryName: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_one_by_nick_or_err("manufacturerByFactoryName", nick)
end

---@param factoryName string
---@return boolean, FGBuildableResourceExtractor[]|nil, string|nil
local function minersByFactoryName(factoryName)
    local ok, nick, e = _make_nick("Miner", factoryName, nil)
    if not ok then return false, nil, "minersByFactoryName: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_all_by_nick("minersByFactoryName", nick)
end

---@param factoryName string
---@return boolean, FGBuildableResourceExtractor|nil, string|nil
local function minerByFactoryName(factoryName)
    local ok, nick, e = _make_nick("Miner", factoryName, nil)
    if not ok then return false, nil, "minerByFactoryName: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_one_by_nick_or_err("minerByFactoryName", nick)
end

---@param factoryName string
---@param itemStack any  -- erwartet .isOutput():boolean und .itemClass.name:string
---@return boolean, FGBuildableStorage[]|nil, string|nil
local function containersByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Container", factoryName, itemStack)
    if not ok then return false, nil, "containersByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_all_by_nick("containersByFactoryStack", nick)
end

---@param factoryName string
---@param itemStack any
---@return boolean, FGBuildableStorage|nil, string|nil
local function containerByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Container", factoryName, itemStack)
    if not ok then return false, nil, "containerByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_one_by_nick_or_err("containerByFactoryStack", nick)
end

---@param factoryName string
---@param itemStack any
---@return boolean, RailroadStation[]|nil, string|nil
local function trainstationsByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Trainstation", factoryName, itemStack)
    if not ok then return false, nil, "trainstationsByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_all_by_nick("trainstationsByFactoryStack", nick)
end

---@param factoryName string
---@param itemStack any
---@return boolean, RailroadStation|nil, string|nil
local function trainstationByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Trainstation", factoryName, itemStack)
    if not ok then return false, nil, "trainstationByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_one_by_nick_or_err("trainstationByFactoryStack", nick)
end

---@param factoryName string
---@param itemStack any
---@return boolean, RailroadSignal[]|nil, string|nil
local function trainsignalsByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Trainsignal", factoryName, itemStack)
    if not ok then return false, nil, "trainsignalsByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_all_by_nick("trainsignalsByFactoryStack", nick)
end

---@param factoryName string
---@param itemStack any
---@return boolean, RailroadSignal|nil, string|nil
local function trainsignalByFactoryStack(factoryName, itemStack)
    local ok, nick, e = _make_nick("Trainsignal", factoryName, itemStack)
    if not ok then return false, nil, "trainsignalByFactoryStack: " .. e end
    ---@diagnostic disable-next-line:  param-type-mismatch
    return _find_one_by_nick_or_err("trainsignalByFactoryStack", nick)
end


-- Modul-Export ----------------------------------------------------------------
return {
    FactoryStack               = FactoryStack,
    Input                      = Input,
    Output                     = Output,
    FactoryInfo                = FactoryInfo,
    containerByFactoryStack    = containerByFactoryStack,
    containersByFactoryStack   = containersByFactoryStack,
    trainstationByFactoryStack = trainstationByFactoryStack,
    trainstationsByFactoryStack= trainstationsByFactoryStack,
    trainsignalByFactoryStack  = trainsignalByFactoryStack,
    trainsignalsByFactoryStack = trainsignalsByFactoryStack,
    manufacturerByFactoryName  = manufacturerByFactoryName,
    manufacturersByFactoryName = manufacturersByFactoryName,
    minerByFactoryName         = minerByFactoryName,
    minersByFactoryName        = minersByFactoryName,
}
