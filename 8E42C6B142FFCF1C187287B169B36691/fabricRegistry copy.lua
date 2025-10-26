NET_CMD_REGISTER = "registerFabric"
NET_CMD_REGISTER_ACK = "registerFabricAck"
NET_CMD_UPDATE_FABRIC = "updateFabric"
NET_CMD_GET_FABRIC_UPDATE = "getFabricUpdate"
NET_CMD_RESET_FABRICREGISTRY = "resetFabricRegistry"


FabricRegistry = {
    fabrics = {}
}

function FabricRegistry:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function FabricRegistry:add(fabric)
    if self:checkMinimum(fabric) then
        local id = fabric.fCoreNetworkCard
        local name = fabric.fName
        log(0, "Adding: FabricRegister:add(fabric): Fabric" .. name .. " with id:" .. id)
        self.fabrics[id] = fabric
    else
        log(3, "Ignorring: FabricRegister:add(fabric)")
    end
end

function FabricRegistry:update(fabric)
    if self:checkMinimum(fabric) then
        local id = fabric.fCoreNetworkCard
        local name = fabric.fName
        log(0, "Update: FabricRegister:update(fabric): Fabric" .. name .. " with id:" .. id)
        self.fabrics[id]:update(fabric)
    else
        log(3, "Ignorring: FabricRegister:Update(fabric)")
    end
end

function FabricRegistry:checkMinimum(fabric)
    return FabricInfo:check(fabric)
end

function FabricRegistry:getAll()
    return self.fabrics
end

--------------------------------------------------------------------------------
-- Konstanten
--------------------------------------------------------------------------------
NET_PORT_DEFAULT                        = 11
NET_CMD_REGISTER                        = "registerFabric"
NET_CMD_REGISTER_ACK                    = "registerFabricAck"
NET_CMD_RESET_FABRICREGISTRY            = "resetFabricRegistry" -- Registry-Reset (kein Hard-Reboot)
-- (separater NetBoot-Reset wäre z.B. "resetAll" auf anderem Port)

--------------------------------------------------------------------------------
-- Elternklasse: FabricRegistryNetworkConnection
--  - Instanzbasiert
--  - Gemeinsame Features: setPort, setResetHandler, triggerReset, close, send, broadcast
--------------------------------------------------------------------------------
FabricRegistryNetworkConnection         = {}
FabricRegistryNetworkConnection.__index = FabricRegistryNetworkConnection

function FabricRegistryNetworkConnection:new(opts)
    local self           = setmetatable({}, FabricRegistryNetworkConnection)
    self.port            = (opts and opts.port) or NET_PORT_DEFAULT
    self.netBootInitDone = false
    self.net             = nil
    self._listenerIds    = {} -- mehrere Listener möglich
    self._onReset        = (opts and opts.onReset) or nil
    self._autoReboot     = (opts and opts.autoReboot ~= nil) and opts.autoReboot or false
    return self
end

function FabricRegistryNetworkConnection:setPort(p)
    assert(type(p) == "number" and p > 0, "setPort: invalid port")
    if self.port == p then return end
    self.port = p
    if self.netBootInitDone then
        self:close()
        self:initNetworkt()
    end
end

function FabricRegistryNetworkConnection:setResetHandler(fn)
    assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
    self._onReset = fn
end

function FabricRegistryNetworkConnection:setAutoReboot(flag)
    self._autoReboot = not not flag
end

function FabricRegistryNetworkConnection:initNetworkt()
    if self.netBootInitDone then return end
    self.net = computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.net, "Net: No Network Card available!")
    self.net:open(self.port)
    event.listen(self.net)
    log(0, "Net: listening on port " .. tostring(self.port))
    self.netBootInitDone = true
end

-- Helper: Listener registrieren & ID merken
function FabricRegistryNetworkConnection:_addListener(flt, fn)
    local id = event.registerListener(flt, fn)
    table.insert(self._listenerIds, id)
    return id
end

