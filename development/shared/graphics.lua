---@diagnostic disable: lowercase-global

--------------------------------------------------------------------------------
-- Typ-Stubs für bessere IntelliSense (keine Runtime-Wirkung)
--------------------------------------------------------------------------------

---@class GPUProxy
---@field drawText fun(self:GPUProxy, pos:Vector2d, text:string, size:number, color:Color|nil, monospace:boolean|nil)
---@field drawRect fun(self:GPUProxy, pos:Vector2d, size:Vector2d, color:Color|nil, image:any|nil, rotation:number|nil)
---@field drawBox  fun(self:GPUProxy, boxSettings:table)
---@field drawLines fun(self:GPUProxy, points:Vector2d[], thickness:number, color:Color|nil)
---@field measureText fun(self:GPUProxy, text:string, size:number, monospace:boolean|nil):Vector2d
---@field flush fun(self:GPUProxy)

--------------------------------------------------------------------------------
-- Color
--------------------------------------------------------------------------------

---@class Color
---@diagnostic disable-next-line: duplicate-doc-field
---@field r number
---@diagnostic disable-next-line: duplicate-doc-field
---@field g number
---@diagnostic disable-next-line: duplicate-doc-field
---@field b number
---@diagnostic disable-next-line: duplicate-doc-field
---@field a number
---@field pattern string
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
---@return Color|nil
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

Color.RED_DARK      = Color.new(0.300, 0.000, 0.000, 1.0)
Color.RED           = Color.new(1.000, 0.000, 0.000, 1.0)
Color.GREEN         = Color.new(0.000, 1.000, 0.000, 1.0)
Color.GREEN_0750    = Color.new(0.000, 0.750, 0.000, 1.0)
Color.GREEN_0500    = Color.new(0.000, 0.500, 0.000, 1.0)
Color.BLUE          = Color.new(0.000, 0.000, 1.000, 1.0)

Color.FICSIT_ORANGE = Color.new(1.000, 0.550, 0.200, 1.0)
Color.YELLOW        = Color.new(1.000, 1.000, 0.000, 1.0)
Color.YELLOW_DARK   = Color.new(0.300, 0.300, 0.000, 1.0)

--------------------------------------------------------------------------------
-- Vector 2d
--------------------------------------------------------------------------------



---@class Vector2d
---@field x integer
---@field y integer
Vector2d         = {}
Vector2d.__index = Vector2d

---@param x any
---@param y any
---@return Vector2d
function Vector2d.new(x, y)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    local o = { x = math.floor(x), y = math.floor(y) }
    return setmetatable(o, Vector2d)
end

--------------------------------------------------------------------------------
-- ScreenElement (Base)
--------------------------------------------------------------------------------

---@class ScreenElement
---@field gpu GPUProxy|nil
---@field position Vector2d           -- immer gesetzt (0,0 default)
---@field dimensions Vector2d|nil     -- optional; Subklassen können Default setzen
---@field subElements ScreenElement[] -- Kinder
ScreenElement = {}
ScreenElement.__index = ScreenElement

---Generischer Konstruktor: sorgt für Defaults & richtigen Metatable-Bind
---@generic T: ScreenElement
---@param cls T                      -- Klassen-Table (z. B. Progressbar)
---@param o table|nil
---@return T
function ScreenElement.new(cls, o)
    o             = o or {}
    o.position    = o.position or Vector2d.new(0, 0)
    o.dimensions  = o.dimensions or o.dimensions -- bleibt ggf. nil
    o.subElements = o.subElements or {}
    return setmetatable(o, cls)
end

---Initialize element with gpu, position and dimensions
---@param gpu GPUProxy
---@param position Vector2d
---@param dimensions Vector2d|nil
function ScreenElement:init(gpu, position, dimensions)
    self.gpu        = gpu
    self.position   = position or Vector2d.new(0, 0)
    self.dimensions = dimensions
end

---Append a child element
---@param e ScreenElement|nil
function ScreenElement:addElement(e)
    if e then table.insert(self.subElements, e) end
end

---Draw children (override in subclasses to render self first)
function ScreenElement:draw()
    for _, element in ipairs(self.subElements) do
        if element.draw then element:draw() end
    end
end

