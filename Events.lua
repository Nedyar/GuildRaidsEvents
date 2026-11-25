-- Events.lua: the guild's events and their sign-ups, as every client works
-- them out from the members' records (see Pack.lua for their fields), and
-- the player's own changes to them.
--
--   - An event is its organizer's (in their record), as its organizer or
--     a moderator last left it: a moderator's change travels in their own
--     record (pe), and the newest of all counts (Rights.lua says who may).
--   - Deleting an event deletes it for everyone, as the game's calendar
--     does: its organizer takes it out of their record; a moderator's or an
--     officer's deletion travels in their own (pe, with x) and counts
--     whatever comes after it, and the organizer's client then takes it out
--     of theirs (Events.Purge). There is no getting a deleted event back.
--   - Its moderators, as in the game's calendar: the organizer names them,
--     and a moderator may name or take back others (never the organizer).
--     Each naming travels in its maker's record (mo); every client replays
--     them all in the order they were made, so one made by someone no
--     longer a moderator by then does not count.
--   - A member's answer (signed up, tentative, not coming; their role and a
--     note) is in their own record, or brought in from outside the game by
--     a bridge character (xs, API.lua): the newest of the two counts. One
--     taken back stays as "not coming", so that the time it was taken back
--     is known.
--   - The sign-ups made in the game's calendar by members whose answer is
--     not the addon's (without the addon, or with it off then) come from
--     the newest list read there by anyone's client (cs,
--     CalendarLists.lua).
--   - A guild event made in the game's calendar that no record has (its
--     creator without the addon) is its creator's all the same, as every
--     client's calendar shows it (MadeInCalendar): its statuses and
--     moderators come from its list read there, and it changes there only;
--     what the addon adds to it (answers, roles, a deletion) travels in
--     the records as for any other.
--   - A sign-up's status (confirmed, standby, out) is the newest any of
--     those who may manage the event gave. Nothing confirms by itself: the
--     game's calendar has no such thing, so the two could not agree.
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

local cache    -- { [key] = event }, until the data or the roster change
local deleted  -- { [key] = event }: those deleted, not in the cache
local lists    -- { [calendar event ID] = list }: the newest list read of each (Lists)

function Events.Invalidate()
    cache, deleted, lists = nil, nil, nil
end

-- The sign-up lists read in the game's calendar (cs), the newest of each
-- calendar event among the guild's members: { [event ID] = { at, cr, de,
-- l, by = who read it } }.
local function Lists(guild)
    local newest = {}
    for guid, record in pairs(guild.members) do
        if not ns.Roster.ready or ns.Roster.members[guid] then
            for id, list in pairs(record.cs or {}) do
                local current = newest[id]
                if not current or list.at > current.at or (list.at == current.at and guid < current.by) then
                    newest[id] = { at = list.at, cr = list.cr, de = list.de, l = list.l, by = guid }
                end
            end
        end
    end
    return newest
end

-- The answer a line of an event's list read in the calendar stands for,
-- Events.SIGNED or TENTATIVE, when the addon shows it: someone signed up
-- there (in any way) whose answer is not the addon's: none of theirs (or
-- one taken back before the list was read), nor one brought in from
-- outside the game. Never the player's own: their client takes it in
-- itself (CalendarMember.lua).
local function CalendarAnswerOf(event, guid, line, list, guild)
    local answer = ns.States.CalendarAnswer(line.s)
    if answer == "none" or guid == ns.playerGUID then
        return nil
    end
    local record = guild.members[guid]
    local own = record and record.su and record.su[event.key]
    if own and (own.st ~= Events.DECLINED or own.at >= list.at) then
        return nil
    end
    for bridge, other in pairs(guild.members) do
        if other.xs and other.xs[event.key] and other.xs[event.key][guid] and ns.Rights.IsBridge(bridge) then
            return nil
        end
    end
    return answer == "signed" and Events.SIGNED or Events.TENTATIVE
end

