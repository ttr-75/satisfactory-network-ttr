local names = {
    "config.lua",
    "shared/helper.lua",
    "shared/items/items[-LANGUAGE-].lua",
    "shared/graphics.lua",
    "factoryRegistry/FactoryInfo.lua",
    "factoryRegistry/FactoryRegistryServer_Main.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()



local regServer = FactoryRegistryServer.new()


while true do
    future.run()
    --regServer:callForUpdates()
end