function FabricRegistryNetworkConnection:_removeAllListeners()
    if #self._listenerIds == 0 then return end
    for _, id in ipairs(self._listenerIds) do
        if event.removeListener then
            pcall(event.removeListener, id)
        elseif event.unregisterListener then
            pcall(event.unregisterListener, id)
        elseif event.cancelListener then
            pcall(event.cancelListener, id)
        end
    end
    self._listenerIds = {}
end

function FabricRegistryNetworkConnection:close()
    self:_removeAllListeners()
    if self.net then pcall(function() self.net:close() end) end
    self.netBootInitDone = false
end

function FabricRegistryNetworkConnection:send(toId, cmd, ...)
    assert(self.netBootInitDone, "send: network not initialized")
    self.net:send(toId, self.port, cmd, ...)
end

function FabricRegistryNetworkConnection:broadcast(cmd, ...)
    assert(self.netBootInitDone, "broadcast: network not initialized")
    self.net:broadcast(self.port, cmd, ...)
end

-- Ein einheitlicher Einstieg, wenn „Registry resetten“ o.ä. ankommt
function FabricRegistryNetworkConnection:triggerReset(fromId)
    if self._onReset then
        local ok, err = pcall(self._onReset, fromId)
        if not ok then log(3, "Reset handler error: " .. tostring(err)) end
    end
    if self._autoReboot then
        computer.reset()
    end
end

--------------------------------------------------------------------------------
-- Client: FabricRegistryClient
--  - Registriert sich beim Server mit NET_CMD_REGISTER (Broadcast)
--  - Reagiert auf ACK
--  - Reagiert auf NET_CMD_RESET_FABRICREGISTRY mit triggerReset()
--------------------------------------------------------------------------------
FabricRegistryClient = setmetatable({}, { __index = FabricRegistryNetworkConnection })
FabricRegistryClient.__index = FabricRegistryClient

function FabricRegistryClient.new(opts)
    local self = FabricRegistryNetworkConnection:new(opts)
    self = setmetatable(self, FabricRegistryClient)
    self.registered = false
    return self
end

-- optional: Listener separat initialisieren (nach initNetworkt())
function FabricRegistryClient:initRegisterListener()
    if not self.netBootInitDone then self:initNetworkt() end
    local f = event.filter { event = "NetworkMessage" }
    self:_addListener(f, function(e, _, fromId, port, cmd, fName)
        if port ~= self.port then return end
        -- Debug: Eingang
        -- log(1, ("Client RX: cmd=%s from=%s"):format(tostring(cmd), tostring(fromId)))

        if cmd == NET_CMD_REGISTER_ACK then
            log(1, "Client: Registration ACK from " .. tostring(fromId))
            self.registered = true
        elseif cmd == NET_CMD_RESET_FABRICREGISTRY then
            log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
            self.registered = false
            self:triggerReset(fromId) -- gemeinsamer Reset-Einstieg (keine Zwangs-Reboots)
        end
    end)
end

-- Einmalige Registrierung anstoßen (z. B. beim Start oder nach Reset)
-- fabricName: String (z. B. fi.fName)
function FabricRegistryClient:register(fabric)
    if not self.netBootInitDone then self:initNetworkt() end
    if self.registered then return true end
    fabricName = tostring(fabricName or "?")
    self:broadcast(NET_CMD_REGISTER, fabricName)
    log(0, ("Client: broadcast '%s' with name '%s'"):format(NET_CMD_REGISTER, fabricName))
    return true
end

--------------------------------------------------------------------------------
-- Server: FabricRegistryServer
--  - Hört auf NET_CMD_REGISTER, legt Einträge an und sendet ACK
--  - Kann optional NET_CMD_RESET_FABRICREGISTRY an alle broadcasten (broadcastRegistryReset)
--------------------------------------------------------------------------------
FabricRegistryServer = setmetatable({}, { __index = FabricRegistryNetworkConnection })
FabricRegistryServer.__index = FabricRegistryServer

