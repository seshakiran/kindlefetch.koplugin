local Store = require("api.bookorbitstore")
local Client = require("api.bookorbitclient")
local FileCheck = require("util.filecheck")
local lfs = require("libs/libkoreader-lfs")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local Guard = require("util.guard")
local Notify = require("util.notifyutil")
local JSON = require("json")
local Queue = {}
local active, initialized, sleeping

local function target(config)
    return table.concat({config.server_url or "",config.username or "",tostring(config.library_id or "")},"\n")
end
local function configured(c)
    return c.server_url and c.access_token and tonumber(c.library_id)
end
function Queue.initialize()
    if initialized then return end
    local store=Store.load()
    if not store then return end
    initialized=true
    for _,job in ipairs(store.jobs) do
        if job.state=="uploading" then
            job.state="uncertain"; job.error="Previous upload interrupted. Check BookOrbit before retrying."
        end
    end
    Store.save()
end

function Queue.enqueue(path,book,manual)
    Queue.initialize()
    local store,err=Store.load()
    if not store then return nil,err end
    if store.config.enabled==false and not manual then return true end
    local size=lfs.attributes(path,"size")
    local modified=lfs.attributes(path,"modification")
    if not size or size<=0 then return nil,"Local book is missing or empty" end
    local destination=configured(store.config) and target(store.config) or nil
    for _,job in ipairs(store.jobs) do
        if job.path==path and job.size==size and job.modified==modified and job.target==destination then
            Queue.kick(); return true
        end
    end
    store.jobs[#store.jobs+1]={path=path,title=book and book.title or path:match("([^/]+)$"),size=size,
        modified=modified,target=destination,state="pending",attempts=0,manual=manual==true}
    local ok; ok,err=Store.save()
    if not ok then return nil,err end
    Queue.kick()
    return true
end

-- Runs only in a child: hash/stream large files without blocking reader input.
function Queue.perform(job,config,history)
    local client=Client.new(config)
    local _,err,code=client:authorized("GET","/auth/me")
    if err then return {error=err,retryable=code==0 or code==429 or code and code>=500,config=config} end
    if lfs.attributes(job.path,"size")~=job.size or lfs.attributes(job.path,"modification")~=job.modified then
        return {error="Local file changed; download it again before uploading",config=config}
    end
    local digest,hash_err=FileCheck.md5(job.path)
    if not digest then return {error=hash_err or "Could not read book",config=config} end
    local hash
    repeat hash,hash_err=digest:step() until hash~=nil
    if not hash then return {error=hash_err or "Could not hash book",config=config} end
    for _,previous in ipairs(history) do
        if previous.state=="uploaded" and previous.target==job.target and previous.hash==hash then
            return {book_id=previous.book_id,hash=hash,duplicate=true,config=config}
        end
    end
    local result,upload_err,uncertain=client:upload(job.path)
    return {book_id=result and result.bookId,hash=hash,error=upload_err,uncertain=uncertain,config=config}
end

function Queue.kick()
    Queue.initialize()
    if active or sleeping or not NetworkMgr:isConnected() then return end
    local store=Store.load()
    if not store or not configured(store.config) then return end
    local now=os.time()
    local job,next_wait
    for _,candidate in ipairs(store.jobs) do
        if candidate.state=="pending" and (store.config.enabled~=false or candidate.manual)
            and (not candidate.target or candidate.target==target(store.config)) then
            if (candidate.next_attempt or 0)<=now then job=candidate; break end
            local wait=candidate.next_attempt-now
            next_wait=next_wait and math.min(next_wait,wait) or wait
        end
    end
    if not job then
        if next_wait then Guard.scheduleIn(math.max(1,next_wait),"retrying BookOrbit queue",Queue.kick,Guard.quiet) end
        return
    end
    job.target=target(store.config); job.state="uploading"; job.attempts=(job.attempts or 0)+1
    if not Store.save() then job.state="pending"; return end
    local config={}
    for k,v in pairs(store.config) do config[k]=v end
    local widget={}
    active={widget=widget,job=job}
    Trapper:wrap(Guard.wrap("uploading to BookOrbit",function()
        local completed,encoded=Trapper:dismissableRunInSubprocess(function()
            local ok,result=pcall(Queue.perform,job,config,store.jobs)
            return JSON.encode(ok and result or {error="Upload worker failed; check BookOrbit before retrying",uncertain=true})
        end,widget,true)
        widget.dismiss_callback=nil
        local decoded,result=pcall(JSON.decode,encoded or "")
        active=nil
        if not completed or not decoded or type(result)~="table" then
            job.state="uncertain"; job.error="Upload interrupted. Check BookOrbit before retrying."
        else
            -- Save a rotated session only when the account/destination did not change meanwhile.
            if result.config and target(store.config)==job.target then
                store.config.access_token=result.config.access_token
                store.config.refresh_token=result.config.refresh_token
            end
            job.hash=result.hash or job.hash; job.error=result.error
            if result.book_id then
                job.book_id=result.book_id; job.state="uploaded"; job.error=nil
                Notify.info("Sent to BookOrbit: "..job.title)
            elseif result.uncertain then job.state="uncertain"
            elseif result.retryable and job.attempts<3 then
                job.state="pending"; job.next_attempt=os.time()+30*2^(job.attempts-1)
            else job.state="failed" end
        end
        if not Store.save() then
            job.state="uncertain"
            Notify.error("Could not save BookOrbit upload status. Check the library before retrying.")
            return
        end
        if job.state=="failed" or job.state=="uncertain" then Notify.info("BookOrbit upload needs attention. Open Kindle Fetch settings → BookOrbit.") end
        Guard.scheduleIn(1,"sending next book to BookOrbit",Queue.kick,Guard.quiet)
    end,function()
        active=nil; job.state="uncertain"; job.error="Upload worker interrupted. Check BookOrbit before retrying."
        Store.save()
    end))
end
function Queue.retry(include_uncertain)
    local store,err=Store.load()
    if not store then return nil,err end
    for _,job in ipairs(store.jobs) do
        if job.state=="failed" or job.state=="pending" or include_uncertain and job.state=="uncertain" then
            job.state="pending"; job.attempts=0; job.next_attempt=nil
        end
    end
    local ok; ok,err=Store.save()
    if ok then Queue.kick() end
    return ok,err
end
function Queue.onSuspend()
    sleeping=true
    if active and active.widget.dismiss_callback then active.widget.dismiss_callback() end
end
function Queue.onResume() sleeping=false; Queue.kick() end
function Queue.stop()
    sleeping=true
    if active and active.widget.dismiss_callback then active.widget.dismiss_callback() end
end
function Queue.isActive() return active~=nil end
return Queue
