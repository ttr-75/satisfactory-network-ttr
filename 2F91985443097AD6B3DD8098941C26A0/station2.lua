local function listInventories( proxy )
    local invs = proxy:getInventories()
    
    print( proxy.internalName, #invs )
    
    for _, inv in pairs( invs ) do
        print( "\t", inv.internalName, inv.size )
    end
end

local station = component.proxy( "5D8C9802494BC778B96A1EA1D94B54E1" ) -- The train station
print( "station:", station.name )

local platforms = station:getAllConnectedPlatforms()
print( "# platforms:", tostring( #platforms ) )

for _, platform in pairs( platforms ) do
    listInventories( platform )
end