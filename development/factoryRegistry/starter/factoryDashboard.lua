require("config.lua")
FactoryDashboardClient = require("factoryRegistry/FactoryDashboard_Main.lua")


--}



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
cli:run()
