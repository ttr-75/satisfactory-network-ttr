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
        self.fabrics[id].update(fabric)
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
    local function handleNetworkMessage(e, s, fromId, p, cmd)
        if e == "NetworkMessage" and p == self.port then
            if cmd == NET_CMD_RESET_FABRICREGISTRY then
                log(2, "Net-FabricRegistryClient:: Received reset command from  \"" .. fromId .. "\"")
                computer.reset()
            elseif cmd == NET_CMD_GET_FABRIC_UPDATE then
                log(0, "Net-FabricRegistryClient:: Received update request  from  \"" .. fromId .. "\"")

                local J = JSON.new { indent = 2, sort_keys = true }
                local serialized = J:encode(self.myFabric)
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
