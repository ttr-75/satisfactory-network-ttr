FabricInfo = {
    __name = "FabricInfo",
    fName = nil,
    fType = nil,
    fCoreNetworkCard = nil,
}

function FabricInfo:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function FabricInfo:setName(name)
    self.fName = name
end


function FabricInfo:setType(type)
    self.fType = type
end

function FabricInfo:setCoreNetworkCard(coreNetworkCard)
    self.fCoreNetworkCard = coreNetworkCard
end

function FabricInfo:update(fabric) 

end

function FabricInfo:check(fabric) 
     if not fabric then
        log(3, "Fabric is nil")
        return false
    end

    local id = fabric.fCoreNetworkCard
    if not id then
        log(3, "Fabric has no CoreNetworkCardId")
        return false
    end

    local name = fabric.fName
    if not name then
        log(3, "Fabric has no Name")
        return false
    end

    return true
end


