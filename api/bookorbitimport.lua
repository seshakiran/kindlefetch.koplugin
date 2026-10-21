-- Explicit BookOrbit acquisition, distinct from a standalone local Kindle Fetch download.
local Store = require("api.bookorbitstore")
local Queue = require("api.bookorbitqueue")
local Client = require("api.bookorbitclient")
local FileUtil = require("util.fileutil")
local FileCheck = require("util.filecheck")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Notify = require("util.notifyutil")
local Import = {}

function Import.find(book, regular_path)
    local store = Store.load()
    local destination = Queue.destination()
    if not store or not destination then return nil end
    for _,job in ipairs(store.jobs) do
        local legacy = regular_path and job.path == regular_path and job.title == book.title
        if legacy and FileUtil.isValidFile(job.path) then
            legacy = lfs.attributes(job.path,"size") == job.size and lfs.attributes(job.path,"modification") == job.modified
        end
        if job.target == destination and
            (tostring(job.source_id) == tostring(book.id) and job.file_type == book.file_type or legacy) then
            return job
        end
    end
end

function Import.start(book, regular_path, context)
    local store,err=Store.load()
    if not store then Notify.error(err); return false end
    if not Queue.destination() then
        Notify.message("Sign in and choose a library in Kindle Fetch → Settings → BookOrbit uploads before importing.")
        return false
    end
    local source_server = Client.normalizeUrl(context.server_url)
    if not source_server or source_server ~= Client.normalizeUrl(store.config.server_url) then
        Notify.error("BookOrbit uploads points to a different server. Select this dashboard's server in Kindle Fetch settings first.")
        return false
    end
    local function complete(job)
        if job.state ~= "uploaded" or not tonumber(job.book_id) then
            Notify.error("BookOrbit import is not confirmed. Your downloaded copy is retained. Open BookOrbit uploads in settings to review/retry.")
            return
        end
        -- Nothing can open before the upload's confirmed server ID was saved.
        context.on_imported({book_id=job.book_id,path=job.path,file_type=book.file_type,
            title=book.title,size=job.size,hash=job.hash})
    end
    local existing=Import.find(book,regular_path)
    if existing then
        if existing.state == "failed" or existing.state == "uncertain" then
            Notify.error("This import needs review in BookOrbit uploads. Check the library before retrying; it will not download from Z-Library again.")
            return false
        end
        if existing.state == "pending" and not existing.manual then
            -- An explicit dashboard import also resumes an older standalone queued upload.
            existing.manual = true
            local saved,save_err = Store.save()
            if not saved then Notify.error(save_err); return false end
        end
        Queue.watch(existing,complete)
        Queue.kick()
        if existing.state ~= "uploaded" then Notify.info("BookOrbit import is already queued") end
        return true
    end
    -- Durable staging: survives restart and is retained as BookOrbit's linked local reading copy.
    local folder=DataStorage:getDataDir() .. "/kindlefetch-imports"
    util.makePath(folder)
    if not FileUtil.isValidDirectory(folder) then Notify.error("Could not create the BookOrbit import folder"); return false end
    local filename=util.getSafeFilename(tostring(book.id).."-"..book.title.."."..book.file_type,folder)
    local path=folder.."/"..filename
    local function queue(path_to_upload)
        local ok,queue_err,job=Queue.enqueue(path_to_upload,book,true,
            {origin="bookorbit",source_id=tostring(book.id),file_type=book.file_type})
        if not ok or not job then Notify.error(queue_err or "Could not queue the BookOrbit import"); return end
        Queue.watch(job,complete)
        if job.state ~= "uploaded" then Notify.info("Importing into BookOrbit...") end
    end
    -- Reuse a complete prior local/staged file instead of consuming another Z-Library download.
    local reusable=FileUtil.isValidFile(path) and path
    if reusable and FileUtil.getSize(reusable)>0 and not FileCheck.problem(reusable,book.file_type) then
        queue(reusable); return true
    end
    require("api.downloader"):downloadForImport(book,path,function(ok,download_err,saved_path)
        if ok then queue(saved_path or path)
        else Notify.error("BookOrbit import download failed: "..tostring(download_err)) end
    end)
    return true
end
return Import
