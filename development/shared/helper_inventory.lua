---@diagnostic disable: lowercase-global

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
---@param objs table
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

--- Summiert Items & Kapazitäten über alle Plattformen aller Trainstations.
---@param stations table
---@param itemMax integer
---@return integer count, integer maxAmount
local function sumTrainstations(stations, itemMax)
  local maxSlots, totals, types = 0, {}, {}
  for _, station in pairs(stations or {}) do
    local platforms = station:getAllConnectedPlatforms() or {}
    for _, p in pairs(platforms) do
      totals, types = readInventory(p, totals, types)
      maxSlots = maxSlots + getMaxSlotsForContainer(p)
    end
  end
  local count = 0
  for _, cnt in pairs(totals) do
    count = count + (cnt or 0)
  end
  return count, maxSlots * (itemMax or 0)
end

return {
  getMaxSlotsForContainer = getMaxSlotsForContainer,
  readInventory           = readInventory,
  sumContainers           = sumContainers,
  sumTrainstations        = sumTrainstations,
}
