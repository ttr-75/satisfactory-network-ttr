local names = { "helper.lua",
    "items.lua",
    "fabricInfo.lua",
    "fabricRegistry/FabricRegistryClient.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()



sleep_s(1)

local fi = FabricInfo:new()
fi.fType = MyItem.ASSEMBLER
fi.fName = "Mehrzweckgeruest"



comp = component.findComponent(classes.Manufacturer)


local cli = FabricRegistryClient.new { fabricInfo = fi }


while true do
    future.loop()
end
