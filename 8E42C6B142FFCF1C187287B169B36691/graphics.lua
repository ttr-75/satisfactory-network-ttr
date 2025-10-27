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
    local o = { r = r, g = g, b = b, a = a }
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
Color.YELLOW        = Color.new(1.000, 1.000, 0.000, 1.0)

--------------------------------------------------------------------------------
-- Vector 2d
--------------------------------------------------------------------------------
Vector2d            = {
    x = 0,
    y = 0,
    pattern = '{x=%d,y=%d}',
}
Vector2d.__index    = Vector2d

---Create a new Vector2d and return it
---@param x number
---@param y number
---@return Vector2d
function Vector2d.new(x, y)
    if x == nil or type(x) ~= "number" then return nil end
    if y == nil or type(y) ~= "number" then return nil end
    local o = { x = math.floor(x), y = math.floor(y) }
    setmetatable(o, { __index = Vector2d })
    return o
end

--------------------------------------------------------------------------------
-- ScreenElement (base)
--------------------------------------------------------------------------------
-- Base for drawable elements that translates local -> screen coords
ScreenElement = {
    gpu = nil,
    position = nil,
    dimensions = nil,
    -- subElements intentionally NOT on class (no shared state)
}
ScreenElement.__index = ScreenElement

function ScreenElement:new(o)
    o             = o or {}
    self.__index  = self
    -- per-instance defaults
    o.subElements = o.subElements or {}
    o.position    = o.position or Vector2d.new(0, 0)
    -- dimensions may remain nil
    return setmetatable(o, self)
end

function ScreenElement:init(gpu, position, dimensions)
    self.gpu        = gpu
    self.position   = position or Vector2d.new(0, 0)
    self.dimensions = dimensions
end

function ScreenElement:addElement(e)
    if e then table.insert(self.subElements, e) end
end

-- Draw children
function ScreenElement:draw()
    for _, element in ipairs(self.subElements) do
        if element.draw then element:draw() end
    end
end

function ScreenElement:flush()
    error('ScreenElement:flush() should not be called; call draw(), then gpu:flush()')
end

function ScreenElement:measureText(Text, Size, bMonospace)
    return self.gpu:measureText(Text, Size, bMonospace)
end

--- Draws Text at local position
function ScreenElement:drawText(position, text, size, color, monospace)
    self.gpu:drawText(self:reposition(position), text, size, color, monospace)
end

--- Draws Rect at local position
function ScreenElement:drawRect(position, size, color, image, rotation)
    self.gpu:drawRect(self:reposition(position), size, color, image, rotation)
end

--- Draws box (already absolute in gpu-space)
function ScreenElement:drawBox(boxSettings)
    self.gpu:drawBox(boxSettings)
end

