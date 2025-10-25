FabricBillbard = {
    regServer = nil,
    gpu = nil,
    input = {},
    output = {},
    pollInterval = 1,
}

function FabricBillbard:init(gpu, input, output)
    print("\nInitialising FabricBillbard\n")
    self.gpu = gpu
    self.input = input
    self.output = output
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
        self.regServer:registerRequestServerCallback(table.unpack(args, 1, args.n))
        --self.regServer:callForUpdates()
        self:collectData()



        p:setValue(i)


        ii:setBox(self:imageBox(Vector2d.new(200, 200), self.output))

        p:draw()
        ii:draw()

        self.gpu:flush()

       

        --if e == "OnMouseDown" then
        --    log(0, "Mouseclicked on" .. pretty_json(s) .. ",".. pretty_json(x) .. "," .. pretty_json(y).. "," .. pretty_json(a).. "," .. pretty_json(b).. "," .. pretty_json(c).. "," .. pretty_json(d))
        --end
        i = i + 0.1
        if (i > 1) then i = 0 end
    end
end

function FabricBillbard:collectData()
    for i = 1, #self.input do
        local inp = self.input[i]
    end
end

function FabricBillbard:imageBox(position, item)
    return {
        position = position,
        size = Vector2d.new(512, 512),
        image = item:getRef(),
        imageSize = Vector2d.new(512, 512)
    }
end
