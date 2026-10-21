-- Run from the repository root; all network/account dependencies are mocked.
local requests = 0
local answer, failure, cancelled
local opts_seen
local settings = {getZlibAccount=function() return {user_id=1,user_key='key'} end,setZlibAccount=function() cancelled=true end}
local http = {CANCELLED='cancelled',UNRESOLVED='dns',sayStatus=function() end,getBody=function(url,opts)
 requests=requests+1; opts_seen=opts
 assert(url=='https://z-library.sk/eapi/user/profile')
 return answer,failure, answer and 200 or nil
end}
package.preload['json']=function() return {decode=function(body) return body end} end
package.preload['util.httputil']=function() return http end
package.preload['util.curlutil']=function() return {} end
package.preload['cache.urlcache']=function() return setmetatable({}, {__index=function() error('Unexpected mirror cache access') end}) end
package.preload['settings.settings']=function() return settings end
package.preload['util.logutil']=function() return setmetatable({}, {__index=function() return function(v) return v end end}) end
package.preload['util.errors']=function() return {LOGGED_OUT='logged out'} end
package.preload['ffi/util']=function() return {template=function(s) return s end} end
package.preload['gettext']=function() return function(s) return s end end
local urls=require('api.urlapi')
assert(#urls:getZlibUrls()==1 and urls:getZlibUrls()[1]=='https://z-library.sk')
assert(#urls:getZlibUrls(true)==1 and #urls:peekZlibUrls()==1)
local account=require('api.zlibaccount')
failure='timeout'
assert(account:request('/eapi/user/profile')==nil and requests==1)
assert(opts_seen.answer_timeout==5 and opts_seen.page_timeout==15 and opts_seen.dns_fallback)
failure='cancelled'
local data,err=account:request('/eapi/user/profile')
assert(data==nil and err=='cancelled' and requests==2)
answer={success=1,user={id=1}};failure=nil
assert(account:request('/eapi/user/profile')==answer and requests==3)
answer={success=0,error='Please login'}
data,err=account:request('/eapi/user/profile')
assert(data==nil and err=='logged out' and cancelled)
package.preload['api.zlibsearch']=function() return {NAME='Z-Library'} end
local sources=require('api.sources')
local count=0
for key in pairs(sources) do assert(key=='zlib');count=count+1 end
assert(count==1)
print('PASS: Z-Library-only registry, no discovery/cache, single request on failure, timeout options, cancel, success, expired login')
