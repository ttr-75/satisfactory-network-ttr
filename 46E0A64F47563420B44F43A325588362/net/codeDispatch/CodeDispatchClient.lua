-------------------------------------------------------------------------------
--- CodeDispatchClient
-------------------------------------------------------------------------------

CodeDispatchClient = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchClient.__index = CodeDispatchClient

function CodeDispatchClient.new(opts)
    local self = NetworkAdapter.new(CodeDispatchClient, opts)
    self.name = NET_NAME_CODE_DISPATCH_CLIENT
    self.port = NET_PORT_CODE_DISPATCH
    self.ver = 1
    self.requestCompleted = {}
    self.loadingRegistry = {}
    self.codes = {}
    self.codeOrder = {}



    local function existsInRegistry(name)
        for _, n in pairs(self.loadingRegistry) do
            if n == name then
                return true
            end
        end
        return false
    end

    local function insertAt(a, i, v)
        local n = #a
        if i == nil then i = n + 1 end
        if i < 1 then i = 1 end
        if i > n + 1 then i = n + 1 end
        table.insert(a, i, v) -- nutzt die eingebaute Verschiebung
        return i
    end

    local function indexOfIn(a, value)
        for i = 1, #a do
            if a[i] == value then return i end
        end
        return nil
    end

    local function removeFrom(a, value)
        local i = indexOfIn(a, value)
        if i then
            table.remove(a, i); return true
        end
        return false
    end


    -- Private functions--
    local function split_on_finished(content)
        assert(type(content) == "string", "content muss String sein")
        local marker = "CodeDispatchClient:finished()"
        local s, e = string.find(content, marker, 1, true) -- plain match
        if not s then
            return nil, content
        end
        local before = string.sub(content, 1, s - 1)
        local after  = string.sub(content, e + 1)
        return before, after
    end

    local function parseModule(name, content)
        if not content then
            log(3, "CodeDispatchClient:Could not load " .. name .. ": Not found.")
            return nil
        end


        local register, content = split_on_finished(content)

        if (register ~= nil) then
            log(1, "CodeDispatchClient:Parsing loaded register " .. name)
            local code, err = load(register)
            if not code then
                log(4, "Failed to parse register " .. name .. ": " .. tostring(err))
            end

            if not code then
                computer.log(4, "CodeDispatchClient:Failed to load module register " .. name)
                return
            end
            log(1, "CodeDispatchClient:Starting Registration " .. name)
            local ok, err = pcall(code)
            if not ok then
                log(4, err)
            end
        end


        log(1, "CodeDispatchClient:Parsing loaded content " .. name)
        local code, err = load(content)
        if not code then
            log(4, "Failed to parse " .. name .. ": " .. tostring(err))
        end

        if not code then
            computer.log(4, "CodeDispatchClient:Failed to load module " .. name)
            return
        end
        log(1, "CodeDispatchClient:Save for Procedure " .. name)
        self.codes[name] = code
        self.requestCompleted[name] = true
    end

    function self:onSetEEPROM(programName, code)
        parseModule(programName, code)
    end

    self:registerWith(function(from, port, cmd, programName, code)
        if port == self.port and cmd == NET_CMD_CODE_DISPATCH_SET_EEPROM then
            log(0, ('CodeDispatchClient: Got code for "%s" from "%s"'):format(programName, from))
            self:onSetEEPROM(programName, code)
        elseif port == self.port and cmd == NET_CMD_CODE_DISPATCH_RESET_ALL then
            log(2, ('CodeDispatchClient: Received reset command from "%s"'):format(from))
            if self._onReset ~= nil then
                log(1, "CodeDispatchClient: Call Reset Callback")
                local ok, err = pcall(self._onReset)
                if not ok then log(3, "Reset handler error: " .. tostring(err)) end
            end
            computer.reset()
        end
    end)

    local function loadModule(name)
        if self.requestCompleted[name] then
            log(2, ('CodeDispatchClient: Already loaded "%s"'):format(name))
            return
        end
        self:broadcast(NET_CMD_CODE_DISPATCH_GET_EEPROM, name)
        log(0, ('CodeDispatchClient: Broadcast-Requesting "%s on port %s"'):format(name, self.port))
        self.requestCompleted[name] = false
    end

    -- Dummy Funktion
    function self:finished()

    end

    function self:loadAndWait()
        if #self.loadingRegistry == 0 then
            self:callAllLoadedFiles()
            return false
        end
        local next = self.loadingRegistry[1]

        while removeFrom(self.loadingRegistry, next) do

        end


        loadModule(next)

        while self.requestCompleted[next] == false do
            future.run()
        end

        self:loadAndWait()
    end

    function self:callAllLoadedFiles()
        for i = 1, #self.codeOrder do
            local name = self.codeOrder[i]
            log(1, "CodeDispatchClient:Running Code: " .. name)
            local ok, err = pcall(self.codes[name])
            if not ok then
                log(4, err)
            end
        end
        self.codeOrder = {}
        self.codes = {}
    end

    local function register(name)
        if self.requestCompleted[name] == nil then
            if existsInRegistry(name) == false then
                log(0, "Neu Registiert:  " .. name)
                insertAt(self.loadingRegistry, 1, name)
                insertAt(self.codeOrder, 1, name)
            else
                log(0, "Nochmals Registiert:  " .. name)
                while removeFrom(self.loadingRegistry, name) do
                    -- Delete all
                end
                insertAt(self.loadingRegistry, 1, name)
            end
            while removeFrom(self.codeOrder, name) do
                -- Delete all
            end
            insertAt(self.codeOrder, 1, name)
        end
    end

    function self:registerForLoading(names)
        local n = #names
        local out = {}
        for i = 1, n do
            out[i] = names[n - i + 1]
        end

        for i = 1, #out do
            register(out[i])
        end
    end

    return self
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