--- Draws polyline
function ScreenElement:drawLines(points, thickness, color)
    if not points or #points < 2 then return end
    local newPoints = {}
    for _, p in ipairs(points) do
        newPoints[#newPoints + 1] = self:reposition(p)
    end
    self.gpu:drawLines(newPoints, thickness, color)
end

function ScreenElement:reposition(vector)
    local px = (self.position and self.position.x or 0) + vector.x
    local py = (self.position and self.position.y or 0) + vector.y
    return Vector2d.new(px, py)
end

-- ===== Local drawing helpers (KEIN reposition) =====
function ScreenElement:drawLocalRect(position, size, color, image, rotation)
    -- position ist bereits lokal relativ zu self.position
    self.gpu:drawRect(position, size, color, image, rotation)
end

function ScreenElement:drawLocalText(position, text, size, color, monospace)
    self.gpu:drawText(position, text, size, color, monospace)
end

function ScreenElement:drawLocalLines(points, thickness, color)
    -- erwartet lokale Punkte; NICHT verschieben
    self.gpu:drawLines(points, thickness, color)
end

function ScreenElement:drawLocalBox(boxSettings)
    self.gpu:drawBox(boxSettings)
end

--------------------------------------------------------------------------------
-- ItemImage
--------------------------------------------------------------------------------
ItemImage = ScreenElement:new()
ItemImage.__index = ItemImage

function ItemImage.new(o)
    o     = o or {}
    o.box = o.box or {}
    o.bg  = o.bg or Color.WHITE
    o.fg  = o.fg or nil
    return setmetatable(o, ItemImage)
end

function ItemImage:setBox(box) self.box = box or {} end

function ItemImage:draw()
    if not self.position and self.box.position then
        self.position = self.box.position
    end
    if not self.dimensions and self.box.size then
        self.dimensions = self.box.size
    end
    if self.box then self:drawBox(self.box) end
end

--------------------------------------------------------------------------------
-- Plotter
--------------------------------------------------------------------------------
Plotter = ScreenElement:new()
Plotter.__index = Plotter

-- defaults per-instance
function Plotter.new(o)
    local plotter         = setmetatable(o or {}, Plotter)
    plotter.color         = plotter.color or Color.GREY_0500
    plotter.lineThickness = plotter.lineThickness or 10
    plotter.dataSource    = plotter.dataSource or nil
    plotter.graph         = plotter.graph or nil
    plotter.scaleFactorX  = plotter.scaleFactorX or nil
    if plotter.dataSource and plotter.graph then
        plotter:setDataSource(plotter.dataSource)
    end
    return plotter
end

function Plotter:setDataSource(dataSource)
    self.dataSource = dataSource
    if not (self.graph and self.graph.dimensions and self.dataSource and self.dataSource.getMaxSize) then
        self.scaleFactorX = nil
        return
    end
    local maxSize = self.dataSource:getMaxSize()
    if not maxSize or maxSize < 2 then
        self.scaleFactorX = nil
    else
        self.scaleFactorX = self.graph.dimensions.x / (maxSize - 1)
    end
end

function Plotter:setColor(color) self.color = color end

function Plotter:setLineThickness(lineThickness) self.lineThickness = lineThickness end

function Plotter:draw()
    if not (self.dataSource and self.dataSource.iterate) then return end
    if not (self.graph and self.graph.dimensions) then return end
    if not self.scaleFactorX then
        self:setDataSource(self.dataSource)
        if not self.scaleFactorX then return end
    end

    local i        = 0
    local points   = {}
    local maxSize  = (self.dataSource.getMaxSize and self.dataSource:getMaxSize()) or 0
    local currSize = self.dataSource.currSize or maxSize

    self.dataSource:iterate(function(currVal)
        local xPos = (i + maxSize - currSize) * self.scaleFactorX
        local yPos = self.graph.dimensions.y - currVal * self.graph.scaleFactorY
        points[#points + 1] = Vector2d.new(xPos, yPos)
        i = i + 1
    end)

    self:drawLines(points, self.lineThickness, self.color)
end

--------------------------------------------------------------------------------
-- Graph
--------------------------------------------------------------------------------
Graph = ScreenElement:new()
Graph.__index = Graph

function Graph.new(o)
    local g             = setmetatable(o or {}, Graph)
    g.scaleFactorY      = g.scaleFactorY or nil
    g.maxVal            = g.maxVal or nil
    g.dimensions        = g.dimensions or nil
    g.scaleMarginFactor = g.scaleMarginFactor or 0.2
    g.dataSources       = g.dataSources or {}
    g.plotters          = g.plotters or {}
    return g
end

function Graph:addPlotter(name, config)
    local plotter = Plotter.new()
    self.plotters[name] = plotter
    if config ~= nil then
        self:configurePlotter(name, config)
    end
end

function Graph:configurePlotter(name, config)
    local plotter = self.plotters[name]
    for k, v in pairs(config) do plotter[k] = v end
    plotter.graph = self
    if rawget(plotter, 'dataSource') ~= nil then
        plotter:setDataSource(config.dataSource)
        if config.dataSource then
            table.insert(self.dataSources, config.dataSource)
        end
    end
end

function Graph:setMaxVal(maxVal)
    if not maxVal or maxVal <= 0 then maxVal = 1 end
    self.maxVal = maxVal
    if self.dimensions then
        self.scaleFactorY = self.dimensions.y / maxVal
    end
end

function Graph:setDimensions(dimensions)
    self.dimensions = dimensions
    -- push dimensions to data sources if they want it
    for _, currItem in ipairs(self.dataSources) do
        currItem.dimensions = dimensions
    end
    -- update plotters' X scaling
    for _, p in pairs(self.plotters) do
        if p.dataSource then p:setDataSource(p.dataSource) end
    end
end

function Graph:draw()
    if self.maxVal == nil then self:autoResize() end
    for _, plotter in pairs(self.plotters) do
        plotter:draw()
    end
end

function Graph:autoResize()
    local maxVal = self:getMaxVal()
    if not maxVal then return end

    if self.scaleFactorY == nil then
        return self:initScaleFactors(maxVal)
    end

    if not self.dimensions then return end
    local maxDisplayableVal = self.dimensions.y / (self.scaleFactorY or 1e-9)
    if (maxDisplayableVal < maxVal) or (maxDisplayableVal * self.scaleMarginFactor > maxVal) then
        self:initScaleFactors(maxVal)
    end
end

function Graph:initScaleFactors(maxVal)
    maxVal = (maxVal and maxVal > 0) and maxVal or 1e-8
    if self.dimensions then
        self.scaleFactorY = self.dimensions.y / (maxVal * (1 + (self.scaleMarginFactor or 0)))
    end
end

function Graph:getMaxVal()
    local maxVal = 0
    for _, ds in ipairs(self.dataSources) do
        if ds and ds.getMaxVal then
            local v = ds:getMaxVal() or 0
            if v > maxVal then maxVal = v end
        end
    end
    return maxVal
end

--------------------------------------------------------------------------------
-- Progressbar
--------------------------------------------------------------------------------
Progressbar = ScreenElement:new()
Progressbar.__index = Progressbar

function Progressbar.new(o)
    local p = setmetatable(o or {}, Progressbar)
    p.value = p.value or 0
    p.bg    = p.bg or Color.WHITE
    p.fg    = p.fg or nil
    return p
end

function Progressbar:setValue(value)
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    self.value = value
end

function Progressbar:setBackground(bg) self.bg = bg end

function Progressbar:setForeground(fg) self.fg = fg end

function Progressbar:draw()
    -- robust clamp
    local v = self.value
    if v ~= v then v = 0 end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    self.value = v

    if not self.dimensions then
        self.dimensions = Vector2d.new(300, 50)
    end

    local origin = self.position -- Vector2d.new(0, 0)

    -- Hintergrund (lokal)
    self:drawLocalRect(origin, self.dimensions, self.bg, nil, nil)

    -- Farbe
    local f = self.fg
    if not f then
        local r = 1 - v
        f = Color.new(r, v, 0, 1)
    end

    -- Füllung (lokal)
    local d = math.floor(self.dimensions.x * v)
    self:drawLocalRect(origin, Vector2d.new(d, self.dimensions.y), f, nil, nil)
end
