FabricRegistry = {
    fabrics = {}
}

function FabricRegistry:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function FabricRegistry:add(fabric)
    if self:checkMinimum(fabric) then
        local id = fabric.fCoreNetworkCard
        if self.fabrics[id] ~= nil then
            return self:update(fabric)
        end
        local name = fabric.fName
        log(0, "Adding: FabricRegister:add(fabric): Fabric" .. name .. " with id:" .. id)
        self.fabrics[id] = fabric
    else
        log(3, "Ignorring: FabricRegister:add(fabric)")
    end
end

function FabricRegistry:update(fabric)
    if self:checkMinimum(fabric) then
        local id = fabric.fCoreNetworkCard
        local name = fabric.fName
        log(0, "Update: FabricRegister:update(fabric): Fabric" .. name .. " with id:" .. id)
        self.fabrics[id]:update(fabric)
    else
        log(3, "Ignorring: FabricRegister:Update(fabric)")
    end
end

function FabricRegistry:checkMinimum(fabric)
    return FabricInfo:check(fabric)
end

function FabricRegistry:getAll()
    return self.fabrics
end
