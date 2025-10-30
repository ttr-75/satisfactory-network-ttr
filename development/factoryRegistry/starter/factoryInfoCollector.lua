
require("config")
local helper = require("shared.helper")
FactoryDataCollertor = require("factoryRegistry.FactoryDataCollertor_Main")





helper.sleep_s(1)


---@diagnostic disable-next-line: undefined-global
assert(fName, "factoryInfoCollector.lua - fName must been set.")
local cli = nil
---@diagnostic disable-next-line: undefined-global
if not stationMin then
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollertor.new { fName = fName }
else
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollertor.new { fName = fName, stationMin = stationMin }
end

cli:run()
