#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
LUA_BIN="${LUA_BIN:-lua}"
LUAC_BIN="${LUAC_BIN:-luac}"
export LUAC_BIN
find api cache settings ui updater util tests -name '*.lua' -exec sh -c '
    for file do
        "$LUAC_BIN" -p "$file" || exit 1
    done
' sh {} +
"$LUAC_BIN" -p main.lua kindlefetch.lua safemode.lua _meta.lua
"$LUA_BIN" tests/native_dns_test.lua
"$LUA_BIN" tests/curl_dns_test.lua
"$LUA_BIN" tests/zlib_account_test.lua
"$LUA_BIN" tests/bookorbit_client_test.lua
"$LUA_BIN" tests/bookorbit_queue_test.lua
"$LUA_BIN" tests/bookorbit_store_test.lua
"$LUA_BIN" tests/bookorbit_search_test.lua
