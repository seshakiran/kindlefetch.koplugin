-- Optional in-process handoff: no account data or BookOrbit implementation is shared.
local PluginShare = require("pluginshare")
local Bridge = {}

function Bridge.register(search)
    local handler = function(query)
        if type(query) ~= "string" then return false end
        query = query:match("^%s*(.-)%s*$"):gsub("%s+", " ")
        if query == "" then return false end
        search(query)
        return true
    end
    PluginShare.kindlefetch_search = handler
    return handler
end

function Bridge.unregister(handler)
    if PluginShare.kindlefetch_search == handler then
        PluginShare.kindlefetch_search = nil
    end
end

return Bridge
