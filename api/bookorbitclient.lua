-- BookOrbit's web/native API uses JWT sessions, separate from KOReader sync keys.
local JSON = require("json")
local http = require("socket.http")
local socketutil = require("socketutil")
local ltn12 = require("ltn12")
local Client = {}
Client.__index = Client

function Client.normalizeUrl(value)
    if type(value) ~= "string" then return nil end
    local url = value:match("^%s*(.-)%s*$"):gsub("/+$", ""):gsub("/api/v1/koreader$", "/api/v1")
    local scheme, authority, path = url:match("^(https?)://([^/%?#]+)([^%?#]*)$")
    if not scheme or authority:find("@", 1, true) or url:find("[%c%s]") then return nil end
    -- Preserve existing LAN/tailnet deployments; never send passwords over public HTTP.
    local host = authority:match("^([^:]+):?%d*$")
    local a,b,c,d = (host or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
    local private = a and b and c and d and a <= 255 and b <= 255 and c <= 255 and d <= 255
        and (a == 10 or a == 127 or a == 192 and b == 168 or a == 172 and b >= 16 and b <= 31
            or a == 100 and b >= 64 and b <= 127)
    if scheme == "http" and host ~= "localhost" and not private then return nil end
    if path ~= "/api/v1" then url = url .. "/api/v1" end
    return url
end

function Client.new(config)
    return setmetatable({config = config}, Client)
end

-- No redirects: credentials must stay at the configured origin. Stream files and bound responses.
function Client:request(method, path, body, source, length, content_type)
    if not Client.normalizeUrl(self.config.server_url) or path:sub(1,1) ~= "/" then
        return nil, "Invalid BookOrbit address", 0
    end
    local headers = {Accept="application/json", Connection="close"}
    if self.config.access_token then headers.Authorization = "Bearer " .. self.config.access_token end
    if body then
        body = JSON.encode(body)
        source, length, content_type = ltn12.source.string(body), #body, "application/json"
    end
    if source then
        headers["Content-Length"], headers["Content-Type"] = tostring(length), content_type
    end
    local chunks, received = {}, 0
    local old_block, old_total = socketutil.block_timeout, socketutil.total_timeout
    local uploading = content_type and content_type:match("^multipart/")
    socketutil:set_timeout(uploading and 30 or 8, uploading and math.min(7200,120 + math.ceil((length or 0)/8192)) or 20)
    local called, ok, code = pcall(http.request, {
        url=self.config.server_url .. path, method=method, headers=headers, source=source,
        redirect=false,
        sink=function(chunk)
            if chunk then
                received = received + #chunk
                if received > 1024*1024 then return nil, "BookOrbit response too large" end
                chunks[#chunks+1] = chunk
            end
            return 1
        end,
    })
    socketutil:set_timeout(old_block, old_total)
    if not called or not ok then return nil, "BookOrbit connection failed; check Wi-Fi and Tailscale", 0 end
    code = tonumber(code) or 0
    local decoded, data = pcall(JSON.decode, table.concat(chunks))
    if code >= 200 and code < 300 and decoded and type(data) == "table" then return data, nil, code end
    -- Do not echo arbitrary server bodies, which can include secrets or HTML.
    local messages = {[401]="BookOrbit sign-in expired. Sign in again", [403]="BookOrbit account lacks upload/library permission",
        [404]="BookOrbit endpoint or library not found", [409]="A file already exists in BookOrbit; check the library",
        [413]="Book exceeds BookOrbit's upload size limit", [415]="Book format is not supported", [429]="BookOrbit rate limit; try later"}
    return nil, messages[code] or ("BookOrbit request failed (HTTP " .. code .. ")"), code
end

function Client:adoptSession(data)
    if type(data) ~= "table" or type(data.accessToken) ~= "string" or data.accessToken == "" then
        return nil, "BookOrbit did not return a native session"
    end
    self.config.access_token = data.accessToken
    if type(data.refreshToken) == "string" then self.config.refresh_token = data.refreshToken end
    return true
end

function Client:login(username, password)
    local data, err = self:request("POST", "/auth/login", {
        username=username, password=password, clientKind="native", deviceLabel="Kindle Fetch",
    })
    if not data then return nil, err end
    local ok; ok, err = self:adoptSession(data)
    if not ok then return nil, err end
    self.config.username = username
    return self.config
end

function Client:refresh()
    if not self.config.refresh_token then return nil, "Sign in to BookOrbit" end
    local data, err = self:request("POST", "/auth/refresh", {refreshToken=self.config.refresh_token})
    if not data then return nil, err end
    return self:adoptSession(data)
end

function Client:authorized(method, path)
    local data, err, code = self:request(method, path)
    if code == 401 and self.config.refresh_token then
        local refreshed; refreshed, err = self:refresh()
        if not refreshed then return nil, err, 401 end
        return self:request(method, path)
    end
    return data, err, code
end

function Client:libraries()
    local data, err = self:authorized("GET", "/libraries")
    if not data then return nil, err end
    -- The supported server endpoint returns a library array.
    local libraries = {}
    for _, library in ipairs(data) do
        if tonumber(library.id) and (library.type == nil or library.type == "books") then
            libraries[#libraries+1] = {id=library.id, name=library.name or tostring(library.id)}
        end
    end
    return libraries
end

function Client:upload(path)
    local id = tonumber(self.config.library_id)
    if not id or id < 1 or id ~= math.floor(id) then return nil, "Choose a BookOrbit library", false end
    local file, err = io.open(path, "rb")
    if not file then return nil, "Local book is missing or unreadable", false end
    local size = file:seek("end"); file:seek("set",0)
    if not size or size <= 0 then file:close(); return nil, "Local book is empty", false end
    local filename = path:match("([^/]+)$"):gsub('[%c"\\]', "_")
    local boundary = "KindleFetch" .. tostring(os.time()) .. tostring(math.random(100000,999999))
    local head = '--'..boundary..'\r\nContent-Disposition: form-data; name="file"; filename="'..filename..'"\r\nContent-Type: application/octet-stream\r\n\r\n'
    local tail = '\r\n--'..boundary..'--\r\n'
    local stage = 0
    local source = function()
        if stage == 0 then stage=1; return head end
        if stage == 1 then
            local chunk, read_err = file:read(65536)
            if chunk then return chunk end
            if read_err then return nil, read_err end
            stage=2; return tail
        end
        return nil
    end
    local called, data, request_err, code = pcall(self.request, self, "POST", "/libraries/"..id.."/upload", nil,
        source, #head+size+#tail, "multipart/form-data; boundary="..boundary)
    file:close()
    if not called then return nil, "Upload interrupted; check BookOrbit before retrying", true end
    if data and tonumber(data.bookId) then return data end
    -- Once a POST may have arrived, don't replay automatically: the server may have saved it.
    return nil, request_err or "BookOrbit did not confirm a book ID; check its library",
        code == 0 or code >= 500 or code >= 200 and code < 300
end

return Client