function FabricRegistryServer.new(opts)
    local self = FabricRegistryNetworkConnection:new(opts)
    self = setmetatable(self, FabricRegistryServer)
    self.reg = {} -- id -> { name=..., fromId=... }
    return self
end

function FabricRegistryServer:initRegisterListener()
    if not self.netBootInitDone then self:initNetworkt() end
    local f = event.filter { event = "NetworkMessage" }
    self:_addListener(f, function(e, _, fromId, port, cmd, fName)
        if port ~= self.port then return end
        -- log(1, ("Server RX: cmd=%s from=%s"):format(tostring(cmd), tostring(fromId)))

        if cmd == NET_CMD_REGISTER then
            local name = tostring(fName or "?")
            self.reg[fromId] = { name = name, fromId = fromId, ts = computer.uptime and computer.uptime() or 0 }
            log(1, ('Server: Registered "%s" from %s'):format(name, tostring(fromId)))
            -- ACK zurück
            self:send(fromId, NET_CMD_REGISTER_ACK)
        elseif cmd == NET_CMD_RESET_FABRICREGISTRY then
            -- Falls du erlaubst, dass ein Client den Reset auslöst, kannst du hier reagieren:
            log(2, 'Server: received registry reset trigger from ' .. tostring(fromId))
            self:clearRegistry()
            -- optional: Clients informieren (z. B. damit sie sich neu registrieren)
            self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
        end
    end)
end

function FabricRegistryServer:clearRegistry()
    self.reg = {}
    log(0, "Server: registry cleared")
end

-- Als Server aktiv anstoßen (z. B. nach (Re-)Start)
function FabricRegistryServer:broadcastRegistryReset()
    if not self.netBootInitDone then self:initNetworkt() end
    self:clearRegistry()
    self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    log(0, "Server: broadcast registry reset")
end














FabricRegistryNetworkConnection = {
    port = 11,
    netBootInitDone = false,
}

function FabricRegistryNetworkConnection:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function FabricRegistryNetworkConnection:initNetworkt()
    if self.netBootInitDone then
        return
    end
    self.net = computer.getPCIDevices(classes.NetworkCard)[1]
    if not self.net then
        error("Net-Boot: Failed to Start: No Network Card available!")
    end
    self.net:open(self.port)
    log(0, "Init FabricRegistryNetworkConnection done on Port " .. self.port)

    event.listen(self.net)
    self.netBootInitDone = true;
end

--------------------------------------------------------------------------------
-- FabricRegistryClient (Variante B: private per-Instanz-Closures)
--------------------------------------------------------------------------------
FabricRegistryClient = FabricRegistryNetworkConnection:new()
FabricRegistryClient.__index = FabricRegistryClient

