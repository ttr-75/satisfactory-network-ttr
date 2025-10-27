names = { "helper.lua",
    "serializer.lua",
    "items.lua",
    "graphics.lua",
    "fabricInfo.lua",
    "fabricRegistry/fabricRegistry.lua",
    "fabricRegistry/FabricRegistryServer.lua",
    "fabricDashboard.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

--------------------------------------------------------------------------------
-- Headline
--------------------------------------------------------------------------------
Headline = ScreenElement:new()
Headline.fontSize = 50
Headline.textColor = Color.GREY_0750
Headline.textVerticalOffset = -22


FabricBillbard = {
    regServer = nil,
    gpu = nil,
    scr = nil,
    currentFabric = nil,
    pollInterval = 1,
}

function FabricBillbard:init(gpu, scr)
    print("\nInitialising FabricBillbard\n")
    self.gpu = gpu
    self.scr = scr
    self.regServer = FabricRegistryServer.new()
    self.regServer:broadcastRegistryReset()
end

function FabricBillbard:run()
    local dash = FabricDashboard.new {}

    local w, h = self.scr:getSize()


    dash:init(self.gpu, self.scr, w * 300, h * 300)

    -- aus deiner FabricInfo befüllen:
    --dash:setFromFabricInfo(myFabricInfo)

    -- Loop
    while true do
        --local args = table.pack(event.pull(self.pollInterval))
        future.run()
        -- self.regServer:callbackEvent(args)
        self.regServer:callForUpdates(self.currentFabric)
        --self:collectData()

        if self.currentFabric == nil then
            local reg = self.regServer:getRegistry()
            local all = reg:getAll()
            for id, fabric in pairs(all) do
                log(0, "Registered Fabrics id:" .. id)
                if fabric ~= nil then
                    self.currentFabric = fabric;
                end
            end
        end

        dash:setFromFabricInfo(self.currentFabric)

        -- ggf. myFabricInfo:update(...) → dann erneut mappen:
        -- dash:setFromFabricInfo(myFabricInfo)
        dash:paint() -- throttled: max 1x/s
    end


    --[[ local p = Progressbar.new();

    p:init(self.gpu, Vector2d.new(10, 10))
    p:setBackground(Color.WHITE)

    local ii = ItemImage.new()
    ii:init(self.gpu)

    local i = 0
    while true do
        local args = table.pack(event.pull(self.pollInterval))
        self.regServer:callbackEvent(args)
        self.regServer:callForUpdates(self.currentFabric)
        self:collectData()

        if self.currentFabric == nil then
            local reg = self.regServer:getRegistry()
            local all = reg:getAll()
            for id, fabric in pairs(all) do
                log(0, "Registered Fabrics id:" .. id)
                if fabric ~= nil then
                    self.currentFabric = fabric;
                end
            end
        end

        if self.currentFabric ~= nil then
            p:setValue(i)

            local myItem = nil



            for _, output in pairs(self.currentFabric.outputs) do
                local itemName = output.itemClass.name
                myItem = MyItemList:get_by_Name(itemName)
            end

            ii:setBox(self:imageBox(Vector2d.new(10, 10), myItem))

            p:draw()
            ii:draw()
        end
        self.gpu:flush()

        --if e == "OnMouseDown" then
        --    log(0, "Mouseclicked on" .. pretty_json(s) .. ",".. pretty_json(x) .. "," .. pretty_json(y).. "," .. pretty_json(a).. "," .. pretty_json(b).. "," .. pretty_json(c).. "," .. pretty_json(d))
        --end
        i = i + 0.1
        if (i > 1) then i = 0 end
    end]]
end

function FabricBillbard:collectData()
    -- for i = 1, #self.input do
    --   local inp = self.input[i]
    --end
end

function FabricBillbard:imageBox(position, item)
    return {
        position = position,
        size = Vector2d.new(256, 256),
        image = item and item:getRef() or "",
        imageSize = Vector2d.new(256, 256)
    }
end
