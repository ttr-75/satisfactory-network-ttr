local names = {
    "helper.lua",
    "file/FileIO.lua",
    "net/media/basics.lua",
    "net/NetworkAdapter.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()

-------------------------------------------------------------------------------
-- MediaServer – liefert Dateien (z. B. PNG) in Chunks
-- Abhängigkeiten: NetHub.lua, NetworkAdapter.lua (bereits bei dir vorhanden)
-- FileIO
-------------------------------------------------------------------------------
NET_PORT_MEDIA          = 42
NET_CMD_MEDIA_CMD_GET   = "media:get"
NET_CMD_MEDIA_CMD_CHUNK = "media:chunk"
NET_CMD_MEDIA_CMD_END   = "media:end"
NET_CMD_MEDIA_CMD_ERR   = "media:error"

assert(type(FileIO) == "table" and type(FileIO.new) == "function", NET_NAME_MEDIA_SERVER .. ": FileIO benötigt")

MediaServer = setmetatable({}, { __index = NetworkAdapter })
MediaServer.__index = MediaServer

local function _sanitize(rel)
    rel = tostring(rel or ""):gsub("^/*", "")
    assert(not rel:find("%.%.", 1, true), NET_NAME_MEDIA_SERVER .. ": Pfad darf kein '..' enthalten")
    return rel
end

function MediaServer.new(opts)
    local self     = NetworkAdapter:new(opts)
    self           = setmetatable(self, MediaServer)
    self.name      = (opts and opts.name) or NET_NAME_MEDIA_SERVER
    self.port      = (opts and opts.port) or NET_PORT_MEDIA
    self.ver       = (opts and opts.ver) or 1
    self.root      = (opts and opts.root) or "srv/media"
    self.chunkSize = (opts and opts.chunkSize) or 32 * 1024
    self.fsio      = FileIO.new { root = self.root, autoMount = true } -- Pflicht & Auto-Mount

    log(0, ("MediaServer:init name=%s port=%d root=%s chunk=%dB")
        :format(self.name, self.port, self.root, self.chunkSize))

    self:registerWith(function(from, port, cmd, reqId, relPath)
        if port ~= self.port or cmd ~= NET_CMD_MEDIA_CMD_GET then return end

        local t0 = now_ms()
        relPath = _sanitize(relPath)
        self.fsio:ensureMounted()

        computer.log(0, "Mounted dev = " .. tostring(self.fsio:getMountedDevice()))
        computer.log(0, "Mounted id  = " .. tostring(self.fsio:getMountedId()))

        local full = self.fsio:abs(relPath)

        log(1, ("MediaServer:GET from=%s req=%s path=%s"):format(tostring(from), tostring(reqId), relPath))

        log(1, ("MediaServer:GET from=%s req=%s path=%s"):format(tostring(from), tostring(reqId), full))

        if self.fsio:isFile(relPath) == false then
            log(3, ("MediaServer:NOT_FOUND path=%s"):format(full))
            self:send(from, NET_CMD_MEDIA_CMD_ERR, reqId, relPath, "not found")
            return
        end

        local f = filesystem.open(full, "rb")
        if not f then
            log(3, ("MediaServer:OPEN_FAIL path=%s"):format(full))
            self:send(from, NET_CMD_MEDIA_CMD_ERR, reqId, relPath, "cannot open")
            return
        end

        local chunks, bytesSum = 0, 0
        while true do
            local chunk = f:read(self.chunkSize)
            if not chunk then break end
            bytesSum = bytesSum + #chunk
            chunks   = chunks + 1
            if chunks % 16 == 1 then
                log(1, ("MediaServer:STREAM path=%s chunks=%d bytes=%d"):format(relPath, chunks, bytesSum))
            end
            self:send(from, NET_CMD_MEDIA_CMD_CHUNK, reqId, relPath, chunk)
            event.pull(0) -- freundlich zum Event-Loop
        end
        f:close()
        self:send(from, NET_CMD_MEDIA_CMD_END, reqId, relPath)

        local dt = now_ms() - t0
        log(0, ("MediaServer:DONE path=%s chunks=%d bytes=%d ms=%d")
            :format(relPath, chunks, bytesSum, dt))
    end)

    return self
end

--[[

-- Server
local nic = computer.getPCIDevices(classes.NetworkCard)[1]
NetHub:init(nic)
local mediaSrv = MediaServer.new{ nic = nic, root="/srv/media" }
while true do event.pull(0.2) end


]]
