require("config")
local helper = require("shared.helper")
FactoryDataCollertor = require("factoryRegistry.FactoryDataCollertor_Main")



---@diagnostic disable-next-line: undefined-global
assert(fName, "factoryInfoCollector.lua - fName must been set.")


helper.sleep_s(1)

local cli = nil
---@diagnostic disable-next-line: undefined-global
if not stationMin then
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollertor.new { fName = fName }
else
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollertor.new { fName = fName, stationMin = stationMin }
end

future.addTask(async(function()
    xpcall(function()
        while true do
            event.pull(TTR_FIN_Config.EVENT_LOOP_TIMEOUT or 0.2)
            cli:checkTrainsignals()
        end
    end, function(err)
        computer.log(1, "[loop] error: ", err, "\n", debug.traceback())
    end)
end))




future.loop()
