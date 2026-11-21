-- Real queue scheduling/worker/persistence path, with no network or credentials.
local now=100000
os.time=function()return now end
local db={config={enabled=true,server_url='https://books.example/api/v1',username='reader',
 library_id=1,access_token='old',refresh_token='refresh-old'},jobs={}}
local saved,connected,scheduled,notices={},false,{},0
package.preload['api.bookorbitstore']=function()return {
 load=function()return db end,
 save=function()local c={};for k,v in pairs(db.config)do c[k]=v end;saved[#saved+1]=c;return true end,
}end
package.preload['libs/libkoreader-lfs']=function()return {attributes=function(_,key)return key=='size' and 10 or 1 end}end
package.preload['ui/network/manager']=function()return {isConnected=function()return connected end}end
package.preload['ui/uimanager']=function()return {}end
package.preload['util.notifyutil']=function()return {info=function()notices=notices+1 end,error=function()end}end
package.preload['util.guard']=function()return {
 quiet=function()end,nextTick=function(_,fn)fn()end,wrap=function(_,fn)return fn end,
 scheduleIn=function(delay,_,fn)scheduled[#scheduled+1]={at=now+delay,fn=fn}end,
}end
local values,serial={},0
package.preload.json=function()return {
 encode=function(v)serial=serial+1;values[tostring(serial)]=v;return tostring(serial)end,
 decode=function(s)return assert(values[s])end,
}end
local during_worker,cancelled
package.preload['ui/trapper']=function()return {
 wrap=function(_,fn)fn()end,
 dismissableRunInSubprocess=function(_,fn,widget)
  widget.dismiss_callback=function()cancelled=true end
  if during_worker then local f=during_worker;during_worker=nil;f()end
  return true,fn()
 end,
}end
local renewals,uploads,mode=0,0,'success'
package.preload['api.bookorbitclient']=function()return {new=function(c)return {
 refresh=function()
  renewals=renewals+1
  if mode=='network' then return nil,'connection failed',0 end
  if mode=='revoked' then return nil,'sign in expired',401 end
  c.access_token='access-'..renewals;c.refresh_token='refresh-'..renewals
  c.session_refreshed_at=now;c.session_reauth_required=nil;c.session_error=nil
  c.session_retry_at=nil;c.session_failures=nil
  return true,nil,200
 end,
 authorized=function()return {}end,
 upload=function()uploads=uploads+1;return {bookId=uploads}end,
}end}end
package.preload['util.filecheck']=function()return {md5=function()return {step=function()return 'hash' end}end}end
local Queue=require('api.bookorbitqueue')
local function advance(seconds)
 now=now+seconds
 local pending=scheduled;scheduled={}
 for _,task in ipairs(pending)do
  if task.at<=now then task.fn()else scheduled[#scheduled+1]=task end
 end
end
Queue.onResume();assert(renewals==0) -- no networking is enabled by this feature
connected=true;Queue.onResume()
assert(renewals==1 and uploads==0 and #db.jobs==0 and not Queue.isActive())
assert(saved[#saved].refresh_token=='refresh-1' and saved[#saved].session_refreshed_at==now)
local timer_count=#scheduled
for _=1,5 do Queue.kick()end
assert(renewals==1 and #scheduled==timer_count)
advance(6*3600);assert(renewals==2 and uploads==0)
connected=false;advance(6*3600);assert(renewals==2)
connected=true;mode='network';Queue.onResume()
assert(renewals==3 and not db.config.session_reauth_required and db.config.session_retry_at==now+30)
Queue.kick();assert(renewals==3)
advance(30);assert(renewals==4 and db.config.session_retry_at==now+60)
mode='success';advance(60)
assert(renewals==5 and not db.config.session_error and not db.config.session_retry_at)
assert(saved[#saved].refresh_token=='refresh-5')
-- A suspended reader must save the rotated token instead of cancelling it.
during_worker=function()Queue.onSuspend()end
cancelled=false;advance(6*3600)
assert(not cancelled and saved[#saved].refresh_token=='refresh-6')
Queue.onResume();assert(renewals==6)
-- Definitively revoked sessions pause renewal; they do not loop or upload.
mode='revoked';advance(6*3600)
assert(renewals==7 and db.config.session_reauth_required and db.config.session_error)
local count=notices
for _=1,4 do Queue.onResume()end
assert(renewals==7 and notices==count)
assert(Queue.enqueue('/books/retained.epub',{title='Retained'},true))
assert(uploads==0 and db.jobs[1].state=='pending')
-- A fresh foreground sign-in unblocks retained files, without downloading.
mode='success';db.config.session_reauth_required=nil;db.config.session_error=nil
db.config.session_refreshed_at=now
Queue.retry(false);assert(uploads==1 and db.jobs[1].state=='uploaded')
-- Disabling auto-uploads also disables idle renewal; explicit imports renew.
db.config.enabled=false;advance(6*3600);assert(renewals==7)
assert(Queue.enqueue('/books/manual.epub',{title='Manual'},true))
assert(renewals==8 and db.jobs[2].state=='uploaded')
-- Never adopt a worker's rotated token into a changed account/destination.
db.config.enabled=true;db.config.session_refreshed_at=0
local token=db.config.refresh_token
during_worker=function()db.config.library_id=2 end
Queue.kick();assert(db.config.refresh_token==token and not Queue.isActive())
print('PASS: idle native-session renewal, saved rotation, bounded retry delays, offline/suspend handling, revoked-session pause, retained uploads, destination binding')
