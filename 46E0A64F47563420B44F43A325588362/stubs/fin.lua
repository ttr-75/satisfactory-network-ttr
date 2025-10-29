---@meta
-- IntelliSense-Stubs für Graphics/GUI – keine Runtime-Wirkung.

-- === Aliases ===
---@alias Vector2d { x: integer, y: integer }
---@alias Color    { r: number, g: number, b: number, a: number, pattern?: string }

-- === GPUProxy (aus deinem Stub-Kopf) ===
---@class GPUProxy
local GPUProxy = {}

---@param pos Vector2d
---@param text string
---@param size number
---@param color Color|nil
---@param monospace boolean|nil
function GPUProxy:drawText(pos, text, size, color, monospace) end

---@param pos Vector2d
---@param size Vector2d
---@param color Color|nil
---@param image any|nil
---@param rotation number|nil
function GPUProxy:drawRect(pos, size, color, image, rotation) end

---@param boxSettings table
function GPUProxy:drawBox(boxSettings) end

---@param points Vector2d[]
---@param thickness number
---@param color Color|nil
function GPUProxy:drawLines(points, thickness, color) end

---@param text string
---@param size number
---@param monospace boolean|nil
---@return Vector2d
function GPUProxy:measureText(text, size, monospace) return { x = 0, y = 0 } end

function GPUProxy:flush() end

-- === Color ===
---@class Color
---@field r number
---@field g number
---@field b number
---@field a number
---@field pattern string|nil
local Color = {}

---@param r number @0..1
---@param g number @0..1
---@param b number @0..1
---@param a number @0..1
---@return Color|nil
function Color.new(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Konstanten (nur für Typzwecke)
Color.BLACK = Color.new(0, 0, 0, 1)
Color.WHITE = Color.new(1, 1, 1, 1)

-- === Vector2d ===
---@class Vector2d
---@field x integer
---@field y integer
local Vector2d = {}

---@param x any
---@param y any
---@return Vector2d
function Vector2d.new(x, y) return { x = 0, y = 0 } end

-- === ScreenElement (Basisklasse) ===
---@class ScreenElement
---@field gpu GPUProxy|nil
---@field position Vector2d
---@field dimensions Vector2d|nil
---@field subElements ScreenElement[]
local ScreenElement = {}

---@generic T: ScreenElement
---@param cls T
---@param o table|nil
---@return T
function ScreenElement.new(cls, o) return o end

---@param gpu GPUProxy
---@param position Vector2d
---@param dimensions Vector2d|nil
function ScreenElement:init(gpu, position, dimensions) end

---@param e ScreenElement|nil
function ScreenElement:addElement(e) end

function ScreenElement:draw() end

function ScreenElement:flush() end

---@param Text string
---@param Size number
---@param bMonospace boolean|nil
---@return Vector2d
function ScreenElement:measureText(Text, Size, bMonospace) return { x = 0, y = 0 } end

---@param position Vector2d
---@param text string
---@param size number
---@param color Color|nil
---@param monospace boolean|nil
function ScreenElement:drawText(position, text, size, color, monospace) end

---@param position Vector2d
---@param size Vector2d
---@param color Color|nil
---@param image any|nil
---@param rotation number|nil
function ScreenElement:drawRect(position, size, color, image, rotation) end

---@param boxSettings table
function ScreenElement:drawBox(boxSettings) end

---@param points Vector2d[]
---@param thickness number
---@param color Color|nil
function ScreenElement:drawLines(points, thickness, color) end

---@param vector Vector2d
---@return Vector2d
function ScreenElement:reposition(vector) return { x = 0, y = 0 } end

---@param position Vector2d
---@param size Vector2d
---@param color Color|nil
---@param image any|nil
---@param rotation number|nil
function ScreenElement:drawLocalRect(position, size, color, image, rotation) end

---@param position Vector2d
---@param text string
---@param size number
---@param color Color|nil
---@param monospace boolean|nil
function ScreenElement:drawLocalText(position, text, size, color, monospace) end

---@param points Vector2d[]
---@param thickness number
---@param color Color|nil
function ScreenElement:drawLocalLines(points, thickness, color) end

---@param boxSettings table
function ScreenElement:drawLocalBox(boxSettings) end

-- === ItemImage ===
---@class ItemImage: ScreenElement
---@field box table
---@field bg Color
---@field fg Color|nil
local ItemImage = {}

---@param o table|nil
---@return ItemImage
function ItemImage.new(o) return o end

function ItemImage:setBox(box) end

function ItemImage:draw() end

-- === Plotter ===
---@class Graph
local Graph = {}

---@class Plotter: ScreenElement
---@field color Color
---@field lineThickness number
---@field dataSource table|nil
---@field graph Graph|nil
---@field scaleFactorX number|nil
local Plotter = {}

---@param o table|nil
---@return Plotter
function Plotter.new(o) return o end

function Plotter:setDataSource(dataSource) end

function Plotter:setColor(color) end

function Plotter:setLineThickness(lineThickness) end

function Plotter:draw() end

-- === Graph ===
---@class Graph: ScreenElement
---@field scaleFactorY number|nil
---@field maxVal number|nil
---@field scaleMarginFactor number
---@field dataSources table[]
---@field plotters table<string, Plotter>
local Graph = {}

---@param o table|nil
---@return Graph
function Graph.new(o) return o end

function Graph:addPlotter(name, config) end

function Graph:configurePlotter(name, config) end

function Graph:setMaxVal(maxVal) end

function Graph:setDimensions(dimensions) end

function Graph:draw() end

function Graph:autoResize() end

function Graph:initScaleFactors(maxVal) end

---@return number
function Graph:getMaxVal() return 0 end

-- === Progressbar ===
---@class Progressbar: ScreenElement
---@field value number
---@field bg Color
---@field fg Color|nil
local Progressbar = {}

---@param o table|nil
---@return Progressbar
function Progressbar.new(o) return o end

function Progressbar:setValue(value) end

function Progressbar:setBackground(bg) end

function Progressbar:setForeground(fg) end

function Progressbar:draw() end

-- (Optional) Export-Typen, falls du global arbeitest:
---@type GPUProxy
gpu = gpu or {} ---@diagnostic disable-line: lowercase-global, missing-fields
