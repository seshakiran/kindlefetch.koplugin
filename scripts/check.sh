#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
LUA_BIN="${LUA_BIN:-lua}"
LUAC_BIN="${LUAC_BIN:-luac}"
export LUAC_BIN
find . -name '*.lua' -not -path './.git/*' -exec sh -c '
    for file do
        "$LUAC_BIN" -p "$file" || exit 1
    done
' sh {} +
"$LUA_BIN" tests/native_dns_test.lua
"$LUA_BIN" tests/curl_dns_test.lua
"$LUA_BIN" tests/zlib_account_test.lua
