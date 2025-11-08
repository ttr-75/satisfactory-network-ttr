--[[
local name = "starter.checkVentile"
local ventils = nil
local tanks = nil
local KEEP_FREE = 1000
]]


require("config")
require("shared.helper_inventory")
local log = require("shared.helper_log").log
local sumTanks = require("shared.helper_inventory").sumTanks
local pj = require("shared.helper").pj
local romanize = require("shared.helper").romanize



---@param factoryName string
---@param itemStack any  -- erwartet .isOutput():boolean und .itemClass.name:string
---@return boolean, FGBuildableStorage[]|nil, string|nil
local function tanks(tankName)
    local nick = "Tank " .. romanize(tankName)
    ---@diagnostic disable-next-line:  param-type-mismatch
    local tanks = {}
    local ids = component.findComponent(nick)
    for i = 1, #ids do
        tanks[i] = component.proxy(ids[i])
    end
    return tanks
end

---@param factoryName string
---@param itemStack any  -- erwartet .isOutput():boolean und .itemClass.name:string
---@return boolean, FGBuildableStorage[]|nil, string|nil
local function ventils(ventilName)
    local nick = "Ventil " .. romanize(ventilName)
    ---@diagnostic disable-next-line:  param-type-mismatch
    local ventils = {}
    local ids = component.findComponent(nick)
    for i = 1, #ids do
        ventils[i] = component.proxy(ids[i])
    end
    return ventils
end


if not tankName or not ventilName then
    log(4, "checkVentile.lua: tankName or ventilName not set in config, exiting.")
    return
end

local tanks = tanks(tankName)
local ventils = ventils(ventilName)

if not ventils then
    log(4, "checkVentile.lua: No ventils configured, exiting.")
    return
end

if not tanks then
    log(4, "checkVentile.lua: No tanks configured, exiting.")
    return
end

if not KEEP_FREE then
    KEEP_FREE = 1000 -- default 1000 mB free
end

local function setFlow(ventils, flow)
    for i = 1, #ventils do
        ventils[i].userFlowLimit = flow
    end
end

future.addTask(
    async(function()
        while true do
            local ok = xpcall(function()
                -- yield, damit der Scheduler nicht blockiert
                event.pull(5)

                local total, max = sumTanks(tanks)
                if total + KEEP_FREE > max then
                    setFlow(ventils, 0)
                    log(0, "set flow to 0")
                else
                    setFlow(ventils, 600)
                    log(0, "set flow to 600")
                end
            end, function(err)
                -- Fehler-Handler: logge und laufe weiter
                log(1, "[ventils-loop] error: ", tostring(err), "\n", debug.traceback())
            end)

            -- falls du bei Fehlern abbrechen willst:
            -- if not ok then break end
        end
    end)
)
log(1, "Started")
future.loop()
