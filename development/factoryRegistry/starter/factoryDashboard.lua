require("config")

local Log              = require("helper_log") -- ggf. "shared.helper_log"
local log              = Log.log
local tb               = Log.traceback

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
-- optional: Name/Tag für sauberere Logs
local LOOP_TAG = "FactoryDashboardStarter"

future.addTask(async(function()
    log(0, "[loop] start:", LOOP_TAG)

    -- Endlosschleife bleibt bestehen, aber jede Iteration ist separat geschützt
    while true do
        -- Schutz pro Tick: Fehler killen nicht den gesamten Task
        local ok = xpcall(function()
            event.pull(TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL or 0.2)
            cli:callForUpdate()
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
