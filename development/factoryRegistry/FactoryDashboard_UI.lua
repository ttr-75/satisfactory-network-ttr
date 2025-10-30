require("shared.helper")
require("shared.items.items[-LANGUAGE-]")
require("shared.graphics")
FactoryInfo = require("factoryRegistry.FactoryInfo")
--require("factoryBillboard.lua")



----------------------------------------------------------------
-- FactoryDashboard – passt direkt zu deiner FactoryInfo-Struktur
----------------------------------------------------------------


---Monotonic-ish milliseconds (prefers game API, falls back to os.clock).
---@return integer ms
local function now_ms()
    return (computer and computer.millis and computer.millis())
        or math.floor(os.clock() * 1000)
end

---FIN icon cache by item name.
---@type table<string, MyItem|nil>
local _icon_cache = {}

---Gets (and caches) the icon/item descriptor for a given item name.
---@param itemName string|nil
---@return MyItem|nil icon
local function get_icon_for(itemName)
    if not itemName then return nil end
    if _icon_cache[itemName] ~= nil then return _icon_cache[itemName] end


    local icon            = MyItemList:get_by_Name(itemName)

    _icon_cache[itemName] = icon
    return _icon_cache[itemName]
end

---@class FactoryDashboard
---@field title string
---@field pad integer
---@field rowH integer
---@field iconSize integer
---@field fontSize integer
---@field headerSize integer
---@field minIntervalMs integer
---@field lastPaint integer
---@field bg Color
---@field fg Color
---@field muted Color
---@field accent Color
---@field inputs { name:string, s:number, c:number, sMax:number, cMax:number }[]
---@field outputs { name:string, s:number, c:number, sMax:number, cMax:number }[]
---@field gpu GPUProxy
---@field scr ScreenProxy
---@field size Vector2d
---@field root ScreenElement
local FactoryDashboard = {}
FactoryDashboard.__index = FactoryDashboard


---Creates a new dashboard instance.
---@param opts table|nil -- { title? = string }
---@return FactoryDashboard
function FactoryDashboard.new(opts)
    local self         = setmetatable({}, FactoryDashboard)
    self.title         = (opts and opts.title) or "Fabrik-Übersicht"
    self.pad           = 14
    self.rowH          = 100
    self.iconSize      = 100
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

    -- Client
    --self.mediaCli      = MediaClient.new()



    return self
end

---Fills inputs/outputs from a FactoryInfo-like table.
---fi.inputs[name] = Input{ itemClass={name=..}, amountStation, amountContainer, maxAmountStation, maxAmountContainer }
---fi.outputs[name] = Output{ ... }
---@param fi FactoryInfo
function FactoryDashboard:setFromFactoryInfo(fi)
    ---@param map table<string, any>|nil
    ---@return { name:string, s:number, c:number, sMax:number, cMax:number }[]
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

---Sets explicit input/output rows (bypassing FactoryInfo mapping).
---@param inputs Input[]|nil
---@param outputs Output[]|nil
function FactoryDashboard:setData(inputs, outputs)
    self.inputs  = inputs or {}
    self.outputs = outputs or {}
end

---Initializes rendering targets and root screen element.
---@param gpu GPUProxy
---@param scr ScreenProxy
function FactoryDashboard:init(gpu, scr)
    self.gpu            = gpu
    self.scr            = scr
    
    local width, height = scr:getSize()
    width               = width * 300
    height              = height * 300

    gpu:bindScreen(scr)

    self.size = Vector2d.new(width or 1920, height or 1080)


    self.root = ScreenElement:new()
    self.root:init(gpu, Vector2d.new(0, 0), self.size)
end

---Optional color logic for a progress bar depending on fraction (currently disabled).
---@param frac number
---@return Color|nil
local function barColor(frac)
    if true then return nil end
    if frac ~= frac then frac = 0 end
    if frac < 0.2 then
        return Color.RED
    elseif frac < 0.5 then
        return Color.FICSIT_ORANGE
    else
        return Color.GREEN_0750
    end
end

