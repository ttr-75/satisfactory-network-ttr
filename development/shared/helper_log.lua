---@diagnostic disable: lowercase-global

require("config")

----------------------------------------------------------------
-- helper.lua – Kleine Helferlein für Logging
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

-------------------------------
-- Listener-Debug-Helfer
-------------------------------
-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
---comment
---@param tag string|nil optional Tag für die Fehlermeldung
---@return function
local function traceback(tag)
  return function(err)
    local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
    log(4, tb)
    return tb
  end
end

local function log(level, ...)
  if level >= (LOG_MIN or TTR_FIN_Config and TTR_FIN_Config.LOG_LEVEL or 0) then
    local parts = _to_strings({ ... }) -- robust bei Zahlen, Booleans, Tabellen (tostring)
    computer.log(level, table.concat(parts, " "))
  end
end

-- Beispiel:
-- log(0, "Hello", 123, true)  -> "Hello 123 true"

return {
  log = log,
  traceback = traceback,
}
