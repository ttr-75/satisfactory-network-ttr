local helper = require("shared.helper")
local pj = helper.pj



-- Miner-Item-Reader (FIN Lua)
-- Übergabe: miner = component.proxy("<UUID>")  -- oder via Nick/Find


-- Hilfsfunktion: ersten belegten Stack in einem Inventory finden
local function firstStack(inv)
    if not inv then return nil end
    local size = inv.size or 0
    for slot = 0, size - 1 do
        local stack = inv:getStack(slot)
        if stack and stack.count and stack.count > 0 and stack.item then
            return stack
        end
    end
    return nil
end

-- Alle relevanten Inventare des Miners einsammeln:
local function collectInventories(miner)
    local list = {}
    -- 1) Direkte Inventare des Actors (z.B. Output-/Buffer)
    for _, inv in ipairs(miner:getInventories() or {}) do
        table.insert(list, inv)
    end
    -- 2) Inventare der Factory Connections (Output-Puffer der Ports)
    for _, conn in ipairs(miner:getFactoryConnectors() or {}) do
        local inv = conn:getInventory()
        if inv then table.insert(list, inv) end
    end
    return list
end

-- Einmal über alle Inventare schauen und den ersten Stack zurückgeben
local function scanOnce(miner)
    for _, inv in ipairs(collectInventories(miner)) do
        local s = firstStack(inv)
        if s then return s end
    end
    return nil
end

-- Hauptfunktion:
-- Gibt bei Erfolg eine Table (Stack) zurück (inkl. s.item, s.count, …)
-- oder nil, falls (bei inaktivem Miner) nichts gefunden wurde / Timeout.
local function readMinedItem(miner, activeTimeoutSeconds)
    local active = (miner.standby == false) -- Factory.standby
    if not active then
        -- Inaktiv: einmal probieren, sonst skip (nil)
        return scanOnce(miner)
    end

    -- Aktiv: wiederholen bis etwas im Inventar landet
    local timeout = tonumber(activeTimeoutSeconds) or 30
    local deadlineTicks = math.floor(timeout / 0.2)
    for i = 1, deadlineTicks do
        local stack = scanOnce(miner)
        if stack then return stack end
        helper.sleep_ms(200) -- kurz yielden, dann erneut prüfen
    end
    return nil      -- Sicherheit: falls nach Timeout immer noch nichts da ist
end

miner = component.proxy(component.findComponent("Miner Schwefel")[1])

-- Beispielnutzung:
--local miner = component.proxy("YOUR-MINER-UUID")
local stack = readMinedItem(miner, 45) -- 45s Timeout im aktiven Fall
if stack then
    local name = (stack.item and (stack.item.type and stack.item.type.name or stack.item.type.name  )) or "Unknown"
    print(("Miner fördert: %s (x%d)"):format(name, stack.count or 0))
else
    print("Kein Item gefunden (Miner inaktiv oder Timeout erreicht).")
end


fac = component.proxy(component.findComponent("Factory Mehrzweckgeruest")[1])

pj(fac)