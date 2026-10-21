local shared = {}
package.preload.pluginshare = function() return shared end
local Bridge = require("util.bookorbitsearch")
local queries = {}
local context = {kind="bookorbit",server_url="https://books.example/api/v1",on_imported=function()end}
local first = Bridge.register(function(query,received) assert(received==context);queries[#queries + 1] = query end)
assert(shared.kindlefetch_search == first)
assert(shared.kindlefetch_import_api == 1)
assert(not first(nil) and not first({}) and not first(" \n "))
assert(#queries == 0)
assert(not first("A title") and not first("A title",{}))
assert(first("  Ursula\n  Le Guin  ",context) and queries[1] == "Ursula Le Guin")
local second = Bridge.register(function(query) queries[#queries + 1] = "new:" .. query end)
Bridge.unregister(first)
assert(shared.kindlefetch_search == second)
assert(shared.kindlefetch_search("Author",context) and queries[2] == "new:Author")
Bridge.unregister(second)
assert(shared.kindlefetch_search == nil)
assert(shared.kindlefetch_import_api == nil)
print("PASS: BookOrbit search handoff validates/normalizes queries and unregisters only its owning reader instance")
