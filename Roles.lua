-- Roles.lua: the role the player signs up with when they have not chosen
-- one for that event (the first answer from the addon, or one taken from
-- the game's calendar): the one they chose last with the specialization
-- they have now, or else the one that specialization stands for.
--
-- WoW Forever's talents are a trait tree per class (C_Traits), with the
-- three classic talent trees as its node groups, left to right as the
-- talent window shows them; with dual spec, each spec group has its own
-- config. The player's specialization is the tree with the most points in
-- the active spec group's config. The game gives no role for a tree (its
-- own specialization info is one per class on Forever), so each class's
-- trees are told here, in that order.
local _, ns = ...

local Roles = {}
ns.Roles = Roles

local Events = ns.Events
local TANK, HEALER, DAMAGE = Events.TANK, Events.HEALER, Events.DAMAGE

-- The role of each class's trees, left to right.
Roles.BY_TREE = {
    WARRIOR = { DAMAGE, DAMAGE, TANK },    -- Arms, Fury, Protection
    PALADIN = { HEALER, TANK, DAMAGE },    -- Holy, Protection, Retribution
    HUNTER = { DAMAGE, DAMAGE, DAMAGE },
    ROGUE = { DAMAGE, DAMAGE, DAMAGE },
    PRIEST = { HEALER, HEALER, DAMAGE },   -- Discipline, Holy, Shadow
    SHAMAN = { DAMAGE, DAMAGE, HEALER },   -- Elemental, Enhancement, Restoration
    MAGE = { DAMAGE, DAMAGE, DAMAGE },
    WARLOCK = { DAMAGE, DAMAGE, DAMAGE },
    DRUID = { DAMAGE, TANK, HEALER },      -- Balance, Feral Combat (tank, by the author's choice), Restoration
}

local function Number(value)
    value = ns.Plain(value)
    return type(value) == "number" and value or nil
end

-- The talent config of the active spec group, or nil.
local function ActiveConfig()
    local Spec = C_SpecializationInfo
    local group = Spec and Number(ns.Try(Spec.GetActiveSpecGroup)) or 1
    local configID = Spec and Number(ns.Try(Spec.GetCombatConfigIDForSpecGroup, group))
    if not configID and C_ClassTalents then
        configID = Number(ns.Try(C_ClassTalents.GetActiveConfigID))
    end
    return configID
end

-- The player's specialization: its tree's place, left to right (1 to 3),
-- and name; nil while no point is spent (or the game does not say).
function Roles.ActiveTree()
    local configID = C_Traits and ActiveConfig()
    local config = configID and ns.Try(C_Traits.GetConfigInfo, configID)
    local treeID = ns.CanRead(config) and type(config.treeIDs) == "table" and Number(config.treeIDs[1])
    local groups = treeID and ns.Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    if not ns.CanRead(groups) then
        return nil
    end
    local tabs = {}
    for position, info in ipairs(groups) do
        local id = ns.CanRead(info) and Number(info.groupID)
        if id then
            tabs[#tabs + 1] = { id = id, order = Number(info.orderIndex) or position, name = ns.Plain(info.displayName) }
        end
    end
    table.sort(tabs, function(a, b)
        return a.order < b.order
    end)
    local ids, index = {}, {}
    for i, tab in ipairs(tabs) do
        ids[i], index[tab.id] = tab.id, i
    end
    local spent = {}
    local infos = #ids > 0 and ns.Try(C_Traits.GetGroupCurrencyInfo, configID, ids)
    for _, info in ipairs(ns.CanRead(infos) and infos or {}) do
        local i = ns.CanRead(info) and index[Number(info.traitNodeGroupID)]
        local currency = i and ns.CanRead(info.currencyInfos) and info.currencyInfos[1]
        spent[i or 0] = currency and ns.CanRead(currency) and Number(currency.spent) or 0
    end
    local best, most = nil, 0
    for i = 1, #tabs do
        if (spent[i] or 0) > most then
            best, most = i, spent[i]
        end
    end
    return best, best and tabs[best].name
end

-- The role the player's class and specialization stand for: damage with no
-- point spent, or for a class not known.
function Roles.OfSpec()
    local _, class = UnitClass("player")
    local roles = Roles.BY_TREE[ns.Plain(class)]
    local tree = Roles.ActiveTree()
    return roles and tree and roles[tree] or DAMAGE
end

-- This character's last choices (never shared): [tree, or 0 with none] =
-- role.
local function Chosen()
    local own = ns.Data.OwnState()
    own.roles = own.roles or {}
    return own.roles
end

-- The role to sign up with when none was chosen for the event.
function Roles.Default()
    if not ns.playerGUID or not ns.db then
        return Roles.OfSpec()
    end
    return Chosen()[Roles.ActiveTree() or 0] or Roles.OfSpec()
end

-- The player chose a role: it is the default with this specialization from
-- now on.
function Roles.Remember(role)
    if ns.playerGUID and ns.db then
        Chosen()[Roles.ActiveTree() or 0] = role
    end
end
