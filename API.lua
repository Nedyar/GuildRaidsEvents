-- API.lua: what other addons may use, in the global table GuildRaidsEvents.
-- It knows nothing of any particular addon: an addon that brings in
-- sign-ups made outside the game (a "bridge") registers, the guild master
-- chooses in the options which characters may bring them in, and those
-- characters' clients add them by character name.
--
--   GuildRaidsEvents.API_VERSION                -- 1
--   GuildRaidsEvents.RegisterBridge(name)       -- shows the options' page of bridge characters
--   GuildRaidsEvents.IsBridgeCharacter()        -- whether this character may bring sign-ups in
--   GuildRaidsEvents.GetEvents(which)           -- "upcoming" (default), "past" or "all": a list of events
--   GuildRaidsEvents.GetEvent(key)              -- one event, or nil
--   GuildRaidsEvents.SetExternalSignUp(key, characterName, status, role, note)
--       -- status "signedUp", "tentative", "declined", or nil to take it back;
--       -- role "tank", "healer" or "damage". Returns true, or false and why:
--       -- "notReady", "notBridge", "noEvent", "locked" (the event takes no
--       -- answers), "notMember", "badStatus", "badRole", "full" (this
--       -- character holds as many as its record can).
--   GuildRaidsEvents.OnChange(callback)         -- called (with no arguments) when the events change
--
-- An event: { key, title, type ("raid", "dungeon", "pvp", "meeting",
-- "other"), place (the raid, dungeon or battleground's name, or nil),
-- placeID (its instance ID, 1 for world PvP, or nil), start (the game's
-- calendar time, as seconds as if it were UTC),
-- startUnix (the same moment as a Unix time), description, organizer (a
-- name), organizerGUID, slots ({ tank, healer, damage } or nil: no limit),
-- minLevel, weekly, autoConfirm, locked (members cannot answer it),
-- cancelled, calendarID (or nil), changed
-- (Unix time), signUps }. A sign-up: { name, guid, class, level, status,
-- role, note, time (Unix time of the answer), manage ("confirmed",
-- "standby", "out", "tentative" or nil), auto (the event set manage by itself),
-- external (brought in from outside the game) }.
local _, ns = ...

local Events = ns.Events

local STATUS = { signedUp = Events.SIGNED, tentative = Events.TENTATIVE, declined = Events.DECLINED }
local STATUS_NAMES = { "signedUp", "tentative", "declined" }
local ROLES = { tank = Events.TANK, healer = Events.HEALER, damage = Events.DAMAGE }
local ROLE_NAMES = { "tank", "healer", "damage" }
local MANAGE_NAMES = { "confirmed", "standby", "out", "tentative" }
local TYPE_NAMES = { [0] = "raid", "dungeon", "pvp", "meeting", "other" }

local API = {}
GuildRaidsEvents = API
API.API_VERSION = 1

local function Copy(event, offset)
    local signUps = {}
    for _, signUp in ipairs(Events.SignUps(event)) do
        signUps[#signUps + 1] = {
            name = signUp.name, guid = signUp.guid, class = signUp.class, level = signUp.level,
            status = STATUS_NAMES[signUp.st], role = signUp.ro and ROLE_NAMES[signUp.ro] or nil, note = signUp.no,
            time = signUp.at, manage = MANAGE_NAMES[signUp.status], auto = signUp.auto == true,
            external = signUp.external == true,
        }
    end
    return {
        key = event.key, title = event.ti, type = TYPE_NAMES[event.ty], place = ns.UI.PlaceName(event.ii),
        placeID = event.ii, start = event.tm, startUnix = event.tm - offset,
        description = event.de, organizer = Events.MemberName(event.owner), organizerGUID = event.owner,
        slots = event.sl and { tank = event.sl.t, healer = event.sl.h, damage = event.sl.d } or nil,
        minLevel = event.ml or 0, weekly = event.wk == true, autoConfirm = event.ac == true, locked = event.lk == true,
        cancelled = event.x == true,
        calendarID = event.ci ~= 0 and event.ci or nil, changed = event.at, signUps = signUps,
    }
end

function API.RegisterBridge(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    for _, known in ipairs(ns.Rights.bridges) do
        if known == name then
            return true
        end
    end
    table.insert(ns.Rights.bridges, name)
    ns.Fire("BridgesChanged")
    return true
end

function API.IsBridgeCharacter()
    return ns.playerGUID ~= nil and ns.Rights.IsBridge(ns.playerGUID)
end

function API.GetEvents(which)
    which = which or "upcoming"
    local list, offset = {}, ns.db and Events.Offset() or 0
    local lists = which == "all" and { "upcoming", "past" } or { which }
    for _, name in ipairs(lists) do
        for _, event in ipairs(Events.List(name)) do
            list[#list + 1] = Copy(event, offset)
        end
    end
    return list
end

function API.GetEvent(key)
    local event = Events.Get(key)
    return event and Copy(event, Events.Offset()) or nil
end

function API.SetExternalSignUp(key, characterName, status, role, note)
    if not ns.playerGUID or not ns.db then
        return false, "notReady"
    end
    local st, ro
    if status ~= nil then
        st = STATUS[status]
        if not st then
            return false, "badStatus"
        end
    end
    if role ~= nil then
        ro = ROLES[role]
        if not ro then
            return false, "badRole"
        end
    end
    local event = Events.Get(key)
    if event and event.lk then
        return false, "locked"
    end
    local guid = Events.FindMember(characterName)
    if not guid then
        return false, "notMember"
    end
    return Events.SetExternal(key, guid, st, ro, type(note) == "string" and note or nil)
end

local listeners = {}
function API.OnChange(callback)
    if type(callback) ~= "function" then
        return false
    end
    if #listeners == 0 then
        ns.On("EventsChanged", function()
            for _, listener in ipairs(listeners) do
                pcall(listener)
            end
        end)
    end
    listeners[#listeners + 1] = callback
    return true
end