-- The newest list read of a calendar event (see Lists), or nil.
function Events.CalendarList(calendarID)
    Events.All()
    return calendarID and lists[calendarID] or nil
end

-- An event's fields (Pack.lua says what each is).
local FIELDS = { "ty", "ti", "tm", "de", "sl", "ml", "ii", "wk", "nx", "lk", "x", "at" }
Events.FIELDS = FIELDS

-- An event's moderators, { [GUID] = true }: every record's namings of it
-- (mo), replayed in the order they were made, each counting only if its
-- maker was the organizer or a moderator by then.
local function Moderators(event, guild)
    local namings = {}
    for guid, record in pairs(guild.members) do
        for target, naming in pairs(record.mo and record.mo[event.key] or {}) do
            namings[#namings + 1] = { by = guid, target = target, on = naming.on, at = naming.at }
        end
    end
    table.sort(namings, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        elseif a.by ~= b.by then
            return a.by < b.by
        end
        return a.target < b.target
    end)
    local moderators = {}
    for _, naming in ipairs(namings) do
        if naming.target ~= event.owner and (naming.by == event.owner or moderators[naming.by]) then
            moderators[naming.target] = naming.on or nil
        end
    end
    return moderators
end

-- The key of an event made in the game's calendar (see MadeInCalendar):
-- its creator's GUID, "/", "C" and its calendar event ID. The ID of its
-- creator's own event, once they take it into the addon, is the same.
function Events.CalendarMadeID(calendarID)
    return "C" .. calendarID
end

-- The moderators of an event made in the calendar: as its newest list read
-- there says.
local function ListModerators(list)
    local moderators = {}
    for guid, line in pairs(list and list.l or {}) do
        if line.m then
            moderators[guid] = true
        end
    end
    return moderators
end

-- The guild events made in the game's calendar that no record has (made
-- without the addon, or with it off), as this client's calendar shows them
-- (CalendarRead.MadeThere), each its creator's: their GUID from the newest
-- list read of it, or from their name. Every client keys it the same way
-- (Events.CalendarMadeID), so two of them never bring it in twice, and its
-- creator's client takes it in under the same key once they run the addon
-- (CalendarOrganizer.lua's Adopt). Not those the player created (their
-- own client takes them in), nor, a moment after it shows, one whose
-- creator is online and runs the addon (their client is likely taking it
-- in). Only what the calendar keeps: no places, level, place or weekly.
local function MadeInCalendar(events, guild)
    local used = {}
    for _, event in pairs(events) do
        used[event.ci] = true
    end
    local made = ns.CalendarRead.MadeThere and ns.CalendarRead.MadeThere() or {}
    for _, entry in ipairs(made) do
        local list = lists[entry.ci]
        local creator = list and list.cr or Events.FindMember(entry.invitedBy)
        local member = creator and guild.members[creator]
        local online = creator and ns.Roster.members[creator] and ns.Roster.members[creator].on
        local waits = member ~= nil and ns.Data.IsShareable(member) and online and not entry.settled
        if creator and not used[entry.ci] and creator ~= ns.playerGUID and not waits
                and (not ns.Roster.ready or ns.Roster.members[creator]) then
            local id = Events.CalendarMadeID(entry.ci)
            local key = creator .. "/" .. id
            events[key] = events[key] or {
                key = key, id = id, owner = creator, by = creator, ci = entry.ci, ty = entry.ty, ti = entry.ti,
                tm = entry.tm, lk = entry.lk or nil, de = list and list.de, ml = 0, at = 0, cal = true,
            }
        end
    end
end

