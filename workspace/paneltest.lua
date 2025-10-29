-- ====== CONFIG ======
local NICK_SCREEN    = "Screen PanelTest"
local NICK_CONTAINER = "Container PanelTest"
local REFRESH_SEC    = 1.0 -- Aktualisierung
local ROW_H          = 64  -- Zeilenhöhe (Iconhöhe)
local ICON_SIZE      = 48  -- Icon-Kantenlänge, wird in Box skaliert
local PAD            = 8   -- Innenabstand

-- ====== HELPERS ======
local LOG_MIN        = 1 -- nur Warn und höher

local function log(level, ...)
    if level >= LOG_MIN then
        computer.log(level, table.concat({ ... }, " "))
    end
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------
local itemList = {}
itemList['Platine'] = 243
itemList['Turbodraht'] = 274



--------------------------------------------------------------------------------
-- Color
--------------------------------------------------------------------------------
Color = {
    r = 0.0,
    g = 0.0,
    b = 0.0,
    a = 0.0,
    pattern = '{r=%1.6f,g=%1.6f,b=%1.6f,a=%1.6f}',
}
Color.__index = Color

---Create a new Color and return it or nil on invalid input
---@param r number
---@param g number
---@param b number
---@param a number
---@return Color
function Color.new(r, g, b, a)
    if r == nil or type(r) ~= "number" then return nil end
    if g == nil or type(g) ~= "number" then return nil end
    if b == nil or type(b) ~= "number" then return nil end
    if a == nil or type(a) ~= "number" then return nil end
    local o = {
        r = r,
        g = g,
        b = b,
        a = a,
    }
    setmetatable(o, { __index = Color })
    return o
end

Color.BLACK         = Color.new(0.000, 0.000, 0.000, 1.0)
Color.WHITE         = Color.new(1.000, 1.000, 1.000, 1.0)
Color.GREY_0750     = Color.new(0.750, 0.750, 0.750, 1.0)
Color.GREY_0500     = Color.new(0.500, 0.500, 0.500, 1.0)
Color.GREY_0250     = Color.new(0.250, 0.250, 0.250, 1.0)
Color.GREY_0125     = Color.new(0.125, 0.125, 0.125, 1.0)

Color.RED           = Color.new(1.000, 0.000, 0.000, 1.0)
Color.GREEN         = Color.new(0.000, 1.000, 0.000, 1.0)
Color.GREEN_0750    = Color.new(0.000, 0.750, 0.000, 1.0)
Color.GREEN_0500    = Color.new(0.000, 0.500, 0.000, 1.0)
Color.BLUE          = Color.new(0.000, 0.000, 1.000, 1.0)

Color.FICSIT_ORANGE = Color.new(1.000, 0.550, 0.200, 1.0)


--------------------------------------------------------------------------------
-- Vector 2d
--------------------------------------------------------------------------------
Vector2d = {
    x = 0,
    y = 0,
    pattern = '{x=%d,y=%d}',
}
Vector2d.__index = Vector2d

---Create a new Vector2d and return it
---@param x integer
---@param y integer
---@return Vector2d
function Vector2d.new(x, y)
    if x == nil or type(x) ~= "number" then return nil end
    if y == nil or type(y) ~= "number" then return nil end
    local o = { x = math.floor(x), y = math.floor(y) }
    setmetatable(o, { __index = Vector2d })
    return o
end

local function byNick(nick)
    local t = component.findComponent(nick)[1]
    assert(t, "Komponente '" .. nick .. "' nicht gefunden")
    return component.proxy(t)
end

-- Liest die erste Inventory des Containers aus und aggregiert nach Item-Typ
local function readInventory(container, totals, types)
    local invs = container:getInventories()
    local inv = invs and invs[1]
    if not inv then return {}, {} end

    if totals == nil then
        totals = {}
    end
    if types == nil then
        types = {}
    end
    -- local totals = {} -- key: type.hash -> sum count
    -- local types  = {} -- key: type.hash -> type (für Namen/MaxStack)

    -- Slots sind 0-basiert und gehen bis size-1
    for slot = 0, inv.size - 1, 1 do
        local stack = inv:getStack(slot)
        if stack and stack.count and stack.count > 0 and stack.item and stack.item.type then
            local t = stack.item.type
            local key = t.hash
            totals[key] = (totals[key] or 0) + stack.count
            types[key] = t
        end
    end
    return totals, types
end


-- MediaSubsystem (liefert Icon-Referenzen)
local media = computer.media
assert(media, "MediaSubsystem nicht gefunden")


local container = byNick(NICK_CONTAINER)
assert(container, "Container nicht gefunden")


local scr = byNick(NICK_SCREEN)
assert(scr, "Screen nicht gefunden")

-- GPU/Screen/Container
local gpu = computer.getPCIDevices(classes.GPU_T2_C)[1]
assert(gpu, "No GPU T2 found. Cannot continue.")

gpu:bindScreen(scr)

local w, h = gpu:getScreenSize()


while true do
    -- gpu = deine GPUT2; scr = Screen-Trace; media = pc.media (wie bei dir gefunden)


    -- Hintergrund „füllen“ (einfach großes Rechteck zeichnen)
    gpu:drawRect(Vector2d.new(0, 0), Vector2d.new(10000, 10000), Color.new(0, 0, 0, 1), "", 0)

    -- Text zeichnen (Farbe pro Drawcall)
    gpu:drawText(Vector2d.new(16, 16), "Hallo GPU T2", 18, Color.new(1, 1, 1, 1), false)


    local totals = {}
    local types = {}


    totals, types = readInventory(container, totals, types)


    local counter = 0;

    local tht = nil

    for key, cnt in pairs(totals) do
        local t = types[key]
        local name = (t and t.name) or ("Type#" .. tostring(key))
        local maxStack = (t and t.max) or nil
        log(0, name .. cnt)
        counter = counter + cnt
        tht = t.name

        local box = {
            position  = Vector2d.new(16, 48),
            size      = Vector2d.new(200, 200),
            image     = "icon:" .. itemList[tht],
            imageSize = Vector2d.new(512, 512)
        } -- 256/512 je nach Icon
        gpu:drawBox(box)
        --end

        gpu:flush() -- T2 hat ebenfalls einen Flush, der die Drawcalls sichtbar macht
        event.pull(REFRESH_SEC)
        --table.insert(rows, { name = name, count = cnt, max = maxStack })
    end

    -- Icon zeichnen
    -- print(itemList[tht])
    -- local icon = media:findGameIcon("icon:888")

    --if icon and icon.isValid then
    local box = {
        position  = Vector2d.new(16, 48),
        size      = Vector2d.new(200, 200),
        image     = "icon:" .. itemList[tht],
        imageSize = Vector2d.new(512, 512)
    }   -- 256/512 je nach Icon
    gpu:drawBox(box)
    --end

    gpu:flush() -- T2 hat ebenfalls einen Flush, der die Drawcalls sichtbar macht
    event.pull(REFRESH_SEC)
end


-- ====== MAIN LOOP ======
while false do
    local ok, err = pcall(draw)
    if not ok then
        clear()
        gpu:setForeground(1, 0.6, 0.6, 1)
        gpu:setText(2, 2, "Fehler: " .. tostring(err))
        gpu:flush()
    end
    event.pull(REFRESH_SEC)
end
