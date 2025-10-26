----------------------------------------------------------------
-- FabricDashboard – passt direkt zu deiner FabricInfo-Struktur
----------------------------------------------------------------
local function now_ms()
    return (computer and computer.millis and computer.millis())
        or math.floor(os.clock() * 1000)
end

-- FIN-Icon Cache
local _icon_cache = {}
local function get_icon_for(itemName)
    if not itemName then return nil end
    if _icon_cache[itemName] ~= nil then return _icon_cache[itemName] end
    
    
    local icon = MyItemList:get_by_Name(itemName)

    _icon_cache[itemName]  = icon
    return _icon_cache[itemName]
end

FabricDashboard = {}
FabricDashboard.__index = FabricDashboard

function FabricDashboard.new(opts)
    local self         = setmetatable({}, FabricDashboard)
    self.title         = (opts and opts.title) or "Fabrik-Übersicht"
    self.pad           = 14
    self.rowH          = 64
    self.iconSize      = 48
    self.fontSize      = 24
    self.headerSize    = 28
    self.minIntervalMs = 1000
    self.lastPaint     = 0

    self.bg            = Color.BLACK
    self.fg            = Color.WHITE
    self.muted         = Color.GREY_0500
    self.accent        = Color.FICSIT_ORANGE

    self.inputs        = {} -- array of rows
    self.outputs       = {}
    return self
end

-- Aus deiner FabricInfo mappen:
-- fi.inputs[name]  = Input{ itemClass={name=..}, amountStation, amountContainer, maxAmountStation, maxAmountContainer }
-- fi.outputs[name] = Output{ ... }
function FabricDashboard:setFromFabricInfo(fi)
    local function rows_from(map)
        local rows = {}
        if map then
            for name, obj in pairs(map) do
                local itemName = name or (obj.itemClass and obj.itemClass.name) or "?"
                rows[#rows + 1] = {
                    name = itemName,
                    s    = obj.amountStation or 0,
                    c    = obj.amountContainer or 0,
                    sMax = obj.maxAmountStation or 0,
                    cMax = obj.maxAmountContainer or 0,
                }
            end
            table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
        end
        return rows
    end
    self.inputs  = rows_from(fi and fi.inputs)
    self.outputs = rows_from(fi and fi.outputs)
end

function FabricDashboard:setData(inputs, outputs)
    self.inputs  = inputs or {}
    self.outputs = outputs or {}
end

function FabricDashboard:init(gpu, scr, width, height)
    --[[
    -- GPU
    local gpu
    if type(gpuNickOrRef) == "string" then
        local t = component.findComponent(gpuNickOrRef)[1]
        assert(t, "GPU '" .. gpuNickOrRef .. "' nicht gefunden")
        gpu = component.proxy(t)
    else
        gpu = gpuNickOrRef
    end
    -- Screen
    local scr
    if type(screenNickOrRef) == "string" then
        local t = component.findComponent(screenNickOrRef)[1]
        assert(t, "Screen '" .. screenNickOrRef .. "' nicht gefunden")
        scr = component.proxy(t)
    else
        scr = screenNickOrRef
    end
    ]]

    gpu:bindScreen(scr)
    self.gpu  = gpu
    self.scr  = scr
    self.size = Vector2d.new(width or 1920, height or 1080)

    self.root = ScreenElement:new()
    self.root:init(gpu, Vector2d.new(0, 0), self.size)
end

-- kleine Farblogik für Füllstand
local function barColor(frac)
    if frac ~= frac then frac = 0 end
    if frac < 0.2 then
        return Color.RED
    elseif frac < 0.5 then
        return Color.FICSIT_ORANGE
    else
        return Color.GREEN_0750
    end
end

-- eine Zeile rendern (zwei Bars: Station / Container)
function FabricDashboard:_drawRow(colX, ix, it, colWidth)
    local y = 120 + (ix - 1) * (self.rowH + self.pad)
    local left = colX + self.pad

    -- Icon
    local icon = get_icon_for(it.name)
    if icon then
        local box     = {}
        box.position  = Vector2d.new(left, y + (self.rowH - self.iconSize) // 2)
        box.size      = Vector2d.new(self.iconSize, self.iconSize)
        box.image     = icon:getRef()
        box.imageSize = Vector2d.new(icon.width or 512, icon.height or 512)
        self.root:drawBox(box)
    end

    -- Text
    local textX = left + self.iconSize + 10
    local line = string.format("%s | Station: %s/%s   Container: %s/%s",
        it.name or "?", tostring(it.s), tostring(it.sMax), tostring(it.c), tostring(it.cMax))
    self.root:drawText(Vector2d.new(textX, y + (self.rowH - self.fontSize) // 2),
        line, self.fontSize, self.fg, false)

    -- Bars rechts: Station + Container
    local barW  = math.max(320, math.floor(colWidth * 0.45))
    local barH  = 16
    local gap   = 6
    local pbX   = colX + colWidth - barW - self.pad
    local sFrac = (it.sMax and it.sMax > 0) and (it.s / it.sMax) or 0
    local cFrac = (it.cMax and it.cMax > 0) and (it.c / it.cMax) or 0

    -- Station-Bar
    local pbS   = Progressbar.new {
        position = Vector2d.new(pbX, y + (self.rowH - (2 * barH + gap)) // 2),
        dimensions = Vector2d.new(barW, barH),
        bg = Color.GREY_0250, fg = barColor(sFrac), value = sFrac
    }
    pbS:init(self.gpu, pbS.position, pbS.dimensions); pbS:draw()
    self.root:drawText(Vector2d.new(pbX - 64, pbS.position.y - 2), "St", 18, self.muted, true)

    -- Container-Bar
    local pbC = Progressbar.new {
        position = Vector2d.new(pbX, pbS.position.y + barH + gap),
        dimensions = Vector2d.new(barW, barH),
        bg = Color.GREY_0250, fg = barColor(cFrac), value = cFrac
    }
    pbC:init(self.gpu, pbC.position, pbC.dimensions); pbC:draw()
    self.root:drawText(Vector2d.new(pbX - 64, pbC.position.y - 2), "Co", 18, self.muted, true)
end

function FabricDashboard:paint()
    local t = now_ms()
    if t - self.lastPaint < self.minIntervalMs then return end
    self.lastPaint = t

    local w, h = self.size.x, self.size.y
    local mid = math.floor(w / 2)

    -- Hintergrund
    self.root:drawRect(Vector2d.new(0, 0), self.size, self.bg, nil, nil)

    -- Titel
    self.root:drawText(Vector2d.new(self.pad, self.pad), self.title, 36, self.accent, false)

    -- Spaltenüberschriften
    self.root:drawText(Vector2d.new(self.pad, 78), "Inputs", self.headerSize, self.fg, false)
    self.root:drawText(Vector2d.new(mid + self.pad, 78), "Outputs", self.headerSize, self.fg, false)

    -- vertikaler Trenner
    self.root:drawRect(Vector2d.new(mid - 1, 72), Vector2d.new(2, h - 80), Color.GREY_0125, nil, nil)

    -- Spaltenbreiten
    local leftW  = mid - 2 * self.pad
    local rightW = (w - mid) - 2 * self.pad

    for i, it in ipairs(self.inputs) do
        self:_drawRow(self.pad, i, it, leftW)
    end
    for i, it in ipairs(self.outputs) do
        self:_drawRow(mid + self.pad, i, it, rightW)
    end

    self.gpu:flush()
end
