---@return Build_TrainStationLeft_C
function getComponent(name)
    local comp = component.findComponent(classes.Build_TrainStationLeft_C)[1]
    computer.log(4, comp)
    local ts = component.proxy(comp)
    return ts
end

---@param trainstation Build_TrainStationLeft_C 
---@return TrainPlatformConnection
function getNextPlatform(trainstation)
    return trainstation.getAllConnectedPlatforms(trainstation)[1];
end

my = getComponent("")




--computer.log(4,ts)

pf = getNextPlatform(my)
pf.


computer.log(4, pf[1])
