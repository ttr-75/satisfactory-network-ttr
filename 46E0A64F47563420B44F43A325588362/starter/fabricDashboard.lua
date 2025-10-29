local names = { "shared/helper.lua",
    "shared/items.lua",
    "shared/graphics.lua",
    "fabricRegistry/FabricInfo.lua",
    "fabricBillboard.lua",
    "fabricDashboard.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()



-- MediaSubsystem (liefert Icon-Referenzen)
--local media = computer.media
--assert(media, "MediaSubsystem nicht gefunden")

NICK_SCREEN = "MyScreen"

local scr = byNick(NICK_SCREEN)
assert(scr, "Screen nicht gefunden")


-- GPU/Screen/Container
local gpu = computer.getPCIDevices(classes.GPU_T2_C)[1]
assert(gpu, "No GPU T2 found. Cannot continue.")
--event.listen(gpu)

--gpu:bindScreen(scr)

log(1, "Billboard Creation")



FabricBillbard:init(gpu, scr)
FabricBillbard:run()