-- The events, and those deleted: { [key] = event } each.
local function Build()
    local events, gone = {}, {}
    local guild = ns.Data.CurrentGuild(false)
    lists = guild and Lists(guild) or {}
    if not guild then
        return events, gone
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
    MadeInCalendar(events, guild)
    for _, event in pairs(events) do
        event.md = event.cal and ListModerators(lists[event.ci]) or Moderators(event, guild)
    end
    local removed = {}
    for guid, record in pairs(guild.members) do
        for key, patch in pairs(record.pe or {}) do
            local event = events[key]
            if event and guid ~= event.owner then
                if patch.x then
                    -- A deletion, by a moderator or an officer.
                    removed[key] = removed[key] or ns.Rights.MayDelete(guid, event)
                elseif not event.cal and patch.at > event.at and ns.Rights.MayManage(guid, event) then
                    for _, field in ipairs(FIELDS) do
                        event[field] = patch[field]
                    end
                    event.by = guid
                end
            end
        end
    end
    local GoneThere = ns.CalendarRead.GoneThere
    for key, event in pairs(events) do
        -- x in an organizer's own event: 0.1.0's first builds' cancelled
        -- events, deleted now. Someone else's whose calendar event this
        -- client found gone: deleted in the game's window while those who
        -- manage it were away (their clients delete it for good).
        if removed[key] or event.x or (GoneThere and not event.cal and event.owner ~= ns.playerGUID and event.ci ~= 0
                and GoneThere(event.ci)) then
            events[key], gone[key] = nil, event
        end
    end
    return events, gone
end

function Events.All()
    if not cache then
        cache, deleted = Build()
    end
    return cache
end

-- The events deleted (by a moderator) that are still in their organizer's
-- record: { [key] = event }.
function Events.Deleted()
    Events.All()
    return deleted
end

function Events.Get(key)
    return key and Events.All()[key]
end

