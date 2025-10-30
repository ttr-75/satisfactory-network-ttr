local NetworkAdapter = require("net.NetworkAdapter")

---@diagnostic disable: lowercase-global

-------------------------------------------------------------------------------
--- CodeDispatchClient – mit in-Memory `require`,
-------------------------------------------------------------------------------

---@class CodeDispatchClient : NetworkAdapter
---@field requestCompleted table<string, boolean>   -- Name -> ob Code empfangen/geparsed
---@field loadingRegistry  string[]                 -- Warteschlange der anzufordernden Dateien
---@field codes            table<string, string>    -- Name -> (Rest-)Code als String
---@field codeOrder        string[]                 -- Ausführungsreihenfolge (wie gehabt)
---@field modules          table<string, any>       -- Name -> ausgewertetes Modul (Cache)
---@field loading          table<string, boolean>   -- Name -> "wird gerade geladen" (Zyklus-Schutz)
---@field _onReset         (fun()|nil)              -- optionaler Reset-Callback
CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

-- ========= Konstruktor =======================================================

---@param opts table|nil
---@return CodeDispatchClient
function CodeDispatchClient.new(opts)
    local self            = NetworkAdapter.new(CodeDispatchClient, opts)
    self.name             = NET_NAME_CODE_DISPATCH_CLIENT
    self.port             = NET_PORT_CODE_DISPATCH
    self.ver              = 1

    self.requestCompleted = {}
    self.loadingRegistry  = {}
    self.codes            = {}
    self.codeOrder        = {}

    -- Neu für require:
    self.modules          = {}
    self.loading          = {}

    self._onReset         = nil

    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end

        if cmd == NET_CMD_CODE_DISPATCH_SET_EEPROM then
            log(0, ('CDC: got code for "%s" from "%s"'):format(tostring(programName), tostring(from)))
            self:onSetEEPROM(tostring(programName or ""), tostring(code or ""))
        elseif cmd == NET_CMD_CODE_DISPATCH_RESET_ALL then
            log(2, ('CDC: received resetAll from "%s"'):format(tostring(from)))
            if self._onReset then
                local ok, err = pcall(self._onReset)
                if not ok then log(3, "CDC: reset handler error: " .. tostring(err)) end
            end
            computer.reset()
        end
    end)

    return self
end

-- ========= Utilities =========================================================

---@param name string
---@return boolean
function CodeDispatchClient:existsInRegistry(name)
    for _, n in pairs(self.loadingRegistry) do
        if n == name then return true end
    end
    return false
end

---@param a string[]
---@param value string
---@return integer|nil
function CodeDispatchClient:indexOfIn(a, value)
    for i = 1, #a do if a[i] == value then return i end end
    return nil
end

---@param a string[]
---@param value string
---@return boolean
function CodeDispatchClient:removeFrom(a, value)
    local i = self:indexOfIn(a, value)
    if i then
        table.remove(a, i); return true
    end
    return false
end

---@param a string[]
---@param i integer|nil
---@param v string
---@return integer
function CodeDispatchClient:insertAt(a, i, v)
    local n = #a
    if i == nil then i = n + 1 end
    if i < 1 then i = 1 end
    if i > n + 1 then i = n + 1 end
    table.insert(a, i, v)
    return i
end

--- Wandelt beliebige require-Schreibweise in eine kanonische Form um:
---  "shared.helper"        -> "shared/helper.lua"
---  "shared/helper"        -> "shared/helper.lua"
---  "shared/helper.lua"    -> "shared/helper.lua"
---@param name string
---@return string
local function _canon(name)
    local s = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return s end

    -- Windows-Backslashes tolerieren
    s = s:gsub("\\", "/")

    -- Falls bereits Slash-Pfade genutzt werden:
    if s:find("/", 1, true) then
        if not s:match("%.lua$") then
            s = s .. ".lua"
        end
        return s
    end

    -- Dot-Notation ohne Slash
    if s:match("%.lua$") then
        -- ".lua" wegschneiden, NUR davor Punkte -> Slashes
        local base = s:sub(1, #s - 4) -- alles vor ".lua"
        base = base:gsub("%.", "/")   -- Punkte zu Slashes
        return base .. ".lua"
    else
        -- Keine Endung -> Punkte zu Slashes, dann ".lua" anhängen
        return (s:gsub("%.", "/")) .. ".lua"
    end
end

-- Maskiert alle Lua-Pattern-Sonderzeichen in einem Literal
local function escape_lua_pattern(s)
    return (s:gsub("(%W)", "%%%1")) -- alles, was nicht %w ist, mit % escapen
end

local function replace_language_chunk(content, language)
    local literal = "[-LANGUAGE-]"
    language = "_" .. language .. ""
    local pattern = escape_lua_pattern(literal)

    -- Falls language '%' enthalten könnte, für gsub-Replacement escapen:
    language = language:gsub("%%", "%%%%")
    return (content:gsub(pattern, language))
end

-- ========= Öffentliche API ===================================================

---@param fn fun()|nil
function CodeDispatchClient:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

---@param programName string
---@param content string
function CodeDispatchClient:onSetEEPROM(programName, content)
    self:parseModule(programName, content)
end

--- Parst Register-Teil (optional) und speichert den ausführbaren Rest **als String**.
---@param name string
---@param content string|nil
function CodeDispatchClient:parseModule(name, content)
    local key = _canon(name)
    if not content then
        log(3, "CodeDispatchClient:Could not load " .. tostring(key) .. ": Not found.")
        return
    end

    -- WICHTIG: String speichern, nicht (nur) Funktion – wir brauchen eine eigene Env für require.
    self.codes[key]            = tostring(content or "")
    self.requestCompleted[key] = true
    log(1, "CDC: stored chunk for " .. tostring(key))
end

--- Fordert ein einzelnes Modul an (wenn noch nicht empfangen).
---@param name string
function CodeDispatchClient:loadModule(name)
    local key = _canon(name)
    if self.requestCompleted[key] then
        log(2, ('CDC: already loaded "%s"'):format(key))
        return
    end
    self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, key)
    log(0, ('CDC: broadcast GET_EEPROM "%s" on port %s'):format(key, self.port))
    self.requestCompleted[key] = false
