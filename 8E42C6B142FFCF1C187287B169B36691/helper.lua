--Logger
function log(level, ...)
    if level >= LOG_MIN then
        computer.log(level, table.concat({ ... }, " "))
    end
end
 
--@param s string
--@param x number
function is_longer_than(s, x)
    log(0, "S: " .. s .. "\nTypS: " .. type(s) ..  "\nX: " .. x ..  "\nTypX: " .. type(x))
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
  opts = opts or {}
  local IND   = (" "):rep(opts.indent or 2)
  local SORT  = (opts.sort_keys ~= false)
  local CYCLE = opts.cycle or "<cycle>"

  local function esc_str(s)
    -- escape control chars, backslash, quotes
    return s:gsub('[%z\1-\31\\"]', function(c)
      local map = { ['\\']='\\\\', ['"']='\\"', ['\b']='\\b',
                    ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
      return map[c] or string.format("\\u%04X", string.byte(c))
    end)
  end

  local function is_array(t)
    -- true if keys are 1..n with no holes
    local n = 0
    for k in pairs(t) do
      if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then return false end
      if k > n then n = k end
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
  end

  local function num_to_json(n)
    if n ~= n or n == math.huge or n == -math.huge then
      return "null"
    end
    return tostring(n)
  end

  local seen = {} -- for cycle detection

  local function serialize(v, depth)
    local tv = type(v)

    if tv == "nil" then
      return "null"
    elseif tv == "boolean" then
      return tostring(v)
    elseif tv == "number" then
      return num_to_json(v)
    elseif tv == "string" then
      return '"' .. esc_str(v) .. '"'
    elseif tv ~= "table" then
      -- userdata/function/thread → stringify type name
      return '"' .. tv .. '"'
    end

    -- table
    if seen[v] then
      return '"' .. esc_str(CYCLE) .. '"'
    end
    seen[v] = true

    local pad   = IND:rep(depth)
    local padIn = IND:rep(depth + 1)

    local arr, n = is_array(v)
    if arr then
      if n == 0 then seen[v] = nil; return "[]" end
      local out = {"["}
      for i = 1, n do
        out[#out+1] = "\n" .. padIn .. serialize(v[i], depth + 1)
        if i < n then out[#out+1] = "," end
      end
      out[#out+1] = "\n" .. pad .. "]"
      seen[v] = nil
      return table.concat(out)
    else
      -- object
      local keys = {}
      for k in pairs(v) do
        if type(k) == "string" then
          keys[#keys+1] = k
        else
          -- non-string keys: show as [tostring(key)]
          keys[#keys+1] = "[" .. tostring(k) .. "]"
        end
      end
      if SORT then table.sort(keys) end
      if #keys == 0 then seen[v] = nil; return "{}" end

      local out, first = {"{"}, true
      for _, k in ipairs(keys) do
        local rawk, displayk = k, k
        -- if we wrapped a non-string key as [x], keep display as that
        if k:sub(1,1) == "[" and k:sub(-1) == "]" then
          -- reconstruct best-effort value by original tostring; not used for lookup
          -- we cannot map back reliably; skip lookup and show as stringified key
          displayk = k
          -- try to pull value via exact printed key (works only if the original key was that string)
          -- fallback: skip (rare). Here we do a safe search for matching tostring:
          local found_v
          for real_k, val in pairs(v) do
            if "["..tostring(real_k).."]" == k then found_v = val; break end
          end
          if found_v ~= nil then
            if not first then out[#out+1] = "," end; first = false
            out[#out+1] = "\n" .. padIn .. '"' .. esc_str(displayk) .. '": ' .. serialize(found_v, depth + 1)
          end
        else
          -- normal string key
          if not first then out[#out+1] = "," end; first = false
          out[#out+1] = "\n" .. padIn .. '"' .. esc_str(rawk) .. '": ' .. serialize(v[rawk], depth + 1)
        end
      end
      out[#out+1] = "\n" .. pad .. "}"
      seen[v] = nil
      return table.concat(out)
    end
  end

  return serialize(value, 0)
end