-- Whether a member moderates the event: named (Moderators), and in its
-- list, as the game's calendar keeps its moderators: their own answer,
-- signed up or tentative, in any status (one taken back leaves the list),
-- or their sign-up made in the calendar.
function Events.IsModerator(event, guid)
    if not (event.md and guid and event.md[guid]) then
        return false
    end
    local guild = ns.Data.CurrentGuild(false)
    local record = guild and guild.members[guid]
    local answer = record and record.su and record.su[event.key]
    if answer and answer.st ~= Events.DECLINED then
        return true
    end
    local list = lists and event.ci ~= 0 and lists[event.ci] or nil
    local line = list and list.l[guid]
    return line ~= nil and guild ~= nil and CalendarAnswerOf(event, guid, line, list, guild) ~= nil
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
-- by = the bridge character that brought it in, calendar = made in the
-- game's calendar } }: each member's own, or the one brought in from
-- outside the game, the newest; or, for those whose answer is not the
-- addon's, the one the calendar has (at: when they gave it, or when it was
-- read).
function Events.Answers(key)
    local answers = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return answers
    end
    local event = Events.Get(key)
    local list = event and event.ci ~= 0 and lists[event.ci]
    for guid, line in pairs(list and list.l or {}) do
        local st = CalendarAnswerOf(event, guid, line, list, guild)
        if st then
            answers[guid] = { guid = guid, st = st, at = line.r or list.at, calendar = true }
        end
    end
    for guid, record in pairs(guild.members) do
        local answer = record.su and record.su[key]
        -- (One taken back before the calendar's list was read: the
        -- calendar's.)
        if answer and not answers[guid] then
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
-- each, among those who may manage it. In one made in the game's calendar,
-- those its newest list read there has (confirmed, standby or out; a
-- tentative line is the member's answer): they are given there.
function Events.Statuses(event)
    local statuses = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return statuses
    end
    if event.cal then
        local list = Events.CalendarList(event.ci)
        for guid, line in pairs(list and list.l or {}) do
            local state = ns.States.FromCalendar(line.s)
            local st = state and ns.States.StatusOf(state)
            if st and st ~= Events.NONE and st ~= Events.PROVISIONAL then
                statuses[guid] = { st = st, at = list.at, by = event.owner }
            end
        end
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

-- The roles given in an event (ra): { [GUID] = { ro, at } }, the newest
-- each, among those who may manage it and each member's own.
function Events.GivenRoles(event)
    local roles = {}
    local guild = ns.Data.CurrentGuild(false)
    if not guild then
        return roles
    end
    for guid, record in pairs(guild.members) do
        local list = record.ra and record.ra[event.key]
        if list then
            local manager = ns.Rights.MayManage(guid, event)
            for target, role in pairs(list) do
                local current = roles[target]
                if (manager or target == guid) and (not current or role.at > current.at) then
                    roles[target] = { ro = role.ro, at = role.at }
                end
            end
        end
    end
    return roles
end

-- An event's sign-ups as shown, in the order they were made: { guid,
-- name, class, level, st, ro, no, at, external, calendar, status } (status:
-- Events.NONE... PROVISIONAL). The answer and the status are made one as
-- the game's calendar has it (States.Merge); the role is the answer's, or
-- one given since.
function Events.SignUps(event)
    local statuses, roles = Events.Statuses(event), Events.GivenRoles(event)
    local list = {}
    for guid, answer in pairs(Events.Answers(event.key)) do
        local entry = ns.Roster.members[guid]
        answer.name = Events.MemberName(guid)
        answer.class = entry and entry.c
        answer.level = entry and entry.l
        answer.st, answer.status = ns.States.Merge(answer, statuses[guid])
        local given = roles[guid]
        if given and given.at > (answer.at or 0) then
            answer.ro = given.ro
        end
        list[#list + 1] = answer
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.guid < b.guid
    end)
    return list
end

-- How many are in each role, those signed up or confirmed only (not those
-- tentative, on standby or out): { [role] = count }.
function Events.Counts(signUps)
    local counts = { 0, 0, 0 }
    for _, signUp in ipairs(signUps) do
        local state = ns.States.Of(signUp)
        if state == "signed" or state == "confirmed" then
            local role = signUp.ro or Events.DAMAGE
            counts[role] = counts[role] + 1
        end
    end
    return counts
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
-- ii, wk, lk }, checked (x: a moderator's deletion). nil when they do
-- not pass.
local function Fields(fields, at, deleting)
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
    copy.at, copy.x = at, deleting or nil
    return ns.Data.CleanFields(copy)
end

-- One of the player's own events in their record, and where.
local function OwnBase(record, key)
    for index, base in ipairs(record.ev or {}) do
        if ns.playerGUID .. "/" .. base.id == key then
            return base, index
        end
    end
end

-- The organizer of a new event is signed up and confirmed in it, as the
-- game's calendar does with its creator, with their default role
-- (Roles.lua); they may answer otherwise later.
local function SignUpOrganizer(record, key, at)
    if not HasRoom(record.su, key, LIMITS.signUps) or not HasRoom(record.ms, key, LIMITS.statusEvents) then
        return
    end
    record.su = record.su or {}
    record.su[key] = { st = Events.SIGNED, ro = ns.Roles.Default(), at = at }
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
-- id: its own ID, for one made in the game's calendar the player takes in
-- (Events.CalendarMadeID); a new one if nil. Returns its key, or nil and
-- why ("invalid").
function Events.Create(fields, id)
    local record = Own()
    if not record then
        return nil, "invalid"
    end
    record.ev = record.ev or {}
    local event = Fields(fields, ns.Now())
    if not event or #record.ev >= LIMITS.events or (id and OwnBase(record, ns.playerGUID .. "/" .. id)) then
        return nil, "invalid"
    end
    event.id, event.ci = id or NewID(record), 0
    table.insert(record.ev, event)
    local key = ns.playerGUID .. "/" .. event.id
    SignUpOrganizer(record, key, event.at)
    if event.wk then
        MakeNext(record, event, event.at)
    end
    Touch(record, "events")
    return key
end

-- Changes an event the player may manage: fields as for Events.Create
-- (deleting: a moderator or an officer deletes it). Its organizer changes
-- it in their record, anyone else in their own (pe). Returns whether it
-- could. One made in the game's calendar changes there only (its deletion
-- is kept, so that everyone stops showing it at once).
local function Change(key, fields, deleting)
    local event = Events.Get(key)
    local record = Own()
    local may = deleting and ns.Rights.MayIDelete or ns.Rights.MayIManage
    if not event or not record or not may(event) or (event.cal and not deleting) then
        return false
    end
    local changed = Fields(fields, NextChange(event.at), deleting)
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
        if base.wk and not wasWeekly and not base.nx then
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

