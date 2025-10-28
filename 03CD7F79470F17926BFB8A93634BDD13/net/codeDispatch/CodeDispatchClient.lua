---@diagnostic disable: lowercase-global




-------------------------------------------------------------------------------
--- CodeDispatchClient
-------------------------------------------------------------------------------

---@class CodeDispatchClient : NetworkAdapter
---@field requestCompleted table<string, boolean>
---@field loadingRegistry  string[]
---@field codes            table<string, function>
---@field codeOrder        string[]
---@field _onReset         fun()|nil
local CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

-- ===== Lokale Utilities (nur Datei-intern) ===================================

local function split_on_finished(content)
    assert(type(content) == "string", "content must be string")
    local marker = "CodeDispatchClient:finished()"
    local s, e = string.find(content, marker, 1, true)
    if not s then return nil, content end
    return string.sub(content, 1, s - 1), string.sub(content, e + 1)
end

local function indexOfIn(a, value)
    for i = 1, #a do if a[i] == value then return i end end
    return nil
end

local function removeFrom(a, value)
    local i = indexOfIn(a, value)
    if i then
        table.remove(a, i); return true
    end
    return false
end

local function insertAt(a, i, v)
    local n = #a
    if i == nil then i = n + 1 end
    if i < 1 then i = 1 end
    if i > n + 1 then i = n + 1 end
    table.insert(a, i, v)
    return i
end

-- ===== Konstruktor ===========================================================

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
    self._onReset         = nil

    -- Listener registrieren (reiner Dispatch)
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

-- ===== Prototyp-Methoden =====================================================

--- Optionaler Reset-Callback.
---@param fn fun()|nil
function CodeDispatchClient:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

--- Verarbeitet eingehenden Code, splittet ggf. Registrierung/Rest, speichert „Rest“.
---@param programName string
---@param content string
function CodeDispatchClient:onSetEEPROM(programName, content)
    if content == "" then
        log(3, "CDC:onSetEEPROM: empty content for " .. programName)
        self.requestCompleted[programName] = true
        return
    end

    local register, rest = split_on_finished(content)
    if register ~= nil then
        log(1, "CDC: parse register " .. programName)
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

    log(1, "CDC: parse content " .. programName)
    local codeFn, err2 = load(rest)
    if not codeFn then
        log(4, "CDC: content parse error " .. tostring(err2))
        self.requestCompleted[programName] = true
        return
    end

    self.codes[programName]            = codeFn
    self.requestCompleted[programName] = true
end

--- Interner Lader (einzelnes Modul anfordern).
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

--- Marker-Funktion (wird serverseitig erkannt).
function CodeDispatchClient:finished() end

--- Lädt registrierte Module nacheinander und wartet auf deren Empfang.
function CodeDispatchClient:loadAndWait()
    if #self.loadingRegistry == 0 then
        self:callAllLoadedFiles()
        return false
    end

    local nextName = self.loadingRegistry[1]
    while removeFrom(self.loadingRegistry, nextName) do end

    self:loadModule(nextName)
    while self.requestCompleted[nextName] == false do
        future.run()
    end

    self:loadAndWait()
end

--- Führt alle empfangenen Module in definierter Reihenfolge aus.
function CodeDispatchClient:callAllLoadedFiles()
    for i = 1, #self.codeOrder do
        local name = self.codeOrder[i]
        log(1, "CDC: run " .. name)
        local ok, err = pcall(self.codes[name])
        if not ok then log(4, err) end
    end
    self.codeOrder = {}
    self.codes     = {}
end

--- Fügt Namen in die Lade-Registrierung ein (dedupliziert, stabilisiert Reihenfolge).
---@param names string[]
function CodeDispatchClient:registerForLoading(names)
    -- invertierte Reihenfolge beibehalten (wie bei dir)
    local n = #names
    local out = {}
    for i = 1, n do out[i] = names[n - i + 1] end

    for i = 1, #out do
        local name = out[i]
        if self.requestCompleted[name] == nil then
            if indexOfIn(self.loadingRegistry, name) == nil then
                insertAt(self.loadingRegistry, 1, name)
                insertAt(self.codeOrder, 1, name)
                log(0, "CDC: registered " .. name)
            else
                while removeFrom(self.loadingRegistry, name) do end
                insertAt(self.loadingRegistry, 1, name)
                while removeFrom(self.codeOrder, name) do end
                insertAt(self.codeOrder, 1, name)
                log(0, "CDC: re-ordered " .. name)
            end
        end
    end
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchClient = CodeDispatchClient.new()


--[[



names = {"helper.lua","serializer.lua","testFolder/testFile.lua","fabricRegistry/basics.lua"}
CodeDispatchClient:loadAndWait(names)
]]


names = {}
CodeDispatchClient:registerForLoading(names)

CodeDispatchClient:loadAndWait()
