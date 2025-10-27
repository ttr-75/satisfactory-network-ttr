-- MediaServer.lua
PORT_MEDIA          = 42
MEDIA_CMD_GET       = "media:get"
MEDIA_CMD_CHUNK     = "media:chunk"
MEDIA_CMD_END       = "media:end"
MEDIA_CMD_ERR       = "media:error"

MediaServer         = {}
MediaServer.__index = MediaServer

function MediaServer.new(opts)
    local self     = setmetatable({}, MediaServer)
    self.root      = (opts and opts.root) or "/srv/media"   -- Basisverzeichnis mit PNGs
    self.chunkSize = (opts and opts.chunkSize) or 32 * 1024 -- 32 KB
    self.nic       = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.nic, "MediaServer: keine NIC")
    return self
end

local function sanitize(rel)
    rel = tostring(rel or "")
    rel = rel:gsub("^/*", "") -- führende / weg
    assert(not rel:find("%.%.", 1, true), "Pfad darf kein '..' enthalten")
    return rel
end

local function read_chunked(path, chunkSize)
    local f = filesystem.open(path, "rb")
    if not f then return nil, "open failed" end
    return function()
        local chunk = f:read(chunkSize)
        if not chunk then
            f:close(); return nil
        end
        return chunk
    end
end

function MediaServer:registerWith(hub)
    hub:register(PORT_MEDIA, "MEDIA", 1, function(from, port, cmd, reqId, relPath)
        if cmd ~= MEDIA_CMD_GET then return end
        local ok, err = pcall(function()
            relPath = sanitize(relPath)
            local full = filesystem.path(self.root, relPath)
            if not filesystem.exists(full) then
                self.nic:send(from, PORT_MEDIA, MEDIA_CMD_ERR, reqId, relPath, "not found")
                return
            end
            local nextChunk = read_chunked(full, self.chunkSize)
            if not nextChunk then
                self.nic:send(from, PORT_MEDIA, MEDIA_CMD_ERR, reqId, relPath, "cannot read")
                return
            end
            -- streamen
            while true do
                local bytes = nextChunk()
                if not bytes then break end
                self.nic:send(from, PORT_MEDIA, MEDIA_CMD_CHUNK, reqId, relPath, bytes)
                -- ein winziger Yield, um das Netz/Listener nicht zu verstopfen
                event.pull(0)
            end
            self.nic:send(from, PORT_MEDIA, MEDIA_CMD_END, reqId, relPath)
        end)
        if not ok then
            self.nic:send(from, PORT_MEDIA, MEDIA_CMD_ERR, reqId, tostring(relPath), tostring(err))
        end
    end)
end
