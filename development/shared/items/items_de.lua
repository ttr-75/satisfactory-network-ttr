---@diagnostic disable: lowercase-global

local helper = require("shared.helper")
local de_umlaute = helper.de_umlaute

--------------------------------------------------------------------------------
-- Types / Klassen
--------------------------------------------------------------------------------

---@class MyItem
---@field name string|nil        -- Anzeigename (deutsch)
---@field id   integer|nil       -- System-/Icon-ID
---@field max  integer|nil       -- max. Stack o.ä. (optional)
---@field ref  string|nil        -- optionaler expliziter Icon-Ref
MyItem = {
    name = nil,
    id = nil,
    max = nil,
    ref = nil
}

MyItem.__index = MyItem

---@param o table|nil
---@return MyItem
function MyItem.new(o)
    return setmetatable(o or {}, MyItem)
end

---@return string  -- Icon-Referenz (z.B. "icon:243")
function MyItem:getRef()
    if self.ref ~= nil then
        return self.ref
    end
    return "icon:" .. self.id
end

---@return string|nil  -- codierter Name (z.B. ohne Umlaute für Keys)
function MyItem:getCodeName()
    return de_umlaute(self.name)
end

---@class MyItemList
---@field k2v table<string, MyItem>  -- Name  -> Item
---@field v2k table<integer, MyItem> -- ID    -> Item
MyItemList = {}
MyItemList.__index = MyItemList

---@return MyItemList
function MyItemList.new()
    return setmetatable({ k2v = {}, v2k = {} }, MyItemList)
end

---@param item MyItem
function MyItemList:addItem(item)
    local name  = item.name
    local id    = item.id;

    -- remove old pairings to keep it bijective
    local oldId = self.k2v[name]
    if oldId ~= nil then self.v2k[oldId] = nil end
    local oldName = self.v2k[id]
    if oldName ~= nil then self.k2v[oldName] = nil end
    if name ~= nil and id ~= nil then
        self.k2v[name] = item
        self.v2k[id] = item
    end
end

---@param name string
---@return MyItem|nil
function MyItemList:get_by_Name(name)
    if self.k2v[name] == nil then
        log(3, "Icon: '" .. name .. "' not implemented yes.")
    end
    return self.k2v[name]
end

---@param id integer
---@return MyItem|nil
function MyItemList:get_by_Id(id)
    if self.v2k[id] == nil then
        log(3, "IconId: '" .. id .. "' not implemented yes.")
    end
    return self.v2k[id]
end

---@param name string
function MyItemList:delete_by_Name(name)
    local item = self.k2v[name]

    if item ~= nil and item.id then
        self.k2v[name] = nil; self.v2k[item.id] = nil
    end
end

---@param id integer
function MyItemList:delete_by_Id(id)
    local item = self.v2k[id]
    if item ~= nil and item.name ~= nil then
        self.v2k[id] = nil; self.k2v[item.name] = nil
    end
end

---@return integer
function MyItemList:size()
    local n = 0; for _ in pairs(self.k2v) do n = n + 1 end; return n
end

--------------------------------------------------------------------------------
-- Items (Konstanten)
--------------------------------------------------------------------------------

---@type MyItemList
MyItemList = MyItemList.new()

-- Parts
---@type MyItem
MyItem.PLATINE = MyItem.new({ name = "Platine", id = 243 })
---@type MyItem
MyItem.TURBODRAHT = MyItem.new({ name = "Turbodraht", id = 274 })
---@type MyItem
MyItem.STAHLTRAEGER = MyItem.new({ name = "Stahlträger", id = 219 })
---@type MyItem
MyItem.MODULARER_RAHMEN = MyItem.new({ name = "Modularer Rahmen", id = 233 })
---@type MyItem
MyItem.MEHRZWECKGERUEST = MyItem.new({ name = "Mehrzweckgerüst", id = 244 })


MyItemList:addItem(MyItem.PLATINE)
MyItemList:addItem(MyItem.TURBODRAHT)
MyItemList:addItem(MyItem.STAHLTRAEGER)
MyItemList:addItem(MyItem.MODULARER_RAHMEN)
MyItemList:addItem(MyItem.MEHRZWECKGERUEST)

-- Buildings
---@type MyItem
MyItem.MINER_MK1 = MyItem.new({ name = "Miner Mk.1 ", id = 10 })
MyItem.ASSEMBLER = MyItem.new({ name = "Assembler", id = 59 })


MyItemList:addItem(MyItem.MINER_MK1)
MyItemList:addItem(MyItem.ASSEMBLER)


-- Monchrom
---@type MyItem
MyItem.THUMBS_UP = MyItem.new({ name = "Thumbs up", id = 339 })
---@type MyItem
MyItem.THUMBS_DOWN = MyItem.new({ name = "Thumbs down", id = 340 })
---@type MyItem
MyItem.POWER = MyItem.new({ name = "Power", id = 352 })
---@type MyItem
MyItem.WARNING = MyItem.new({ name = "Warning", id = 362 })
---@type MyItem
MyItem.CHECK_MARK = MyItem.new({ name = "Check Mark", id = 598 })

MyItemList:addItem(MyItem.THUMBS_UP)
MyItemList:addItem(MyItem.THUMBS_DOWN)
MyItemList:addItem(MyItem.POWER)
MyItemList:addItem(MyItem.WARNING)
MyItemList:addItem(MyItem.CHECK_MARK)

--[[
MyItemList["Platine"] = 243
MyItemList["Turbodraht"] = 274
MyItemList["Stahlträger"] = 219
MyItemList["Mehrzweckgerüst"] = 74


MyItemListEntry = {
    PLATINE = MyItemList["Platine"],
    TURBODRAHT = MyItemList["Turbodraht"],
    STAHLTRAEGER = MyItemList["Stahltraeger"],
    MEHRZWECKGERUEST = MyItemList["Mehrzweckgeruest"],
}

]] --

-- usage
-- local m = MyItemList.new()
-- m:set("alice", 101)
-- print(m:get_by_key("alice"))   --> 101
-- print(m:get_by_value(101))     --> "alice"
