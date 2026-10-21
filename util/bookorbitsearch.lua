-- Optional in-process handoff: no account data or BookOrbit implementation is shared.
local PluginShare = require("pluginshare")
local Bridge = {}

function Bridge.register(search)
    local handler = function(query, context)
        if type(query) ~= "string" then return false end
        query = query:match("^%s*(.-)%s*$"):gsub("%s+", " ")
        if query == "" then return false end
        -- The catalog supplies a completion callback, never service credentials.
        if type(context) ~= "table" or context.kind ~= "bookorbit" or type(context.on_imported) ~= "function" then
            return false
        end
        search(query, context)
        return true
    end
    PluginShare.kindlefetch_search = handler
    PluginShare.kindlefetch_import_api = 1
    return handler
end

function Bridge.unregister(handler)
    if PluginShare.kindlefetch_search == handler then
        PluginShare.kindlefetch_search = nil
        PluginShare.kindlefetch_import_api = nil
    end
end

return Bridge
