---@diagnostic disable: lowercase-global
---@diagnostic disable: lowercase-global
--[[
  helper.lua – Kleine Helferlein für Zeit, Inventories, JSON, Events
  ---------------------------------------------------------------
  Dieses Modul bündelt wiederverwendbare Utility-Funktionen für:
   • Zeitmessung & kooperatives Sleep
   • String-Checks / -Suche (inkl. deutscher Umlaute)
   • Komponenten-Lookups per Nickname (FicsItNetworks)
   • Schönes JSON-Dumping (pretty print)

  Wichtig:
   • Erwartet, dass `shared/helper_log.lua` ein Log-Interface bereitstellt.
   • Erwartet, dass `shared/serializer.lua` ein globales `JSON`-Objekt registriert,
     z.B. JSON.new({ indent = 2, sort_keys = true }):encode(table).
   • Designed für FicsItNetworks (computer, event, component).

  API bleibt unverändert.
]]

local Helper_log = require("shared.helper_log")
local log = Helper_log.log
local JSON = require("shared.serializer")
local i18n = require("shared.helper[-LANGUAGE-]")



---@param where string  -- Kontext (für Fehlertexte)
---@param fn fun():any  -- Aufruf, der fehlschlagen kann
---@return boolean, any|nil, string|nil
local function pcall_norm(where, fn)
  local ok, res = pcall(fn)
  if not ok then
    -- res enthält hier die Fehlermeldung vom pcall
    return false, nil, string.format("%s: %s", where, tostring(res))
  end
  return true, res, nil
end


----------------------------------------------------------------
-- Zeit & Sleep
----------------------------------------------------------------

--- Liefert Zeitstempel in Millisekunden.
-- Bevorzugt FicsItNetworks `computer.millis()`, fallback `os.clock()`.
-- @return number ms – monotone Millisekunden (Best-Effort)
local function now_ms()
  -- FN: computer.millis() liefert typischerweise monotone Millisekunden.
  -- Fallback: os.clock() ist CPU-Zeit in Sekunden → *1000; nicht perfekt, aber stabil genug.
  return (computer and computer.millis and computer.millis())
      or math.floor(os.clock() * 1000)
end

--- Kooperativer Sleep: blockiert mindestens `ms` Millisekunden,
-- lässt aber Event-Loop durchlaufen (UI/Netzwerk bleibt reaktiv).
-- Intern wird in Scheiben (max 250ms) gewartet.
-- @param ms number Wartezeit in Millisekunden
local function sleep_ms(ms)
  if not ms or ms <= 0 then return end
  local deadline = now_ms() + ms
  while true do
    local remaining = deadline - now_ms()
    if remaining <= 0 then break end
    event.pull(math.min(remaining, 250) / 1000) -- max 250ms pro Pull hält UI/Netzwerk reaktiv
  end
end

--- Sleep in Sekunden (Convenience-Wrapper um `sleep_ms`).
-- @param seconds number Wartezeit in Sekunden
local function sleep_s(seconds)
  sleep_ms(math.floor((seconds or 0) * 1000))
end

--- Throttle-Decorator: ruft `fn` höchstens alle `interval_ms` Millisekunden auf.
-- Calls, die zu früh kommen, werden still verworfen (Rückgabe = nil).
-- @param fn function Die zu drosselnde Funktion
-- @param interval_ms number Mindestabstand zwischen Aufrufen in Millisekunden
-- @return function Gedrosselte Wrapper-Funktion
-- Achtung: Nur wenn ein Aufruf „durchkommt“, wird der Return-Wert von `fn` weitergegeben.
local function throttle_ms(fn, interval_ms)
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

----------------------------------------------------------------
-- Strings
----------------------------------------------------------------


---@param v any
---@return string
local function to_str(v) return v == nil and "nil" or tostring(v) end

---@param v any
---@return boolean
local function is_str(v) return type(v) == "string" end

--- Prüft defensiv, ob `s` länger als `x` ist.
-- @param s any Erwartet string, sonst false
-- @param x any Erwartet number, sonst false
-- @return boolean true, wenn s ein String ist und #s > x
local function is_longer_than(s, x)
  if type(s) ~= "string" then return false end
  if type(x) ~= "number" then return false end
  return #s > x
end

--- Fall-insensitive Teilstring-Suche ohne Patterns.
-- @param s string|nil
-- @param sub string|nil
-- @return boolean true, wenn gefunden
local function string_icontains(s, sub)
  if s == nil or sub == nil then return false end
  return string.find(string.lower(s), string.lower(sub), 1, true) ~= nil
end

--- Fall-sensitive Teilstring-Suche ohne Patterns.
-- @param s string|nil Volltext
-- @param sub string|nil gesuchter Teilstring
-- @param caseSensitiv boolean|nil true = case-sensitive (Default), false = case-insensitive
-- @return boolean true, wenn gefunden
local function string_contains(s, sub, caseSensitiv)
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

local function romanize(s)
  if type(s) ~= "string" then return s end
  return i18n.romanize(s)
end


--------------------------------------------------------------------------------
-- Safe FicsitNetwork Helpers (Nick / Class lookup)
-- Rückgabesignatur überall: ok:boolean, result:any|nil, err:string|nil
--------------------------------------------------------------------------------
---@generic T
---@param t T[]|nil
---@return boolean, T[]|nil, string|nil  -- ok, arrayOrNil, err
local function _normalize_ids(t)
  if t == nil then return true, {}, nil end -- "keine Treffer" ist ok
  if type(t) ~= "table" then return false, nil, "ids: not a table" end
  return true, t, nil
end
--------------------------------------------------------------------------------
-- component.findComponent: akzeptiert String-Query ODER Klasseninstanz
--------------------------------------------------------------------------------

