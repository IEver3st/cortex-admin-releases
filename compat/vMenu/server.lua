-- vMenu keeps bans in this resource's server storage (and older versions in
-- bans.json). Only a resource named vMenu can read them, so Cortex Admin asks
-- here once on start and owns them from then on.
local PREFIX = 'vmenu_ban_'
local MAX_RECORDS = 4096

local function addRecord(records, seen, record)
    if type(record) ~= 'table' or #records >= MAX_RECORDS then return end
    local uuid = record.uuid
    if type(uuid) ~= 'string' or uuid == '' or seen[uuid] then return end
    seen[uuid] = true
    records[#records + 1] = record
end

exports('GetBanRecords', function()
    if GetInvokingResource() ~= 'cortex-admin' then return {} end
    local records, seen = {}, {}
    local handle = StartFindKvp(PREFIX)
    if handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not key then break end
            local raw = GetResourceKvpString(key)
            local ok, record = pcall(json.decode, raw or '')
            if ok then addRecord(records, seen, record) end
        end
        EndFindKvp(handle)
    end
    local legacy = LoadResourceFile(GetCurrentResourceName(), 'bans.json')
    local ok, list = pcall(json.decode, legacy or '')
    if ok and type(list) == 'table' then
        for index = 1, #list do addRecord(records, seen, list[index]) end
    end
    return records
end)

exports('RemoveBanRecord', function(uuid)
    if GetInvokingResource() ~= 'cortex-admin' or type(uuid) ~= 'string' or uuid == '' then return false end
    DeleteResourceKvp(PREFIX .. uuid)
    local resource = GetCurrentResourceName()
    local ok, list = pcall(json.decode, LoadResourceFile(resource, 'bans.json') or '')
    if ok and type(list) == 'table' then
        local kept = {}
        for index = 1, #list do
            if type(list[index]) ~= 'table' or list[index].uuid ~= uuid then kept[#kept + 1] = list[index] end
        end
        if #kept ~= #list then SaveResourceFile(resource, 'bans.json', json.encode(kept), -1) end
    end
    return true
end)
