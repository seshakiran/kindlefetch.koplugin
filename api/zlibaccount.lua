local JSON = require("json")
local HttpUtil = require("util.httputil")
local LogUtil = require("util.logutil")
local KindleFetchSettings = require("settings.settings")
local UrlApi = require("api.urlapi")
local Errors = require("util.errors")
local T = require("ffi/util").template
local _ = require("gettext")

-- the Z-Library account Kindle Fetch is logged into, as Z-Library only lets those logged in search for and
-- download books, and asking it about the account, through the API its own app uses
local ZlibAccount = {
    -- when Z-Library no longer accepts the account's key (see Errors)
    LOGGED_OUT_ERROR = Errors.LOGGED_OUT,
}

function ZlibAccount:isLoggedIn()
    return KindleFetchSettings:getZlibAccount() ~= nil
end

-- the email of the account logged into, if there is one
function ZlibAccount:getEmail()
    local account = KindleFetchSettings:getZlibAccount()
    return account and account.email
end

-- what Z-Library's API answered, as the account logged into, or nil and what went wrong. forgets the account once
-- Z-Library no longer accepts it
local function readAnswer(self, data, path, account)
    if data.success ~= 1 and data.success ~= true then
        local message = type(data.error) == "string" and data.error ~= "" and data.error or nil
        LogUtil.warn("Z-Library answered", path, "with an error:", message or "none given")
        -- "Please login", once the key no longer logs into the account, or when it was logged out of
        if message and message:lower():find("login", 1, true) then
            if account then
                KindleFetchSettings:setZlibAccount(nil)
            end
            return nil, self.LOGGED_OUT_ERROR
        end
        return nil, message and T(_("Z-Library says: %1"), message) or _("unexpected response from Z-Library")
    end
    return data
end

-- Ask the configured domain once. HTTP may retry a DNS failure once using encrypted DNS;
-- there is no mirror discovery or repeated login attempt after an HTTP response.
function ZlibAccount:request(path, form)
    local url = UrlApi:getZlibUrls()[1]
    local account = KindleFetchSettings:getZlibAccount()
    local cookies = account and string.format("remix_userid=%s; remix_userkey=%s", account.user_id, account.user_key)
    HttpUtil.sayStatus(T(_("Connecting to %1..."), LogUtil.site(url)))
    local body, err, status = HttpUtil.getBody(url .. path, {
        form = form,
        cookies = cookies or "",
        answer_timeout = 5,
        page_timeout = 15,
        dns_fallback = true,
        -- Search has no download/account side effects and can safely recover once from an aborted socket.
        retry_connection_abort = path == "/eapi/book/search",
    })
    if err == HttpUtil.CANCELLED then
        return nil, err
    end
    if not body then
        if err == HttpUtil.UNRESOLVED then
            return nil, _("Could not resolve z-library.sk. Check Wi-Fi or run Kindle Fetch Diagnostics → Test connection.")
        end
        return nil, T(_("Could not connect to z-library.sk: %1"), tostring(err or status or _("no response")))
    end
    local ok, data = pcall(JSON.decode, body)
    if ok and type(data) == "table" then
        return readAnswer(self, data, path, account)
    end
    LogUtil.warn("Z-Library API did not return JSON for", path, "HTTP", status)
    if status and status >= 400 then
        return nil, T(_("z-library.sk returned HTTP %1. Try again later or check the site in your browser."), status)
    end
    return nil, _("z-library.sk returned a web page instead of its API. It may require a browser check; login could not be completed.")
end

-- log into the account with the email and password, keeping the user id and key Z-Library answers with rather than
-- the password. returns whether it logged in, and why not
function ZlibAccount:login(email, password)
    local data, err = self:request("/eapi/user/login", {
        { "email", email },
        { "password", password },
    })
    if not data then
        return false, err
    end

    local user = type(data.user) == "table" and data.user or {}
    local user_id, user_key = tonumber(user.id), user.remix_userkey
    -- the key is sent to curl in a cookie, so it's only ever letters and digits
    if not (user_id and type(user_key) == "string" and user_key:find("^%w+$")) then
        LogUtil.warn("Z-Library's answer to logging in didn't say how to log in")
        return false, _("unexpected response from Z-Library")
    end
    KindleFetchSettings:setZlibAccount({
        email = email,
        user_id = user_id,
        user_key = user_key,
    })
    LogUtil.info("logged in to Z-Library")
    return true
end

function ZlibAccount:logout()
    KindleFetchSettings:setZlibAccount(nil)
    LogUtil.info("logged out of Z-Library")
end

return ZlibAccount
