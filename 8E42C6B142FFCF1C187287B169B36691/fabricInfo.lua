FabricInfo = {
    __name = "FabricInfo",
    fName = nil,
    fType = nil,
    fCoreNetworkCard = nil,
    item = nil,
    containerInventory = nil,
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


