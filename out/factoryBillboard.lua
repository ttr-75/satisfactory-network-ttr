names = { "shared/helper.lua",
    "shared/items/items[-LANGUAGE-].lua",
    "shared/graphics.lua",
    "factoryRegistry/FactoryInfo.lua",
    "factoryRegistry/FactoryRegistry.lua",
    "factoryRegistry/FactoryDashboard_Main.lua",
    "factoryDashboard.lua",
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


FactoryBillbard = {
    regServer = nil,
    gpu = nil,
    scr = nil,
    currentFactory = nil,
    pollInterval = 1,
}

function FactoryBillbard:init(gpu, scr)
    print("\nInitialising FactoryBillbard\n")
    self.gpu = gpu
    self.scr = scr
    self.regServer = FactoryRegistryServer.new()
    self.regServer:broadcastRegistryReset()
end

function FactoryBillbard:run()
    local dash = FactoryDashboard.new {}

    local w, h = self.scr:getSize()


    dash:init(self.gpu, self.scr, w * 300, h * 300)

    -- aus deiner FactoryInfo befüllen:
    --dash:setFromFactoryInfo(myFactoryInfo)

    -- Loop
    while true do
        --local args = table.pack(event.pull(self.pollInterval))
        future.run()
        -- self.regServer:callbackEvent(args)
        self.regServer:callForUpdates(self.currentFactory)
        --self:collectData()

        if self.currentFactory == nil then
            local reg = self.regServer:getRegistry()
            local all = reg:getAll()
            for id, factory in pairs(all) do
                log(0, "Registered Factorys id:" .. id)
                if factory ~= nil then
                    self.currentFactory = factory;
                end
            end
        end

        dash:setFromFactoryInfo(self.currentFactory)

        -- ggf. myFactoryInfo:update(...) → dann erneut mappen:
        -- dash:setFromFactoryInfo(myFactoryInfo)
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
        self.regServer:callForUpdates(self.currentFactory)
        self:collectData()

        if self.currentFactory == nil then
            local reg = self.regServer:getRegistry()
            local all = reg:getAll()
            for id, factory in pairs(all) do
                log(0, "Registered Factorys id:" .. id)
                if factory ~= nil then
                    self.currentFactory = factory;
                end
            end
        end

        if self.currentFactory ~= nil then
            p:setValue(i)

            local myItem = nil



            for _, output in pairs(self.currentFactory.outputs) do
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

function FactoryBillbard:collectData()
    -- for i = 1, #self.input do
    --   local inp = self.input[i]
    --end
end

function FactoryBillbard:imageBox(position, item)
    return {
        position = position,
        size = Vector2d.new(256, 256),
        image = item and item:getRef() or "",
        imageSize = Vector2d.new(256, 256)
    }
end
