require("config")

FactoryRegistryServer = require("factoryRegistry.FactoryRegistryServer_Main")

require("shared.helper").sleep_ms(math.random(500)) -- kleine Initial-Verzögerung

local regServer = FactoryRegistryServer.new()
--future.addTask(async(function()
   -- xpcall(function()
     --   while true do
       --     event.pull(TTR_FIN_Config.EVENT_LOOP_TIMEOUT or 0.2)
       -- end
    --end, function(err)
    --    computer.log(1, "[loop] error: ", err, "\n", debug.traceback())
    --end)
--end))



future.loop()
