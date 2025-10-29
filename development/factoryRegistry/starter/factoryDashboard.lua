FactoryDashboardClient = require("factoryRegistry/FactoryDashboard_Main.lua")


--}



local cli = FactoryDashboardClient.new { fName = fName }
cli:run()
-- MediaSubsystem (liefert Icon-Referenzen)
--local media = computer.media
--assert(media, "MediaSubsystem nicht gefunden")



--[[
NICK_SCREEN = "MyScreen"

local scr = byNick(NICK_SCREEN)
assert(scr, "Screen nicht gefunden")


-- GPU/Screen/Container
local gpu = computer.getPCIDevices(classes.GPU_T2_C)[1]
assert(gpu, "No GPU T2 found. Cannot continue.")
--event.listen(gpu)

--gpu:bindScreen(scr)

log(1, "Billboard Creation")



FactoryBillbard:init(gpu, scr)
FactoryBillbard:run()
]]
