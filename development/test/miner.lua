local config = require("config")
local helper = require("shared.helper")
local pj = helper.pj



--- Liest Fluid-Level einer (Fluid-)Freight-Platform.
--- Gibt (current, max, fluidClassOrNil) zurück.
---@param platform any  -- FIN Actor-Proxy der Plattform
---@return number, number, any
local function read_platform_fluid(platform)
    if not platform or type(platform.getComponents) ~= "function" then
        return 0, 0, nil
    end

    -- 1) Bevorzugt: internen Tank (PipeReservoir) nehmen -> hat content + max
    local reservoirs = {}
    -- In FIN kann man Klassenobjekte an getComponents übergeben:
    -- meist via globaler 'classes' Tabelle erreichbar.
    local ok, cls = pcall(function() return classes.PipeReservoir end)
    if ok and cls then
        local ok2, arr = pcall(function() return platform:getComponents(cls) end)
        if ok2 and type(arr) == "table" and arr[1] then reservoirs = arr end
    end

    pj(reservoirs)

    if reservoirs[1] then
        print("Found Reservoir")
        local r = reservoirs[1]
        local cur = tonumber(r.fluidContent) or 0
        local max = tonumber(r.maxFluidContent) or 0

        -- Optional: Fluid-Typ (ItemType-Class) mitgeben
        local ftype = nil
        if type(r.getFluidType) == "function" then
            local okT, t = pcall(function() return r:getFluidType() end)
            if okT then ftype = t end
        end
        return cur, max, ftype
    end

    -- 2) Fallback: PipeConnections summieren (liefert Inhalt, aber kein Max).
    -- Nützlich, wenn kein Reservoir exponiert ist.
    local total = 0
    if type(platform.getPipeConnectors) == "function" then
        local okC, conns = pcall(function() return platform:getPipeConnectors() end)
        if okC and type(conns) == "table" then
            for _, pc in ipairs(conns) do
                local amt = tonumber(pc.fluidBoxContent) or 0
                total = total + amt
            end
        end
    end
    -- Max unbekannt ohne Reservoir; 0 signalisiert "unbekannt".
    return total, 0, nil
end



local function read_platform_fluid2(platform)
    -- comps = platform:getComponents(classes.PipeReservoir
    local inventory = platform:getInventories()[1]
    if not inventory then
        return 0, 0, nil
    end
    size = inventory.itemCount
    local fluid = inventory:getStack(0)
    print(size .. " m³".. (fluid.count / 1000) .. " m³", fluid.item.type.name)


    pcbs = platform:getComponents(classes.PipeConnectionBase)
    pj(pcbs)
    for _, pcb in pairs(pcbs) do
        pj(pcb:getConnection())
    end
end
-- Beispiel-Nutzung:
-- local platform = byAllNick("EN_Your Fluid Platform Nick") -- oder dein vorhandener Proxy
-- local cur, max, ftype = read_platform_fluid(platform)
-- print("Fluid:", cur, "/", (max > 0 and max or "unknown"), "type:", ftype and tostring(ftype) or "n/a")

function station_fluid()
    cn = component.findComponent("Trainstation Rohoel")

    station = component.proxy(cn[1])


    local platforms = station:getAllConnectedPlatforms() or {}
    for _, p in pairs(platforms) do
        local cur, max, ftype = read_platform_fluid2(p)

        --    pj(cur)
        --  pj(max)
        --pj(ftype)

        --    totals, types = readInventory(p, totals, types)
        --    maxSlots = maxSlots + getMaxSlotsForContainer(p)
    end
end

function tanks()
    cn = component.findComponent("Tank Rohoel")
    tank = component.proxy(cn[1])

    -- for _, n in pairs(cn) do
    --    local tank = component.proxy(n)
    pj(tank.fluidContent)
    pj(tank.maxFluidContent)
    -- end
end

station_fluid()

