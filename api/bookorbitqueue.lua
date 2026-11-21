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
local watchers = {}
local SESSION_INTERVAL = 6 * 60 * 60
local session_timer_at
local SESSION_FIELDS = {"access_token", "refresh_token", "session_refreshed_at",
    "session_reauth_required", "session_error", "session_retry_at", "session_failures"}

local function target(config)
    return table.concat({config.server_url or "",config.username or "",tostring(config.library_id or "")},"\n")
end
local function configured(c)
    return c.server_url and c.access_token and tonumber(c.library_id)
end
local function copySession(into, from)
    for _,key in ipairs(SESSION_FIELDS) do into[key] = from[key] end
end
local function armSession(delay)
    local at = os.time() + math.max(1, delay)
    if session_timer_at and session_timer_at <= at then return end
    session_timer_at = at
    Guard.scheduleIn(math.max(1,delay), "renewing BookOrbit session", function()
        if session_timer_at ~= at then return end
        session_timer_at = nil
        Queue.kick()
    end, Guard.quiet)
end

-- Keep a rolling native session alive even between uploads. Use the same
-- worker lock as uploads/account changes, and never turn networking on.
local function renewSession(store)
    local destination = target(store.config)
    local config = {}
    for k,v in pairs(store.config) do config[k] = v end
    local widget = {}
    active = {kind="session", widget=widget}
    local function failed(error_text, code)
        store.config.session_error = error_text
        if code == 401 or code == 403 then
            if not store.config.session_reauth_required then
                Notify.info("BookOrbit session was revoked or expired. Sign in again under Kindle Fetch → Settings → BookOrbit uploads.")
            end
            store.config.session_reauth_required = true
        else
            local n = (store.config.session_failures or 0) + 1
            store.config.session_failures = n
            local delay = n <= 3 and 30 * 2^(n-1) or 3600
            store.config.session_retry_at = os.time() + delay
            armSession(delay)
        end
    end
    Trapper:wrap(Guard.wrap("renewing BookOrbit login",function()
        local completed,encoded = Trapper:dismissableRunInSubprocess(function()
            local ok,result,err,code = pcall(function()
                local refreshed,refresh_err,refresh_code = Client.new(config):refresh()
                return refreshed,refresh_err,refresh_code
            end)
            return JSON.encode({ok=ok and result or false, error=ok and err or "BookOrbit session renewal interrupted",
                code=ok and code or 0, config=config})
        end,widget,true)
        widget.dismiss_callback = nil
        active = nil
        if target(store.config) ~= destination then return end
        local decoded,result = pcall(JSON.decode,encoded or "")
        if completed and decoded and type(result)=="table" and result.ok then
            copySession(store.config,result.config)
        else
            failed(completed and decoded and type(result)=="table" and result.error or "BookOrbit session renewal interrupted",
                completed and decoded and type(result)=="table" and result.code or 0)
        end
        if not Store.save() then
            Notify.error("Could not save renewed BookOrbit login. Keep KOReader open and check storage before restarting.")
            return
        end
        if not store.config.session_reauth_required and not store.config.session_retry_at then
            Guard.nextTick("resuming BookOrbit uploads",Queue.kick,Guard.quiet)
        end
    end,function()
        active=nil
        if target(store.config)==destination then
            failed("BookOrbit session renewal interrupted",0)
            Store.save()
        end
    end))
end
function Queue.destination()
    local store = Store.load()
    return store and configured(store.config) and target(store.config) or nil
end
local function announce(job)
    local callback = watchers[job]
    if not callback then return end
    if job.state == "uploaded" then watchers[job] = nil end
    Guard.nextTick("finishing BookOrbit import", function() callback(job) end, Guard.quiet)
end
function Queue.watch(job, callback)
    watchers[job] = callback
    if job.state == "uploaded" or job.state == "failed" or job.state == "uncertain" then announce(job) end
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

function Queue.enqueue(path,book,manual,opts)
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
            Queue.kick(); return true,nil,job
        end
    end
    opts = opts or {}
    local job={path=path,title=book and book.title or path:match("([^/]+)$"),size=size,
        modified=modified,target=destination,state="pending",attempts=0,manual=manual==true,
        origin=opts.origin,source_id=opts.source_id or book and book.id and tostring(book.id),
        file_type=opts.file_type or book and book.file_type}
    store.jobs[#store.jobs+1]=job
    local ok; ok,err=Store.save()
    if not ok then return nil,err end
    Queue.kick()
    return true,nil,job
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
    -- Explicit imports still renew when automatic uploads are switched off.
    if store.config.refresh_token and (store.config.enabled~=false or job) then
        if store.config.session_reauth_required then return end
        local due = store.config.session_retry_at or
            ((tonumber(store.config.session_refreshed_at) or 0) + SESSION_INTERVAL)
        if due <= now then renewSession(store); return end
        armSession(due-now)
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
                copySession(store.config,result.config)
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
        if job.state=="uploaded" or job.state=="failed" or job.state=="uncertain" then announce(job) end
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
    -- Let a short token rotation finish so its replacement token can be saved.
    if active and active.kind~="session" and active.widget.dismiss_callback then active.widget.dismiss_callback() end
end
function Queue.onResume() sleeping=false; Queue.kick() end
function Queue.stop()
    sleeping=true
    if active and active.widget.dismiss_callback then active.widget.dismiss_callback() end
end
function Queue.isActive() return active~=nil end
return Queue
