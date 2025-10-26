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
-- Konstanten (wie in deiner Originaldatei)
--------------------------------------------------------------------------------
NET_PORT_DEFAULT                        = 11
NET_CMD_REGISTER                        = "registerFabric"
NET_CMD_REGISTER_ACK                    = "registerFabricAck"
NET_CMD_GET_FABRIC_UPDATE               = "getFabricUpdate"
NET_CMD_UPDATE_FABRIC                   = "updateFabric"
NET_CMD_RESET_FABRICREGISTRY            = "resetFabricRegistry"

--------------------------------------------------------------------------------
-- Elternklasse: instanzbasiert, gemeinsame Features
--------------------------------------------------------------------------------
FabricRegistryNetworkConnection         = {}
FabricRegistryNetworkConnection.__index = FabricRegistryNetworkConnection

function FabricRegistryNetworkConnection:new(opts)
    local self           = setmetatable({}, FabricRegistryNetworkConnection)
    self.port            = (opts and opts.port) or NET_PORT_DEFAULT
    self.netBootInitDone = false
    self.net             = nil
    self._listenerIds    = {}
    self._onReset        = (opts and opts.onReset) or nil
    self._autoReboot     = (opts and opts.autoReboot ~= nil) and opts.autoReboot or true
    return self
end

function FabricRegistryNetworkConnection:setPort(p)
    assert(type(p) == "number" and p > 0, "setPort: invalid port")
    if self.port == p then return end
    self.port = p
    if self.netBootInitDone then
        self:close(); self:initNetworkt()
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

function FabricRegistryNetworkConnection:_addListener(flt, fn)
    -- flt = event.filter({ sender = net })
    local id = event.registerListener(flt, fn)
    table.insert(self._listenerIds, id)
    log(0, "Listerner Registered:" .. id)
    return id
end

function FabricRegistryNetworkConnection:_removeAllListeners()
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

function FabricRegistryNetworkConnection:triggerReset(fromId)
    if self._onReset then
        local ok, err = pcall(self._onReset, fromId)
        if not ok then log(3, "Reset handler error: " .. tostring(err)) end
    end
    if self._autoReboot then computer.reset() end
end

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------
FabricRegistryClient = setmetatable({}, { __index = FabricRegistryNetworkConnection })
FabricRegistryClient.__index = FabricRegistryClient

function FabricRegistryClient.new(opts)
    local self = FabricRegistryNetworkConnection:new(opts)
    self = setmetatable(self, FabricRegistryClient)
    self.myFabricInfo = (opts and opts.fabricInfo) or nil

    self.registered = false
    -- === HOOKS, in die deine Original-Logik eingesetzt wird ===
    function self:onRegisterAck(fromId)
        -- KEEP: deine bisherige Logik, wenn ACK eingeht (z.B. Flags setzen, Logs)
        log(1, "Client: Registration ACK from " .. tostring(fromId) .. " Build FabricInfo now.")
        self.myFabricInfo:setCoreNetworkCard(self.net.id)
        self:performUpdate()

        self.registered = true
    end

    function self:onRegistryReset(fromId)
        -- KEEP: deine bisherige Logik beim Registry-Reset (früher: computer.reset())
        log(2, 'Client: Registry reset requested by "' .. tostring(fromId) .. '"')
        self.registered = false
        -- hier NICHT hart rebooten – einheitlich über triggerReset:
        self:triggerReset(fromId)
    end

    function self:onGetFabricUpdate(fromId, payloadA, payloadB)
        log(0, "Net-FabricRegistryClient:: Received update request  from  \"" .. fromId .. "\"")

        self:performUpdate()

        local J = JSON.new { indent = 2, sort_keys = true }
        local serialized = J:encode(self.myFabricInfo)
        self:send(fromId, NET_CMD_UPDATE_FABRIC, serialized)
        log(0, "Net-FabricRegistryClient::update send to  \"" .. fromId .. "\"")
    end

    -- statt: function performUpdate() ... end
    function self:performUpdate()
        local comp = component.findComponent(classes.Manufacturer)
        if #comp > 0 then
            local manufacturer = component.proxy(comp[1])
            local recipe = manufacturer:getRecipe()

            if recipe ~= nil then
                local products = recipe:getProducts()
                for _, product in pairs(products) do
                    local p = product
                    local item = MyItemList:get_by_Name(p.type.name)
                    item.max = p.type.max
                    local output = Output:new {
                        itemClass          = item,
                        amountStation      = math.random(3000),
                        amountContainer    = math.random(3000),
                        maxAmountStation   = 3000,
                        maxAmountContainer = 3000
                    }

                    local containers = containerByFabricStack(self.myFabricInfo.name, output)




                    for _, container in pairs(containers) do
                        print(container.nick)

                        -- meist hat der Container genau 1 Inventory
                        local invs = container.getInventories and container:getInventories() or nil
                        -- local inv  = (invs and invs[1]) or (container.getInventory and container:getInventory()) or nil

                        for _, inv in pairs(invs) do
                            -- 1) Direkte Größe?
                            if inv.size then return print(inv.size) end
                            if inv.getSize then
                                local ok, sz = pcall(function() return inv:getSize() end)
                                if ok and type(sz) == "number" then print(sz) end
                            end
                            if inv.getCapacity then
                                local ok, cap = pcall(function() return inv:getCapacity() end)
                                if ok and type(cap) == "number" then return print(cap) end
                            end
                            if inv.getSlotCount then
                                local ok, sc = pcall(function() return inv:getSlotCount() end)
                                if ok and type(sc) == "number" then return print(sc) end
                            end
                        end
                    end
                    self.myFabricInfo:updateOutput(output) -- <– korrektes Feld
                end
                for _, ingredient in pairs(recipe:getIngredients()) do
                    local it = MyItemList:get_by_Name(ingredient.type.name)
                    it.max = ingredient.type.max
                    local input = Input:new {
                        itemClass          = it,
                        amountStation      = 0,
                        amountContainer    = 0,
                        maxAmountStation   = 3000,
                        maxAmountContainer = 3000
                    }
                    self.myFabricInfo:updateInput(input) -- <– korrektes Feld
                end
            end
        end
    end

    return self
