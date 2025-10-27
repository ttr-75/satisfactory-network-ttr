LOG_MIN = 1 -- nur Warn und höher






-- MediaSubsystem (liefert Icon-Referenzen)
--local media = computer.media
--assert(media, "MediaSubsystem nicht gefunden")

NICK_SCREEN = "MyScreen"

local scr = byNick(NICK_SCREEN)
assert(scr, "Screen nicht gefunden")
--x,y=scr:getSize()
--log(1,"ScreenSize: X:" .. x .." Y:" .. y )

-- GPU/Screen/Container
local gpu = computer.getPCIDevices(classes.GPU_T2_C)[1]
assert(gpu, "No GPU T2 found. Cannot continue.")
--event.listen(gpu)

--gpu:bindScreen(scr)

log(1, "Billboard Creation")

--[[

FabricBillbard:init(gpu, scr)
FabricBillbard:run()
]]