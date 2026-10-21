local JSON = require("json")
local DataStorage = require("datastorage")
local Store = {}
local cached
local function path() return DataStorage:getSettingsDir() .. "/kindlefetch_bookorbit.json" end
function Store.load()
    if cached then return cached end
    local f,open_err,open_code = io.open(path(), "r")
    if not f then
        if open_code~=2 then return nil,"Could not read BookOrbit settings: "..tostring(open_err) end
        cached={config={enabled=true}, jobs={}}; return cached
    end
    local text=f:read("*a"); f:close()
    local ok, data=pcall(JSON.decode,text)
    if not ok or type(data)~="table" or type(data.config)~="table" or type(data.jobs)~="table" then
        return nil, "BookOrbit settings/queue cannot be read; preserve the file and restore a backup"
    end
    local states={pending=true,uploading=true,uploaded=true,failed=true,uncertain=true}
    for _,job in ipairs(data.jobs) do
        if type(job)~="table" or type(job.path)~="string" or not states[job.state]
            or type(job.size)~="number" or type(job.modified)~="number" then
            return nil,"BookOrbit queue is damaged; preserve the file and restore a backup"
        end
    end
    cached=data
    return cached
end
function Store.save()
    if not cached then return nil, "BookOrbit store not loaded" end
    local ok, text=pcall(JSON.encode,cached)
    if not ok then return nil,"Could not encode BookOrbit settings" end
    local f=io.open(path()..".new","w")
    if not f then return nil,"Could not save BookOrbit settings/queue" end
    pcall(function()
        local ffi=require("ffi")
        ffi.cdef[[int chmod(const char *path, unsigned int mode);]]
        ffi.C.chmod(path()..".new",384)
    end)
    local written=f:write(text); local closed=f:close()
    if not written or not closed then return nil,"Could not save BookOrbit settings/queue" end
    if not os.rename(path()..".new",path()) then return nil,"Could not commit BookOrbit settings/queue" end
    return true
end
return Store
