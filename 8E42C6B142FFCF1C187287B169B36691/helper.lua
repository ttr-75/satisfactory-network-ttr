----------------------------------------------------------------
-- helper.lua – Kleine Helferlein für Logging, Zeit, Inventories, JSON, Events
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------

-------------------------------
-- Logging
-------------------------------
-- Hinweis: LOG_MIN sollte global gesetzt sein (z. B. 0=Info, 1=Info+, 2=Warn, 3=Error, 4=Fatal)
-- Alte Version nutzte table.concat({ ... }, " "), was crasht, wenn ... Nicht-Strings enthält. (fix)
local function _to_strings(tbl)
  local out = {}
  for i = 1, #tbl do out[i] = tostring(tbl[i]) end
  return out
end

function log(level, ...)
  if level >= (LOG_MIN or 0) then
    local parts = _to_strings({ ... }) -- robust bei Zahlen, Booleans, Tabellen (tostring)
    computer.log(level, table.concat(parts, " "))
  end
end

-- Beispiel:
-- log(0, "Hello", 123, true)  -> "Hello 123 true"

-------------------------------
-- Zeit & Sleep
-------------------------------
-- now_ms: bevorzugt FN's computer.millis(), sonst Fallback os.clock()
function now_ms()
  return (computer and computer.millis and computer.millis())
      or math.floor(os.clock() * 1000)
end

-- Kooperativer Sleep: blockiert mindestens ms Millisekunden, lässt aber Events durch (event.pull)
function sleep_ms(ms)
  if not ms or ms <= 0 then return end
  local deadline = now_ms() + ms
  while true do
    local remaining = deadline - now_ms()
    if remaining <= 0 then break end
    event.pull(math.min(remaining, 250) / 1000) -- max 250ms pro Pull hält UI/Netzwerk reaktiv
  end
end

function sleep_s(seconds)
  sleep_ms(math.floor((seconds or 0) * 1000))
end

-- Throttle-Wrapper: ruft fn höchstens alle interval_ms auf.
-- Achtung: Rückgabewert von fn geht nur dann durch, wenn ein Call ausgeführt wurde.
function throttle_ms(fn, interval_ms)
  local last = 0
  return function(...)
    local t = now_ms()
    if t - last >= interval_ms then
      last = t
      return fn(...)
    end
    -- sonst still ignorieren (nil-Return)
  end
end

-------------------------------
-- Strings
-------------------------------
-- Prüft, ob s länger als x ist (defensiv & leise).
function is_longer_than(s, x)
  if type(s) ~= "string" then return false end
  if type(x) ~= "number" then return false end
  return #s > x
end

-- Umlaute „de“-kodieren (ä→ae, ö→oe, ü→ue, Ä→Ae, Ö→Oe, Ü→Ue, ß→ss)
-- Alte Version: viele gsubs nacheinander; hier 1x Mapping + ein gsub.

function de_umlaute(s)
  if s == nil then return nil end
  assert(type(s) == "string", "String erwartet")
  -- Ersetzt jedes Zeichen, das NICHT Buchstabe (%a), Ziffer (%d) oder Leerzeichen ist.
  return (s:gsub("ä", "ae"):gsub("ü", "ue"):gsub("ö", "oe"):gsub("Ä", "Ae"):gsub("Ü", "Ue"):gsub("Ö", "Oe"):gsub("ß", "ss"):gsub(" ", ""))
  --return s
end

-------------------------------
-- Komponenten
-------------------------------
-- Proxy über Nickname holen (wirft assert mit klarer Fehlermeldung)
function byNick(nick)
  local t = component.findComponent(nick)[1]
  assert(t, "Komponente '" .. tostring(nick) .. "' nicht gefunden")
  return component.proxy(t)
end

-- Alle Proxys über Nickname holen (array)
function byAllNick(nick)
  local refs = component.findComponent(nick)
  assert(refs and #refs > 0, "Komponente '" .. tostring(nick) .. "' nicht gefunden")
  local arr = {}
  for i, ref in ipairs(refs) do
    local prox = component.proxy(ref)
    assert(prox, "Proxy für '" .. tostring(nick) .. "' nicht gefunden (Index " .. i .. ")")
    arr[#arr + 1] = prox
  end
  return arr
end

-------------------------------
-- Inventories
-------------------------------
-- Slot-Anzahl eines Containers bestimmen.
-- Besser als „0..100 probieren“: erst API nutzen (size/getSize/getCapacity); Fallback: kurzer Scan.
function getMaxSlotsForContainer(container)
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
function readInventory(container, totals, types)
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

-------------------------------
-- JSON Pretty-Print
-------------------------------
-- pretty_json(value, opts) → string
-- opts = { indent=2, sort_keys=true, cycle="<cycle>" }
function pretty_json(value, opts)
  local J = JSON.new(opts or { indent = 2, sort_keys = true })
  return J:encode(value)
end

-- Kurzform zum Dumpen (print + JSON)
function pj(value)
  print(pretty_json(value))
end

-------------------------------
-- Listener-Debug-Helfer
-------------------------------
-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
  return function(err)
    local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
    computer.log(4, tb)
    return tb
  end
end

-- safe_listener(tag, fn): verpackt fn in xpcall, sodass Fehler nicht „leise“ bleiben.
function safe_listener(tag, fn)
  assert(type(fn) == "function", "safe_listener needs a function")
  return function(...)
    local ok, res = xpcall(fn, _traceback(tag), ...)
    return res
  end
end

-- hübsches Argument-Logging
function fmt_args(...)
  local t = table.pack(...)
  for i = 1, t.n do t[i] = tostring(t[i]) end
  return table.concat(t, ", ")
end
