-- Rights.lua: who may do what with the guild's events, from the guild
-- roster and the guild's options.
--
--   - Creating an event: whoever the game lets add guild events to its
--     calendar (C_Calendar.CanAddEvent), as their rank allows.
--   - Changing or deleting an event, giving its sign-ups a status
--     (confirmed, standby, out), and naming or taking back its moderators:
--     its organizer and its moderators (Events.IsModerator), as in the
--     game's calendar. The game itself still has the last word on each
--     change (Calendar.lua: the calendar first).
--   - Deleting any event: also the guild master and the members whose rank
--     has the game's "Has officer privileges", as the game's calendar lets
--     them (seen in game). Their rank gives them nothing else.
--   - Bringing in sign-ups made outside the game (API.lua): the characters
--     the guild master chose in the addon's options.
--
-- Every client decides from its own data: what someone may no longer do
-- stops counting everywhere, also for what they did before.
--
-- The guild's options are its guild master's: they travel in the record of
-- the member the roster shows as guild master (rank index 0), cf (see
-- Pack.lua), and any other member's are ignored, so nobody else can set
-- them.
local _, ns = ...

local Rights = {}
ns.Rights = Rights

-- Addons that bring in sign-ups made outside the game (API.RegisterBridge):
-- { name... }. The options' page of bridge characters shows only then.
Rights.bridges = {}

-- The game's rank permission "Has officer privileges" (GuildControlUI's
-- OfficerCheckbox).
Rights.OFFICER_FLAG = 22

local rankCache = {}  -- [rank index] = whether the rank has it

function Rights.ForgetRanks()
    wipe(rankCache)
end

-- rankIndex: as the roster gives it, 0 for the guild master.
function Rights.IsOfficerRank(rankIndex)
    if rankIndex == 0 then
        return true
    elseif type(rankIndex) ~= "number" then
        return false
    end
    local officer = rankCache[rankIndex]
    if officer == nil then
        local flags = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
            and ns.Try(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
        officer = ns.CanRead(flags) and ns.Plain(flags[Rights.OFFICER_FLAG]) == true
        rankCache[rankIndex] = officer
    end
    return officer
end

function Rights.IsGM(guid)
    local entry = guid and ns.Roster.members[guid]
    return entry ~= nil and entry.ri == 0
end

-- The guild master or an officer, by their rank in the roster.
function Rights.IsOfficer(guid)
    local entry = guid and ns.Roster.members[guid]
    return entry ~= nil and Rights.IsOfficerRank(entry.ri)
end

-- Whether guid may change or delete the event, give its sign-ups a status
-- and name its moderators: its organizer or one of its moderators.
function Rights.MayManage(guid, event)
    if not guid or not event then
        return false
    end
    return guid == event.owner or ns.Events.IsModerator(event, guid)
end

function Rights.MayIManage(event)
    return Rights.MayManage(ns.playerGUID, event)
end

-- Whether guid may delete the event: those who manage it, and officers.
function Rights.MayDelete(guid, event)
    return Rights.MayManage(guid, event) or (event ~= nil and Rights.IsOfficer(guid))
end

function Rights.MayIDelete(event)
    return Rights.MayDelete(ns.playerGUID, event)
end

-- Whether the game lets the current character add guild events.
function Rights.MayCreate()
    return ns.Plain(ns.Try(C_Calendar.CanAddEvent)) == true
end

-- The guild's options ----------------------------------------------------------------------

local gm  -- the guild master's GUID, while the roster still says so

function Rights.GM()
    local members = ns.Roster.members
    local entry = gm and members[gm]
    if entry and entry.ri == 0 then
        return gm
    end
    gm = nil
    for guid, member in pairs(members) do
        if member.ri == 0 then
            gm = guid
            break
        end
    end
    return gm
end

-- { t, br = { GUID... } } as the guild master set them; nil while they have
-- not.
function Rights.Options()
    local guid = Rights.GM()
    local guild = guid and ns.Data.CurrentGuild(false)
    local record = guild and guild.members[guid]
    return record and record.cf or nil
end

-- The characters that may bring in sign-ups made outside the game.
function Rights.BridgeCharacters()
    local options = Rights.Options()
    return options and options.br or {}
end

function Rights.IsBridge(guid)
    for _, other in ipairs(Rights.BridgeCharacters()) do
        if other == guid then
            return true
        end
    end
    return false
end

function Rights.MayEditOptions()
    return ns.playerGUID ~= nil and Rights.IsGM(ns.playerGUID)
end

-- Changes the guild's options, as its guild master: change(options) edits
-- a copy of them, which replaces them in our record, shared with the guild.
-- Returns whether it could.
function Rights.EditOptions(change)
    if not Rights.MayEditOptions() then
        return false
    end
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return false
    end
    local options = { br = {} }
    for _, guid in ipairs(Rights.BridgeCharacters()) do
        -- Not the characters no longer in the guild.
        if ns.Roster.members[guid] then
            options.br[#options.br + 1] = guid
        end
    end
    change(options)
    options.t = math.max(ns.Now(), (record.cf and record.cf.t or 0) + 1)
    record.cf = options
    ns.Data.TouchOwn(record, "options")
    return true
end

-- Adds a guild member as a bridge character, by name. Returns true, or
-- false and why ("notMaster", "notFound", "already", "full").
function Rights.AddBridge(name)
    if not Rights.MayEditOptions() then
        return false, "notMaster"
    end
    local guid = ns.Events.FindMember(name)
    if not guid then
        return false, "notFound"
    end
    if Rights.IsBridge(guid) then
        return false, "already"
    end
    if #Rights.BridgeCharacters() >= ns.Pack.LIMITS.bridges then
        return false, "full"
    end
    Rights.EditOptions(function(options)
        options.br[#options.br + 1] = guid
    end)
    return true
end

function Rights.RemoveBridge(guid)
    return Rights.EditOptions(function(options)
        for i = #options.br, 1, -1 do
            if options.br[i] == guid then
                table.remove(options.br, i)
            end
        end
    end)
end
