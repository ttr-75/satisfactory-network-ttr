local LOG_MIN = 1 -- nur Warn und höher

local function log(level, ...)
    if level >= LOG_MIN then
        computer.log(level, table.concat({ ... }, " "))
    end
end

---local function listInventories(proxy)
---    local invs = proxy:getInventories()
---
--- log(1,proxy.internalName .. #invs)
---
--- for _, inv in pairs(invs) do
---  log(1,inv.internalName .. inv.size)
---end
---end


-- Liest die erste Inventory des Containers aus und aggregiert nach Item-Typ
local function readInventory(container, totals, types)
    local invs = container:getInventories()
    local inv = invs and invs[1]
    if not inv then return {}, {} end

    if totals == nil then
        totals = {}
    end
    if types == nil then
        types = {}
    end
    -- local totals = {} -- key: type.hash -> sum count
    -- local types  = {} -- key: type.hash -> type (für Namen/MaxStack)

    -- Slots sind 0-basiert und gehen bis size-1
    for slot = 0, inv.size - 1, 1 do
        local stack = inv:getStack(slot)
        if stack and stack.count and stack.count > 0 and stack.item and stack.item.type then
            local t = stack.item.type
            local key = t.hash
            totals[key] = (totals[key] or 0) + stack.count
            types[key] = t
        end
    end
    return totals, types
end

---@param max integer
---@param stationid string
local function shouldTrainBeSend(max, stationid)
    local station = component.proxy(stationid) -- The train station
    log(0, "station:" .. station.name)


    local platforms = station:getAllConnectedPlatforms()
    log(0, "# platforms:" .. tostring(#platforms))

    local totals = {}
    local types = {}

    for _, platform in pairs(platforms) do
        totals, types = readInventory(platform, totals, types)
    end

    local counter = 0;

    for key, cnt in pairs(totals) do
        local t = types[key]
        local name = (t and t.name) or ("Type#" .. tostring(key))
        local maxStack = (t and t.max) or nil
        log(0, name .. cnt)
        counter = counter + cnt
        --table.insert(rows, { name = name, count = cnt, max = maxStack })
    end

    log(0, "Total:" .. counter)
    if counter <= max then
        return true
    else
        return false
    end
end

--@param nick_name string
--@return string id
local function getStationID(nick_name)
    return component.findComponent("Trainstation " .. nick_name)[1];
end


--@param nick_name string
--@return string id
local function getSignalID(nick_name)
    return component.findComponent("Trainsignal " .. nick_name)[1];
end

--@param nick_name string
--@return string id
local function getMiniPanellID(nick_name)
    return component.findComponent("MiniPanel " .. nick_name)[1];
end

local stationid = getStationID(nick_name);
local signalid = getSignalID(nick_name);
local miniPanelid = getMiniPanellID(nick_name);

log(1, nick_name);
log(1, stationid);
log(1, signalid);
log(1, miniPanelid);

--@param id  string
--@param status boolean
local function setIndicator(id, status)
    cp = component.proxy(id)
    module = cp:getModule(0, 0)
    if status then
        module:setColor(0.0, 1.0, 0.0, 0.0);
    else
        module:setColor(1.0, 0.0, 0.0, 0.0);
    end
end

--@param id  string
--@param status boolean
local function setSignal(id, status)
    signal = component.proxy(id)
    block = signal:getObservedBlock()
    if status then
        block.isPathBlock = false
    else
        block.isPathBlock = true
    end
end

while true do
    local _shouldTrainBeSend = shouldTrainBeSend(max, stationid)
    ---log(0,_shouldTrainBeSend)
    setIndicator(miniPanelid, _shouldTrainBeSend)
    setSignal(signalid, _shouldTrainBeSend)
end
