require("config")
FactoryDashboardClient = require("factoryRegistry.FactoryDashboard_Main")


-- Validate required inputs
---@diagnostic disable-next-line: undefined-global
if fName == nil or tostring(fName) == "" then
    error("factoryDashboard.lua: fName is required and must not be nil/empty")
    computer.stop()
end
---@diagnostic disable-next-line: undefined-global
if scrName == nil or tostring(scrName) == "" then
    error("factoryDashboard.lua: scrName is required and must not be nil/empty")
    computer.stop()
end

---@diagnostic disable-next-line: undefined-global
local cli = FactoryDashboardClient.new { fName = fName, scrName = scrName }

future.addTask(async(function()
    xpcall(function()
        while true do
            event.pull(TTR_FIN_Config.EVENT_LOOP_TIMEOUT or 0.2)
            cli:callForUpdate()
        end
    end, function(err)
        computer.log(1, "[loop] error: ", err, "\n", debug.traceback())
    end)
end))



future.loop()
