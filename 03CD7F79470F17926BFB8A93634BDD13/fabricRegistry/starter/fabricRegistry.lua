local names = { "shared/helper.lua",
    "shared/items.lua",
    "shared/graphics.lua",
    "fabricRegistry/fabricInfo.lua",
    "fabricRegistry/FabricRegistryServer.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()



local regServer = FabricRegistryServer.new()


while true do
    future.run()
    regServer:callForUpdates()
end
