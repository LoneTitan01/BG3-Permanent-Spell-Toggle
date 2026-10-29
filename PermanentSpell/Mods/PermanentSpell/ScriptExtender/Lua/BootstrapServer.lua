-- Permanent Spell
-- Every playable character gets the PermanentSpell_Toggle passive. While a caster has it toggled on,
-- any Until Long Rest status they put on a party member is swapped for its permanent copy
-- (PERMSPELL_<status>, see Shared.lua), which long rests do not remove.
-- Anyone carrying a permanent copy gets the End Permanent Spells cantrip, which removes only those
-- copies. Toggling the passive off turns that caster's copies back into normal Until Long Rest statuses.

Ext.Require("Shared.lua")

local S = PermanentSpell
local get, stat = S.get, S.stat

local ModuleUUID = "92193c79-05ee-4f53-bd95-b530316b0a59"
local PASSIVE = "PermanentSpell_Toggle"
local MARKER = "PERMANENT_SPELL_ACTIVE"
local CANTRIP = "PermanentSpell_EndPermanentSpells"

-- Used by the old restore-after-rest version. Kept registered so old saves load; cleared on load.
Ext.Vars.RegisterModVariable(ModuleUUID, "Records", {
    Server = true, WriteableOnServer = true, Persistent = true
})

-- Osiris names objects "<name>_<uuid>"; this keys on the bare UUID.
local function uuid(object)
    if type(object) ~= "string" then return nil end
    local id = object:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
    if not id or id == "00000000-0000-0000-0000-000000000000" then return nil end
    return id:lower()
end

local function liveStatuses(target)
    local entity = Ext.Entity.Get(target)
    return entity and get(entity, "ServerCharacter", "StatusManager", "Statuses")
end

local function liveStatus(target, statusId)
    local list = liveStatuses(target)
    if not list then return nil end
    local ok, result = pcall(function()
        for _, status in pairs(list) do
            if status.StatusId == statusId then return status end
        end
    end)
    if ok then return result end
    return nil
end

local function causeUuid(cause)
    if cause == nil then return nil end
    local id = get(cause, "Uuid", "EntityUuid")
    if not id then
        local ok, entity = pcall(Ext.Entity.Get, cause)
        id = ok and entity and get(entity, "Uuid", "EntityUuid")
    end
    return uuid(id)
end

