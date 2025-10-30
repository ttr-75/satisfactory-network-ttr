require("config")
FactoryRegistryServer = require("factoryRegistry.FactoryRegistryServer_Main")



local regServer = FactoryRegistryServer.new()


while true do
    future.run()
    --regServer:callForUpdates()
end
