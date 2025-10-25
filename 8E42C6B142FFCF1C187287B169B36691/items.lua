MyItem = {
    name = nil,
    id = nil,
    ref = nil
}

MyItem.__index = MyItem
function MyItem.new(o)
    return setmetatable(o or {}, MyItem)
end

function MyItem:getRef()
    if self.ref ~= nil then
        return self.ref
    end
    return "icon:" .. self.id
end

function MyItem:getCodeName()   
    return de_umlaute(self.name)
end

-- BiMap: bijective map (each key maps to exactly one value and vice versa)
local MyItemList = {}
MyItemList.__index = MyItemList

function MyItemList.new()
    return setmetatable({ k2v = {}, v2k = {} }, MyItemList)
end

function MyItemList:addItem(item)
    local name    = item.name
    local id      = item.id;

    -- remove old pairings to keep it bijective
    local oldId = self.k2v[name]
    if oldId ~= nil then self.v2k[oldId] = nil end
    local oldName = self.v2k[id]
    if oldName ~= nil then self.k2v[oldName] = nil end
    self.k2v[name] = item
    self.v2k[id] = item
end

function MyItemList:get_by_Name(name) return self.k2v[name] end

function MyItemList:get_by_Id(id) return self.v2k[id] end

function MyItemList:delete_by_Name(name)
    local item = self.k2v[name]
    local id = item.id
    if item ~= nil then
        self.k2v[name] = nil; self.v2k[id] = nil
    end
end

function MyItemList:delete_by_Id(id)
    local item = self.v2k[id]
    local name = item.name
    if item ~= nil then
        self.v2k[id] = nil; self.k2v[name] = nil
    end
end

function MyItemList:size()
    local n = 0; for _ in pairs(self.k2v) do n = n + 1 end; return n
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------
MyItemList = MyItemList.new()
-- Parts
MyItem.PLATINE = MyItem.new({ name = "Platine", id = 243 })
MyItem.TURBODRAHT = MyItem.new({ name = "Turbodraht", id = 274 })
MyItem.STAHLTRAEGER = MyItem.new({ name = "Stahlträger", id = 219 })
MyItem.MEHRZWECKGERUEST = MyItem.new({ name = "Mehrzweckgerüst", id = 244 })


MyItemList:addItem(MyItem.PLATINE)
MyItemList:addItem(MyItem.TURBODRAHT)
MyItemList:addItem(MyItem.STAHLTRAEGER)
MyItemList:addItem(MyItem.MEHRZWECKGERUEST)

-- Buildings
MyItem.ASSEMBLER = MyItem.new({ name = "Assembler", id = 59 })

MyItemList:addItem(MyItem.ASSEMBLER)


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