-- Every status on the target as {id, caster}.
local function statusList(target)
    local list = liveStatuses(target)
    local found = {}
    if not list then return found end
    pcall(function()
        for _, status in pairs(list) do found[#found + 1] = {status.StatusId, status.Cause} end
    end)
    for _, entry in ipairs(found) do entry[2] = causeUuid(entry[2]) end
    return found
end

-- nil when the toggle state cannot be read.
local function passiveToggledOn(character)
    local entity = Ext.Entity.Get(character)
    local passives = entity and get(entity, "PassiveContainer", "Passives")
    if not passives then return nil end
    local ok, result = pcall(function()
        for _, item in pairs(passives) do
            local passive = item.Passive
            if passive and passive.PassiveId == PASSIVE then return passive.ToggledOn == true end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

local function isToggled(character)
    if not character then return false end
    if Osi.HasActiveStatus(character, MARKER) == 1 then return true end
    return passiveToggledOn(character) == true
end

local function isPartyCharacter(target)
    return Osi.IsCharacter(target) == 1 and Osi.IsPartyMember(target, 0) == 1
end

-- True when this status on the target came from an Until Long Rest spell and has a permanent copy.
local function qualifies(target, statusId)
    S.EnsureCopies()
    if statusId == MARKER or S.isPermanentCopy(statusId) or not S.Copies[statusId] then return false end
    local data = stat(statusId)
    if not data or S.hasFlag(get(data, "StatusPropertyFlags"), "IgnoreResting") then return false end
    local live = liveStatus(target, statusId)
    local lifetime = live and tonumber(get(live, "LifeTime"))
    if lifetime and lifetime >= 0 then return false end
    local spell = live and get(live, "SourceSpell", "Prototype")
    if type(spell) == "string" and spell ~= "" then return not S.isConcentration(spell) end
    return true
end

-- Osiris databases are nil until the story is bound.
local function players()
    local list = {}
    local ok, rows = pcall(function() return Osi.DB_Players:Get(nil) end)
    if ok and rows then
        for _, row in pairs(rows) do
            local id = uuid(row[1])
            if id then list[#list + 1] = id end
        end
    end
    return list
end

-- Gives the cantrip to characters carrying a permanent spell and takes it from everyone else.
local function refreshCantrip(target)
    if not Ext.Entity.Get(target) or not isPartyCharacter(target) then return end
    local has = false
    for _, entry in ipairs(statusList(target)) do
        if S.Originals[entry[1]] then has = true break end
    end
    local known = Osi.HasSpell(target, CANTRIP) == 1
    if has and not known then
        Osi.AddSpell(target, CANTRIP, 0, 0)
    elseif not has and known then
        Osi.RemoveSpell(target, CANTRIP, 0)
    end
end

-- Status events fire before the status list settles, so check a moment later.
local function refreshCantripSoon(target)
    Ext.Timer.WaitFor(200, function() refreshCantrip(target) end)
end

local function makePermanent(target, statusId, caster)
    local copy = S.Copies[statusId]
    if not copy then return end
    Osi.RemoveStatus(target, statusId)
    Osi.ApplyStatus(target, copy, -1, 1, caster)
end

-- Turns a caster's permanent spells back into normal Until Long Rest spells.
local function revertCaster(caster)
    for _, player in ipairs(players()) do
        for _, entry in ipairs(statusList(player)) do
            local original = S.Originals[entry[1]]
            if original and entry[2] == caster then
                Osi.RemoveStatus(player, entry[1])
                Osi.ApplyStatus(player, original, -1, 1, caster)
            end
        end
        refreshCantripSoon(player)
    end
end

-- Removes every permanent spell from this mod on the target. Other permanent effects are untouched.
local function removePermanentSpells(target)
    for _, entry in ipairs(statusList(target)) do
        if S.Originals[entry[1]] then Osi.RemoveStatus(target, entry[1]) end
    end
    refreshCantripSoon(target)
end

-- Converts spells that were already active before the toggle was turned on.
local function scanTarget(target)
    for _, entry in ipairs(statusList(target)) do
        local caster = entry[2]
        if caster and isToggled(caster) and qualifies(target, entry[1]) then
            makePermanent(target, entry[1], caster)
        end
    end
    refreshCantripSoon(target)
end

local function scanParty()
    for _, player in ipairs(players()) do scanTarget(player) end
end

local function ensurePassive(character)
    if not Ext.Entity.Get(character) then return end
    if Osi.HasPassive(character, PASSIVE) == 0 then Osi.AddPassive(character, PASSIVE) end
    -- Keep the marker in step with the toggle if something stripped it.
    if passiveToggledOn(character) == true and Osi.HasActiveStatus(character, MARKER) == 0 then
        Osi.ApplyStatus(character, MARKER, -1, 1, character)
    end
end

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
    Ext.Timer.WaitFor(500, function()
        S.EnsureCopies()
        for _, player in ipairs(players()) do ensurePassive(player) end
        Ext.Vars.GetModVariables(ModuleUUID).Records = nil
        scanParty()
    end)
end)

Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    ensurePassive(character)
    local id = uuid(character)
    if id then refreshCantripSoon(id) end
end)

Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", function(character)
    local id = uuid(character)
    if id and Osi.HasSpell(id, CANTRIP) == 1 then Osi.RemoveSpell(id, CANTRIP, 0) end
end)

Ext.Osiris.RegisterListener("RespecCompleted", 1, "after", function(character)
    ensurePassive(character)
    local id = uuid(character)
    if id then refreshCantripSoon(id) end
end)

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(object, statusId, causee, _)
    local target = uuid(object)
    if not target then return end
    if statusId == MARKER then
        scanParty()
        return
    end
    S.EnsureCopies()
    if S.Originals[statusId] then
        refreshCantripSoon(target)
        return
    end
    if not S.Copies[statusId] or not isPartyCharacter(object) then return end
    local caster = uuid(causee) or causeUuid(get(liveStatus(target, statusId), "Cause"))
    if caster and isToggled(caster) and qualifies(target, statusId) then
        makePermanent(target, statusId, caster)
    end
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(object, statusId, _, _)
    local target = uuid(object)
    if not target then return end
    if S.Originals[statusId] then
        refreshCantripSoon(target)
        return
    end
    if statusId ~= MARKER then return end
    -- Read the toggle a moment later, once the passive has finished switching off.
    Ext.Timer.WaitFor(100, function()
        if Osi.HasActiveStatus(target, MARKER) ~= 1 and passiveToggledOn(target) ~= true then
            revertCaster(target)
        end
    end)
end)

Ext.Osiris.RegisterListener("CastedSpell", 5, "after", function(caster, spell, _, _, _)
    if spell ~= CANTRIP then return end
    local id = uuid(caster)
    if id then removePermanentSpells(id) end
end)
