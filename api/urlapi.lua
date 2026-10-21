-- This build uses the user's chosen Z-Library domain directly. There is no
-- Wikipedia lookup, mirror rotation, or dependency on addresses cached by older builds.
local UrlApi = {}
local ZLIB_URL = "https://z-library.sk"

function UrlApi:getZlibUrls()
    return { ZLIB_URL }
end

function UrlApi:peekZlibUrls()
    return { ZLIB_URL }
end

-- Compatibility with the account request interface; one fixed domain has no ordering to save.
function UrlApi:preferZlibUrl() end
function UrlApi:deleteZlibUrl() end
function UrlApi:restZlibUrl() end

return UrlApi
