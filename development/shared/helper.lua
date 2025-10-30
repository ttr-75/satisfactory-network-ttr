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
require("shared.serializer")




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

--- Prüft defensiv, ob `s` länger als `x` ist.
-- @param s any Erwartet string, sonst false
-- @param x any Erwartet number, sonst false
-- @return boolean true, wenn s ein String ist und #s > x
local function is_longer_than(s, x)
  if type(s) ~= "string" then return false end
  if type(x) ~= "number" then return false end
  return #s > x
end

--- Kodiert deutsche Umlaute (ä→ae, ö→oe, ü→ue, Ä→Ae, Ö→Oe, Ü→Ue, ß→ss)
-- und entfernt Leerzeichen (praktisch für Keys).
-- @param s string|nil
-- @return string|nil kodierter String (oder nil, wenn s=nil war)
local function de_umlaute(s)
  if s == nil then return nil end
  assert(type(s) == "string", "String erwartet")
  -- Ersetzt jedes Zeichen, das NICHT Buchstabe (%a), Ziffer (%d) oder Leerzeichen ist.
  return (s:gsub("ä", "ae"):gsub("ü", "ue"):gsub("ö", "oe"):gsub("Ä", "Ae"):gsub("Ü", "Ue"):gsub("Ö", "Oe"):gsub("ß", "ss"):gsub(" ", ""))
  --return s
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

--- Fall-insensitive Teilstring-Suche ohne Patterns.
-- @param s string|nil
-- @param sub string|nil
-- @return boolean true, wenn gefunden
local function string_icontains(s, sub)
  if s == nil or sub == nil then return false end
  return string.find(string.lower(s), string.lower(sub), 1, true) ~= nil
end

----------------------------------------------------------------
-- Komponenten (FicsItNetworks)
----------------------------------------------------------------

--- Holt eine Komponente per Nickname und gibt deren Proxy zurück.
-- @param nick string Nickname der Komponente (findComponent)
-- @return table Proxy-Objekt
-- @raise assert, wenn Komponente nicht gefunden wird
local function byNick(nick)
  local t = component.findComponent(nick)[1]
  assert(t, "Komponente '" .. tostring(nick) .. "' nicht gefunden")
  return component.proxy(t)
end

--- Holt alle Komponenten-Proxys zu einem Nickname (Array).
-- @param nick string Nickname (findComponent kann mehrere Referenzen liefern)
-- @return table[] Array von Proxys (mindestens 1 Eintrag)
-- @raise assert, wenn keine Komponente gefunden oder Proxy fehlgeschlagen
local function byAllNick(nick)
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
  de_umlaute = de_umlaute,
  string_contains = string_contains,
  string_icontains = string_icontains,
  byNick = byNick,
  byAllNick = byAllNick,
  pretty_json = pretty_json,
  pj = pj,
}