end

function FabricRegistryClient:initRegisterListener()
    if not self.netBootInitDone then self:initNetworkt() end
    local f = event.filter { event = "NetworkMessage" }
    self:_addListener(f, safe_listener("FabricRegistryClient", function(e, _, fromId, port, cmd, a, b)
        if port ~= self.port then return end
        -- Debug:
        --log(0, ("Client RX cmd=%s from=%s"):format(tostring(cmd), tostring(fromId)))

        if cmd == NET_CMD_REGISTER_ACK then
            self:onRegisterAck(fromId)
        elseif cmd == NET_CMD_RESET_FABRICREGISTRY then
            self:onRegistryReset(fromId)
        elseif cmd == NET_CMD_GET_FABRIC_UPDATE then
            self:onGetFabricUpdate(fromId, a, b)
        end
    end))
end

-- Aufruf aus deiner Logik: einmal registrieren (oder nach Reset erneut)
function FabricRegistryClient:register(fabricInfo)
    if not self.netBootInitDone then self:initNetworkt() end
    if self.registered then return true end

    self.myFabricInfo = fabricInfo
    --pj(tostring(self.myFabricInfo))
    -- einfache Typ-/Formprüfung (falls du FabricInfo als Klasse hast, gern ersetzen)
    if tostring(self.myFabricInfo):find("FabricInfo", 1, true) == nil then
        log(3, "Net-FabricRegistryClient: Cannot broadcast '" ..
            NET_CMD_REGISTER .. "' on port " .. self.port .. " – object is no FabricInfo")
        return false
    end

    local fabricName = self.myFabricInfo.fName

    fabricName = tostring(fabricName or "?")
    if (fabricName == "?") then
        log(3, "Net-FabricRegistryClient: Cannot broadcast '" ..
            NET_CMD_REGISTER .. "' on port " .. self.port .. " – fabricName is not set")
        return false
    end
    self:broadcast(NET_CMD_REGISTER, fabricName)
    log(0, ("Client: broadcast '%s' with name '%s'"):format(NET_CMD_REGISTER, fabricName))
    return true
end

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------
FabricRegistryServer = setmetatable({}, { __index = FabricRegistryNetworkConnection })
FabricRegistryServer.__index = FabricRegistryServer

