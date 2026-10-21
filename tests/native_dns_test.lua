-- Run from the repository root; all network/account dependencies are mocked.
local fixture={Status=0,Answer={{name='z-library.sk.',type=5,data='edge.example.',TTL=120},{name='edge.example.',type=1,data='203.0.113.20',TTL=60}}}
package.preload.json=function() return {decode=function(s) if s=='invalid' then error('bad json') end return fixture end} end
local methods={connect=function(_,target) return target end,close=function()end}
local connect=methods.connect
package.preload.socket=function() return {tcp=function()return setmetatable({},{__index=methods})end} end
local dns=require('util.dnsutil')
local lookups=0
local function fetch(url)lookups=lookups+1;assert(url:find('https://1.1.1.1/',1,true));return 'answer',nil,200 end
assert(dns.resolve('z-library.sk',fetch)=='203.0.113.20')
assert(dns.resolve('z-library.sk',fetch)=='203.0.113.20' and lookups==1)
fixture={Status=0,Answer={{name='unrelated.example',type=1,data='203.0.113.30',TTL=30}}}
assert(dns.resolve('not-in-answer.example',fetch)==nil)
fixture={Status=0,Answer={{name='bad-ip.example',type=1,data='256.1.1.1',TTL=30}}}
assert(dns.resolve('bad-ip.example',fetch)==nil)
assert(dns.resolve('bad host',fetch)==nil)
assert(dns.resolve('invalid-json.example',function()return 'invalid',nil,200 end)==nil)
local a,err=dns.resolve('cancel.example',function()return nil,'cancelled' end)
assert(a==nil and err=='cancelled')
local socketutil={block_timeout=5,total_timeout=15,set_timeout=function(self,b,t)self.block_timeout=b;self.total_timeout=t end,reset_timeout=function(self)self.block_timeout=60;self.total_timeout=-1 end,table_sink=function(t)return function(s)if s then t[#t+1]=s end return 1 end end}
local resolver_calls=0
local http={request=function(opts)
 if opts.url:find('https://1.1.1.1/',1,true) then
  resolver_calls=resolver_calls+1
  assert(opts.headers.Accept=='application/dns-json' and opts.source==nil and opts.headers.Cookie==nil)
  opts.sink('answer'); return 1,200,{}
 end
 assert(opts.url=='https://native-only.example/api')
 assert(socketutil.block_timeout==5 and socketutil.total_timeout==15)
 assert(require('socket').tcp():connect('native-only.example',443)=='203.0.113.40')
 opts.sink('API response');return 1,200,{}
end}
package.preload['socket.http']=function()return http end
package.preload.ltn12=function()return {}end
package.preload.socketutil=function()return socketutil end
package.preload.util=function()return {}end
package.preload['ui/trapper']=function()return {}end
package.preload['util.curlutil']=function()return {canFetch=function()return false end,getErrorMeaning=function(c)return c==6 and 'dns' or 'error'end,exitCodeFor=function()end}end
package.preload['util.fileutil']=function()return {}end
package.preload['util.logutil']=function()return setmetatable({},{__index=function()return function(s)return s end end})end
package.preload['util.proxyutil']=function()return {get=function()end}end
package.preload['util.errors']=function()return {CANCELLED='cancelled'}end
package.preload['settings.settings']=function()return {getEncryptedDns=function()return true end}end
package.preload['ffi/util']=function()return {template=function(s)return s end}end
package.preload.gettext=function()return function(s)return s end end
fixture={Status=0,Answer={{name='native-only.example',type=1,data='203.0.113.40',TTL=60}}}
local util=require('util.httputil')
local body=util.getBody('https://native-only.example/api',{answer_timeout=5,page_timeout=15,dns_fallback=true})
assert(body=='API response' and resolver_calls==1 and methods.connect==connect)
body=util.getBody('https://native-only.example/api',{answer_timeout=5,page_timeout=15,dns_fallback=true})
assert(body=='API response' and resolver_calls==1 and methods.connect==connect)
print('PASS: native HTTP without curl; secure DNS bootstrap, no credential forwarding, CNAME validation, cache, malformed answers, cancellation, timeout restoration, TCP restoration')
local before_sources={}
local sent={}
require('ltn12').source={string=function(value)
 local used=false
 return function()if not used then used=true;return value end end
end}
require('util').urlEncode=function(value)return value end
local old_http=http.request
local attempts=0
http.request=function(opts)
 if opts.url:find('https://1.1.1.1/',1,true) then return old_http(opts) end
 attempts=attempts+1
 before_sources[#before_sources+1]=opts.source
 sent[#sent+1]=opts.source()
 if attempts==1 then opts.sink('partial response');return nil,'Software caused connection abort' end
 opts.sink('complete search response');return 1,200,{}
end
local recovered=util.getBody('https://native-only.example/api',{form={{'message','author'}},answer_timeout=5,page_timeout=15,dns_fallback=true,retry_connection_abort=true})
assert(recovered=='complete search response' and attempts==2)
assert(before_sources[1]~=before_sources[2] and sent[1]==sent[2])
assert(resolver_calls==2,'DNS must be refreshed after abort')
attempts=0
http.request=function(opts)
 if opts.url:find('https://1.1.1.1/',1,true) then return old_http(opts) end
 attempts=attempts+1;return nil,'Software caused connection abort'
end
local failed=util.getBody('https://native-only.example/api',{answer_timeout=5,page_timeout=15,dns_fallback=true,retry_connection_abort=true})
assert(failed==nil and attempts==2,'Retry must stop after second abort')
attempts=0
failed=util.getBody('https://native-only.example/api',{answer_timeout=5,page_timeout=15,dns_fallback=true})
assert(failed==nil and attempts==1,'Login/file requests must not be replayed')
print('PASS: aborted search recovers once with fresh DNS/form/sink; repeated abort stops; other operations are not retried')
