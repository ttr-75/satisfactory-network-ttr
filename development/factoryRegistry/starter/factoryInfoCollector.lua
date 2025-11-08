--[[
local name = "factoryRegistry.starter.factoryInfoCollector"

fName="Treibstoff 1"
fIgnore="Polymerharz"
fSignal = false
fManufacturer = nil
stationMin = 1000

]]
require("config")

local Log            = require("shared.helper_log")
local log            = Log.log
local tb             = Log.traceback

FactoryDataCollector = require("factoryRegistry.FactoryDataCollector_Main")

-- Weiche Validierung
local function _is_empty(s) return s == nil or tostring(s) == "" end
---@diagnostic disable-next-line: undefined-global
if _is_empty(fName) then
    log(4, "factoryInfoCollector.lua: fName is required (nil/empty) – waiting for configuration...")
end

-- kleine Initial-Verzögerung, wie gehabt
require("shared.helper").sleep_ms(1000 + math.random(5000)) -- kleine Initial-Verzögerung

if fSignal == nil then
    fSignal = true
end
-- Robuste Konstruktion mit Retry (5s Backoff)
local cli
while true do
    local ok, obj, err
    ---@diagnostic disable-next-line: undefined-global
    local ok, obj, err = FactoryDataCollector.new { fName = fName, stationMin = stationMin, fIgnore = fIgnore, fManufacturer = fManufacturer, fSignal = fSignal }

    if ok and obj then
        cli = obj
        break
    end
    log(4, ("factoryInfoCollector.lua: client init failed [%s] %s – retry in 5s")
        :format(err and err.code or "?", err and err.message or "unknown"))
    event.pull(5.0)
end

-- Loop-Tag für schöne Logs
local LOOP_TAG = "FactoryInfoCollectorStarter"

future.addTask(async(function()
    log(0, "[loop] start:", LOOP_TAG)

    local TICK    = TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL or 0.2
    local BACKOFF = 0.5

    while true do
        local iter_ok = xpcall(function()
            event.pull(TICK)

            -- Fatal? -> sauber schließen & neu aufbauen
            if cli.isFatal and cli:isFatal() then
                local err = cli.getError and cli:getError() or nil
                log(4, ("[loop] fatal state: %s (%s) – closing adapter")
                    :format(err and err.message or "unknown", err and err.code or "?"))
                pcall(function()
                    if cli.close then
                        cli:close("fatal")
                    end
                end)

                -- Reinit + Backoff
                while true do
                    local ok2, obj2, e2
                    ---@diagnostic disable-next-line: undefined-global

                    ---@diagnostic disable-next-line: undefined-global
                    ok2, obj2, e2 = FactoryDataCollector.new { fName = fName, stationMin = stationMin, fIgnore = fIgnore, fManufacturer = fManufacturer, fSignal = fSignal }

                    if ok2 and obj2 then
                        cli = obj2
                        log(1, "[loop] client re-initialized")
                        break
                    end
                    log(4, ("[loop] reinit failed [%s] %s – retry in 5s")
                        :format(e2 and e2.code or "?", e2 and e2.message or "unknown"))
                    event.pull(5.0)
                end
                return
            end

            -- Normales Update
        end, tb(LOOP_TAG))

        if not iter_ok then
            event.pull(BACKOFF)
        end
    end
end))

if fSignal == false then
    log(0, "[loop] signal check disabled:", LOOP_TAG)
else
    future.addTask(async(function()
        log(0, "[loop] start:", LOOP_TAG)

        --local TICK = TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL or 0.2
        local TICK_INTERVAL = 0.5
        local BACKOFF       = 0.5

        while true do
            event.pull(TICK_INTERVAL)
            local iter_ok = xpcall(function()
                --event.pull(TICK)

                -- Fatal? -> sauber schließen & neu aufbauen


                -- Normales Update
                local ok_call = true
                if cli.checkTrainsignals then
                    ok_call = cli:checkTrainsignals()
                    log(0, "[loop] check signal:", LOOP_TAG)
                end
                if not ok_call then
                    event.pull(BACKOFF)
                end
            end, tb(LOOP_TAG))

            if not iter_ok then
                event.pull(BACKOFF)
            end
        end
    end))
end




--[[ Restart loop for scheduled computer restarts according to configuration ]]
future.addTask(async(function()
    log(1, "[loop] restart loop start:", LOOP_TAG)



    while true do
        -- Pro Tick geschützt
        local iter_ok = xpcall(function()
            local min = TTR_FIN_Config.RESTART_COMPUTERS_MIN or 30
            local max = TTR_FIN_Config.RESTART_COMPUTERS_MAX or 60

            if min < 10 then min = 10 end
            if max < min + 5 then max = min + 5 end


            local restart_time = math.random(min * 60, max * 60)
            log(1, ("[loop] restart in %d secondes (%f minutes)"):format(restart_time, restart_time / 60))
            event.pull(restart_time)
            log(2, "[loop] restarting computer now")
            computer.reset()
        end, tb(LOOP_TAG))
    end
end))


future.loop()
