---@meta
-- IntelliSense-Stubs für Graphics/GUI – keine Runtime-Wirkung.

---@class ScreenProxy
---@---@field getSize fun(self:ScreenProxy):integer, integer
local ScreenProxy = {}

function ScreenProxy:getSize() return 100, 50 end -- optionaler Hint

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

--- Bindet diese GPU an einen Screen.
---@param screen ScreenProxy|any
---@return boolean ok, string? err   -- falls deine Runtime so etwas zurückgibt
function GPUProxy:bindScreen(screen) return true end

-- (Optional) Export-Typen, falls du global arbeitest:
---@type GPUProxy
gpu = gpu or {} ---@diagnostic disable-line: lowercase-global, missing-fields
