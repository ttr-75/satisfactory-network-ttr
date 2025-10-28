---@diagnostic disable: lowercase-global

local names = {
    "fabricRegistry/FabricRegistry.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- FabricRegistry
--------------------------------------------------------------------------------

---@class FabricRegistry
---@field fabrics table<string, FabricInfo>  -- key = fCoreNetworkCard (Sender-ID)
FabricRegistry = {
    fabrics = {}
}
FabricRegistry.__index = FabricRegistry

---@param o table|nil
---@return FabricRegistry
function FabricRegistry:new(o)
    o = o or {}
    o.fabrics = o.fabrics or {}
    return setmetatable(o, self)
end

--- Fügt ein FabricInfo ein, falls gültig. Existiert die ID, wird stattdessen aktualisiert.
---@param fabric FabricInfo
function FabricRegistry:add(fabric)
    if not self:checkMinimum(fabric) then
        log(3, "FabricRegistry:add: minimum check failed")
        return
    end
    local id   = fabric.fCoreNetworkCard
    local name = fabric.fName
    if self.fabrics[id] ~= nil then
        -- bereits vorhanden → merge/update
        self.fabrics[id]:update(fabric)
        log(0, ("FabricRegistry:add -> update id=%s name=%s"):format(tostring(id), tostring(name)))
        return
    end
    self.fabrics[id] = fabric
    log(0, ("FabricRegistry:add -> insert id=%s name=%s"):format(tostring(id), tostring(name)))
end

--- Aktualisiert ein bestehendes FabricInfo (wenn vorhanden).
---@param fabric FabricInfo
function FabricRegistry:update(fabric)
    if not self:checkMinimum(fabric) then
        log(3, "FabricRegistry:update: minimum check failed")
        return
    end
    local id = fabric.fCoreNetworkCard
    local cur = self.fabrics[id]
    if not cur then
        -- Optional: wenn nicht vorhanden, als add behandeln
        self.fabrics[id] = fabric
        log(0, ("FabricRegistry:update -> insert id=%s"):format(tostring(id)))
        return
    end
    cur:update(fabric)
    log(0, ("FabricRegistry:update -> merged id=%s"):format(tostring(id)))
end

--- Minimalprüfung delegiert an FabricInfo:check
---@param fabric FabricInfo|nil
---@return boolean
function FabricRegistry:checkMinimum(fabric)
    return FabricInfo:check(fabric)
end

--- Liefert alle Einträge (ID → FabricInfo).
---@return table<string, FabricInfo>
function FabricRegistry:getAll()
    return self.fabrics
end

-- ====== optionale Helfer (nur Komfort, keine Verhaltensänderung) ======

--- Sucht einen Eintrag per ID (CoreNetworkCard).
---@param id string
---@return FabricInfo|nil
function FabricRegistry:getById(id)
    return self.fabrics[id]
end

--- Sucht einen Eintrag per Name.
---@param name string
---@return FabricInfo|nil
function FabricRegistry:getByName(name)
    for _, fi in pairs(self.fabrics) do
        if fi.fName == name then return fi end
    end
    return nil
end

---- Entfernt einen Eintrag per ID.
---@param id string
---@return boolean  -- true, wenn entfernt
function FabricRegistry:removeById(id)
    if self.fabrics[id] ~= nil then
        self.fabrics[id] = nil
        return true
    end
    return false
end

--- Anzahl registrierter Fabrics.
---@return integer
function FabricRegistry:size()
    local n = 0
    for _ in pairs(self.fabrics) do
        n = n + 1
    end
    return n
end

--- Löscht alle Einträge.
function FabricRegistry:clear()
    self.fabrics = {}
end
