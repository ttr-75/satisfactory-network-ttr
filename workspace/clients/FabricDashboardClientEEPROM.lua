NET_CMD_RESET_ALL = "resetAll"

MyClient = {
    port = 8,
    netBootInitDone = false,
    _listenerId = nil,
    _onReset = nil,
}
MyClient.__index = MyClient

function MyClient:new(o)
    return setmetatable(o or {}, MyClient)
end

function MyClient:setPort(p)
    assert(type(p) == "number" and p > 0, "setPort: invalid port")
    self.port = p
end

function MyClient:setResetHandler(fn)
    computer.log(2, "Net-Boot: setResetHandlerCalled")
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

function MyClient:initNetBoot()
    if self.netBootInitDone then return end

    self.net = computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.net, "Net-Boot: No Network Card available!")

    self.net:open(self.port)
    event.listen(self.net)

    -- Listener
    local f = event.filter { event = "NetworkMessage" }
    self._listenerId = event.registerListener(f, function(ev, nic, fromId, port, cmd, ...)
        -- Verbose Debug: zeig, was wirklich reinkommt
        --log(0, ("NB RX ev=%s port=%s cmd=%s from=%s"):format(
        --   tostring(ev), tostring(port), tostring(cmd), tostring(fromId)))

        if port ~= self.port then return end
        if cmd ~= NET_CMD_RESET_ALL then return end

        computer.log(2, ('Net-Boot: Received reset command from "%s"'):format(fromId))
        if self._onReset ~= nil then
            computer.log(2, "Net-Boot: Call Callback")
            local ok, err = pcall(self._onReset)
            if not ok then computer.log(3, "Reset handler error: " .. tostring(err)) end
        elseif type(netBootReset) == "function" then
            pcall(netBootReset)
        end
        -- optional aufräumen:
        -- self:close()
        computer.reset()
    end)

    computer.log(0, "Net-Boot: listening on port " .. tostring(self.port))
    self.netBootInitDone = true
end

function MyClient:close()
    if self._listenerId then
        if event.removeListener then
            pcall(event.removeListener, self._listenerId)
        elseif event.unregisterListener then
            pcall(event.unregisterListener, self._listenerId)
        elseif event.cancelListener then
            pcall(event.cancelListener, self._listenerId)
        end
        self._listenerId = nil
    end
    if self.net then pcall(function() self.net:close() end) end
    self.netBootInitDone = false
end

-- Fragt Code vom Server an und wartet bis timeoutSec (default 30s) auf Antwort
function MyClient:loadFromNetBoot(name, timeoutSec)
    if not self.netBootInitDone then self:initNetBoot() end
    timeoutSec = timeoutSec or 30

    self.net:broadcast(self.port, "getEEPROM", name)
    computer.log(0, ('Net-Boot: Requesting "%s"'):format(name))

    local deadline = (computer.millis and computer.millis() or 0) + timeoutSec * 1000
    while true do
        local e, _, s, p, cmd, programName, code = event.pull(0.25)
        if e == "NetworkMessage" and p == self.port and cmd == "setEEPROM" and programName == name then
            computer.log(0, ('Net-Boot: Got code for "%s" from "%s"'):format(name, s))
            return code
        end
        if computer.millis and computer.millis() >= deadline then
            computer.log(3, "Net-Boot: Request timeout reached")
            return nil
        end
    end
end

function MyClient:loadCode(name)
    computer.log(0, "Loading " .. name .. " from net boot")
    return self:loadFromNetBoot(name)
end

function MyClient:parseModule(name)
    local content = self:loadCode(name)
    if not content then
        computer.log(3, "Could not load " .. name .. ": Not found.")
        return nil
    end
    computer.log(0, "Parsing loaded content")
    local code, err = load(content)
    if not code then
        computer.log(4, "Failed to parse " .. name .. ": " .. tostring(err))
        event.pull(2)
        computer.reset()
    end
    return code
end

function MyClient:loadModule(name)
    computer.log(0, "Loading " .. name .. " through the bootloader")
    local code = self:parseModule(name)
    if not code then
        computer.log(4, "Failed to load module " .. name)
        return
    end
    computer.log(0, "Starting " .. name)
    local ok, err = pcall(code)
    if not ok then
        computer.log(3, err)
        event.pull(2)
        computer.reset()
    end
end

-- Beispiel:
-- local c = MyClient:new()
-- c:setResetHandler(function() computer.log(0, "clean up before reset") end)
-- c:initNetBoot()
-- c:loadModule("station2.lua")

c = MyClient:new()
c:setResetHandler(function() computer.log(0, "clean up before reset") end)

LOG_MIN = 0 -- nur Warn und höher

c:loadModule("helper.lua");
c:loadModule("serializer.lua");
c:loadModule("items.lua");
c:loadModule("graphics.lua");
c:loadModule("fabricInfo.lua");
c:loadModule("fabricRegistry.lua");
c:loadModule("fabricBillboard.lua");
c:loadModule("fabricDashboard.lua");
c:close()

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

testing = false

if testing then
    local scr2 = byNick("myScreen2")
    gpu:bindScreen(scr2)

    -- Hintergrund
    gpu:drawRect(Vector2d.new(0, 0), Vector2d.new(300, 290), Color.WHITE, nil, nil)
    gpu:flush()
else
    FabricBillbard:init(gpu, scr)
    FabricBillbard:run()
end
