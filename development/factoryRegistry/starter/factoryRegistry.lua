require("config.lua")
FactoryRegistryServer = require("factoryRegistry/FactoryRegistryServer_Main.lua")



local regServer = FactoryRegistryServer.new()


while true do
    future.run()
    --regServer:callForUpdates()
end
