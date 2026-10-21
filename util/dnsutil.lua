local JSON = require("json")

local DnsUtil = {}
local cached = {}
local unpackValues = unpack or table.unpack

local function ipv4(value)
    if type(value) ~= "string" then return false end
    local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    return a and tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255
end

function DnsUtil.hostname(url)
    return type(url) == "string" and url:match("^https?://([%w%.%-]+)[:/]?") or nil
end

function DnsUtil.isAddress(host)
    return ipv4(host) or (type(host) == "string" and host:find(":", 1, true) ~= nil)
end

function DnsUtil.forget(host)
    if type(host) == "string" then cached[host:lower()] = nil end
end

-- fetch is supplied by HTTP so this module does not depend on either HTTP implementation.
-- The resolver URL is an IP literal: it never needs the device's broken hostname lookup.
function DnsUtil.resolve(host, fetch)
    if type(host) ~= "string" or #host > 253 or not host:match("^[%w%.%-]+$") then
        return nil, "invalid DNS hostname"
    end
    host = host:lower()
    if ipv4(host) then return host end
    local entry = cached[host]
    if entry and os.time() < entry.expires then return entry.address end
    local body, err, status = fetch("https://1.1.1.1/dns-query?name=" .. host .. "&type=A")
    if not body or status ~= 200 then
        return nil, err or ("encrypted DNS lookup failed: " .. tostring(status or "no response"))
    end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" or data.Status ~= 0 or type(data.Answer) ~= "table" then
        return nil, "encrypted DNS returned no usable answer for " .. host
    end
    local ttl = 300
    for _, record in ipairs(data.Answer) do
        if type(record) == "table" and tonumber(record.TTL) then
            ttl = math.min(ttl, math.max(0, tonumber(record.TTL)))
        end
    end
    local names = { [host] = true }
    for _ = 1, 8 do
        for _, record in ipairs(data.Answer) do
            if type(record) == "table" and type(record.name) == "string" and names[record.name:lower():gsub("%.$", "")] then
                if record.type == 5 and type(record.data) == "string" then
                    names[record.data:lower():gsub("%.$", "")] = true
                elseif record.type == 1 and ipv4(record.data) then
                    cached[host] = { address = record.data, expires = os.time() + ttl }
                    return record.data
                end
            end
        end
    end
    return nil, "encrypted DNS returned no IPv4 address for " .. host
end

-- LuaSec's connector receives the original hostname for TLS/SNI. Substitute only
-- its underlying TCP connect address, and restore the shared method before returning.
-- fn must be synchronous (LuaSocket HTTP is); no coroutine may yield in this scope.
function DnsUtil.withAddress(host, address, fn)
    assert(ipv4(address), "invalid resolved address")
    local socket = require("socket")
    local probe = assert(socket.tcp())
    local methods = getmetatable(probe).__index
    local connect = methods.connect
    probe:close()
    methods.connect = function(sock, target, port, ...)
        if type(target) == "string" and target:lower() == host:lower() then target = address end
        return connect(sock, target, port, ...)
    end
    local results = { pcall(fn) }
    methods.connect = connect
    if not results[1] then error(results[2], 0) end
    return unpackValues(results, 2, 5)
end

return DnsUtil
