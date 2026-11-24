-- Events.lua: the guild's events and their sign-ups, as every client works
-- them out from the members' records (see Pack.lua for their fields), and
-- the player's own changes to them.
--
--   - An event is its organizer's (in their record), as its organizer or
--     an officer last left it: an officer's change travels in the officer's
--     own record (pe), and the newest of all counts (Rights.lua says who
--     may).
--   - A member's answer (signed up, tentative, not coming; their role and a
--     note) is in their own record, or brought in from outside the game by
--     a bridge character (xs, API.lua): the newest of the two counts.
--   - A sign-up's status (confirmed, standby, out) is the newest any of
--     those who may manage the event gave. In an event that confirms by
--     itself, those who signed up without a status are confirmed while
--     their role has places, in the order they signed up, and the rest are
--     on standby: every client works it out the same way.
--
-- Times: an event starts at a time of the game's calendar, which is the
-- server's. It is kept as seconds as if that time were UTC (Events.Naive),
-- so every client reads the same day and hour whatever its own time zone.
-- The times of changes (at) are the server's real time (GetServerTime).
local _, ns = ...

local Events = {}
ns.Events = Events

local LIMITS = ns.Pack.LIMITS

Events.TYPES = { 0, 1, 2, 3, 4 }  -- raid, dungeon, PvP, meeting, other (the game's numbers)
Events.RAID, Events.DUNGEON, Events.PVP, Events.MEETING, Events.OTHER = 0, 1, 2, 3, 4
-- A member's answer.
Events.SIGNED, Events.TENTATIVE, Events.DECLINED = 1, 2, 3
-- A sign-up's status, given by those who manage the event: as the game's
-- calendar offers them (Tentative too).
Events.NONE, Events.CONFIRMED, Events.STANDBY, Events.OUT, Events.PROVISIONAL = 0, 1, 2, 3, 4
-- Roles, and the field of each in an event's places (sl).
Events.TANK, Events.HEALER, Events.DAMAGE = 1, 2, 3
Events.ROLE_FIELD = { "t", "h", "d" }

local DAY = 86400
Events.WEEK = 7 * DAY
Events.DURATION = 2 * 3600       -- an event is upcoming until this long after it starts
Events.KEEP = 7 * DAY            -- and shown among the past ones this long after
Events.FORGET = 30 * DAY         -- answers to events nobody knows of any more are dropped after this

-- Time ---------------------------------------------------------------------------------------

-- Days since 1970-01-01 of a date of the (proleptic) Gregorian calendar.
local function DaysFromCivil(year, month, day)
    year = month <= 2 and year - 1 or year
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400
    local dayOfYear = math.floor((153 * ((month + 9) % 12) + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

local function CivilFromDays(days)
    days = days + 719468
    local era = math.floor(days / 146097)
    local dayOfEra = days - era * 146097
    local yearOfEra = math.floor((dayOfEra - math.floor(dayOfEra / 1460) + math.floor(dayOfEra / 36524)
        - math.floor(dayOfEra / 146096)) / 365)
    local dayOfYear = dayOfEra - (365 * yearOfEra + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
    local shifted = math.floor((5 * dayOfYear + 2) / 153)
    local day = dayOfYear - math.floor((153 * shifted + 2) / 5) + 1
    local month = shifted < 10 and shifted + 3 or shifted - 9
    local year = yearOfEra + era * 400
    return month <= 2 and year + 1 or year, month, day
end

-- A time of the game's calendar as the addon keeps it.
function Events.Naive(year, month, day, hour, minute)
    return DaysFromCivil(year, month, day) * DAY + (hour or 0) * 3600 + (minute or 0) * 60
end

-- { year, month, day, hour, minute, weekday (1 Sunday ... 7 Saturday, as
-- the game counts them) } of such a time.
function Events.DateOf(naive)
    local days = math.floor(naive / DAY)
    local year, month, day = CivilFromDays(days)
    local rest = naive - days * DAY
    return {
        year = year, month = month, day = day, hour = math.floor(rest / 3600), minute = math.floor(rest % 3600 / 60),
        weekday = (days + 4) % 7 + 1,
    }
end

-- Now, in the game's calendar.
function Events.Now()
    local t = C_DateAndTime.GetCurrentCalendarTime()
    return Events.Naive(t.year, t.month, t.monthDay, t.hour, t.minute) + GetServerTime() % 60
end

-- How far the game's calendar runs ahead of real (Unix) time.
function Events.Offset()
    return math.floor((Events.Now() - GetServerTime()) / 60 + 0.5) * 60
end

-- Members ------------------------------------------------------------------------------------

function Events.MemberName(guid)
    local entry = guid and ns.Roster.members[guid]
    if entry and entry.n then
        return entry.n
    end
    local guild = ns.Data.CurrentGuild(false)
    return ns.Data.NameOf(guid, guild and guild.members[guid])
end

-- A guild member's GUID by name, in any case, with or without a realm.
function Events.FindMember(name)
    if type(name) ~= "string" then
        return nil
    end
    local wanted = strtrim(name):gsub("%-.*$", ""):lower()
    if wanted == "" then
        return nil
    end
    for guid, entry in pairs(ns.Roster.members) do
        if type(entry.n) == "string" and entry.n:gsub("%-.*$", ""):lower() == wanted then
            return guid
        end
    end
end

-- The guild's events ------------------------------------------------------------------------

local cache  -- { [key] = event }, until the data or the roster change

function Events.Invalidate()
    cache = nil
end

local FIELDS = { "ty", "ti", "tm", "de", "sl", "ml", "ii", "wk", "nx", "ac", "lk", "x", "at" }

local function Build()
    local events = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return events
    end
    local roster = ns.Roster.members
    for guid, record in pairs(guild.members) do
        -- Not the events of members gone from the guild.
        if not ns.Roster.ready or roster[guid] then
            for _, base in ipairs(record.ev or {}) do
                local key = guid .. "/" .. base.id
                local event = { key = key, id = base.id, owner = guid, by = guid, ci = base.ci or 0 }
                for _, field in ipairs(FIELDS) do
                    event[field] = base[field]
                end
                events[key] = event
            end
        end
    end
    for guid, record in pairs(guild.members) do
        for key, patch in pairs(record.pe or {}) do
            local event = events[key]
            if event and guid ~= event.owner and patch.at > event.at and ns.Rights.IsOfficer(guid) then
                for _, field in ipairs(FIELDS) do
                    event[field] = patch[field]
                end
                event.by = guid
            end
        end
    end
    return events
end

function Events.All()
    if not cache then
        cache = Build()
    end
    return cache
end

function Events.Get(key)
    return key and Events.All()[key]
end

function Events.IsUpcoming(event, now)
    return event.tm + Events.DURATION > (now or Events.Now())
end

-- The events to list: "upcoming" (the soonest first) or "past" (the last
-- KEEP days, the latest first).
function Events.List(which)
    local now, list = Events.Now(), {}
    for _, event in pairs(Events.All()) do
        local upcoming = Events.IsUpcoming(event, now)
        if (which == "upcoming" and upcoming) or (which == "past" and not upcoming and event.tm + Events.KEEP > now) then
            list[#list + 1] = event
        end
    end
    table.sort(list, function(a, b)
        if a.tm ~= b.tm then
            if which == "past" then
                return a.tm > b.tm
            end
            return a.tm < b.tm
        end
        return a.key < b.key
    end)
    return list
end

-- Sign-ups -------------------------------------------------------------------------------------

-- The answers to an event: { [GUID] = { guid, st, ro, no, at, external,
-- by = the bridge character that brought it in } }: each member's own, or
-- the one brought in from outside the game, the newest.
function Events.Answers(key)
    local answers = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return answers
    end
    for guid, record in pairs(guild.members) do
        local answer = record.su and record.su[key]
        if answer then
            answers[guid] = { guid = guid, st = answer.st, ro = answer.ro, no = answer.no, at = answer.at }
        end
    end
    for bridge, record in pairs(guild.members) do
        local list = record.xs and record.xs[key]
        if list and ns.Rights.IsBridge(bridge) then
            for guid, answer in pairs(list) do
                local current = answers[guid]
                if not current or answer.at > current.at then
                    answers[guid] = {
                        guid = guid, st = answer.st, ro = answer.ro, no = answer.no, at = answer.at, external = true,
                        by = bridge,
                    }
                end
            end
        end
    end
    return answers
end

-- The statuses given in an event: { [GUID] = { st, at, by } }, the newest
-- each, among those who may manage it.
function Events.Statuses(event)
    local statuses = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return statuses
    end
    for guid, record in pairs(guild.members) do
        local list = record.ms and record.ms[event.key]
        if list and ns.Rights.MayManage(guid, event) then
            for target, status in pairs(list) do
                local current = statuses[target]
                if not current or status.at > current.at then
                    statuses[target] = { st = status.st, at = status.at, by = guid }
                end
            end
        end
    end
    return statuses
end

-- An event's sign-ups as shown, in the order they were made: { guid,
-- name, class, level, st, ro, no, at, external, status, auto } (status:
-- Events.NONE... PROVISIONAL; auto: the event set it by itself). The answer
-- and the status are made one as the game's calendar has it (States.Merge).
function Events.SignUps(event)
    local statuses = Events.Statuses(event)
    local list = {}
    for guid, answer in pairs(Events.Answers(event.key)) do
        local entry = ns.Roster.members[guid]
        answer.name = Events.MemberName(guid)
        answer.class = entry and entry.c
        answer.level = entry and entry.l
        answer.st, answer.status = ns.States.Merge(answer, statuses[guid])
        list[#list + 1] = answer
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.guid < b.guid
    end)
    if event.ac then
        local used = { 0, 0, 0 }
        for _, signUp in ipairs(list) do
            if signUp.st == Events.SIGNED and signUp.status == Events.CONFIRMED then
                local role = signUp.ro or Events.DAMAGE
                used[role] = used[role] + 1
            end
        end
        for _, signUp in ipairs(list) do
            if signUp.st == Events.SIGNED and signUp.status == Events.NONE then
                local role = signUp.ro or Events.DAMAGE
                local places = event.sl and event.sl[Events.ROLE_FIELD[role]]
                if not places or used[role] < places then
                    signUp.status = Events.CONFIRMED
                    used[role] = used[role] + 1
                else
                    signUp.status = Events.STANDBY
                end
                signUp.auto = true
            end
        end
    end
    return list
end

-- How many are in each role, those tentative too (all but those left out),
-- and how many of them are tentative: { [role] = count }, tentative.
function Events.Counts(signUps)
    local States = ns.States
    local counts, tentative = { 0, 0, 0 }, 0
    for _, signUp in ipairs(signUps) do
        local isTentative = States.IsTentative(signUp)
        if States.Goes(signUp) or isTentative then
            local role = signUp.ro or Events.DAMAGE
            counts[role] = counts[role] + 1
        end
        if isTentative then
            tentative = tentative + 1
        end
    end
    return counts, tentative
end

-- The player's own sign-up to an event (from Events.SignUps), or nil.
function Events.Mine(event, signUps)
    for _, signUp in ipairs(signUps or Events.SignUps(event)) do
        if signUp.guid == ns.playerGUID then
            return signUp
        end
    end
end

-- The player's own changes ----------------------------------------------------------------------

local function Own()
    return ns.Data.GetOwnRecord(true)
end

local function Touch(record, kind)
    ns.Data.TouchOwn(record, kind)
    Events.Invalidate()
end

-- Whether a list of the player's record (by event, or by GUID inside one
-- event) takes key: it has it already, or has room for one more. A record
-- over its LIMITS could not be read again (Pack.lua).
local function HasRoom(list, key, max)
    if list == nil or list[key] ~= nil then
        return true
    end
    local count = 0
    for _ in pairs(list) do
        count = count + 1
        if count >= max then
            return false
        end
    end
    return true
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function Events.ToBase36(number)
    number = math.floor(number)
    local text = ""
    repeat
        local digit = number % 36
        text = DIGITS:sub(digit + 1, digit + 1) .. text
        number = math.floor(number / 36)
    until number == 0
    return text
end

local lastID
local function NewID(record)
    local taken = {}
    for _, event in ipairs(record.ev or {}) do
        taken[event.id] = true
    end
    local number = math.max(GetServerTime(), (lastID or 0) + 1)
    while taken[Events.ToBase36(number)] do
        number = number + 1
    end
    lastID = number
    return Events.ToBase36(number)
end

local function NextChange(at)
    return math.max(ns.Now(), (at or 0) + 1)
end

-- The fields an event is made of, from the form: { ty, ti, tm, de, sl, ml,
-- ii, wk, ac, lk }, checked. nil when they do not pass.
local function Fields(fields, at, cancelled)
    local copy = {}
    for _, field in ipairs(FIELDS) do
        copy[field] = fields[field]
    end
    if copy.de == "" then
        copy.de = nil
    end
    -- The calendar keeps hours and minutes only: an event starts on a
    -- whole minute, so the two always match.
    if type(copy.tm) == "number" then
        copy.tm = copy.tm - copy.tm % 60
    end
    copy.at, copy.x = at, cancelled or nil
    return ns.Data.CleanFields(copy)
end

-- The role the player signs up with: the one they chose last (this
-- character's own, OwnState().role), damage at first.
function Events.LastRole()
    local own = ns.playerGUID and ns.db and ns.Data.OwnState()
    return own and own.role or Events.DAMAGE
end

-- The organizer of a new event is signed up and confirmed in it, as the
-- game's calendar does with its creator; they may answer otherwise later.
local function SignUpOrganizer(record, key, at)
    if not HasRoom(record.su, key, LIMITS.signUps) or not HasRoom(record.ms, key, LIMITS.statusEvents) then
        return
    end
    record.su = record.su or {}
    record.su[key] = { st = Events.SIGNED, ro = Events.LastRole(), at = at }
    record.ms = record.ms or {}
    record.ms[key] = record.ms[key] or {}
    record.ms[key][ns.playerGUID] = { st = Events.CONFIRMED, at = at }
end

-- Next week's event of a weekly event of the player's: the same fields a
-- week later (the first week to come, after a long absence), weekly too,
-- taking answers again, not in the calendar yet, its organizer signed up.
-- A weekly event has it from the start, and the one after once it starts:
-- so there are always two to come.
local function MakeNext(record, base, at)
    if #record.ev >= LIMITS.events then
        return
    end
    local nextEvent = {}
    for _, field in ipairs(FIELDS) do
        nextEvent[field] = base[field]
    end
    nextEvent.tm = base.tm + Events.WEEK
    local now = Events.Now()
    while nextEvent.tm <= now do
        nextEvent.tm = nextEvent.tm + Events.WEEK
    end
    nextEvent.at, nextEvent.id, nextEvent.ci = at, NewID(record), 0
    nextEvent.lk, nextEvent.nx, nextEvent.x = nil, nil, nil
    base.nx = true
    table.insert(record.ev, nextEvent)
    SignUpOrganizer(record, ns.playerGUID .. "/" .. nextEvent.id, at)
end

-- Creates an event organized by the player (a weekly one with next week's).
-- Returns its key, or nil and why ("invalid").
function Events.Create(fields)
    local record = Own()
    if not record then
        return nil, "invalid"
    end
    record.ev = record.ev or {}
    local event = Fields(fields, ns.Now())
    if not event or #record.ev >= LIMITS.events then
        return nil, "invalid"
    end
    event.id, event.ci = NewID(record), 0
    table.insert(record.ev, event)
    local key = ns.playerGUID .. "/" .. event.id
    SignUpOrganizer(record, key, event.at)
    if event.wk then
        MakeNext(record, event, event.at)
    end
    Touch(record, "events")
    return key
end

local function OwnBase(record, key)
    for index, base in ipairs(record.ev or {}) do
        if ns.playerGUID .. "/" .. base.id == key then
            return base, index
        end
    end
end

-- Changes an event the player may manage: fields as for Events.Create.
-- Its organizer changes it in their record, an officer in their own (pe).
-- cancelled: true or false to cancel it or bring it back, nil to leave it.
-- Returns whether it could.
function Events.Change(key, fields, cancelled)
    local event = Events.Get(key)
    local record = Own()
    if not event or not record or not ns.Rights.MayIManage(event) then
        return false
    end
    if cancelled == nil then
        cancelled = event.x
    end
    local changed = Fields(fields, NextChange(event.at), cancelled)
    if not changed then
        return false
    end
    if event.owner == ns.playerGUID then
        local base = OwnBase(record, key)
        if not base then
            return false
        end
        local wasWeekly = base.wk
        changed.nx = base.nx
        for _, field in ipairs(FIELDS) do
            base[field] = changed[field]
        end
        -- Made weekly: next week's at once, as for a new weekly event.
        if base.wk and not wasWeekly and not base.nx and not base.x then
            MakeNext(record, base, ns.Now())
        end
    else
        if not HasRoom(record.pe, key, LIMITS.patches) then
            return false
        end
        record.pe = record.pe or {}
        record.pe[key] = changed
    end
    Touch(record, "events")
    return true
end

-- Cancels an event (it stays listed, marked, until it is past), or brings
-- it back.
function Events.Cancel(key, cancelled)
    local event = Events.Get(key)
    return event ~= nil and Events.Change(key, event, cancelled ~= false)
end

-- Deletes one of the player's own cancelled events, for everyone: it goes
-- from their record, with their answer and the statuses they gave in it.
-- Returns whether it did.
function Events.Delete(key)
    local record = Own()
    local event = Events.Get(key)
    if not record or not event or event.owner ~= ns.playerGUID or not event.x then
        return false
    end
    local _, index = OwnBase(record, key)
    if not index then
        return false
    end
    table.remove(record.ev, index)
    if #record.ev == 0 then
        record.ev = nil
    end
    for _, field in ipairs({ "su", "ms", "xs" }) do
        if record[field] then
            record[field][key] = nil
        end
    end
    Touch(record, "events")
    return true
end

-- The player answers an event: st Events.SIGNED, TENTATIVE or DECLINED,
-- with a role and a note; st nil takes the answer back.
function Events.Answer(key, st, role, note)
    local record = Own()
    if not record or not Events.Get(key) then
        return false
    end
    record.su = record.su or {}
    local old = record.su[key]
    if st then
        if not HasRoom(record.su, key, LIMITS.signUps) then
            return false
        end
        note = note and strtrim(note) or nil
        record.su[key] = {
            st = st, ro = role, no = note ~= "" and ns.Data.CleanText(note, LIMITS.note) or nil, at = NextChange(old and old.at),
        }
    else
        record.su[key] = nil
    end
    Touch(record, "signUps")
    return true
end

-- Gives a sign-up a status (Events.NONE takes it back), as someone who may
-- manage the event.
function Events.SetStatus(key, guid, st)
    local event = Events.Get(key)
    local record = Own()
    if not event or not record or not ns.Rights.MayIManage(event) then
        return false
    end
    if not HasRoom(record.ms, key, LIMITS.statusEvents) or not HasRoom(record.ms and record.ms[key], guid, LIMITS.perEvent) then
        return false
    end
    record.ms = record.ms or {}
    record.ms[key] = record.ms[key] or {}
    local old = record.ms[key][guid]
    record.ms[key][guid] = { st = st, at = NextChange(old and old.at) }
    Touch(record, "statuses")
    return true
end

-- Brings in a sign-up made outside the game, as a bridge character
-- (API.lua): st nil takes it back. Returns true, or false and why.
function Events.SetExternal(key, guid, st, role, note)
    local record = Own()
    if not record then
        return false, "notReady"
    end
    if not ns.Rights.IsBridge(ns.playerGUID) then
        return false, "notBridge"
    end
    if not Events.Get(key) then
        return false, "noEvent"
    end
    if not ns.Roster.members[guid] then
        return false, "notMember"
    end
    if st and (not HasRoom(record.xs, key, LIMITS.statusEvents)
            or not HasRoom(record.xs and record.xs[key], guid, LIMITS.perEvent)) then
        return false, "full"
    end
    record.xs = record.xs or {}
    record.xs[key] = record.xs[key] or {}
    local old = record.xs[key][guid]
    if st then
        note = note and strtrim(note) or nil
        record.xs[key][guid] = {
            st = st, ro = role, no = note ~= "" and ns.Data.CleanText(note, LIMITS.note) or nil, at = NextChange(old and old.at),
        }
    else
        record.xs[key][guid] = nil
        if not next(record.xs[key]) then
            record.xs[key] = nil
        end
    end
    Touch(record, "external")
    return true
end

-- The calendar's event ID of an event the player organizes, once it is in
-- the game's calendar (Calendar.lua).
function Events.SetCalendarID(key, calendarID)
    local record = Own()
    local base = record and OwnBase(record, key)
    if not base or base.ci == calendarID then
        return false
    end
    base.ci = calendarID
    Touch(record, "events")
    return true
end

-- Upkeep ------------------------------------------------------------------------------------------

-- The next event of the player's weekly events (MakeNext), and the end of
-- what is past: the player's events KEEP days after
-- they start, and their answers and statuses to events past or nobody knows
-- of any more.
function Events.Tidy()
    local record = ns.Data.GetOwnRecord(false)
    if not record or not ns.Roster.ready then
        return
    end
    local now, realNow, changed = Events.Now(), ns.Now(), false
    for _, base in ipairs(record.ev or {}) do
        -- The one before it started (it is within a week): the next one.
        if base.wk and not base.x and not base.nx and base.tm <= now + Events.WEEK then
            MakeNext(record, base, realNow)
            changed = true
        end
    end
    for index = #(record.ev or {}), 1, -1 do
        if record.ev[index].tm + Events.KEEP < now then
            table.remove(record.ev, index)
            changed = true
        end
    end
    if record.ev and #record.ev == 0 then
        record.ev = nil
    end
    Events.Invalidate()
    local all = Events.All()
    local function Gone(key, at)
        local event = all[key]
        if event then
            return event.tm + Events.KEEP < now
        end
        return at + Events.FORGET < realNow
    end
    for _, field in ipairs({ "su", "pe" }) do
        for key, item in pairs(record[field] or {}) do
            if Gone(key, item.at) then
                record[field][key] = nil
                changed = true
            end
        end
        if record[field] and not next(record[field]) then
            record[field] = nil
        end
    end
    for _, field in ipairs({ "ms", "xs" }) do
        for key, list in pairs(record[field] or {}) do
            local newest = 0
            for _, item in pairs(list) do
                newest = math.max(newest, item.at)
            end
            if Gone(key, newest) then
                record[field][key] = nil
                changed = true
            end
        end
        if record[field] and not next(record[field]) then
            record[field] = nil
        end
    end
    if changed then
        Touch(record, "events")
    end
end

function Events.Init()
    local function Changed()
        Events.Invalidate()
        ns.Debounce("EventsChanged", 0.2, function()
            ns.Fire("EventsChanged")
        end)
    end
    ns.On("DataChanged", Changed)
    ns.On("RosterUpdated", function()
        ns.Rights.ForgetRanks()
        Changed()
    end)
    C_Timer.After(30, Events.Tidy)
    C_Timer.NewTicker(600, Events.Tidy)
end
