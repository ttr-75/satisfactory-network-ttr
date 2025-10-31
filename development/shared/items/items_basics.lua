---@diagnostic disable: lowercase-global
--[[
items_basics.lua
----------------
Zweck:
  - Definiert den Item-Datentyp `MyItem` (Werte + Helper-Methoden)
  - Definiert die Sammlung `MyItemList` (bijektiv: Name <-> Id)
  - Stellt ein sprachneutrales Konstanten-Table `MyItemConst` bereit
Design:
  - Klassen sind local (keine Globals).
  - `addItem` hält Bijektivität, indem alte Zuordnungen bereinigt werden.
  - Logging via shared.helper.log (Level 3 = Warn).
Export:
  return {
    MyItem, MyItemList, MyItemConst, new_list()
  }
--]]

-- Abhängigkeiten ----------------------------------------------------------------
local helper = require("shared.helper")
local de_umlaute = helper.de_umlaute ---@type fun(s:string):string
local log = helper.log or function(...) end ---@type fun(level:integer, ...)|fun(...)

-- ==============================================================================
--  Klasse: MyItem
-- ==============================================================================
---@class MyItem
---@field name string|nil  -- Anzeigename (sprachabhängig)
---@field id   integer|nil -- Eindeutige numerische Id / Icon-Id
---@field max  integer|nil -- Optional: z.B. Stackgröße
---@field ref  string|nil  -- Optional: explizite Icon-Ref ("icon:123")
local MyItem = {}
MyItem.__index = MyItem

--- Konstruktor für MyItem.
---@param o table|nil  -- Felder: name, id, max?, ref?
---@return MyItem
function MyItem.new(o)
    return setmetatable(o or {}, MyItem)
end

--- Icon-/Referenzstring liefern.
---@return string
function MyItem:getRef()
    if self.ref ~= nil then return self.ref end
    return "icon:" .. tostring(self.id)
end

--- Kodierten Namen (z.B. ohne Umlaute) liefern – praktisch für Keys.
---@return string|nil
function MyItem:getCodeName()
    return self.name and de_umlaute(self.name) or nil
end

-- ==============================================================================
--  Klasse: MyItemList
-- ==============================================================================
---@class MyItemList
---@field k2v table<string, MyItem>  -- Name -> Item
---@field v2k table<integer, MyItem> -- Id   -> Item
local MyItemList = {}
MyItemList.__index = MyItemList

--- Neue, leere Itemliste.
---@return MyItemList
function MyItemList.new()
    return setmetatable({ k2v = {}, v2k = {} }, MyItemList)
end

--- Item hinzufügen; hält Bijektivität (Name/Id eindeutig).
---@param item MyItem|nil
function MyItemList:addItem(item)
    if not item or not item.name or not item.id then
        log(3, "MyItemList:addItem skipped (missing name or id)")
        return
    end
    -- Kollisionen bereinigen:
    local oldByName = self.k2v[item.name]
    if oldByName and oldByName.id then self.v2k[oldByName.id] = nil end

    local oldById = self.v2k[item.id]
    if oldById and oldById.name then self.k2v[oldById.name] = nil end

    -- Neue Paarungen setzen:
    self.k2v[item.name] = item
    self.v2k[item.id]   = item
end

--- Lookup per exaktem Namen (loggt Warnung, falls unbekannt).
---@param name string
---@return MyItem|nil
function MyItemList:get_by_Name(name)
    if self.k2v[name] == nil then log(3, "Item '" .. tostring(name) .. "' not implemented.") end
    return self.k2v[name]
end

--- Lookup per Id (loggt Warnung, falls unbekannt).
---@param id integer
---@return MyItem|nil
function MyItemList:get_by_Id(id)
    if self.v2k[id] == nil then log(3, "ItemId '" .. tostring(id) .. "' not implemented.") end
    return self.v2k[id]
end

--- Entfernt ein Item anhand des Namens (bereinigt beide Tabellen).
---@param name string
function MyItemList:delete_by_Name(name)
    local item = self.k2v[name]
    if item and item.id then
        self.k2v[name] = nil
        self.v2k[item.id] = nil
    end
end

--- Entfernt ein Item anhand der Id (bereinigt beide Tabellen).
---@param id integer
function MyItemList:delete_by_Id(id)
    local item = self.v2k[id]
    if item and item.name then
        self.v2k[id] = nil
        self.k2v[item.name] = nil
    end
end

--- Anzahl der Items (entspricht size(k2v)).
---@return integer
function MyItemList:size()
    local n = 0; for _ in pairs(self.k2v) do n = n + 1 end; return n
end

-- ==============================================================================
--  Konstanten-Namespace
-- ==============================================================================
-- Container für sprachspezifische Konstanten (DE/EN/…)
-- -> Sprachdateien (z.B. items_de.lua) füllen dieses Table mit MyItem-Instanzen.
local MyItemConst = {}

-- ==============================================================================
--  Export
-- ==============================================================================
return {
    MyItem = MyItem,
    MyItemList = MyItemList,
    MyItemConst = MyItemConst, -- <- Konstanten leben hier (werden in Sprachdateien gesetzt)
    --- Convenience: neue Itemliste erzeugen
    ---@return MyItemList
    new_list = function() return MyItemList.new() end
}
