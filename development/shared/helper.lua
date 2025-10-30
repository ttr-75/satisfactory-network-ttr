---@diagnostic disable: lowercase-global

local Helper_log = require("shared/helper_log.lua")
local log = Helper_log.log
require("shared/serializer.lua")





----------------------------------------------------------------
-- helper.lua – Kleine Helferlein für  Zeit, Inventories, JSON, Events
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------


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

---@param s string
---@return string  -- codierter String (z.B. ohne Umlaute für Keys)
function de_umlaute(s)
  if s == nil then return nil end
  assert(type(s) == "string", "String erwartet")
  -- Ersetzt jedes Zeichen, das NICHT Buchstabe (%a), Ziffer (%d) oder Leerzeichen ist.
  return (s:gsub("ä", "ae"):gsub("ü", "ue"):gsub("ö", "oe"):gsub("Ä", "Ae"):gsub("Ü", "Ue"):gsub("Ö", "Oe"):gsub("ß", "ss"):gsub(" ", ""))
  --return s
end

-- true, wenn sub als *reiner* Teilstring in s vorkommt (kein Pattern)
---@param s string
---@param sub string
---@param caseSensitiv boolean
---@return boolean   -- true, wenn sub als *reiner* Teilstring in s vorkommt (kein Pattern)
function string_contains(s, sub, caseSensitiv)
  if not caseSensitiv then
    caseSensitiv = true
  end
  if caseSensitiv then
    if s == nil or sub == nil then return false end
    return string.find(s, sub, 1, true) ~= nil
  else
    return string_icontains(s, sub)
  end
end

-- case-insensitive Suche (ebenfalls ohne Patterns)
function string_icontains(s, sub)
  if s == nil or sub == nil then return false end
  return string.find(string.lower(s), string.lower(sub), 1, true) ~= nil
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
