-- Confirm BookOrbit acquisition never opens early, double-queues, or fetches a confirmed book twice.
local db={config={server_url='https://books.example/api/v1',access_token='session',library_id=1,enabled=false},jobs={}}
local calls,opened,errors=0,{},{}
local files={}
local watch={}
package.preload['api.bookorbitstore']=function()return {load=function()return db end,save=function()return true end}end
local Queue={destination=function()return db.config.access_token and 'destination' end,kick=function()end}
function Queue.enqueue(path,book,manual,opts)
 assert(manual and opts.origin=='bookorbit' and db.config.enabled==false)
 local job={path=path,target='destination',state='pending',source_id=tostring(book.id),origin=opts.origin,file_type=opts.file_type}
 db.jobs[#db.jobs+1]=job;return true,nil,job
end
function Queue.watch(job,fn)watch[job]=fn;if job.state=='uploaded' then fn(job)end end
package.preload['api.bookorbitqueue']=function()return Queue end
package.preload['api.bookorbitclient']=function()return {normalizeUrl=function(url)return url end}end
package.preload['util.fileutil']=function()return {isValidDirectory=function()return true end,isValidFile=function(path)return files[path]~=nil end,getSize=function(path)return files[path] and 100 or 0 end}end
package.preload['util.filecheck']=function()return {problem=function()return nil end}end
package.preload.datastorage=function()return {getDataDir=function()return '/reader' end}end
package.preload['libs/libkoreader-lfs']=function()return {attributes=function()end}end
package.preload.util=function()return {makePath=function()end,getSafeFilename=function(name)return name end}end
package.preload['util.notifyutil']=function()return {error=function(err)errors[#errors+1]=err end,message=function(err)errors[#errors+1]=err end,info=function()end}end
package.preload['api.downloader']=function()return {downloadForImport=function(_,book,path,done)
 calls=calls+1;files[path]=true;done(true,nil,path)
end}end
local Import=require('api.bookorbitimport')
local context={server_url='https://books.example/api/v1',on_imported=function(job)opened[#opened+1]=job end}
local book={id=42,title='A title',file_type='epub'}
assert(Import.start(book,nil,context));assert(calls==1 and #db.jobs==1 and #opened==0)
local job=db.jobs[1]
job.manual=false
assert(Import.start(book,nil,context));assert(calls==1 and #db.jobs==1)
assert(job.manual==true)
job.state='uploaded';job.book_id=987;watch[job](job)
assert(#opened==1 and opened[1].book_id==987 and opened[1].path==job.path)
assert(Import.start(book,nil,context));assert(calls==1 and #db.jobs==1 and #opened==2)
job.state='uncertain';assert(not Import.start(book,nil,context));assert(calls==1 and #opened==2)
job.state='failed';assert(not Import.start(book,nil,context));assert(calls==1)
-- A book uploaded by 0.9.x can be linked/opened using its existing queue record.
db.jobs={{path='/downloads/Existing.epub',title='Existing',target='destination',state='uploaded',book_id=123,size=100}}
assert(Import.start({id=99,title='Existing',file_type='epub'},'/downloads/Existing.epub',context))
assert(opened[#opened].book_id==123 and calls==1)
context.server_url='https://other.example/api/v1';assert(not Import.start(book,nil,context));assert(calls==1)
context.server_url=db.config.server_url;db.config.access_token=nil
assert(not Import.start(book,nil,context));assert(calls==1 and #errors>=4)
print('PASS: BookOrbit import waits for confirmed upload, retains source identity, reuses pending/old/completed jobs, holds uncertain jobs, validates destination, and works with standalone auto-upload off')
-- Exercise the real prompt-free downloader entry point, including concurrent-download rejection.
local source=assert(io.open('api/downloader.lua','r')):read('*a')
local start=assert(source:find('function Downloader:downloadForImport(',1,true))
local finish=assert(source:find('\n-- each download',start,true))
local actual={active_downloads={},cantDownloadTo=function()end}
local transferred
function actual:_startDownloadInBackground(received,path,callback,retry)
 transferred={book=received,path=path,callback=callback,retry=retry}
end
local env={Downloader=actual,NetworkMgr={runWhenConnected=function(_,fn)fn()end},pairs=pairs,_=function(s)return s end}
local chunk
if setfenv then chunk=assert(loadstring(source:sub(start,finish-1)));setfenv(chunk,env)
else chunk=assert(load(source:sub(start,finish-1),'import downloader','t',env))end
chunk()
actual:downloadForImport(book,'/staging/book.epub',function()end)
assert(transferred.book.bookorbit_import==true and book.bookorbit_import==nil and transferred.book.id==book.id)
assert(transferred.path=='/staging/book.epub' and transferred.retry==false)
transferred=nil;actual.active_downloads[book.id]={}
local rejected
actual:downloadForImport(book,'/staging/book.epub',function(ok,err)rejected=not ok and err end)
assert(rejected and transferred==nil)
print('PASS: dedicated import transfer bypasses regular download flow, marks only its copied book, and prevents concurrent re-downloads')
