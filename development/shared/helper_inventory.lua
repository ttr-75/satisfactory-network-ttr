---@diagnostic disable: lowercase-global


local helper = require("shared.helper")
local Helper_log = require("shared.helper_log")
local log = Helper_log.log



-------------------------------
-- Inventories
-------------------------------
-- Slot-Anzahl eines Containers bestimmen.
-- Besser als „0..100 probieren“: erst API nutzen (size/getSize/getCapacity); Fallback: kurzer Scan.
local function getMaxSlotsForContainer(container)
  if not container then return 0 end

  -- Versuche an die Inventories zu kommen:
  local invs = (container.getInventories and container:getInventories()) or 0
  if not invs or #invs == 0 then return 0 end

  local inv = invs[1]
  if not inv then return 0 end

  -- 1) Direkte Größe?
  if inv.size then return inv.size end
  if inv.getSize then
    local ok, sz = pcall(function() return inv:getSize() end)
    if ok and type(sz) == "number" then return sz end
  end
  if inv.getCapacity then
    local ok, cap = pcall(function() return inv:getCapacity() end)
    if ok and type(cap) == "number" then return cap end
  end
  if inv.getSlotCount then
    local ok, sc = pcall(function() return inv:getSlotCount() end)
    if ok and type(sc) == "number" then return sc end
  end

  -- 2) Fallback: knapper Scan (z. B. bis 128); stop, wenn getStack(i) nil liefert
  local maxSlots = 0
  for i = 0, 128 do
    local ok, stack = pcall(function() return inv:getStack(i) end)
    if not ok or stack == nil then
      break
    end
    maxSlots = maxSlots + 1
  end
  return maxSlots
end

-- Liest die erste Inventory des Containers aus und aggregiert nach Item-Typ.
-- totals: Map hash -> Summe; types: Map hash -> item.type (für Namen/MaxStack)
local function readInventory(container, totals, types)
  if not (container and container.getInventories) then return {}, {} end

  local invs = container:getInventories()
  local inv  = invs and invs[1]
  if not inv then return {}, {} end

  totals     = totals or {}
  types      = types or {}

  -- Größe ermitteln (Property oder Methode)
  local size = inv.size
  if not size and inv.getSize then
    local ok, sz = pcall(function() return inv:getSize() end)
    size = ok and sz or nil
  end
  if type(size) ~= "number" then
    -- Fallback: konservativ 0..127 scannen
    size = 128
  end

  for slot = 0, size - 1 do
    local ok, stack = pcall(function() return inv:getStack(slot) end)
    if not ok then break end
    if stack and stack.count and stack.count > 0 and stack.item and stack.item.type then
      local t     = stack.item.type
      local key   = t.hash
      totals[key] = (totals[key] or 0) + stack.count
      types[key]  = types[key] or t
    end
  end
  return totals, types
end

--- Summiert Items & Kapazitäten über eine Menge "Container-ähnlicher" Objekte.
--- Erwartet: getMaxSlotsForContainer(obj), readInventory(obj, totals, types)
---@param objs FGBuildableStorage[]|nil
---@param itemMax integer
---@return integer count, integer maxAmount
local function sumContainers(objs, itemMax)
  local maxSlots, totals, types = 0, {}, {}
  for _, obj in pairs(objs or {}) do
    maxSlots = maxSlots + getMaxSlotsForContainer(obj)
    totals, types = readInventory(obj, totals, types)
  end
  local count = 0
  for _, cnt in pairs(totals) do
    count = count + (cnt or 0)
  end
  return count, maxSlots * (itemMax or 0)
end

--- Summiert Items & Kapazitäten über eine Menge "Container-ähnlicher" Objekte.
--- Erwartet: getMaxSlotsForContainer(obj), readInventory(obj, totals, types)
---@param objs PipeReservoir[]|nil
---@return integer count, integer maxAmount
local function sumTanks(objs)
  local max, total = 0, 0
  for _, obj in pairs(objs or {}) do
    max = max + obj.maxFluidContent
    total = total + obj.fluidContent
    if (total > max) then
      total = max
    end
  end

  return total, max
end

--- Summiert Items & Kapazitäten über alle Plattformen aller Trainstations.
---@param stations RailroadStation[]|nil
---@param itemMax integer
---@return integer count, integer maxAmount
local function sumTrainstations(stations, itemMax)
  local count, max = 0, 0
  -- local maxSlots, totals, types = 0, {}, {}
  for _, station in pairs(stations or {}) do
    local platforms = station:getAllConnectedPlatforms() or {}
    for _, p in pairs(platforms) do
      if p and p:isA(classes.Build_TrainPlatformDockingSideFluid_C) then
        print("Fluid platform found" .. type(p))
        local inventory = p:getInventories()[1]
        local fluid = inventory:getStack(0)
        cnt = (fluid.count or 0) / 1000
        count = count + math.floor(cnt)
        max = max + 1800
      else
        print("Solid platform found" .. type(p))
        local totals, types = readInventory(p, {}, {})
        local maxSlots = getMaxSlotsForContainer(p)
        print("Max:" .. maxSlots)
        for _, cnt in pairs(totals) do
          count = count + (cnt or 0)
        end
        max = (maxSlots or 0) * (itemMax or 0)
      end
    end
  end

  return count, max
end


-- Miners
-- Hilfsfunktion: ersten belegten Stack in einem Inventory finden
---comment
---@param inv Inventory
---@return { count: integer, item: ItemType-Class}|nil
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
---comment
---@param miner FGBuildableResourceExtractor
---@return table
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
---comment
---@param miner FGBuildableResourceExtractor
---@return { count: integer, item: ItemType-Class }|nil
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
---@param miner FGBuildableResourceExtractor
---@param activeTimeoutSeconds integer|nil
---@return { count: integer, item: ItemType-Class }|nil  -- item.type oder nil
local function readMinedItemStack(miner, activeTimeoutSeconds)
  local active = (miner.standby == false) -- Factory.standby
  if not active then
    -- Inaktiv: einmal probieren, sonst skip (nil)
    return scanOnce(miner)
  end

  -- Aktiv: wiederholen bis etwas im Inventar landet
  local timeout = tonumber(activeTimeoutSeconds) or 30
  local deadlineTicks = math.floor(timeout / 0.2)
  local stack = nil
  for i = 1, deadlineTicks do
    stack = scanOnce(miner)
    if stack then return stack end
    helper.sleep_ms(200) -- kurz yielden, dann erneut prüfen
  end

  return nil -- Sicherheit: falls nach Timeout immer noch nichts da ist
end

return {
  getMaxSlotsForContainer = getMaxSlotsForContainer,
  readInventory           = readInventory,
  sumContainers           = sumContainers,
  sumTanks                = sumTanks,
  sumTrainstations        = sumTrainstations,
  readMinedItemStack      = readMinedItemStack
}
