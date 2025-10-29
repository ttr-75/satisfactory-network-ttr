---@diagnostic disable: lowercase-global

-------------------------------------------------------------------------------
--- CodeDispatchClient (Prototyp-Methoden, gleiche Logik)
-------------------------------------------------------------------------------

---@class CodeDispatchClient : NetworkAdapter
---@field requestCompleted table<string, boolean>   -- Name -> ob Code empfangen/geparsed
---@field loadingRegistry  string[]                 -- Warteschlange der anzufordernden Dateien
---@field codes            table<string, function>  -- Name -> geladene Chunk-Funktion
---@field codeOrder        string[]                 -- Ausführungsreihenfolge
---@field _onReset         (fun()|nil)              -- optionaler Reset-Callback
CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

-- ========= Konstruktor =======================================================

---@param opts table|nil
---@return CodeDispatchClient
function CodeDispatchClient.new(opts)
    -- Generischer Basiskonstruktor: gibt bereits CodeDispatchClient zurück
    local self            = NetworkAdapter.new(CodeDispatchClient, opts)
    self.name             = NET_NAME_CODE_DISPATCH_CLIENT
    self.port             = NET_PORT_CODE_DISPATCH
    self.ver              = 1

    self.requestCompleted = {}
    self.loadingRegistry  = {}
    self.codes            = {}
    self.codeOrder        = {}
    self._onReset         = nil

    -- Listener registrieren (reiner Dispatch → ruft Prototyp-Methoden)
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

-- ========= Hilfs-Methoden (aus lokalen Funktionen gemacht) ===================

--- Prüft, ob ein Name in der Registry steht.
---@param name string
---@return boolean
function CodeDispatchClient:existsInRegistry(name)
    for _, n in pairs(self.loadingRegistry) do
        if n == name then return true end
    end
    return false
end

--- Sucht den Index eines Werts in einem Array.
---@param a string[]
---@param value string
---@return integer|nil
function CodeDispatchClient:indexOfIn(a, value)
    for i = 1, #a do
        if a[i] == value then return i end
    end
    return nil
end

--- Entfernt das erste Vorkommen eines Werts aus einem Array.
---@param a string[]
---@param value string
---@return boolean removed
function CodeDispatchClient:removeFrom(a, value)
    local i = self:indexOfIn(a, value)
    if i then
        table.remove(a, i); return true
    end
    return false
end

--- Fügt an Position i ein (mit Bounds-Clamp).
---@param a string[]
---@param i integer|nil
---@param v string
---@return integer pos
function CodeDispatchClient:insertAt(a, i, v)
    local n = #a
    if i == nil then i = n + 1 end
    if i < 1 then i = 1 end
    if i > n + 1 then i = n + 1 end
    table.insert(a, i, v)
    return i
end

--- Splittet Content an Marker "CodeDispatchClient:finished()".
---@param content string
---@return string|nil before
---@return string after
function CodeDispatchClient:split_on_finished(content)
    assert(type(content) == "string", "content muss String sein")
    local marker = "CodeDispatchClient:finished()"
    local s, e = string.find(content, marker, 1, true)
    if not s then
        return nil, content
    end
    return string.sub(content, 1, s - 1), string.sub(content, e + 1)
end

-- ========= Öffentliche Methoden (Logik beibehalten) ==========================

--- Optionaler Reset-Callback setzen.
---@param fn fun()|nil
function CodeDispatchClient:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

--- Handler: eingehenden Code verarbeiten.
---@param programName string
---@param content string
function CodeDispatchClient:onSetEEPROM(programName, content)
    self:parseModule(programName, content)
end

--- Parst „Register“-Teil (optional) und speichert den ausführbaren Rest.
---@param name string
---@param content string|nil
function CodeDispatchClient:parseModule(name, content)
    if not content then
        log(3, "CodeDispatchClient:Could not load " .. tostring(name) .. ": Not found.")
        return
    end

    local register, rest = self:split_on_finished(content)

    if register ~= nil then
        log(1, "CDC: parse register " .. tostring(name))
        local regFn, err = load(register)
        if not regFn then
            log(4, "CDC: register parse error " .. tostring(err))
        else
            local ok, perr = pcall(regFn)
            if not ok then log(4, perr) end
        end
    else
        rest = content
    end

    log(1, "CDC: parse content " .. tostring(name))
    local codeFn, err2 = load(rest)
    if not codeFn then
        log(4, "CDC: content parse error " .. tostring(err2))
        return
    end

    self.codes[name]            = codeFn
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

--- Marker-Funktion (wird serverseitig am Code erkannt).
function CodeDispatchClient:finished() end

--- Lädt registrierte Module nacheinander und wartet auf deren Empfang.
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

--- Führt alle gespeicherten Module in definierter Reihenfolge aus.
function CodeDispatchClient:callAllLoadedFiles()
    for i = 1, #self.codeOrder do
        local name = self.codeOrder[i]
        log(1, "CDC: run " .. tostring(name))
        local ok, err = pcall(self.codes[name])
        if not ok then log(4, err) end
    end
    self.codeOrder = {}
    self.codes     = {}
end

--- Interner Registrierer (wie dein ursprüngliches `register`).
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

--- Fügt mehrere Namen zur Ladeliste hinzu (reihenfolgebehaftet wie zuvor).
---@param names string[]
function CodeDispatchClient:registerForLoading(names)
    local n = #names
    local out = {}
    for i = 1, n do out[i] = names[n - i + 1] end
    for i = 1, #out do
        self:_register(out[i])
    end
end

--- Fügt name zur Ladeliste hinzu und startet den CLient.
---@param name string | nil
function CodeDispatchClient:startClient(name)
    assert(name, "CodeDispatchClient:startClient(name): name can not be nil")
    self:registerForLoading({ name })
    self:loadAndWait()
end
