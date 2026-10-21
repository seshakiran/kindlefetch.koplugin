local prefix=os.tmpname(); os.remove(prefix)
-- A directory isn't needed: isolate the store's two filenames under /tmp.
package.preload.datastorage=function()return {getSettingsDir=function()return '/tmp' end}end
local original_open,original_rename=io.open,os.rename
local function translate(path)return path:gsub('/tmp/kindlefetch_bookorbit.json',prefix..'-bookorbit.json')end
io.open=function(path,mode)return original_open(translate(path),mode)end
os.rename=function(from,to)return original_rename(translate(from),translate(to))end
local values,count={},0
package.preload.json=function()return {
 encode=function(value)
  count=count+1;local key='serialized-'..count
  local function copy(v) if type(v)~='table' then return v end;local out={};for k,item in pairs(v)do out[k]=copy(item)end;return out end
  values[key]=copy(value);return key
 end,
 decode=function(text)assert(values[text],'malformed');return values[text]end,
}end
local Store=require('api.bookorbitstore')
local data=assert(Store.load());assert(data.config.enabled==true and #data.jobs==0)
data.config.access_token='private-test-session';data.jobs[1]={path='/books/test.epub',state='pending',size=100,modified=1}
assert(Store.save())
package.loaded['api.bookorbitstore']=nil;Store=require('api.bookorbitstore')
local restored=assert(Store.load());assert(restored.jobs[1].state=='pending' and restored.config.access_token=='private-test-session')
local before=assert(io.open('/tmp/kindlefetch_bookorbit.json','r')):read('*a')
os.rename=function()return nil,'disk failure'end
restored.jobs[1].state='uploading';assert(not Store.save())
local f=assert(io.open('/tmp/kindlefetch_bookorbit.json','r'));assert(f:read('*a')==before);f:close()
os.rename=function(from,to)return original_rename(translate(from),translate(to))end
f=assert(io.open('/tmp/kindlefetch_bookorbit.json','w'));f:write('corrupted');f:close()
package.loaded['api.bookorbitstore']=nil;Store=require('api.bookorbitstore')
assert(not Store.load());assert(not Store.save())
io.open=original_open;os.rename=original_rename
os.remove(prefix..'-bookorbit.json');os.remove(prefix..'-bookorbit.json.new')
print('PASS: BookOrbit store persists sessions/jobs, atomic rename failure preserves prior file, corrupt store is not overwritten')