function FabricRegistryClient.new()
    local self = setmetatable({}, FabricRegistryClient)
    self.registered = false -- Instanzzustand
    self.myFabric = nil


    ----------------------------------------------------------------------
    -- PRIVATE: sendRegisterRequest (nicht exportiert)
    ----------------------------------------------------------------------
    local function sendRegisterRequest(fabric)
        if not self.netBootInitDone then self:initNetworkt() end
        if self.registered then return false end


        -- einfache Typ-/Formprüfung (falls du FabricInfo als Klasse hast, gern ersetzen)
        if tostring(fabric):find("FabricInfo", 1, true) == nil then
            log(3, "Net-FabricRegistryClient: Cannot broadcast '" ..
                NET_CMD_REGISTER .. "' on port " .. self.port .. " – object is no FabricInfo")
            return false
        end

        local fName = fabric.fName or "<noname>"


        -- Broadcast senden
        self.net:broadcast(self.port, NET_CMD_REGISTER, fName)
        log(0, "Net-FabricRegistryClient: Broadcasting '" .. NET_CMD_REGISTER ..
            "' on port " .. self.port .. " with name '" .. fName .. "'")

        -- Auf ACK warten (kooperativ, nicht volle 30s blocken)
        local deadline = (computer.millis and computer.millis() or 0) + 30000
        while computer.millis() < deadline do
            local e, s, from, p, cmd = event.pull(0.25) -- kurzer Poll
            if e == "NetworkMessage" and p == self.port and cmd == NET_CMD_REGISTER_ACK then
                log(1, "Net-FabricRegistryClient: Got Ack for \"" .. fName .. "\" from \"" .. tostring(from) .. "\"")
                self.registered = true
                self.myFabric = fabric
                self.myFabric:setCoreNetworkCard(self.net.id)
                return true
            end
        end
        log(3, "Net-FabricRegistryClient: Request Timeout reached! Retry later…")
    end

    ----------------------------------------------------------------------
    -- PRIVATE: checkForReboot (nicht exportiert)
    ----------------------------------------------------------------------

    local function performUpdate()
        local comp = component.findComponent(classes.Manufacturer)
        if (#comp > 0) then
            local manufacturer = component.proxy(comp[1])
            local recipe = manufacturer:getRecipe()
            if recipe ~= nil then
                local products = recipe:getProducts()
                if #products == 1 then
                    local p = products[1]
                    local a = p.amount
                    local t = p.type
                    --local J = JSON.new { indent = 2, sort_keys = true }
                    --local s = J:encode(t)
                    -- print(t.name)
                    --local l = .new()
                    local item = MyItemList:get_by_Name(t.name)
                    item.max = t.max
                    local output = Output:new { itemClass = item, amountStation = math.random(3000), amountContainer = math.random(3000), maxAmountStation = 3000, maxAmountContainer = 3000 }
                    self.myFabric:updateOutput(output)
                    -- local J = JSON.new { indent = 2, sort_keys = true }
                    -- local serialized = J:encode(self.myFabric)
                    -- print(serialized)
                else
                    log(3,
                        "Fabric with more then 1 Output product not implemented yet - FabricRegistryClient:performUpdate")
                end

                local ingredients = recipe:getIngredients()
                for _, ingredient in pairs(ingredients) do
                    local a = ingredient.amount
                    local t = ingredient.type

                    pj(t.name)

                    --local l = .new()
                    local item = MyItemList:get_by_Name(t.name)
                    item.max = t.max
                    local input = Input:new { itemClass = item, amountStation = math.random(3000), amountContainer = math.random(3000), maxAmountStation = 3000, maxAmountContainer = 3000 }
                    self.myFabric:updateInput(input)
                    -- local J = JSON.new { indent = 2, sort_keys = true }
                    -- local serialized = J:encode(self.myFabric)
                    -- print(serialized)
                end
            end
        end
    end

    local function handleNetworkMessage(e, s, fromId, p, cmd)
        if e == "NetworkMessage" and p == self.port then
            if cmd == NET_CMD_RESET_FABRICREGISTRY then
                log(2, "Net-FabricRegistryClient:: Received reset command from  \"" .. fromId .. "\"")
                if self._onReset ~= nil then
                    computer.log(2, "Net-Boot: Call Callback")
                    local ok, err = pcall(self._onReset)
                    if not ok then computer.log(3, "Reset handler error: " .. tostring(err)) end
                end
                computer.reset()
            elseif cmd == NET_CMD_GET_FABRIC_UPDATE then
                log(0, "Net-FabricRegistryClient:: Received update request  from  \"" .. fromId .. "\"")

                performUpdate()

                local J = JSON.new { indent = 2, sort_keys = true }
                local serialized = J:encode(self.myFabric)
                -- print(serialized)

                -- local serialized2 = J:encode(self.myFabric.outputs)
                -- print(serialized)

                self.net:send(fromId, self.port, NET_CMD_UPDATE_FABRIC, serialized)
                log(0, "Net-FabricRegistryClient::update send to  \"" .. fromId .. "\"")
            end
        end
        -- Platzhalter: hier deine Logik (z.B. Flag prüfen und ggf. resetten)
        -- if needReboot then computer.reset() end
    end


    ----------------------------------------------------------------------
    -- ÖFFENTLICH: einzig sichtbare Methode
    ----------------------------------------------------------------------
    function self:callbackEvent(fabric, args)
        sendRegisterRequest(fabric)
        handleNetworkMessage(table.unpack(args, 1, args.n))
    end

    function self:setPort(p)
        assert(type(p) == "number" and p > 0, "setPort: invalid port")
        self.port = p
    end

    function self:setResetHandler(fn)
        computer.log(2, "Net-Boot: setResetHandlerCalled")
        assert(fn == nil or type(fn) == "function", "setResetHandler: function or nil expected")
        self._onReset = fn
    end

    return self
end

--------------------------------------------------------------------------------
-- FabricRegistryServer (Variante B: private per-Instanz-Closures)
--------------------------------------------------------------------------------
FabricRegistryServer = FabricRegistryNetworkConnection:new()
FabricRegistryServer.__index = FabricRegistryServer

function FabricRegistryServer.new()
    local self = setmetatable({}, FabricRegistryServer)
    self.reg = FabricRegistry:new() -- eigene, leere Registry für diesen Server
    self.last = 0

    -- ===== PRIVATE: Netzwerk-Handler (nicht exportiert) =====
    local function handleNetworkMessage(e, s, fromId, port, cmd, arg1)
        if e ~= "NetworkMessage" or port ~= self.port then return end
        log(0, 'Net-FabricRegistryServer: Handle' .. cmd)
        if cmd == NET_CMD_REGISTER then
            log(0, ('Net-FabricRegistryServer: Received Register from "%s"'):format(fromId))
            local fInfo = FabricInfo:new()
            fInfo:setName(arg1)
            fInfo:setCoreNetworkCard(fromId)
            self.reg:add(fInfo)
            -- ACK an den Absender zurück
            self.net:send(fromId, self.port, NET_CMD_REGISTER_ACK)
        elseif cmd == NET_CMD_UPDATE_FABRIC then
            log(0, ('Net-FabricRegistryServer: Received Update from "%s"'):format(fromId))
            local J = JSON.new { indent = 2, sort_keys = true }
            local o = J:decode(arg1)
            --print(arg1)
            --local id = o.fCoreNetworkCard
            self:getRegistry():update(o)
        end
    end

    -- ===== ÖFFENTLICH: vom Main-Loop aufrufen, args = table.pack(event.pull(...)) =====
    function self:callbackEvent(args)
        -- local J = JSON.new { indent = 2, sort_keys = true }
        --local serialized = J:encode(table.unpack(args, 1, args.n))
        --print(serialized)
        if not self.netBootInitDone then self:initNetworkt() end
        if args and args.n then
            handleNetworkMessage(table.unpack(args, 1, args.n))
        end
    end

    function self:callForUpdates(fabric)
        local t = now_ms()
        if t - self.last >= 1000 then
            self.last = t

            if self.reg:checkMinimum(fabric) then
                local fromId = fabric.fCoreNetworkCard
                local name = fabric.fName
                log(0, "Net-FabricRegistryServer: Send UpdateRequest for " .. name)
                self.net:send(fromId, self.port, NET_CMD_GET_FABRIC_UPDATE)
            else
            end
        end
    end

    return self
end

-- ===== OVERRIDE: Server-spezifische Netz-Init (inkl. Reset-Broadcast) =====
function FabricRegistryServer:initNetworkt()
    if self.netBootInitDone then return end
    self.net = computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.net, "Net-FabricRegistryServer: Failed to Start: No Network Card available!")
    self.net:open(self.port)
    event.listen(self.net)
    log(0, "Net-FabricRegistryServer: Init FabricRegistryServer network on Port " .. self.port)

    -- *** Neu: beim Start alle Clients informieren ***
    self.net:broadcast(self.port, NET_CMD_RESET_FABRICREGISTRY)

    self.netBootInitDone = true
end

-- ===== ÖFFENTLICH: Zugriff auf die Registry =====
function FabricRegistryServer:getRegistry()
    return self.reg
end
