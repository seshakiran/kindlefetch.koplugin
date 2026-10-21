-- Run from the repository root; all network/account dependencies are mocked.
package.preload['util.dnsutil']=function() return {hostname=function()end} end
package.preload['settings.settings']=function() return {getEncryptedDns=function() return false end} end
local outputs, bodies, calls, secure = {}, {}, 0, false
package.preload['socket.http']=function() return {} end
package.preload['ltn12']=function() return {} end
package.preload['socketutil']=function() return {} end
package.preload['util']=function() return {} end
package.preload['ui/trapper']=function() return {isWrapped=function() return true end,dismissablePopen=function()
 calls=calls+1;return true,table.remove(outputs,1)
end} end
package.preload['util.curlutil']=function() return {
 getErrorMeaning=function(code) return code==6 and 'dns' or 'timeout' end,
 createPageFile=function() return 'page' end,
 fetchCommand=function() return 'mock curl' end,
 canFetch=function() return true end,
 enableSessionEncryptedDns=function() if secure then return false end;secure=true;return true end,
 isTlsFailure=function() return false end,
} end
package.preload['util.fileutil']=function() return {readFile=function() return table.remove(bodies,1) end,removeFile=function() end} end
package.preload['util.logutil']=function() return setmetatable({}, {__index=function() return function(v) return v end end}) end
package.preload['util.proxyutil']=function() return {} end
package.preload['util.errors']=function() return {CANCELLED='cancelled'} end
package.preload['ffi/util']=function() return {template=function(s) return s end} end
package.preload['gettext']=function() return function(s) return s end end
local http=require('util.httputil')
outputs={'000 6','200 0'};bodies={'','{"success":1}'}
local body=http.requestBody('https://z-library.sk/eapi/user/profile',{dns_fallback=true})
assert(body=='{"success":1}' and calls==2 and secure)
outputs={'000 6'};bodies={''}
local err
body,err=http.requestBody('https://z-library.sk/eapi/user/profile',{dns_fallback=true})
assert(body==nil and err=='dns' and calls==3)
secure=false;outputs={'000 28'};bodies={''}
body,err=http.requestBody('https://z-library.sk/eapi/user/login',{dns_fallback=true})
assert(body==nil and err=='timeout' and calls==4 and not secure)
print('PASS: DNS retries once securely; persistent DNS failure stops; timed-out login is not retried')
