local db={config={enabled=true,server_url='https://books.example/api/v1',username='reader',library_id=1,access_token='session'},jobs={}}
local saves,connected,scheduled=0,false,{}
local save_ok=true
package.preload['api.bookorbitstore']=function() return {load=function() return db end,save=function() saves=saves+1; return save_ok end} end
local files={['/books/one.epub']={size=100,modification=1},['/books/copy.epub']={size=100,modification=2}}
package.preload['libs/libkoreader-lfs']=function()return {attributes=function(path,name) return files[path] and files[path][name] end}end
package.preload['ui/network/manager']=function()return {isConnected=function()return connected end}end
package.preload['ui/uimanager']=function()return {}end
package.preload['util.notifyutil']=function()return {info=function()end,error=function()end}end
package.preload['util.guard']=function()return {quiet=function()end,nextTick=function(_,fn)fn()end,wrap=function(_,fn)return fn end,scheduleIn=function(delay,_,fn)scheduled[#scheduled+1]={delay,fn}end}end
local encoded
package.preload.json=function()return {encode=function(v)encoded=v;return 'json' end,decode=function()return encoded end}end
package.preload['ui/trapper']=function()return {wrap=function(_,fn)fn()end,dismissableRunInSubprocess=function(_,fn)return true,fn()end}end
local upload_calls=0
local preflight_error
package.preload['api.bookorbitclient']=function()return {new=function(config)return {
 authorized=function()if preflight_error then return nil,'offline',0 end; return {} end,
 upload=function() upload_calls=upload_calls+1; return {bookId=77} end,
}end}end
package.preload['util.filecheck']=function()return {md5=function()return {step=function()return 'same-content-hash' end}end}end
local Queue=require('api.bookorbitqueue')
assert(Queue.enqueue('/books/one.epub',{title='One'})); assert(#db.jobs==1 and db.jobs[1].state=='pending')
Queue.enqueue('/books/one.epub',{title='One'}); assert(#db.jobs==1)
assert(not Queue.enqueue('/books/missing.epub',{}))
connected=true; Queue.kick(); assert(db.jobs[1].state=='uploaded' and upload_calls==1 and db.jobs[1].book_id==77)
Queue.enqueue('/books/copy.epub',{title='Copy'}); assert(db.jobs[2].state=='uploaded' and upload_calls==1)
files['/books/three.epub']={size=200,modification=3}
preflight_error=true; Queue.enqueue('/books/three.epub',{}); assert(db.jobs[3].state=='pending' and db.jobs[3].attempts==1 and db.jobs[3].next_attempt)
db.jobs[3].next_attempt=0; Queue.kick(); db.jobs[3].next_attempt=0; Queue.kick(); assert(db.jobs[3].state=='failed' and db.jobs[3].attempts==3)
preflight_error=false
local old_perform=Queue.perform
Queue.perform=function()return {error='lost reply',uncertain=true}end
Queue.retry(false); assert(db.jobs[3].state=='uncertain')
Queue.retry(false); assert(db.jobs[3].state=='uncertain')
Queue.perform=old_perform; Queue.retry(true); assert(db.jobs[3].state=='uploaded')
db.config.enabled=false
files['/books/four.epub']={size=100,modification=4}; Queue.enqueue('/books/four.epub',{}); assert(#db.jobs==3)
db.config.enabled=true; connected=false
Queue.enqueue('/books/four.epub',{}); db.config.library_id=2; connected=true; Queue.kick(); assert(db.jobs[4].state=='pending')
db.config.library_id=1; save_ok=false; Queue.kick(); assert(db.jobs[4].state=='pending' and not Queue.isActive())
save_ok=true
local notified=0
Queue.watch(db.jobs[4],function(job)assert(job.state=='uploaded' and job.book_id);notified=notified+1 end)
assert(notified==0)
Queue.kick();assert(notified==1)
Queue.kick();assert(notified==1)
assert(saves>0)
print('PASS: BookOrbit durable queue, offline retention, duplicate hashes, bounded safe retries, uncertain uploads held, destination binding, failed persistence blocks upload')