end

--- Lädt registrierte Module nacheinander und wartet auf deren Empfang (wie gehabt).
---@return boolean|nil false wenn sofort alles ausgeführt wurde
function CodeDispatchClient:loadAndWait()
    if #self.loadingRegistry == 0 then
        self:callAllLoadedFiles()
        return false
    end

    local nextName = self.loadingRegistry[1]
    while self:removeFrom(self.loadingRegistry, nextName) do end

    self:loadModule(nextName)
    while self.requestCompleted[nextName] == false do
        future.run()
    end

    self:loadAndWait()
end

--- Führt alle gespeicherten Module in definierter Reihenfolge aus
--- (jetzt via _require, damit Rückgabewerte/Namespaces landen).
function CodeDispatchClient:callAllLoadedFiles()
    for i = 1, #self.codeOrder do
        local name = self.codeOrder[i]
        log(1, "CDC: run " .. tostring(name))
        local ok, err = pcall(function() self:_require(name) end)
        if not ok then log(4, err) end
    end
    self.codeOrder = {}
    self.codes     = {}
end

--- Interner Registrierer (wie zuvor).
---@param name string
function CodeDispatchClient:_register(name)
    local key = _canon(name)
    if self.requestCompleted[key] == nil then
        if not self:existsInRegistry(key) then
            log(0, "CDC: register " .. tostring(key))
            self:insertAt(self.loadingRegistry, 1, key)
            self:insertAt(self.codeOrder, 1, key)
        else
            log(0, "CDC: re-register " .. tostring(key))
            while self:removeFrom(self.loadingRegistry, key) do end
            self:insertAt(self.loadingRegistry, 1, key)
        end
        while self:removeFrom(self.codeOrder, key) do end
        self:insertAt(self.codeOrder, 1, key)
    end
end

---@param names string[]
function CodeDispatchClient:registerForLoading(names)
    local n, out = #names, {}
    for i = 1, n do out[i] = names[n - i + 1] end -- reverse
    for i = 1, #out do self:_register(out[i]) end
end

--- Komfort: ein Modul registrieren und direkt laden
---@param name string
function CodeDispatchClient:startClient(name)
    assert(name, "CodeDispatchClient:startClient(name): name can not be nil")
    self:registerForLoading({ name })
    self:loadAndWait()
end

-- ========= In-Memory `require` ==============================================

--- Führt ein Modul (String) in eigener Env mit lokalem `require` aus und cached das Ergebnis.
---@param name string
---@return any module
function CodeDispatchClient:_executeModule(name)
    local key = _canon(name)
    local chunk = self.codes[key]
    if not chunk then
        error("CDC: no code for module " .. tostring(key))
    end

    if self.loading[key] then
        error("CDC: cyclic require: " .. tostring(key))
    end
    self.loading[key] = true

    local env = setmetatable({
        require = function(dep) return self:_require(dep) end,
        exports = {}, -- Fallback, falls Modul nichts returned
    }, { __index = _G, __newindex = _G })

    -- TODO Staabiler machen: Language-Chunks ersetzen
    if TTR_FIN_Config and TTR_FIN_Config.language then
        chunk = replace_language_chunk(chunk, TTR_FIN_Config.language)
    end

    local fn, perr = load(chunk, key, "t", env)
    if not fn then
        self.loading[key] = nil
        error("CDC: load env error for " .. tostring(key) .. ": " .. tostring(perr))
    end

    local ok, ret = pcall(fn)
    self.loading[key] = nil
    if not ok then error("CDC: runtime error in " .. tostring(key) .. ": " .. tostring(ret)) end

    local mod = (ret ~= nil) and ret or (next(env.exports) and env.exports) or true
    self.modules[key] = mod
    return mod
end

--- In-Memory-Require mit Nachladen/Warten/Cache
---@param name string
---@return any module
function CodeDispatchClient:_require(name)
    local key = _canon(name)
    if self.modules[key] ~= nil then
        return self.modules[key]
    end

    -- Code bereits vorhanden?
    if not self.codes[key] then
        -- Nachfordern & warten – das erlaubt require() *innerhalb* von Modulen
        self:loadModule(key)
        while self.requestCompleted[key] == false do
            future.run()
        end
        if not self.codes[key] then
            error("require('" .. tostring(key) .. "'): no code after fetch")
        end
    end

    return self:_executeModule(key)
end