function ScreenElement:flush()
    error('ScreenElement:flush() should not be called; call draw(), then gpu:flush()')
end

---Measure a text string
---@param Text string
---@param Size number
---@param bMonospace boolean|nil
---@return Vector2d
function ScreenElement:measureText(Text, Size, bMonospace)
    return self.gpu:measureText(Text, Size, bMonospace)
end

---Draw text at local position
---@param position Vector2d
---@param text string
---@param size number
---@param color Color|nil
---@param monospace boolean|nil
function ScreenElement:drawText(position, text, size, color, monospace)
    self.gpu:drawText(self:reposition(position), text, size, color, monospace)
end

---Draw rectangle at local position
---@param position Vector2d
---@param size Vector2d
---@param color Color|nil
---@param image any|nil
---@param rotation number|nil
function ScreenElement:drawRect(position, size, color, image, rotation)
    self.gpu:drawRect(self:reposition(position), size, color, image, rotation)
end

---Draws a prebuilt box (already in gpu-space)
---@param boxSettings table
function ScreenElement:drawBox(boxSettings)
    self.gpu:drawBox(boxSettings)
end

---Draw a polyline (local points)
---@param points Vector2d[]
---@param thickness number
---@param color Color|nil
function ScreenElement:drawLines(points, thickness, color)
    if not points or #points < 2 then return end
    local newPoints = {}
    for _, p in ipairs(points) do
        newPoints[#newPoints + 1] = self:reposition(p)
    end
    self.gpu:drawLines(newPoints, thickness, color)
end

---Translate local coords to absolute gpu coords
---@param vector Vector2d
---@return Vector2d
function ScreenElement:reposition(vector)
    local px = (self.position and self.position.x or 0) + vector.x
    local py = (self.position and self.position.y or 0) + vector.y
    return Vector2d.new(px, py)
end

-- ===== Local drawing helpers (NO reposition) =====

---Draw local rect (already relative to self.position)
---@param position Vector2d
---@param size Vector2d
---@param color Color|nil
---@param image any|nil
---@param rotation number|nil
function ScreenElement:drawLocalRect(position, size, color, image, rotation)
    -- position ist bereits lokal relativ zu self.position
    self.gpu:drawRect(position, size, color, image, rotation)
end

---Draw local text
---@param position Vector2d
---@param text string
---@param size number
---@param color Color|nil
---@param monospace boolean|nil
function ScreenElement:drawLocalText(position, text, size, color, monospace)
    self.gpu:drawText(position, text, size, color, monospace)
end

---Draw local polyline
---@param points Vector2d[]
---@param thickness number
---@param color Color|nil
function ScreenElement:drawLocalLines(points, thickness, color)
    -- erwartet lokale Punkte; NICHT verschieben
    self.gpu:drawLines(points, thickness, color)
end

---Draw local box
---@param boxSettings table
function ScreenElement:drawLocalBox(boxSettings)
    self.gpu:drawBox(boxSettings)
end

--------------------------------------------------------------------------------
-- ItemImage
--------------------------------------------------------------------------------

---@class ItemImage : ScreenElement
---@field box table        -- z.B. { position=Vector2d, size=Vector2d, color=Color, image=?, rotation=? }
---@field bg  Color        -- Fallback-Hintergrund (falls box.color fehlt)
---@field fg  Color|nil    -- nicht zwingend genutzt, aber vorhanden für Layout
ItemImage = setmetatable({}, { __index = ScreenElement })
ItemImage.__index = ItemImage

---@param o table|nil
---@return ItemImage
function ItemImage.new(o)
    local self = ScreenElement.new(ItemImage, o or {})
    self.box   = self.box or {}
    self.bg    = self.bg or Color.WHITE
    self.fg    = self.fg or nil
    return self
end

---Set box settings (position/size,..)
---@param box table
function ItemImage:setBox(box) self.box = box or {} end

---Draw item image (box first), then children
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

---@class Plotter : ScreenElement
---@field color         Color
---@field lineThickness number
---@field dataSource    table|nil   -- erwartet: :iterate(cb), :getMaxSize(), currSize
---@field graph         Graph|nil
---@field scaleFactorX  number|nil
Plotter = setmetatable({}, { __index = ScreenElement })
Plotter.__index = Plotter

---@param o table|nil
---@return Plotter
function Plotter.new(o)
    local self         = ScreenElement.new(Plotter, o or {})
    self.color         = self.color or Color.GREY_0500
    self.lineThickness = self.lineThickness or 10
    self.dataSource    = self.dataSource or nil
    self.graph         = self.graph or nil
    self.scaleFactorX  = self.scaleFactorX or nil

    -- Wenn bereits Source & Graph vorhanden → X-Skalierung vorab bestimmen
    if self.dataSource and self.graph then
        self:setDataSource(self.dataSource)
    end
    return self
end

---Bind data source & compute X scaling
---@param dataSource table|nil
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

---@param color Color
function Plotter:setColor(color) self.color = color end

---@param lineThickness number
function Plotter:setLineThickness(lineThickness) self.lineThickness = lineThickness end

---Render polyline from data source
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

---@class Graph : ScreenElement
---@field scaleFactorY      number|nil
---@field maxVal            number|nil
---@field scaleMarginFactor number    -- z.B. 0.2 → 20% Luft über Datenmaximum
---@field dataSources       table[]   -- Quellen, aus denen maxVal berechnet wird
---@field plotters          table<string, Plotter>
Graph = setmetatable({}, { __index = ScreenElement })
Graph.__index = Graph

---@param o table|nil
---@return Graph
function Graph.new(o)
    local self             = ScreenElement.new(Graph, o or {})
    self.scaleFactorY      = self.scaleFactorY or nil
    self.maxVal            = self.maxVal or nil
    self.scaleMarginFactor = self.scaleMarginFactor or 0.2
    self.dataSources       = self.dataSources or {}
    self.plotters          = self.plotters or {}
    return self
end

---Add a named plotter
---@param name string
---@param config table|nil
function Graph:addPlotter(name, config)
    local plotter = Plotter.new()
    self.plotters[name] = plotter
    if config ~= nil then
        self:configurePlotter(name, config)
    end
end

---Configure an existing plotter
---@param name string
---@param config table
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

---Set max Y value (recomputes Y scale)
---@param maxVal number
function Graph:setMaxVal(maxVal)
    if not maxVal or maxVal <= 0 then maxVal = 1 end
    self.maxVal = maxVal
    if self.dimensions then
        self.scaleFactorY = self.dimensions.y / maxVal
    end
end

---Set graph dimensions and propagate to DS/plotters
---@param dimensions Vector2d
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

---Draw all plotters (auto-resize if needed)
function Graph:draw()
    if self.maxVal == nil then self:autoResize() end
    for _, plotter in pairs(self.plotters) do
        plotter:draw()
    end
end

---Auto-adjust Y scale to data (with margin)
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

---(Re)compute Y scale from maxVal and margin
---@param maxVal number
function Graph:initScaleFactors(maxVal)
    maxVal = (maxVal and maxVal > 0) and maxVal or 1e-8
    if self.dimensions then
        self.scaleFactorY = self.dimensions.y / (maxVal * (1 + (self.scaleMarginFactor or 0)))
    end
end

---Compute overall max across data sources
---@return number
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

---@class Progressbar : ScreenElement
---@field value number         -- 0..1
---@field bg    Color          -- Hintergrundfarbe
---@field fg    Color|nil      -- optionale Füllfarbe (sonst grün→rot Verlauf)
Progressbar = setmetatable({}, { __index = ScreenElement })
Progressbar.__index = Progressbar

---@param o table|nil
---@return Progressbar
function Progressbar.new(o)
    -- Basisklasse initialisieren → position = (0,0), subElements = {}
    local self = ScreenElement.new(Progressbar, o or {})
    self.value = self.value or 0
    self.bg    = self.bg or Color.WHITE
    self.fg    = self.fg or nil
    -- dimensions bleiben absichtlich nil; werden beim Zeichnen mit Default belegt
    return self
end

---Set clamped value
---@param value number
function Progressbar:setValue(value)
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    self.value = value
end

---@param bg Color
function Progressbar:setBackground(bg) self.bg = bg end

---@param fg Color|nil
function Progressbar:setForeground(fg) self.fg = fg end

---Render progress bar (background + fill)
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
