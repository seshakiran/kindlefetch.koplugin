local UIManager=require("ui/uimanager")
local MultiInputDialog=require("ui/widget/multiinputdialog")
local Menu=require("ui/widget/menu")
local ConfirmBox=require("ui/widget/confirmbox")
local Screen=require("device").screen
local Trapper=require("ui/trapper")
local NetworkMgr=require("ui/network/manager")
local Store=require("api.bookorbitstore")
local Client=require("api.bookorbitclient")
local Queue=require("api.bookorbitqueue")
local JSON=require("json")
local Notify=require("util.notifyutil")
local Guard=require("util.guard")
local WaitingMessage=require("ui.waitingmessage")
local UI={}
local function save()
    local ok,err=Store.save()
    if not ok then Notify.error(err) end
    return ok
end
local function run(message,fn,done)
    NetworkMgr:runWhenConnected(function()
        local widget
        local function closeWidget()
            if widget and not widget.closed then UIManager:close(widget); widget.closed=true end
        end
        Trapper:wrap(Guard.wrap("connecting to BookOrbit",function()
            widget=WaitingMessage.new(message)
            UIManager:show(widget); UIManager:forceRePaint()
            local completed,encoded=Trapper:dismissableRunInSubprocess(function()
                local ok,data,err=pcall(fn)
                return JSON.encode({data=ok and data or nil,error=ok and err or "BookOrbit request failed"})
            end,widget,true)
            closeWidget()
            local ok,result=pcall(JSON.decode,encoded or "")
            if not completed then return end
            if not ok or not result.data then Notify.error(ok and result.error or "BookOrbit returned an unreadable response"); return end
            done(result.data)
        end,function(err) closeWidget(); Notify.error(err) end))
    end)
end
function UI.login()
    if Queue.isActive() then Notify.info("Wait for the current BookOrbit upload to finish"); return end
    local store,err=Store.load()
    if not store then Notify.error(err); return end
    local existing=G_reader_settings and G_reader_settings:readSetting("bookorbit") or {}
    local dialog
    dialog=MultiInputDialog:new{
        title="Sign in to BookOrbit for uploads",
        fields={{text=store.config.server_url or existing and existing.server_url or "",hint="BookOrbit server URL"},
            {text=store.config.username or "",hint="Website username (not sync username)"},
            {text="",hint="Website password",text_type="password"}},
        buttons={{{text="Cancel",id="close",callback=function() UIManager:close(dialog) end},
            {text="Sign in",is_enter_default=true,callback=function()
                local fields=dialog:getFields()
                local url=Client.normalizeUrl(fields[1])
                if not url or fields[2]=="" or fields[3]=="" then
                    Notify.info("Enter an HTTPS or private LAN/Tailscale URL and your BookOrbit website login"); return
                end
                UIManager:close(dialog)
                local config={server_url=url,enabled=store.config.enabled~=false}
                run("Signing in to BookOrbit...",function() return Client.new(config):login(fields[2],fields[3]) end,function(result)
                    -- Preserve the selected library only when signing back into the same account/server.
                    if store.config.server_url==result.server_url and store.config.username==result.username then
                        result.library_id=store.config.library_id; result.library_name=store.config.library_name
                    end
                    store.config=result
                    if save() then UI.chooseLibrary() end
                end)
            end}}},
    }
    UIManager:show(dialog); dialog:onShowKeyboard()
end
function UI.chooseLibrary()
    if Queue.isActive() then Notify.info("Wait for the current BookOrbit upload to finish"); return end
    local store,err=Store.load()
    if not store then Notify.error(err); return end
    if not store.config.access_token then UI.login(); return end
    run("Loading BookOrbit libraries...",function()
        local client=Client.new(store.config)
        local libraries,request_err=client:libraries()
        if not libraries then return nil,request_err end
        return {libraries=libraries,config=client.config}
    end,function(result)
        store.config=result.config
        if not save() then return end
        local menu,items
        items={}
        for _,library in ipairs(result.libraries) do
            local chosen=library
            items[#items+1]={text=chosen.name,callback=function()
                store.config.library_id=chosen.id; store.config.library_name=chosen.name
                UIManager:close(menu)
                if save() then Queue.retry(false); UI.show() end
            end}
        end
        if #items==0 then Notify.error("No book libraries are available to this account"); return end
        local size=Screen:getSize()
        menu=Menu:new{title="Upload to BookOrbit library",item_table=items,width=size.w,height=size.h,covers_fullscreen=true}
        UIManager:show(menu)
    end)
