-- MediaClient.lua
PORT_MEDIA          = 42
MEDIA_CMD_GET       = "media:get"
MEDIA_CMD_CHUNK     = "media:chunk"
MEDIA_CMD_END       = "media:end"
MEDIA_CMD_ERR       = "media:error"

MediaClient         = {}
MediaClient.__index = MediaClient

function MediaClient.new(opts)
    local self     = setmetatable({}, MediaClient)
    self.nic       = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    self.cacheRoot = (opts and opts.cacheRoot) or "/tmp/media"
    self.pending   = {} -- reqId -> { rel, parts = {strings}, done=false, err=nil }
    assert(self.nic, "MediaClient: keine NIC")
    return self
end

local function ensure_dir(path)
    local dir = filesystem.path(path)
    if dir and not filesystem.exists(dir) then filesystem.makeDirectory(dir) end
end

local function new_req_id()
    -- simple reqId
    return tostring(now_ms()) .. "-" .. math.random(100000, 999999)
end

function MediaClient:registerWith(hub)
    hub:register(PORT_MEDIA, "MEDIA", 1, function(from, port, cmd, reqId, relPath, payload)
        local tr = self.pending[reqId]
        if not tr then return end -- unbekannt/abgelaufen → ignorieren

        if cmd == MEDIA_CMD_CHUNK then
            tr.parts[#tr.parts + 1] = payload
        elseif cmd == MEDIA_CMD_END then
            -- speichern
            local dst = filesystem.path(self.cacheRoot, relPath)
            ensure_dir(dst)
            local f = filesystem.open(dst, "wb")
            for i = 1, #tr.parts do f:write(tr.parts[i]) end
            f:close()
            tr.done   = true
            tr.result = dst
        elseif cmd == MEDIA_CMD_ERR then
            tr.err  = payload or "unknown"
            tr.done = true
        end
    end)
end

--- Holt relPath vom Server und gibt lokalen Cache-Pfad zurück (oder nil bei Fehler/Timeout)
-- timeout_ms: Default 5000
function MediaClient:fetch(relPath, timeout_ms)
    relPath      = tostring(relPath or "")
    timeout_ms   = timeout_ms or 5000
    local req    = new_req_id()

    -- wenn bereits im Cache, direkt zurück
    local cached = filesystem.path(self.cacheRoot, relPath)
    if filesystem.exists(cached) then return cached end

    -- Transfer-Objekt anlegen
    self.pending[req] = { rel = relPath, parts = {}, done = false, err = nil }

    -- Anfrage broadcasten (oder send, wenn du eine Server-ID hast)
    self.nic:broadcast(PORT_MEDIA, MEDIA_CMD_GET, req, relPath)

    -- warten bis fertig/timeout
    local deadline = now_ms() + timeout_ms
    while now_ms() < deadline do
        if self.pending[req].done then
            local tr = self.pending[req]
            self.pending[req] = nil
            if tr.err then
                log(3, "MediaClient: fetch error:", tr.err)
                return nil
            end
            return tr.result
        end
        event.pull(0.1)
    end

    -- Timeout
    self.pending[req] = nil
    log(3, "MediaClient: timeout for", relPath)
    return nil
end
