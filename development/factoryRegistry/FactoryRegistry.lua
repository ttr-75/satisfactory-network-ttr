---@diagnostic disable: lowercase-global

local FI = require("factoryRegistry/FactoryInfo.lua")

--------------------------------------------------------------------------------
-- FactoryRegistry
--------------------------------------------------------------------------------

---@class FactoryRegistry
---@field factorys table<string, FactoryInfo>  -- key = fCoreNetworkCard (Sender-ID)
local FactoryRegistry = {
    factorys = {}
}
FactoryRegistry.__index = FactoryRegistry

---@param o table|nil
---@return FactoryRegistry
function FactoryRegistry:new(o)
    o = o or {}
    o.factorys = o.factorys or {}
    return setmetatable(o, self)
end

--- Fügt ein FactoryInfo ein, falls gültig. Existiert die ID, wird stattdessen aktualisiert.
---@param factory FactoryInfo
function FactoryRegistry:add(factory)
    if not self:checkMinimum(factory) then
        log(3, "FactoryRegistry:add: minimum check failed")
        return
    end
    local id   = factory.fCoreNetworkCard
    local name = factory.fName
    if self.factorys[id] ~= nil then
        -- bereits vorhanden → merge/update
        self.factorys[id]:update(factory)
        log(0, ("FactoryRegistry:add -> update id=%s name=%s"):format(tostring(id), tostring(name)))
        return
    end
    self.factorys[id] = factory
    log(0, ("FactoryRegistry:add -> insert id=%s name=%s"):format(tostring(id), tostring(name)))
end

--- Aktualisiert ein bestehendes FactoryInfo (wenn vorhanden).
---@param factory FactoryInfo
function FactoryRegistry:update(factory)
    if not self:checkMinimum(factory) then
        log(3, "FactoryRegistry:update: minimum check failed")
        return
    end
    local id = factory.fCoreNetworkCard
    if not id then
        log(3, "FactoryRegistry:update: no fCoreNetworkCard in factory")
        return
    else
        local cur = self.factorys[id]
        if not cur then
            -- Optional: wenn nicht vorhanden, als add behandeln
            self.factorys[id] = factory
            log(0, ("FactoryRegistry:update -> insert id=%s"):format(tostring(id)))
            return
        end
        cur:update(factory)
        log(0, ("FactoryRegistry:update -> merged id=%s"):format(tostring(id)))
    end
end

--- Minimalprüfung delegiert an FactoryInfo:check
---@param factory FactoryInfo|nil
---@return boolean
function FactoryRegistry:checkMinimum(factory)
    return FI.FactoryInfo:check(factory)
end

--- Liefert alle Einträge (ID → FactoryInfo).
---@return table<string, FactoryInfo>
function FactoryRegistry:getAll()
    return self.factorys
end

-- ====== optionale Helfer (nur Komfort, keine Verhaltensänderung) ======

--- Sucht einen Eintrag per ID (CoreNetworkCard).
---@param id string
---@return FactoryInfo|nil
function FactoryRegistry:getById(id)
    return self.factorys[id]
end

--- Sucht einen Eintrag per Name.
---@param name string
---@return FactoryInfo|nil
function FactoryRegistry:getByName(name)
    for _, fi in pairs(self.factorys) do
        if fi.fName == name then return fi end
    end
    return nil
end

---- Entfernt einen Eintrag per ID.
---@param id string
---@return boolean  -- true, wenn entfernt
function FactoryRegistry:removeById(id)
    if self.factorys[id] ~= nil then
        self.factorys[id] = nil
        return true
    end
    return false
end

--- Anzahl registrierter Factorys.
---@return integer
function FactoryRegistry:size()
    local n = 0
    for _ in pairs(self.factorys) do
        n = n + 1
    end
    return n
end

--- Löscht alle Einträge.
function FactoryRegistry:clear()
    self.factorys = {}
end

return FactoryRegistry
