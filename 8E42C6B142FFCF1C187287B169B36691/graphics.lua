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

--------------------------------------------------------------------------------
-- ScreenElement
--------------------------------------------------------------------------------
--[[
     Offers the regular GPU T2 drawing commands, translating
     the coordinates to a screen location.

     This serves as the base for a graphics library, allowing
     multiple elements to be added that will (re)draw when
     this Element is being (re)drawn
]]
ScreenElement = {
    gpu = nil,
    position = nil,
    dimensions = nil,
    subElements = {},

    -- Helper functions at the bottom of this script
    reposition = nil,
}

function ScreenElement:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

function ScreenElement:init(gpu, position, dimensions)
    self.gpu = gpu
    self.position = position
    self.dimensions = dimensions
end

function ScreenElement:addElement(e)
    if e == nil then
        return
    end

    table.insert(self.subElements, e)
end

-- Draw the element and all sub elements that have been added
function ScreenElement:draw()
    print("Repainting")
    for _, element in pairs(self.subElements) do
        element:draw()
    end
end

function ScreenElement:flush()
    computer.error('ScreenElement:flush() should not be called; call draw(), then do a gpu:flush()')
end

function ScreenElement:measureText(Text, Size, bMonospace)
    return self.gpu:measureText(Text, Size, bMonospace)
end

--- Draws some Text at the given position (top left corner of the text), text, size, color and rotation.
---@param position Vector2D @The position of the top left corner of the text.
---@param text string @The text to draw.
---@param size number @The font size used.
---@param color Color @The color of the text.
---@param monospace boolean @True if a monospace font should be used.
function ScreenElement:drawText(position, text, size, color, monospace)
    self.gpu:drawText(
        self:reposition(position),
        text,
        size,
        color,
        monospace
    )
end

--- Draws a Rectangle with the upper left corner at the given local position, size, color and rotation around the upper left corner.
---@param position Vector2D @The local position of the upper left corner of the rectangle.
---@param size Vector2D @The size of the rectangle.
---@param color Color @The color of the rectangle.
---@param image string @If not empty string, should be image reference that should be placed inside the rectangle.
---@param rotation number @The rotation of the rectangle around the upper left corner in degrees.
function ScreenElement:drawRect(position, size, color, image, rotation)
    self.gpu:drawRect(
        self:reposition(position),
        size,
        color,
        image,
        rotation
    )
end

--- Draws a Boxe with the upper left corner at the given local position, size, color and rotation around the upper left corner.
---@param position Vector2D @The local position of the upper left corner of the rectangle.
---@param size Vector2D @The size of the rectangle.
---@param color Color @The color of the rectangle.
---@param image string @If not empty string, should be image reference that should be placed inside the rectangle.
---@param rotation number @The rotation of the rectangle around the upper left corner in degrees.
function ScreenElement:drawBox(boxSettings)
    self.gpu:drawBox(boxSettings)
end

--- Draws connected lines through all given points with the given thickness and color.
---@param points Vector2D[] @The local points that get connected by lines one after the other.
---@param thickness number @The thickness of the lines.
---@param color Color @The color of the lines.
function ScreenElement:drawLines(points, thickness, color)
    if #points < 2 then
        return
    end

    local newPoints = {}

    for _, currPoint in pairs(points) do
        table.insert(newPoints, self:reposition(currPoint))
    end

    self.gpu:drawLines(
        newPoints,
        thickness,
        color
    )
end

function ScreenElement:reposition(vector)
    return Vector2d.new(
        self.position.x + vector.x,
        self.position.y + vector.y
    )
end

--------------------------------------------------------------------------------
-- Image
--------------------------------------------------------------------------------
ItemImage = ScreenElement:new()

ItemImage.__index = ItemImage
ItemImage.box = {}
ItemImage.bg = Color.WHITE
ItemImage.fg = nil



function ItemImage.new()
    return setmetatable({}, ItemImage)
end

function ItemImage:setBox(box)
    self.box = box
end

function ItemImage:draw()
    if not self.position then 
        self.position = self.box.position
    end
    if not self.dimensions then
        self.dimensions = self.box.size
    end
    self:drawBox(self.box)
end

--------------------------------------------------------------------------------
-- Plotter
--------------------------------------------------------------------------------
Plotter = ScreenElement:new()

Plotter.__index = Plotter
Plotter.graph = nil -- The graph this plotter belongs to
Plotter.maxVal = nil
Plotter.scaleFactorX = nil
Plotter.color = Color.GREY_0500
Plotter.lineThickness = 10
Plotter.dataSource = {}

