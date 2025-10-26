--Logger
function log(level, ...)
  if level >= LOG_MIN then
    computer.log(level, table.concat({ ... }, " "))
  end
end

-- Zeit in ms (FN: computer.millis; Fallback: os.clock)
function now_ms()
  return (computer and computer.millis and computer.millis())
      or math.floor(os.clock() * 1000)
end

-- blockiert für mind. ms Millisekunden, aber kooperativ
function sleep_ms(ms)
  if not ms or ms <= 0 then return end
  local deadline = now_ms() + ms
  while true do
    local remaining = deadline - now_ms()
    if remaining <= 0 then break end
    -- in kleinen Häppchen warten, Events erlauben
    event.pull(math.min(remaining, 250) / 1000) -- max 250ms pro Pull
  end
end

function sleep_s(seconds)
  sleep_ms(math.floor((seconds or 0) * 1000))
end

-- Throttle-Wrapper
function throttle_ms(fn, interval_ms)
  local last = 0
  return function(...)
    local t = now_ms()
    if t - last >= interval_ms then
      last = t
      return fn(...)
    end
    -- sonst: still ignorieren
  end
end

--@param s string
--@param x number
function is_longer_than(s, x)
  log(0, "S: " .. s .. "\nTypS: " .. type(s) .. "\nX: " .. x .. "\nTypX: " .. type(x))
  if s == nil then return false end -- nil → nicht länger
  if x == nil then return false end -- nil → nicht länger
  if type(s) ~= "string" then return false end
  if type(x) ~= "number" then return false end
  return #s > x
end

function de_umlaute(s)
  if s == nil then return nil end
  assert(type(s) == "string", "String erwartet")
  -- Ersetzt jedes Zeichen, das NICHT Buchstabe (%a), Ziffer (%d) oder Leerzeichen ist.
  return (s:gsub("ä", "ae"):gsub("ü", "ue"):gsub("ö", "oe"):gsub("Ä", "Ae"):gsub("Ü", "Ue"):gsub("Ö", "Oe"):gsub("ß", "ss"))
  --return s
end

function byNick(nick)
  local t = component.findComponent(nick)[1]
  assert(t, "Komponente '" .. nick .. "' nicht gefunden")
  return component.proxy(t)
end

-- Liest die erste Inventory des Containers aus und aggregiert nach Item-Typ
function readInventory(container, totals, types)
  local invs = container:getInventories()
  local inv = invs and invs[1]
  if not inv then return {}, {} end

  --local totals = {} -- key: type.hash -> sum count
  --local types  = {} -- key: type.hash -> type (für Namen/MaxStack)

  if totals == nil then
    totals = {}
  end
  if types == nil then
    types = {}
  end

  -- Slots sind 0-basiert und gehen bis size-1
  for slot = 0, inv.size - 1, 1 do
    local stack = inv:getStack(slot)
    if stack and stack.count and stack.count > 0 and stack.item and stack.item.type then
      local t = stack.item.type
      local key = t.hash
      totals[key] = (totals[key] or 0) + stack.count
      types[key] = t
    end
  end
  return totals, types
end

-- pretty_json(value, opts) -> string
-- opts = {
--   indent = 2,       -- spaces per indent level
--   sort_keys = true, -- sort object keys alphabetically
--   cycle = "<cycle>" -- placeholder when a reference cycle is found
-- }
function pretty_json(value, opts)
  if opts == nil then
    opts = { indent = 2, sort_keys = true }
  end
  local J = JSON.new(opts)
  local s = J:encode(value)
  return s
end

function pj(value)
  print(pretty_json(value))
end