end
function UI.show()
    Queue.initialize()
    local store,err=Store.load()
    if not store then Notify.error(err); return end
    local counts={pending=0,uploading=0,uploaded=0,failed=0,uncertain=0}
    local last_error
    for _,job in ipairs(store.jobs) do counts[job.state]=(counts[job.state] or 0)+1; last_error=job.error or last_error end
    local menu
    local function close() UIManager:close(menu) end
    local items={
        {text="Account: "..(store.config.username or "Sign in required"),callback=function() close(); UI.login() end},
        {text="Library: "..(store.config.library_name or "Choose a library"),callback=function() close(); UI.chooseLibrary() end},
        {text="Upload after download: "..(store.config.enabled==false and "Off" or "On"),callback=function()
            store.config.enabled=store.config.enabled==false
            if save() then close(); Queue.kick(); UI.show() end
        end},
        {text=string.format("Waiting: %d · Uploading: %d · Sent: %d",counts.pending,counts.uploading,counts.uploaded),callback=function() close(); UI.show() end},
        {text=string.format("Failed: %d · Check library first: %d",counts.failed,counts.uncertain),callback=function()
            Notify.message(last_error or "No failed uploads. Originals stay on your reader.")
        end},
        {text="Retry waiting/failed uploads",callback=function() local ok,retry_err=Queue.retry(false); if not ok then Notify.error(retry_err) end; close() end},
        {text="Send an existing book...",callback=function() close(); UI.browse(require("settings.settings"):getDownloadDir()) end},
        {text="Retry interrupted uploads...",callback=function()
            UIManager:show(ConfirmBox:new{text="An interrupted upload may already be in BookOrbit. Check the website first. Retry these uploads?",ok_text="Retry",ok_callback=function() local ok,retry_err=Queue.retry(true); if not ok then Notify.error(retry_err) end; close() end})
        end},
        {text="Sign out of uploads",callback=function()
            if Queue.isActive() then Notify.info("Wait for the current upload to finish"); return end
            store.config.access_token=nil; store.config.refresh_token=nil
            if save() then close() end
        end},
    }
    local size=Screen:getSize()
    menu=Menu:new{title="BookOrbit uploads",item_table=items,width=size.w,height=size.h,covers_fullscreen=true}
    UIManager:show(menu)
end
function UI.browse(folder)
    local FileUtil=require("util.fileutil")
    local lfs=require("libs/libkoreader-lfs")
    local names,err=FileUtil.listDir(folder)
    if not names then Notify.error(err); return end
    table.sort(names)
    local menu,items=nil,{}
    local parent=folder:match("^(.*)/[^/]+/?$")
    if parent and parent~=folder then
        items[#items+1]={text="↑ Parent folder",callback=function() UIManager:close(menu); UI.browse(parent~="" and parent or "/") end}
    end
    local formats={epub=true,pdf=true,mobi=true,azw=true,azw3=true,fb2=true,cbz=true,cbr=true,txt=true,rtf=true,docx=true}
    for _,name in ipairs(names) do
        local path=folder:gsub("/+$", "").."/"..name
        local mode=lfs.attributes(path,"mode")
        local extension=name:match("%.([^.]+)$")
        if mode=="directory" then
            items[#items+1]={text="▸ "..name,callback=function() UIManager:close(menu); UI.browse(path) end}
        elseif mode=="file" and formats[(extension or ""):lower()] then
            items[#items+1]={text=name,callback=function()
                UIManager:show(ConfirmBox:new{text="Send this book to your selected BookOrbit library?\n\n"..name,ok_text="Send",ok_callback=function()
                    local ok,queue_err=Queue.enqueue(path,{title=name},true)
                    if not ok then Notify.error(queue_err); return end
                    UIManager:close(menu); Notify.info("Book queued for BookOrbit"); UI.show()
                end})
            end}
        end
    end
    if #items==0 then items[1]={text="No supported books in this folder"} end
    local size=Screen:getSize()
    menu=Menu:new{title="Send to BookOrbit",item_table=items,width=size.w,height=size.h,covers_fullscreen=true}
    UIManager:show(menu)
end
return UI
