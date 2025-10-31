---@diagnostic disable: lowercase-global
-- DE-Konstanten definieren und Liste zurückgeben

local basic = require("shared.items.items_basics")
local MyItem, MyItemList, MyItemConst = basic.MyItem, basic.MyItemList, basic.MyItemConst

-- 1) DE-KONSTANTEN auf dem separaten Namespace setzen
MyItemConst.SCHWEFEL           = MyItem.new({ name = "Schwefel",           id = 203 })
MyItemConst.PLATINE            = MyItem.new({ name = "Platine",            id = 243 })
MyItemConst.TURBODRAHT         = MyItem.new({ name = "Turbodraht",         id = 274 })
MyItemConst.STAHLTRAEGER       = MyItem.new({ name = "Stahlträger",        id = 219 })
MyItemConst.MODULARER_RAHMEN   = MyItem.new({ name = "Modularer Rahmen",   id = 233 })
MyItemConst.MEHRZWECKGERUEST   = MyItem.new({ name = "Mehrzweckgerüst",    id = 244 })

-- Buildings
MyItemConst.MINER_MK1          = MyItem.new({ name = "Miner Mk.1",         id = 10  })
MyItemConst.ASSEMBLER          = MyItem.new({ name = "Assembler",          id = 59  })

-- Monochrom / Icons
MyItemConst.THUMBS_UP          = MyItem.new({ name = "Thumbs up",          id = 339 })
MyItemConst.THUMBS_DOWN        = MyItem.new({ name = "Thumbs down",        id = 340 })
MyItemConst.POWER              = MyItem.new({ name = "Power",              id = 352 })
MyItemConst.WARNING            = MyItem.new({ name = "Warning",            id = 362 })
MyItemConst.CHECK_MARK         = MyItem.new({ name = "Check Mark",         id = 598 })

-- 2) Liste aus den Konstanten befüllen
local list = MyItemList.new()

-- Parts
list:addItem(MyItemConst.SCHWEFEL)
list:addItem(MyItemConst.PLATINE)
list:addItem(MyItemConst.TURBODRAHT)
list:addItem(MyItemConst.STAHLTRAEGER)
list:addItem(MyItemConst.MODULARER_RAHMEN)
list:addItem(MyItemConst.MEHRZWECKGERUEST)

-- Buildings
list:addItem(MyItemConst.MINER_MK1)
list:addItem(MyItemConst.ASSEMBLER)

-- Monochrom
list:addItem(MyItemConst.THUMBS_UP)
list:addItem(MyItemConst.THUMBS_DOWN)
list:addItem(MyItemConst.POWER)
list:addItem(MyItemConst.WARNING)
list:addItem(MyItemConst.CHECK_MARK)

-- 3) Export (nur die *Liste* als Rückgabewert)
return list
