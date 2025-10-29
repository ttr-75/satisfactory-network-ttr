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
    if not content then
        log(3, "CodeDispatchClient:Could not load " .. tostring(name) .. ": Not found.")
        return
    end

    -- WICHTIG: String speichern, nicht (nur) Funktion – wir brauchen eine eigene Env für require.
    self.codes[name]            = tostring(content or "")
    self.requestCompleted[name] = true
    log(1, "CDC: stored chunk for " .. tostring(name))
end

--- Fordert ein einzelnes Modul an (wenn noch nicht empfangen).
---@param name string
function CodeDispatchClient:loadModule(name)
    if self.requestCompleted[name] then
        log(2, ('CDC: already loaded "%s"'):format(name))
        return
    end
    self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, name)
    log(0, ('CDC: broadcast GET_EEPROM "%s" on port %s'):format(name, self.port))
    self.requestCompleted[name] = false
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
    if self.requestCompleted[name] == nil then
        if not self:existsInRegistry(name) then
            log(0, "CDC: register " .. tostring(name))
            self:insertAt(self.loadingRegistry, 1, name)
            self:insertAt(self.codeOrder, 1, name)
        else
            log(0, "CDC: re-register " .. tostring(name))
            while self:removeFrom(self.loadingRegistry, name) do end
            self:insertAt(self.loadingRegistry, 1, name)
        end
        while self:removeFrom(self.codeOrder, name) do end
        self:insertAt(self.codeOrder, 1, name)
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
    local chunk = self.codes[name]
    if not chunk then
        error("CDC: no code for module " .. tostring(name))
    end

    if self.loading[name] then
        error("CDC: cyclic require: " .. tostring(name))
    end
    self.loading[name] = true

    local env = setmetatable({
        require = function(dep) return self:_require(dep) end,
        exports = {}, -- Fallback, falls Modul nichts returned
    }, { __index = _G, __newindex = _G })

    local fn, perr = load(chunk, name, "t", env)
    if not fn then
        self.loading[name] = nil
        error("CDC: load env error for " .. tostring(name) .. ": " .. tostring(perr))
    end

    local ok, ret = pcall(fn)
    self.loading[name] = nil
    if not ok then error("CDC: runtime error in " .. tostring(name) .. ": " .. tostring(ret)) end

    local mod = (ret ~= nil) and ret or (next(env.exports) and env.exports) or true
    self.modules[name] = mod
    return mod
end

--- In-Memory-Require mit Nachladen/Warten/Cache
---@param name string
---@return any module
function CodeDispatchClient:_require(name)
    if self.modules[name] ~= nil then
        return self.modules[name]
    end

    -- Code bereits vorhanden?
    if not self.codes[name] then
        -- Nachfordern & warten – das erlaubt require() *innerhalb* von Modulen
        self:loadModule(name)
        while self.requestCompleted[name] == false do
            future.run()
        end
        if not self.codes[name] then
            error("require('" .. tostring(name) .. "'): no code after fetch")
        end
    end

    return self:_executeModule(name)
end
