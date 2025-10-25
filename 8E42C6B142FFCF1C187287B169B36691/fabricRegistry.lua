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
    if not fabric then
        log(3, "Ignorring: FabricRegister:add(nil)")
        return
    end

    local id = fabric.fCoreNetworkCard
    if not id then
        log(3, "Ignorring: FabricRegister:add(fabric): Fabric has no CoreNetworkCardId")
        return
    end

    local name = fabric.fName
    if not name then
        log(3, "Ignorring: FabricRegister:add(fabric): Fabric has no Name")
        return
    end

    log(0, "Adding: FabricRegister:add(fabric): Fabric" .. name .. " with id:" .. id)
    self.fabrics[id] = fabric
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

    ----------------------------------------------------------------------
    -- PRIVATE: sendRegisterRequest (nicht exportiert)
    ----------------------------------------------------------------------
    local function sendRegisterRequest(fabric)
        if not self.netBootInitDone then self:initNetworkt() end
        if self.registered then return true end

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
        while true do
            -- kurzer Poll, damit du CPU schonst und andere Events durchkommen
            local e, _, fromId, p, cmd = event.pull(0.25)
            if e == "NetworkMessage" and p == self.port and cmd == NET_CMD_REGISTER_ACK then
                log(1, "Net-FabricRegistryClient: Got Ack for \"" .. fName ..
                    "\" from Server \"" .. tostring(fromId) .. "\"")
                self.registered = true
                return true
            end
            -- Timeout prüfen (falls computer.millis nicht existiert, brechen wir nach ~30s trotzdem ab)
            if computer.millis and computer.millis() >= deadline then
                log(3, "Net-FabricRegistryClient: Request timeout – retry later…")
                return false
            end
        end
    end

    ----------------------------------------------------------------------
    -- PRIVATE: checkForReboot (nicht exportiert)
    ----------------------------------------------------------------------
    local function checkForReboot(e, _, s, p, cmd, programName)
        if e == "NetworkMessage" and p == self.port then
            if cmd == NET_CMD_RESET_FABRICREGISTRY  then
                log(2, "Net-FabricRegistryClient:: Received reset command from Server \"" .. s .. "\"")
                computer.reset()
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
        checkForReboot(table.unpack(args, 1, args.n))
    end

    return self
end

--------------------------------------------------------------------------------
-- FabricRegistryServer
--------------------------------------------------------------------------------
FabricRegistryServer = FabricRegistryNetworkConnection:new()

FabricRegistryServer.__index = FabricRegistryServer
FabricRegistryServer.reg = nil

function FabricRegistryServer.new()
    local o = setmetatable({}, FabricRegistryServer)
    o.reg = FabricRegistry:new()
    return o
end

function FabricRegistryServer:registerRequestServerCallback(e, s, fromId, port, cmd, fName)
    if not self.netBootInitDone then
        self:initNetworkt()
    end

    if e == "NetworkMessage" then
        log(0, "Eventlistener '" .. cmd .. "' called.")
        if port == self.port and cmd == NET_CMD_REGISTER then
            computer.log(1, ('Net-FabricRegistryServer: Received Register from "%s"'):format(fromId))
            local fInfo = FabricInfo:new()
            fInfo:setName(fName)
            fInfo:setCoreNetworkCard(fromId)
            self.reg:add(fInfo)
            self.net:send(fromId, self.port, NET_CMD_REGISTER_ACK)
            --   end
        end
    end
    return
end

function FabricRegistryServer:getRegistry()
    return self.reg
end
