-- factoryRegistry.starter.factoryInfoCollector

require("config")


local sleep_s        = require("shared.helper").sleep_s
local Log            = require("shared.helper_log")
local log            = Log.log
local tb             = Log.traceback

FactoryDataCollector = require("factoryRegistry.FactoryDataCollector_Main")



---@diagnostic disable-next-line: undefined-global
assert(fName, "factoryInfoCollector.lua - fName must been set.")


sleep_s(1)

local cli = nil
---@diagnostic disable-next-line: undefined-global
if not stationMin then
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollector.new { fName = fName }
else
    ---@diagnostic disable-next-line: undefined-global
    cli = FactoryDataCollector.new { fName = fName, stationMin = stationMin }
end


-- optional: Name/Tag für sauberere Logs
local LOOP_TAG = "FactoryInfoCollectorStarter"

future.addTask(async(function()
    log(0, "[loop] start:", LOOP_TAG)


    while true do
        -- Schutz pro Tick: Fehler killen nicht den gesamten Task
        local ok = xpcall(function()
            event.pull(TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL or 0.2)
            cli:checkTrainsignals()
        end, tb(LOOP_TAG)) -- nutzt deinen traceback-Logger

        -- Falls eine Iteration scheitert, wurde der Stacktrace bereits geloggt.
        -- Hier kannst du optional Backoff/Telemetry setzen:
        if not ok then
            -- Kleiner Cooldown verhindert „Fehler-Spam“ bei harten Dauerfehlern
            event.pull(0.1)
            -- oder: log(2, "[loop] tick failed — continuing:", LOOP_TAG)
        end
    end
end))


future.loop()
