local names = {
    "fabricRegistry/FabricDataCollertor_Main.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()



sleep_s(1)


---@diagnostic disable-next-line: undefined-global
assert(fName, "fabricInfoCollector.lua - fName must been set.")
local cli = nil
---@diagnostic disable-next-line: undefined-global
if not stationMin then
    ---@diagnostic disable-next-line: undefined-global
    cli = FabricDataCollertor.new { fName = fName }
else
    ---@diagnostic disable-next-line: undefined-global
    cli = FabricDataCollertor.new { fName = fName, stationMin = stationMin }
end

cli:run()
