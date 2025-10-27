local names = {
    "fabricRegistry/basics.lua",
    "fabricRegistry/FabricRegistry.lua",
    "net/NetworkAdapter.lua",
    "fabricRegistry/FabricRegistryClient.lua",

}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()