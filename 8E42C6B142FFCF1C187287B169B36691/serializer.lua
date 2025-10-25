-- JSON "Klasse" ohne require – einfach in deine Datei kopieren.
-- Nutzung:
--   local J = JSON.new{ indent = 2, sort_keys = true }
--   local s = J:encode(obj)
--   local t = J:decode(s)
--
-- Oder mit Default:
--   local s = json_encode(obj, { indent = 4 })
--   local t = json_decode(s)

JSON = {}
JSON.__index = JSON

function JSON.new(opts)
  return setmetatable({ opts = opts or {} }, JSON)
end

function JSON:setopts(opts)
  if not opts then return end
  for k, v in pairs(opts) do self.opts[k] = v end
end

-- ======== ENCODE ========
-- opts (optional) überschreibt Instanz-Optionen:
--   indent=2, sort_keys=true, cycle="<cycle>"
function JSON:encode(value, opts)
  opts = (function(base, override)
    base = base or {}
    if not override then return base end
    local merged = {}
    for k, v in pairs(base) do merged[k] = v end
    for k, v in pairs(override) do merged[k] = v end
    return merged
  end)(self.opts, opts)

  local IND   = (" "):rep(opts.indent or 2)
  local SORT  = (opts.sort_keys ~= false)
  local CYCLE = opts.cycle or "<cycle>"

  local function esc_str(s)
    return s:gsub('[%z\1-\31\\"]', function(c)
      local m = { ['\\']='\\\\', ['"']='\\"', ['\b']='\\b',
                  ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
      return m[c] or string.format("\\u%04X", string.byte(c))
    end)
  end

  local function is_array(t)
    local n, max = 0, 0
    for k in pairs(t) do
      if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then return false end
      if k > max then max = k end
      n = n + 1
    end
    for i = 1, max do if t[i] == nil then return false end end
    return true, max
  end

  local function num_to_json(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    return tostring(n)
  end

  local seen = {} -- cycle detection

  local function ser(v, depth)
    local tv = type(v)
    if tv == "nil"     then return "null"
    elseif tv == "boolean" then return tostring(v)
    elseif tv == "number"  then return num_to_json(v)
    elseif tv == "string"  then return '"'..esc_str(v)..'"'
    elseif tv ~= "table"   then return '"'..tv..'"' -- fallback
    end

    if seen[v] then return '"'..esc_str(CYCLE)..'"' end
    seen[v] = true

    local pad, padIn = IND:rep(depth), IND:rep(depth+1)
    local isArr, n = is_array(v)
    if isArr then
      if n == 0 then seen[v] = nil; return "[]" end
      local out = {"["}
      for i = 1, n do
        out[#out+1] = "\n"..padIn..ser(v[i], depth+1)
        if i < n then out[#out+1] = "," end
      end
      out[#out+1] = "\n"..pad.."]"
      seen[v] = nil
      return table.concat(out)
    else
      -- object: nur string-Keys sind echtes JSON
      local keys = {}
      for k in pairs(v) do
        if type(k) == "string" then keys[#keys+1] = k end
      end
      if SORT then table.sort(keys) end
      if #keys == 0 then seen[v] = nil; return "{}" end
      local out = {"{"}
      for i, k in ipairs(keys) do
        out[#out+1] = "\n"..padIn..'"'..esc_str(k)..'": '..ser(v[k], depth+1)
        if i < #keys then out[#out+1] = "," end
      end
      out[#out+1] = "\n"..pad.."}"
      seen[v] = nil
      return table.concat(out)
    end
  end

  return ser(value, 0)
end

-- ======== DECODE ========
-- kleiner rekursiver Parser; unterstützt \uXXXX (BMP)
function JSON:decode(s)
  assert(type(s) == "string", "json.decode: string expected")
  local i, len = 1, #s

  local function peek() return s:sub(i,i) end
  local function nextc() local c=s:sub(i,i); i=i+1; return c end
  local function skip_ws()
    while true do
      local c = peek()
      if c == " " or c == "\t" or c == "\r" or c == "\n" then i = i + 1 else break end
    end
  end

  local function parse_literal(lit, val)
    if s:sub(i, i+#lit-1) == lit then i = i + #lit; return val end
    error("json.decode: expected "..lit.." at pos "..i)
  end

  local function hex4_to_char(h)
    local n = tonumber(h,16)
    if not n then return "" end
    if n < 0x80 then return string.char(n)
    elseif n < 0x800 then
      local b1 = 0xC0 + math.floor(n/0x40)
      local b2 = 0x80 + (n % 0x40)
      return string.char(b1, b2)
    else
      local b1 = 0xE0 + math.floor(n/0x1000)
      local b2 = 0x80 + (math.floor(n/0x40) % 0x40)
      local b3 = 0x80 + (n % 0x40)
      return string.char(b1, b2, b3)
    end
  end

  local parse_value -- forward

  local function parse_string()
    local quote = nextc()
    if quote ~= '"' then error('json.decode: expected " at pos '..(i-1)) end
    local out = {}
    while true do
      if i > len then error("json.decode: unterminated string") end
      local c = nextc()
      if c == '"' then return table.concat(out) end
      if c == "\\" then
        local e = nextc()
        if e == '"'  then out[#out+1] = '"'
        elseif e == "\\" then out[#out+1] = "\\"
        elseif e == "/"  then out[#out+1] = "/"
        elseif e == "b"  then out[#out+1] = "\b"
        elseif e == "f"  then out[#out+1] = "\f"
        elseif e == "n"  then out[#out+1] = "\n"
        elseif e == "r"  then out[#out+1] = "\r"
        elseif e == "t"  then out[#out+1] = "\t"
        elseif e == "u"  then
          local h = s:sub(i, i+3)
          if #h<4 or not h:match("^%x%x%x%x$") then
            error("json.decode: invalid \\u escape at pos "..i)
          end
          out[#out+1] = hex4_to_char(h); i = i + 4
        else
          error("json.decode: invalid escape \\"..tostring(e).." at pos "..(i-1))
        end
      else
        out[#out+1] = c
      end
    end
  end

  local function parse_number()
    local start = i
    if peek() == '-' then i = i + 1 end
    if peek() == '0' then i = i + 1
    else
      if not peek():match("%d") then error("json.decode: number expected at "..i) end
      while peek() and peek():match("%d") do i = i + 1 end
    end
    if peek() == '.' then
      i = i + 1
      if not peek():match("%d") then error("json.decode: digits after . expected at "..i) end
      while peek() and peek():match("%d") do i = i + 1 end
    end
    if peek() == 'e' or peek() == 'E' then
      i = i + 1
      if peek() == '+' or peek() == '-' then i = i + 1 end
      if not peek():match("%d") then error("json.decode: digits in exponent expected at "..i) end
      while peek() and peek():match("%d") do i = i + 1 end
    end
    return tonumber(s:sub(start, i-1))
  end

  local function parse_array()
    local arr = {}
    i = i + 1 -- skip [
    skip_ws()
    if peek() == "]" then i = i + 1; return arr end
    local idx = 1
    while true do
      arr[idx] = parse_value()
      idx = idx + 1
      skip_ws()
      local c = nextc()
      if c == "]" then break end
      if c ~= "," then error("json.decode: expected , or ] at pos "..(i-1)) end
      skip_ws()
    end
    return arr
  end

  local function parse_object()
    local obj = {}
    i = i + 1 -- skip {
    skip_ws()
    if peek() == "}" then i = i + 1; return obj end
    while true do
      if peek() ~= '"' then error('json.decode: expected key " at pos '..i) end
      local key = parse_string()
      skip_ws()
      if nextc() ~= ":" then error("json.decode: expected : at pos "..(i-1)) end
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = nextc()
      if c == "}" then break end
      if c ~= "," then error("json.decode: expected , or } at pos "..(i-1)) end
      skip_ws()
    end
    return obj
  end

  function parse_value()
    skip_ws()
    local c = peek()
    if c == '"' then return parse_string()
    elseif c == '-' or (c and c:match("%d")) then return parse_number()
    elseif c == '{' then return parse_object()
    elseif c == '[' then return parse_array()
    elseif c == 't' then return parse_literal("true", true)
    elseif c == 'f' then return parse_literal("false", false)
    elseif c == 'n' then return parse_literal("null", nil)
    else
      error("json.decode: unexpected char "..tostring(c).." at pos "..i)
    end
  end

  local result = parse_value()
  skip_ws()
  if i <= len then
    local rest = s:sub(i):match("^%s*$")
    if not rest then error("json.decode: trailing characters at pos "..i) end
  end
  return result
end

-- Default-Instanz + Helfer
JSON.default = JSON.new()
function json_encode(value, opts) return JSON.default:encode(value, opts) end
function json_decode(str)         return JSON.default:decode(str) end



--[[     USAGE


local J = JSON.new{ indent = 2, sort_keys = true }
local s = J:encode({ b=2, a=1, arr={10,20}, ok=true })
print(s)
local t = J:decode(s)
print(t.a, t.arr[2])  -- 1  20

-- Oder über die Default-Funktionen:
print(json_encode({x=1}, {indent=4}))

]]