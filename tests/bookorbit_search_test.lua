local shared = {}
package.preload.pluginshare = function() return shared end
local Bridge = require("util.bookorbitsearch")
local queries = {}
local first = Bridge.register(function(query) queries[#queries + 1] = query end)
assert(shared.kindlefetch_search == first)
assert(not first(nil) and not first({}) and not first(" \n "))
assert(#queries == 0)
assert(first("  Ursula\n  Le Guin  ") and queries[1] == "Ursula Le Guin")
local second = Bridge.register(function(query) queries[#queries + 1] = "new:" .. query end)
Bridge.unregister(first)
assert(shared.kindlefetch_search == second)
assert(shared.kindlefetch_search("Author") and queries[2] == "new:Author")
Bridge.unregister(second)
assert(shared.kindlefetch_search == nil)
print("PASS: BookOrbit search handoff validates/normalizes queries and unregisters only its owning reader instance")