---Draws one data row with icon, labels and two bars (station/container).
---@param colX integer
---@param posY integer
---@param ix integer
---@param it MyItem
---@param colWidth integer
function FactoryDashboard:_drawRow(colX, posY, ix, it, colWidth)
    local y = posY + 120 + (ix - 1) * (self.rowH + self.rowH) + self.pad
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
    local line = string.format("%s", it.name or "?")
    self.root:drawText(Vector2d.new(textX, y + (self.rowH - self.fontSize) // 2),
        line, self.fontSize, self.fg, false)

    local line = string.format("Station: %s/%s",
        tostring(it.s), tostring(it.sMax))
    self.root:drawText(Vector2d.new(textX, y + (self.rowH + self.rowH - self.fontSize) // 2),
        line, self.fontSize, self.fg, false)

    local line = string.format("Container: %s/%s",
        tostring(it.c), tostring(it.cMax))
    self.root:drawText(Vector2d.new(textX, y + (self.rowH + self.rowH + self.rowH - self.fontSize) // 2),
        line, self.fontSize, self.fg, false)

    -- Bars rechts: Station + Container
    local barW  = math.max(320, math.floor(colWidth * 0.45))
    local barH  = 50
    local gap   = 6
    local pbX   = colX + colWidth - barW - self.pad
    local sFrac = (it.sMax and it.sMax > 0) and (it.s / it.sMax) or 0
    local cFrac = (it.cMax and it.cMax > 0) and (it.c / it.cMax) or 0

    -- Station-Bar
    local pbS   = Progressbar.new {
        position = Vector2d.new(pbX, y + (self.rowH + self.rowH - (2 * barH + gap)) // 2),
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

---Paints an output warning icon (aggregated from outputs).
---@param position Vector2d|nil
---@param size Vector2d|nil
function FactoryDashboard:paintOuputWarning(position, size)
    local posY = self.pad
    local posX = self.size.x - 200 - self.pad
    if position ~= nil then
        posX = position.x
        posY = position.y
    end

    if size == nil then
        size = Vector2d.new(200, 200)
    end

    local icon = MyItem.CHECK_MARK
    local color = Color.GREEN
    for i, it in pairs(self.outputs) do
        local sFrac = it.s / it.sMax
        local cFrac = it.c / it.cMax
        if sFrac < 0.5 then
            icon = MyItem.WARNING
            color = Color.YELLOW
            if cFrac < 0.2 then
                icon = MyItem.POWER
                color = Color.RED
            end
        end
        if sFrac < 0.1 then
            icon = MyItem.POWER
            color = Color.RED
        end
    end

    -- Bild direkt laden
    --local img, err = self.mediaCli:load_png_via_media(icon, 8000)
    --if not img then
    --   log(3, "load_png_via_media failed: " .. tostring(err))
    --end

    self.root:drawLocalRect(position, size, color, icon:getRef())
    --[[local icon = get_icon_for(it.name)
    self.root:drawBox({
        position  = Vector2d.new(posX, posY),
        size      = titleIconSize,
        image     = icon and icon:getRef() or "",
        imageSize = titleIconSize,

    })]]
end

---Paints an input warning icon (aggregated from inputs).
---@param position Vector2d|nil
---@param size Vector2d|nil
function FactoryDashboard:paintInputWarning(position, size)
    local posY = self.pad
    local posX = self.size.x - 500 - self.pad
    if position ~= nil then
        posX = position.x
        posY = position.y
    end

    if size == nil then
        size = Vector2d.new(200, 200)
    end

    local color = Color.GREEN
    local icon = MyItem.CHECK_MARK
    for i, it in pairs(self.inputs) do
        local sFrac = it.s / it.sMax
        local cFrac = it.c / it.cMax
        if cFrac < 0.5 then
            icon = MyItem.WARNING
            color = Color.YELLOW
            if sFrac < 0.2 then
                icon = MyItem.POWER
                color = Color.RED
            end
        end
        if cFrac < 0.1 then
            icon = MyItem.POWER
            color = Color.RED
        end
    end



    self.root:drawLocalRect(position, size, color, icon:getRef())
    --[[local icon = get_icon_for(it.name)
    self.root:drawBox({
        position  = Vector2d.new(posX, posY),
        size      = titleIconSize,
        image     = icon and icon:getRef() or "",
        imageSize = titleIconSize,

    })]]
end

function FactoryDashboard:paint()
    local t = now_ms()
    if t - self.lastPaint < self.minIntervalMs then return end
    self.lastPaint = t

    local w, h = self.size.x, self.size.y
    local mid = math.floor(w / 2)

    -- Hintergrund
    self.root:drawRect(Vector2d.new(0, 0), self.size, self.bg, nil, nil)

    -- Titel
    local posX, posY = self.pad, self.pad;
    local titleIconSize = Vector2d.new(200, 200);
    self.title = ""
    for i, it in ipairs(self.outputs) do
        local icon = get_icon_for(it.name)
        self.root:drawBox({
            position  = Vector2d.new(posX, posY),
            size      = titleIconSize,
            image     = icon and icon:getRef() or "",
            imageSize = titleIconSize,

        })
        posX = posX + titleIconSize.x + self.pad
        self.title = it.name .. " " .. self.title
    end

    self.root:drawText(Vector2d.new(posX, posY + titleIconSize.y - 72 * 2), self.title, 72, self.accent, false)

    posX = self.pad
    posY = posY + titleIconSize.y + self.pad
    -- Spaltenüberschriften
    self.root:drawText(Vector2d.new(posX, posY), "Inputs", self.headerSize, self.fg, false)
    self.root:drawText(Vector2d.new(mid + posX, posY), "Outputs", self.headerSize, self.fg, false)

    -- vertikaler Trenner
    self.root:drawRect(Vector2d.new(mid - 1, posY), Vector2d.new(2, h - 80), Color.GREY_0125, nil, nil)

    -- Spaltenbreiten
    local leftW  = mid - 2 * self.pad
    local rightW = (w - mid) - 2 * self.pad

    for i, it in ipairs(self.inputs) do
        self:_drawRow(self.pad, posY, i, it, leftW)
    end
    for i, it in ipairs(self.outputs) do
        self:_drawRow(mid + self.pad, posY, i, it, rightW)
    end

    local sizeW = Vector2d.new(50, 50)
    self:paintInputWarning(Vector2d.new(posX + 200, posY), sizeW)
    self:paintOuputWarning(Vector2d.new(mid + posX + 200, posY), sizeW)


    self.gpu:flush()
end

return FactoryDashboard
