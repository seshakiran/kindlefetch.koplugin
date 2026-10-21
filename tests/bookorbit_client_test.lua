-- Exercise the real multipart stream and native session protocol; no accounts or external network.
local values,serial={},0
package.preload.json=function() return {
 encode=function(v) serial=serial+1; local key='json'..serial; values[key]=v; return key end,
 decode=function(v) assert(values[v], 'invalid json'); return values[v] end,
} end
local json=require('json')
package.preload.ltn12=function() return {source={string=function(value)
 local sent=false; return function() if not sent then sent=true; return value end end
end}} end
local timeout={block_timeout=17,total_timeout=29}
function timeout:set_timeout(a,b) self.block_timeout=a; self.total_timeout=b end
package.preload.socketutil=function() return timeout end
local responses,requests={},{}
package.preload['socket.http']=function() return {request=function(opts)
 assert(opts.redirect==false and opts.headers.Cookie==nil and opts.headers['x-auth-key']==nil)
 local body=''
 if opts.source then while true do local chunk,err=opts.source(); assert(not err); if not chunk then break end; body=body..chunk end end
 requests[#requests+1]={opts=opts,body=body}
 local response=table.remove(responses,1); assert(response,'unexpected request')
 if response.raise then error('transport failure') end
 if response.network then return nil,'aborted' end
 opts.sink(response.raw or json.encode(response.data)); return 1,response.code
end} end
local Client=require('api.bookorbitclient')
assert(Client.normalizeUrl('https://books.example/')=='https://books.example/api/v1')
assert(Client.normalizeUrl('http://100.64.1.2:3000/api/v1')=='http://100.64.1.2:3000/api/v1')
assert(not Client.normalizeUrl('http://public.example'))
assert(not Client.normalizeUrl('https://user:pass@books.example'))
assert(not Client.normalizeUrl('https://books.example/#fragment'))
local client=Client.new({server_url='https://books.example/api/v1'})
responses={{code=200,data={accessToken='access-one',refreshToken='refresh-one'}}}
assert(client:login('test-user','test-password'))
local login=values[requests[1].body]
assert(login.clientKind=='native' and login.username=='test-user' and login.password=='test-password')
assert(client.config.password==nil and client.config.access_token=='access-one')
responses={{code=401,data={}},{code=200,data={accessToken='access-two',refreshToken='refresh-two'}},
 {code=200,data={{id=1,name='Books',type='books'},{id=2,name='Podcasts',type='podcasts'}}}}
local libraries=assert(client:libraries()); assert(#libraries==1 and libraries[1].id==1)
assert(client.config.refresh_token=='refresh-two' and requests[4].opts.headers.Authorization=='Bearer access-two')
local path=os.tmpname()..'.epub'; local f=assert(io.open(path,'wb')); f:write('PK\3\4',string.rep('book-content',20000)); f:close()
client.config.library_id=1
responses={{code=201,data={bookId=123}}}
local uploaded=assert(client:upload(path)); assert(uploaded.bookId==123)
local upload=requests[#requests]
assert(upload.opts.url=='https://books.example/api/v1/libraries/1/upload')
assert(tonumber(upload.opts.headers['Content-Length'])==#upload.body)
assert(upload.body:find('name="file"',1,true) and upload.body:find('PK\3\4',1,true))
assert(upload.body:match('\r\n%-%-[^\r]+%-%-\r\n$'))
responses={{network=true}}
local result,err,uncertain=client:upload(path); assert(not result and uncertain)
responses={{code=409,data={message='private server details'}}}
result,err,uncertain=client:upload(path); assert(not result and not uncertain and not err:find('private server',1,true))
responses={{code=200,raw='<html>sign-in page</html>'}}
result,err,uncertain=client:upload(path); assert(not result and err and uncertain==true)
responses={{raise=true}}
assert(not client:request('GET','/auth/me'))
assert(timeout.block_timeout==17 and timeout.total_timeout==29)
os.remove(path)
print('PASS: BookOrbit native login/rotation, origin restrictions, streamed multipart bytes/length, response/error handling, timeout restoration')