function FabricRegistryServer.new(opts)
    local self = FabricRegistryNetworkConnection:new(opts)
    self = setmetatable(self, FabricRegistryServer)
    self.reg = FabricRegistry:new() -- eigene, leere Registry für diesen Server
    self.last = 0

    -- deine bestehende Registry-Struktur weiter verwenden:
    --self.reg = {} -- id -> { name=..., fromId=..., ts=... }  (ODER ersetze durch dein FabricRegistry-Objekt)
    -- === HOOKS: hier deine Original-Logik einfügen ===
    function self:onRegister(fromId, fName)
        -- KEEP: Original-Server-Logik beim Register (FabricInfo anlegen, speichern, …)
        local name = tostring(fName or "?")

        local fInfo = FabricInfo:new()
        fInfo:setName(fName)
        fInfo:setCoreNetworkCard(fromId)
        self.reg:add(fInfo)
        -- ACK an den Absender zurück
        log(1, ('Server: Registered "%s" from %s'):format(fName, tostring(fromId)))
        self:send(fromId, NET_CMD_REGISTER_ACK)
    end

    -- function self:onRegistryReset(fromId)
    --    -- KEEP: wie du beim Reset verfahren willst (Registry leeren, etc.)
    --    self:clearRegistry()
    --     log(0, "Server: registry cleared (by " .. tostring(fromId) .. ")")
    -- optional Clients informieren, damit sie neu registrieren:
    --     self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    -- end

    -- function self:onGetFabricUpdate(fromId, payloadA, payloadB)
    -- KEEP: wenn der Client Updates anfragt → antworte mit deinen Daten
    -- Beispiel: self:send(fromId, NET_CMD_UPDATE_FABRIC, <dein JSON/String/…>)
    --end

    function self:onUpdateFabric(fromId, fabricInfoS)
        -- KEEP: falls Client etwas am Server aktualisiert
        log(0, ('Net-FabricRegistryServer: Received Update from "%s"'):format(fromId))
        local J = JSON.new { indent = 2, sort_keys = true }
        local o = J:decode(fabricInfoS)
        --print(arg1)
        --local id = o.fCoreNetworkCard
        self:getRegistry():update(o)
    end

    return self
end

function FabricRegistryServer:initRegisterListener()
    if not self.netBootInitDone then self:initNetworkt() end
    local f = event.filter { event = "NetworkMessage" }
    self:_addListener(f, safe_listener("FabricRegistryClient", function(e, _, fromId, port, cmd, a, b)
        if port ~= self.port then return end
        -- Debug:
        --log(0, ("Server RX cmd=%s from=%s"):format(tostring(cmd), tostring(fromId)))

        if cmd == NET_CMD_REGISTER then
            self:onRegister(fromId, a)
            --elseif cmd == NET_CMD_RESET_FABRICREGISTRY then
            --    self:onRegistryReset(fromId)
            --elseif cmd == NET_CMD_GET_FABRIC_UPDATE then
            --    self:onGetFabricUpdate(fromId, a, b)
        elseif cmd == NET_CMD_UPDATE_FABRIC then
            self:onUpdateFabric(fromId, a)
        elseif cmd == NET_CMD_RESET_ALL then
            self:triggerReset(fromId)
        end
    end))
end

function FabricRegistryServer:callForUpdates(fabricInfo)
    local t = now_ms()
    if t - self.last >= 1000 then
        self.last = t

        if self.reg:checkMinimum(fabricInfo) then
            local fromId = fabricInfo.fCoreNetworkCard
            local name = fabricInfo.fName
            log(0, "Net-FabricRegistryServer: Send UpdateRequest for " .. name)
            self.net:send(fromId, self.port, NET_CMD_GET_FABRIC_UPDATE)
        else
        end
    end
end

function FabricRegistryServer:clearRegistry()
    -- KEEP: falls du eine eigene Registry-Klasse hast, ruf hier deren clear/reset
    self.reg = FabricRegistry:new()
end

function FabricRegistryServer:broadcastRegistryReset()
    if not self.netBootInitDone then self:initNetworkt() end
    self:clearRegistry()
    self:broadcast(NET_CMD_RESET_FABRICREGISTRY)
    log(0, "Server: broadcast registry reset")
end

-- ===== ÖFFENTLICH: Zugriff auf die Registry =====
function FabricRegistryServer:getRegistry()
    return self.reg
end

--[[
-- Server
local srv = FabricRegistryServer.new{ port = 11 }
srv:initNetworkt()
srv:initRegisterListener()

-- Client
local cli = FabricRegistryClient.new{ port = 11 }
cli:initNetworkt()
cli:initRegisterListener()
cli:register("Mehrzweckgeruest")

-- Loop
while true do
  event.pull(0.1)
  if not cli.registered then cli:register("Mehrzweckgeruest") end
end]]
