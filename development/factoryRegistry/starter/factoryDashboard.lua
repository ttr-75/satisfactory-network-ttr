require("config")

local Log              = require("shared.helper_log")
local log              = Log.log
local tb               = Log.traceback

FactoryDashboardClient = require("factoryRegistry.FactoryDashboard_Main")

-- Weiche Validierung: keine harten Stops
local function _is_empty(s) return s == nil or tostring(s) == "" end
if _is_empty(fName) then
    log(4, "factoryDashboard.lua: fName is required (nil/empty) – waiting for configuration...")
end
if _is_empty(scrName) then
    log(3, "factoryDashboard.lua: scrName not set – will try to run headless until a screen appears")
end

require("shared.helper").sleep_ms(math.random((TTR_FIN_Config and TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL * 1000) or
1000))                                                                                                                            -- kleine Initial-Verzögerung



-- Robuste Konstruktion mit Retry (5s Backoff), passend zur New-Signatur (ok,self,err)
local cli
while true do
    local ok, obj, err = FactoryDashboardClient.new { fName = fName, scrName = scrName }
    if ok and obj then
        cli = obj
        break
    end
    -- NO_FACTORY_INFO o.ä.: loggen und erneut probieren
    log(4, ("factoryDashboard.lua: client init failed [%s] %s – retry in 5s")
        :format(err and err.code or "?", err and err.message or "unknown"))
    event.pull(5.0)
end

-- optional: Name/Tag für sauberere Logs
local LOOP_TAG = "FactoryDashboardStarter"

future.addTask(async(function()
    log(0, "[loop] start:", LOOP_TAG)

    local TICK = TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL or 0.2
    local BACKOFF = 0.5

    while true do
        -- Pro Tick geschützt
        local iter_ok = xpcall(function()
            event.pull(TICK)

            -- Falls der Client sich selbst fatal markiert hat → schließen & retry bauen
            if cli:isFatal() then
                local err = cli:getError()
                log(4, ("[loop] fatal state: %s (%s) – closing adapter")
                    :format(err and err.message or "unknown", err and err.code or "?"))
                pcall(function() cli:close("fatal") end) -- nutzt NetHub:unregister
                -- Neuaufbau versuchen (gleiche Logik wie oben)
                while true do
                    local ok2, obj2, e2 = FactoryDashboardClient.new { fName = fName, scrName = scrName }
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
            local ok3 = cli:callForUpdate()
            if not ok3 then
                -- callForUpdate liefert bei Soft-Fehlern false – kleiner Backoff
                event.pull(BACKOFF)
            end
        end, tb(LOOP_TAG))

        if not iter_ok then
            -- Stacktrace ist bereits geloggt – kleiner Cooldown gegen Spam
            event.pull(BACKOFF)
        end
    end
end))



future.loop()
