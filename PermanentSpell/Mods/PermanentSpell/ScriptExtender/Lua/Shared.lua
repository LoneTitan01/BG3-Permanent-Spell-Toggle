-- Permanent Spell: shared by server and client.
-- When stats load, every status applied for -1 turns by a non-concentration spell (an Until Long Rest
-- spell) gets a copy named PERMSPELL_<status> with IgnoreResting added. The copy behaves exactly like
-- the original but a long rest does not remove it, so the game treats it as permanent.
-- Both sides build the same copies so the client can show them and the save can load them.

PermanentSpell = PermanentSpell or {}
local M = PermanentSpell

M.PREFIX = "PERMSPELL_"
M.Copies = {}     -- original status -> permanent copy
M.Originals = {}  -- permanent copy -> original status

-- Reads nested fields without erroring on missing properties.
function M.get(object, ...)
    local keys = {...}
    local ok, value = pcall(function()
        local v = object
        for _, key in ipairs(keys) do
            if v == nil then return nil end
            v = v[key]
        end
        return v
    end)
    if ok then return value end
    return nil
end

-- Returns flags as a list of strings, whether stored as "A;B" or as a table.
function M.flagList(flags)
    local list = {}
    if type(flags) == "string" then
        for flag in flags:gmatch("[^;]+") do
            flag = flag:match("^%s*(.-)%s*$")
            if flag ~= "" then list[#list + 1] = flag end
        end
    elseif type(flags) == "table" or type(flags) == "userdata" then
        pcall(function()
            for _, flag in pairs(flags) do
                if type(flag) == "string" then list[#list + 1] = flag end
            end
        end)
    end
    return list
end

function M.hasFlag(flags, flag)
    for _, value in ipairs(M.flagList(flags)) do
        if value == flag then return true end
    end
    return false
end

function M.stat(name)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, result = pcall(Ext.Stats.Get, name, nil, false)
    if ok then return result end
    return nil
end

function M.isConcentration(spell)
    local data = M.stat(spell)
    return data ~= nil and M.hasFlag(M.get(data, "SpellFlags"), "IsConcentration")
end

function M.isPermanentCopy(statusId)
    return type(statusId) == "string" and statusId:sub(1, #M.PREFIX) == M.PREFIX
end

-- Finds ApplyStatus(...) entries with a negative duration, in raw strings or parsed functor tables.
local function collectInfinite(value, found, depth)
    depth = depth or 0
    if value == nil or depth > 8 then return end
    if type(value) == "string" then
        for args in value:gmatch("ApplyStatus%(([^%)]*)%)") do
            local parts = {}
            for part in args:gmatch("[^,]+") do parts[#parts + 1] = part:match("^%s*(.-)%s*$") end
            local status, duration
            if #parts >= 4 and tonumber(parts[2]) == nil then
                status, duration = parts[2], parts[4]   -- ApplyStatus(TARGET,STATUS,chance,duration)
            elseif #parts >= 3 then
                status, duration = parts[1], parts[3]   -- ApplyStatus(STATUS,chance,duration)
            end
            if status and tonumber(duration) and tonumber(duration) < 0 then found[status] = true end
        end
        return
    end
    if type(value) ~= "table" and type(value) ~= "userdata" then return end
    local statusId = M.get(value, "StatusId")
    if type(statusId) == "string" and statusId ~= "" then
        local duration = tonumber(M.get(value, "Duration"))
        if duration and duration < 0 then found[statusId] = true end
    end
    pcall(function()
        for _, child in pairs(value) do collectInfinite(child, found, depth + 1) end
    end)
end

local function untilLongRestStatuses()
    local found = {}
    local ok, names = pcall(Ext.Stats.GetStats, "SpellData")
    if ok and names then
        for _, name in ipairs(names) do
            local data = M.stat(name)
            if data and not M.hasFlag(M.get(data, "SpellFlags"), "IsConcentration") then
                collectInfinite(M.get(data, "TooltipStatusApply"), found)
                collectInfinite(M.get(data, "SpellProperties"), found)
                collectInfinite(M.get(data, "SpellSuccess"), found)
            end
        end
    end
    return found
end

local function createCopy(statusId, sync)
    if M.isPermanentCopy(statusId) then return end
    local data = M.stat(statusId)
    if not data then return end
    local flags = M.flagList(M.get(data, "StatusPropertyFlags"))
    for _, flag in ipairs(flags) do
        if flag == "IgnoreResting" then return end   -- already survives long rests
    end
    local name = M.PREFIX .. statusId
    local copy = M.stat(name)
    local created = false
    if not copy then
        local ok, result = pcall(Ext.Stats.Create, name, "StatusData", statusId)
        copy = ok and result or nil
        created = copy ~= nil
    end
    if not copy then return end
    if not M.hasFlag(M.get(copy, "StatusPropertyFlags"), "IgnoreResting") then
        flags[#flags + 1] = "IgnoreResting"
        if not pcall(function() copy.StatusPropertyFlags = flags end) then return end
        created = true
    end
    -- Copies made after stats finished loading have to be sent to the client.
    if created and sync then pcall(function() copy:Sync() end) end
    M.Copies[statusId] = name
    M.Originals[name] = statusId
end

-- Builds (or re-finds) the permanent copies. Safe to call more than once.
function M.CreateCopies(sync)
    M.Copies, M.Originals = {}, {}
    for statusId in pairs(untilLongRestStatuses()) do createCopy(statusId, sync) end
    M.Ready = true
    Ext.Utils.Print(("[PermanentSpell] %d permanent spell statuses ready"):format(
        (function() local n = 0 for _ in pairs(M.Copies) do n = n + 1 end return n end)()))
end

function M.EnsureCopies()
    if not M.Ready then M.CreateCopies(Ext.IsServer()) end
end

-- Stats reload: build fresh. Loading a save without a stats reload: re-find the existing copies.
Ext.Events.StatsLoaded:Subscribe(function() M.CreateCopies(false) end)
Ext.Events.SessionLoaded:Subscribe(M.EnsureCopies)