function Plotter.new(o)
    local plotter = setmetatable(o or {}, Plotter)

    if o ~= nil and rawget(o, 'dataSource') ~= nil then
        plotter:setDataSource(o.dataSource)
    end

    return plotter
end

function Plotter:setDataSource(dataSource)
    self.dataSource = dataSource
    self.scaleFactorX = self.graph.dimensions.x / (self.dataSource:getMaxSize() - 1)
end

function Plotter:setColor(color)
    self.color = color
end

function Plotter:setLineThickness(lineThickness)
    self.lineThickness = lineThickness
end

function Plotter:draw()
    local i = 0
    local points = {}
    self.dataSource:iterate(
        function(currVal)
            local xPos = (i + self.dataSource.maxSize - self.dataSource.currSize) * self.scaleFactorX
            local yPos = self.graph.dimensions.y - currVal * self.graph.scaleFactorY

            local position = Vector2d.new(xPos, yPos)
            table.insert(points, position)
            i = i + 1
        end
    )

    self:drawLines(points, self.lineThickness, self.color)
end

--------------------------------------------------------------------------------
-- Graph
--------------------------------------------------------------------------------
Graph = ScreenElement:new()

Graph.__index = Graph
Graph.scaleFactorY = nil
Graph.maxVal = nil
Graph.dimensions = nil
Graph.scaleMarginFactor = 0.2
Graph.dataSources = {}
Graph.plotters = {}

function Graph.new()
    return setmetatable({}, Graph)
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
    for k, v in pairs(config) do
        plotter[k] = v
    end
    plotter.graph = self

    if rawget(plotter, 'dataSource') ~= nil then
        plotter:setDataSource(config.dataSource)
        table.insert(self.dataSources, config.dataSource or {})
    end
end

function Graph:setMaxVal(maxVal)
    self.maxVal = maxVal
    self.scaleFactorY = self.dimensions.y / maxVal
end

function Graph:setDimensions(dimensions)
    self.dimensions = dimensions

    for _, currItem in ipairs(self.dataSources) do
        currItem.dimensions = dimensions
    end
end

function Graph:draw()
    if self.maxVal == nil then
        self:autoResize()
    end

    for _, plotter in pairs(self.plotters) do
        plotter:draw()
    end
end

function Graph:autoResize()
    local maxVal = self:getMaxVal()

    if self.scaleFactorY == nil then
        return self:initScaleFactors(maxVal)
    end

    local maxDisplayableVal = self.dimensions.y / (self.scaleFactorY or 0.00000000001)
    if
        maxDisplayableVal < maxVal or
        maxDisplayableVal * self.scaleMarginFactor > maxVal
    then
        self:initScaleFactors(maxVal)
    end
end

function Graph:initScaleFactors(maxVal)
    if maxVal == nil then
        maxVal = 0.00000000001
    end

    self.scaleFactorY = self.dimensions.y / (maxVal * (1 + self.scaleMarginFactor))
end

function Graph:getMaxVal()
    local maxVal = nil

    for _, currItem in ipairs(self.dataSources) do
        maxVal = math.max(maxVal or currItem:getMaxVal(), currItem:getMaxVal())
    end
    return maxVal
end

--------------------------------------------------------------------------------
-- Progressbar
--------------------------------------------------------------------------------
Progressbar = ScreenElement:new()

Progressbar.__index = Progressbar
Progressbar.value = nil
Progressbar.bg = Color.WHITE
Progressbar.fg = nil



function Progressbar.new()
    --self.dimensions = Vector2d.new(300,50)
    return setmetatable({}, Progressbar)
end

function Progressbar:setValue(value)
    self.value = value
end

function Progressbar:setBackground(bg)
    self.bg = bg
end

function Progressbar:setForeground(fg)
    self.fg = fg
end

function Progressbar:draw()
    assert((self.value < 0) == (self.value > 1), "Value must be between 0 and 1")

    if not self.dimensions then
        self.dimensions = Vector2d.new(300, 50)
    end
    self:drawRect(self.position, self.dimensions, self.bg, nil, nil)

    local f = self.fg
    if not f then
        local r = 1 - self.value
        f = Color.new(r, self.value, 0, 1)
    end

    local d = self.dimensions.x * self.value;
    --log(0, "Color: r:" .. f.r .. " g:" .. self.value .. " b:0")
    --log(0, "Dimension: x:" .. d .. " y:" .. self.dimensions.y)
    self:drawRect(self.position, Vector2d.new(d, self.dimensions.y), f, nil, nil)
end