function Events.Change(key, fields)
    return Change(key, fields)
end

-- Takes one of the player's own events out of their record, with their
-- answer, and the statuses and moderators they gave in it. Whether it did.
local function RemoveOwn(record, key)
    local _, index = OwnBase(record, key)
    if not index then
        return false
    end
    table.remove(record.ev, index)
    if #record.ev == 0 then
        record.ev = nil
    end
    for _, field in ipairs({ "su", "ms", "xs", "mo", "ra" }) do
        if record[field] then
            record[field][key] = nil
        end
    end
    Touch(record, "events")
    return true
end

-- Deletes an event the player may delete (Rights.MayDelete), for everyone.
-- Returns whether it did.
function Events.Delete(key)
    local event = Events.Get(key)
    local record = Own()
    if not event or not record then
        return false
    elseif event.owner == ns.playerGUID then
        return RemoveOwn(record, key)
    end
    return Change(key, event, true)
end

-- One of the player's own events a moderator deleted (Events.Deleted): out
-- of their record too. Whether it was.
function Events.Purge(key)
    local record = Own()
    local event = Events.Deleted()[key]
    return record ~= nil and event ~= nil and event.owner == ns.playerGUID and RemoveOwn(record, key)
end

-- The player answers an event: st Events.SIGNED, TENTATIVE or DECLINED,
-- with a role and a note; st nil takes the answer back: it stays as not
-- coming, with the time it was taken back, so that a list read in the
-- calendar before it does not bring them back (CalendarAnswerOf).
function Events.Answer(key, st, role, note)
    local record = Own()
    local event = Events.Get(key)
    if not record or not event then
        return false
    end
    if (st == nil or st == Events.DECLINED) and Events.IsModerator(event, ns.playerGUID) then
        -- Out of its list, a moderator is one no more, as in the game's
        -- calendar: signing up again does not make them one again.
        Events.SetModerator(key, ns.playerGUID, false)
    end
    record.su = record.su or {}
    local old = record.su[key]
    if st then
        if not HasRoom(record.su, key, LIMITS.signUps) then
            return false
        end
        record.su[key] = { st = st, ro = role, no = ns.Data.CleanNote(note), at = NextChange(old and old.at) }
    elseif old and old.st ~= Events.DECLINED then
        record.su[key] = { st = Events.DECLINED, ro = old.ro, at = NextChange(old.at) }
    end
    Touch(record, "signUps")
    return true
end

-- Changes the note of the player's own answer, nothing else: its time,
-- and so the order they signed up in and how it stands against the
-- statuses given, stays. Whether it did.
function Events.SetNote(key, note)
    local record = Own()
    local answer = record and record.su and record.su[key]
    if not answer or not Events.Get(key) then
        return false
    end
    answer.no = ns.Data.CleanNote(note)
    Touch(record, "signUps")
    return true
end

-- Gives a sign-up a status (Events.NONE takes it back), as someone who may
-- manage the event (its organizer's too, as in the game's calendar). Not in
-- one made in the game's calendar: given there (Calendar.GiveThere).
function Events.SetStatus(key, guid, st)
    local event = Events.Get(key)
    local record = Own()
    if not event or not record or event.cal or not ns.Rights.MayIManage(event) then
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

-- Names a moderator of the event (on true) or takes it back, as its
-- organizer or one of its moderators; never its organizer. Not in one made
-- in the game's calendar: named there (Calendar.GiveThere).
function Events.SetModerator(key, guid, on)
    local event = Events.Get(key)
    local record = Own()
    if not event or not record or not guid or guid == event.owner or event.cal or not ns.Rights.MayIManage(event) then
        return false
    end
    if not HasRoom(record.mo, key, LIMITS.statusEvents) or not HasRoom(record.mo and record.mo[key], guid, LIMITS.perEvent) then
        return false
    end
    record.mo = record.mo or {}
    record.mo[key] = record.mo[key] or {}
    local old = record.mo[key][guid]
    record.mo[key][guid] = { on = on == true, at = NextChange(old and old.at) }
    Touch(record, "statuses")
    return true
