---@diagnostic disable: lowercase-global

local Helper_log = require("shared.helper_log")
local log = Helper_log.log



----------------------------------------------------------------
-- helper_safe_listern.lua –  Events
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------


-------------------------------
-- Listener-Debug-Helfer
-------------------------------
-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
  return function(err)
    local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
    log(4, tb)
    return tb
  end
end

-- safe_listener(tag, fn): verpackt fn in xpcall, sodass Fehler nicht „leise“ bleiben.
local function safe_listener(tag, fn)
  assert(type(fn) == "function", "safe_listener needs a function")
  return function(...)
    local ok, res = xpcall(fn, _traceback(tag), ...)
    return res
  end
end

-- hübsches Argument-Logging
local function fmt_args(...)
  local t = table.pack(...)
  for i = 1, t.n do t[i] = tostring(t[i]) end
  return table.concat(t, ", ")
end

return {
  safe_listener = safe_listener,
  fmt_args = fmt_args,
}