---@diagnostic disable: lowercase-global
---@diagnostic disable: lowercase-global


--- Kodiert deutsche Umlaute (ä→ae, ö→oe, ü→ue, Ä→Ae, Ö→Oe, Ü→Ue, ß→ss)
-- und entfernt Leerzeichen (praktisch für Keys).
-- @param s string|nil
-- @return string|nil kodierter String (oder nil, wenn s=nil war)
local function romanize(s)
  if s == nil then return nil end
  assert(type(s) == "string", "String erwartet")
  -- Ersetzt jedes Zeichen, das NICHT Buchstabe (%a), Ziffer (%d) oder Leerzeichen ist.
  return (s:gsub("ä", "ae"):gsub("ü", "ue"):gsub("ö", "oe"):gsub("Ä", "Ae"):gsub("Ü", "Ue"):gsub("Ö", "Oe"):gsub("ß", "ss"))
  --return s
end


return {
  romanize = romanize,
}