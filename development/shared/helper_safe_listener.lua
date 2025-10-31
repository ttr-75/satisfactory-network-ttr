---@diagnostic disable: lowercase-global


local traceback = require("shared.helper_log").traceback



----------------------------------------------------------------
-- helper_safe_listern.lua –  Events
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------



-- safe_listener(tag, fn): verpackt fn in xpcall, sodass Fehler nicht „leise“ bleiben.
local function safe_listener(tag, fn)
  assert(type(fn) == "function", "safe_listener needs a function")
  return function(...)
    local ok, res = xpcall(fn, traceback(tag), ...)
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