---@param query_or_class string|any  -- Nick-Query oder classes.* Instanz
---@return boolean, string[]|nil, string|nil
local function _safe_find_ids(query_or_class)
  local ok, ids, err = pcall_norm("findComponent", function()
    return component.findComponent(query_or_class) -- kann nil oder table liefern
  end)
  if not ok then return false, nil, err end
  return _normalize_ids(ids)
end

--------------------------------------------------------------------------------
-- component.proxy: genau EIN id -> component oder nil (wenn nicht existent)
--------------------------------------------------------------------------------

---@param id string
---@return boolean, table|nil, string|nil
local function _safe_proxy_one(id)
  if not is_str(id) or id == "" then
    return false, nil, "proxy: invalid id (string expected)"
  end
  local ok, comp, err = pcall_norm("proxy(" .. id .. ")", function()
    return component.proxy(id)
  end)
  if not ok then return false, nil, err end
  if comp == nil then
    -- id existiert nicht (mehr) -> das ist KEIN harter Fehler; caller kann entscheiden
    return true, nil, nil
  end
  return true, comp, nil
end

--------------------------------------------------------------------------------
-- byNick: erster Treffer per Nick-Query (z. B. "miner iron north")
-- ok=true + comp=nil  -> kein Treffer (nicht fatal)
-- ok=false            -> echter Fehler (Parameter/Schnittstelle)
--------------------------------------------------------------------------------

---@param query string
---@return boolean, table|nil, string|nil  -- ok, componentOrNil, err
local function byNick(query)
  if not is_str(query) or query == "" then
    return false, nil, "byNick: query must be non-empty string"
  end

  local okIds, ids, errIds = _safe_find_ids(query)
  if not okIds then return false, nil, errIds end
  if #ids == 0 then return true, nil, nil end -- kein Treffer

  ---@diagnostic disable-next-line: need-check-nil
  local okP, comp, errP = _safe_proxy_one(ids[1])
  if not okP then return false, nil, errP end
  -- comp kann legit nil sein, wenn der Komponent gerade weg ist
  return true, comp, nil
end

--------------------------------------------------------------------------------
-- byAllNick: alle Treffer per Nick-Query
-- ok=true + {}       -> keine Treffer (nicht fatal)
-- ok=false           -> Fehler
--------------------------------------------------------------------------------

---@param query string
---@return boolean, table[]|nil, string|nil  -- ok, componentsOrNil, err
---@param exactly boolean|nil  -- true = nur exakte Treffer, false = alle Treffer (default)
local function byAllNick(query, exactly)
  if exactly == nil then exactly = false end
  if not is_str(query) or query == "" then
    return false, nil, "byAllNick: query must be non-empty string"
  end

  local okIds, ids, errIds = _safe_find_ids(query)
  if not okIds then return false, nil, errIds end

  local out = {}
  for i = 1, #ids do
    ---@diagnostic disable-next-line: need-check-nil
    local okP, comp, errP = _safe_proxy_one(ids[i])
    if not okP then
      -- harter Fehler -> gesamten Call als Fehler behandeln (konsistente Semantik)
      return false, nil, errP
    end
    if comp then
      if exactly and comp.nick == query then
        out[#out + 1] = comp
        log(0, "byAllNick: matched exactly: " .. tostring(comp.nick) .. " for query: " .. tostring(query))
      elseif exactly == false then
        out[#out + 1] = comp
        log(0, "byAllNick: matched (not exactly): " .. tostring(comp.nick) .. " for query: " .. tostring(query))
      end
    end
  end
  return true, out, nil
end

--------------------------------------------------------------------------------
-- byClass: alle Treffer für eine Klasseninstanz (z. B. classes.FGBuildableMinerMK1)
-- ok=true + {}       -> keine Treffer
-- ok=false           -> Fehler
--------------------------------------------------------------------------------

---@param classInstance any
---@return boolean, table[]|nil, string|nil
local function byClass(classInstance)
  if classInstance == nil then
    return false, nil, "byClass: classInstance must not be nil"
  end

  local okIds, ids, errIds = _safe_find_ids(classInstance)
  if not okIds then return false, nil, errIds end

  local out = {}
  for i = 1, #ids do
    ---@diagnostic disable-next-line: need-check-nil
    local okP, comp, errP = _safe_proxy_one(ids[i])
    if not okP then
      return false, nil, errP
    end
    if comp then out[#out + 1] = comp end
  end
  return true, out, nil
end

----------------------------------------------------------------
-- JSON Pretty-Print
----------------------------------------------------------------

--- Pretty-Print für Lua-Tabellen/Values via globalem JSON-Objekt.
-- @param value any Lua-Wert (Table, String, Number, Bool, ...)
-- @param opts table|nil z.B. { indent=2, sort_keys=true, cycle="<cycle>" }
-- @return string JSON-String
-- Hinweis: `shared/serializer.lua` sollte `JSON.new()` global verfügbar machen.
local function pretty_json(value, opts)
  local J = JSON.new(opts or { indent = 2, sort_keys = true })
  return J:encode(value)
end

--- Kurzform zum Debug-Dumpen von Werten (print + JSON).
-- @param value any
local function pj(value)
  print(pretty_json(value))
end



return {
  now_ms = now_ms,
  sleep_ms = sleep_ms,
  sleep_s = sleep_s,
  throttle_ms = throttle_ms,
  is_longer_than = is_longer_than,
  romanize = romanize,
  string_contains = string_contains,
  string_icontains = string_icontains,
  byNick = byNick,
  byAllNick = byAllNick,
  byClass = byClass,
  pretty_json = pretty_json,
  pj = pj,
  pcall_norm = pcall_norm,
  is_str = is_str,
  to_str = to_str,
}
