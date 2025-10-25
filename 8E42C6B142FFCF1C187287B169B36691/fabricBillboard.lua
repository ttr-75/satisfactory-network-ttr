FabricBillbard = {
    regServer = nil,
    gpu = nil,
    currentFactory = nil,
    pollInterval = 1,
}

function FabricBillbard:init(gpu)
    print("\nInitialising FabricBillbard\n")
    self.gpu = gpu
    self.regServer = FabricRegistryServer:new()
end

function FabricBillbard:run()
    local p = Progressbar.new();

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

        
        local reg = self.regServer:getRegistry()
        local all = reg:getAll()
        for id, fabric in pairs(all) do
            log(0, "Registered Fabrics id:" .. id)
            if fabric ~= nil then
                self.currentFactory = fabric;
            end
        end

        if self.currentFactory ~= nil then
            p:setValue(i)


            ii:setBox(self:imageBox(Vector2d.new(200, 200), nil))

            p:draw()
            ii:draw()
        end
        self.gpu:flush()

        --if e == "OnMouseDown" then
        --    log(0, "Mouseclicked on" .. pretty_json(s) .. ",".. pretty_json(x) .. "," .. pretty_json(y).. "," .. pretty_json(a).. "," .. pretty_json(b).. "," .. pretty_json(c).. "," .. pretty_json(d))
        --end
        i = i + 0.1
        if (i > 1) then i = 0 end
    end
end

function FabricBillbard:collectData()
    -- for i = 1, #self.input do
    --   local inp = self.input[i]
    --end
end

function FabricBillbard:imageBox(position, item)
    return {
        position = position,
        size = Vector2d.new(512, 512),
        image = item and item:getRef() or "",
        imageSize = Vector2d.new(512, 512)
    }
end