end

-- Whether the player may change that sign-up's role: anyone's, managing
-- the event; their own, always.
function Events.MayChangeRole(event, guid)
    return event ~= nil and guid ~= nil and (guid == ns.playerGUID or ns.Rights.MayIManage(event))
end

-- Changes a sign-up's role (Events.MayChangeRole), in the player's record
-- (ra), newer than the answer it changes: the answer itself, and so the
-- order they signed up in, stays.
function Events.SetRole(key, guid, role)
    local event = Events.Get(key)
    local record = Own()
    if not record or not Events.MayChangeRole(event, guid) or not Events.ROLE_FIELD[role] then
        return false
    end
    if not HasRoom(record.ra, key, LIMITS.statusEvents) or not HasRoom(record.ra and record.ra[key], guid, LIMITS.perEvent) then
        return false
    end
    record.ra = record.ra or {}
    record.ra[key] = record.ra[key] or {}
    local old = record.ra[key][guid]
    local answer = Events.Answers(key)[guid]
    record.ra[key][guid] = { ro = role, at = math.max(NextChange(old and old.at), (answer and answer.at or 0) + 1) }
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
        record.xs[key][guid] = { st = st, ro = role, no = ns.Data.CleanNote(note), at = NextChange(old and old.at) }
    else
        record.xs[key][guid] = nil
        if not next(record.xs[key]) then
            record.xs[key] = nil
        end
    end
    Touch(record, "external")
    return true
end

-- A calendar event's sign-up list as the player's client just read it
-- (CalendarLists.lua): { at, cr, de, l }, shared in their record (cs).
-- Whether it was.
function Events.ShareList(calendarID, list)
    local record = Own()
    if not record or not HasRoom(record.cs, calendarID, LIMITS.statusEvents) then
        return false
    end
    record.cs = record.cs or {}
    record.cs[calendarID] = list
    Touch(record, "lists")
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
    local all, deletedEvents = Events.All(), Events.Deleted()
    -- A deleted event's are kept while it is in its organizer's record: a
    -- moderator's deletion (pe) counts only with their answer and naming.
    local function Gone(key, at)
        local event = all[key] or deletedEvents[key]
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
    for _, field in ipairs({ "ms", "xs", "mo", "ra" }) do
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
    -- The lists read in the calendar: those of events past or no longer
    -- known (after a day: one may be out of the player's calendar for a
    -- while), and those someone else read since.
    local byID = {}
    for _, list in ipairs({ all, deletedEvents }) do
        for _, event in pairs(list) do
            if event.ci ~= 0 then
                byID[event.ci] = event
            end
        end
    end
    for id, list in pairs(record.cs or {}) do
        local event, newest = byID[id], lists[id]
        if (event and event.tm + Events.KEEP < now) or (not event and list.at + DAY < realNow)
                or (newest and newest.by ~= ns.playerGUID and newest.at > list.at) then
            record.cs[id] = nil
            changed = true
        end
    end
    if record.cs and not next(record.cs) then
        record.cs = nil
    end
    if changed then
        Touch(record, "events")
    end
end

-- The guild's data, the roster or the calendar's guild events changed: the
-- events are worked out again, and the window told a moment later.
function Events.Changed()
    Events.Invalidate()
    ns.Debounce("EventsChanged", 0.2, function()
        ns.Fire("EventsChanged")
    end)
end

function Events.Init()
    ns.On("DataChanged", Events.Changed)
    ns.On("RosterUpdated", function()
        -- Ranks' permissions may have changed too.
        ns.Rights.ForgetRanks()
        Events.Changed()
    end)
    C_Timer.After(30, Events.Tidy)
    C_Timer.NewTicker(600, Events.Tidy)
end
