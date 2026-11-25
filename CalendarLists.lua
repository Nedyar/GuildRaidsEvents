-- CalendarLists.lua: the sign-up lists of the guild's events as the game's
-- calendar has them (see Calendar.lua), read by any member's client and
-- shared with the guild (cs, Pack.lua), so that everyone sees the sign-ups
-- made there by members whose answer is not the addon's: without the
-- addon, or with it off then (Events.Answers).
--
-- Any member may open a guild event and read its list, as the game's
-- calendar window shows it to anyone who views the event. So that not
-- every client opens every event all the time, one client reads each event
-- every two minutes, the members online who run the addon taking turns
-- (Lists.Elected); the others read it every quarter of an hour, in case
-- the one whose turn it is does not. A list is shared only when it changed
-- since anyone shared it: by any other client, only if nobody shared it
-- within a turn after (the one whose turn it is shares it at once). Lists
-- are also read whenever an event is open for another reason: its
-- statuses looked at, or the player viewing it in the game's window.
--
-- What a list keeps: the lines of those signed up in some way (or
-- tentative), with their status, whether they moderate, and when they
-- answered; not the reader's own (their client takes it in itself), nor
-- those whose answer is the addon's (one of their own, not taken back),
-- nor the creator's of an event made in the addon (its organizer's client
-- keeps it in step). Of an event made in the calendar, every line, and
-- its description: its statuses and moderators come from there. And the
-- creator's GUID.
local _, ns = ...

local Calendar, Read, Lists = ns.Calendar, ns.CalendarRead, ns.CalendarLists
local Events, States = ns.Events, ns.States
local Note = Calendar.Note
local Plain = Read.Plain

local READ_EVERY = 120       -- seconds of each turn to read an event, and between two reads by whose turn it is
local OTHERS_EVERY = 900     -- seconds between two reads by any other
local SHARE_WAIT = READ_EVERY + 30  -- seconds any other waits before it shares a list that changed: the
                                    -- one whose turn it is (or the next) reads and shares it meanwhile

local lastRead = {}          -- [event ID] = server time this client last read it
local soon = {}              -- [event ID] = true: read it next, and share it at once (Lists.ReadSoon)

-- The player just changed that calendar event (its description, say): its
-- list is read at the next step, and shared at once.
function Lists.ReadSoon(calendarID)
    soon[calendarID] = true
    Calendar.TickSoon()
end

-- Whether it is the player's turn to read that calendar event (now: server
-- time; now if nil). The members online who run the addon (who shared
-- their record) take turns of READ_EVERY each, one after another, in an
-- order drawn once from their GUIDs (by hash), so the turn always falls on
-- the one who has gone longest without it; each event starts the round at
-- another of them, so that one turn does not bring all the events. Every
-- client works out the same, with nothing sent; when someone comes online
-- or leaves, the round goes on with them in their place in the order.
function Lists.Elected(calendarID, now)
    local guild = ns.Data.CurrentGuild(false)
    local round, hashes = { ns.playerGUID }, { [ns.playerGUID] = ns.Pack.Hash(ns.playerGUID) }
    for guid, record in pairs(guild and guild.members or {}) do
        local member = ns.Roster.members[guid]
        if guid ~= ns.playerGUID and member and member.on and ns.Data.IsShareable(record) then
            round[#round + 1] = guid
            hashes[guid] = ns.Pack.Hash(guid)
        end
    end
    table.sort(round, function(a, b)
        if hashes[a] ~= hashes[b] then
            return hashes[a] < hashes[b]
        end
        return a < b
    end)
    local turn = math.floor((now or ns.Now()) / READ_EVERY)
    return round[(turn + calendarID) % #round + 1] == ns.playerGUID
end

-- When a line of the open event answered, as server time, or nil.
local function ResponseTime(index)
    local t = ns.Try(C_Calendar.EventGetInviteResponseTime, index)
    if not ns.CanRead(t) then
        return nil
    end
    local year, month, day, hour, minute = Plain(t.year), Plain(t.month), Plain(t.monthDay), Plain(t.hour), Plain(t.minute)
    if Plain(t.weekday) == 0 or type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number" then
        return nil
    end
    local at = Events.Naive(year, month, day, hour or 0, minute or 0) - Events.Offset()
    return ns.Lib.IsTime(at) and at or nil
end

-- Whether the line of that member is kept in an event's list (see the top
-- of this file).
local function Kept(event, guid, creator, guild)
    if event.cal then
        return true
    elseif guid == ns.playerGUID or creator then
        return false
    end
    local record = guild and guild.members[guid]
    local own = record and record.su and record.su[event.key]
    return own == nil or own.st == Events.DECLINED
end

-- Whether two lists hold the same (not counting when they were read, nor
-- when each answered).
local function Same(a, b)
    if not a or not b or a.cr ~= b.cr or (a.de or "") ~= (b.de or "") then
        return false
    end
    for guid, line in pairs(a.l) do
        local other = b.l[guid]
        if not other or other.s ~= line.s or (other.m == true) ~= (line.m == true) then
            return false
        end
    end
    for guid in pairs(b.l) do
        if not a.l[guid] then
            return false
        end
    end
    return true
end

-- Reads the list of an event's calendar event, open now, and shares it if
-- it changed since anyone shared it (at once when urgent: the player just
-- changed it there). Not a list with no creator's line: every event's has
-- one, so it is not all there yet. Whether it was shared.
function Lists.Take(event, urgent)
    if not event or event.ci == 0 or Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return false
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    if not ns.CanRead(info) then
        return false
    end
    local guild = ns.Data.CurrentGuild(false)
    local list = { l = {}, de = event.cal and (Plain(info.description) or "") or nil }
    for index = 1, Plain(ns.Try(C_Calendar.GetNumInvites)) or 0 do
        local invite = ns.Try(C_Calendar.EventGetInvite, index)
        local guid = ns.CanRead(invite) and Plain(invite.guid)
        local status = guid and Plain(invite.inviteStatus)
        if type(guid) == "string" and ns.Lib.IsGUID(guid) and type(status) == "number" then
            local creator = Plain(invite.modStatus) == "CREATOR"
            if creator then
                list.cr = guid
            end
            if States.CalendarAnswer(status) ~= "none" and Kept(event, guid, creator, guild) then
                list.l[guid] = { s = status, m = Plain(invite.modStatus) == "MODERATOR", r = ResponseTime(index) }
            end
        end
    end
    if not list.cr then
        return false
    end
    local readAt = ns.Now()
    lastRead[event.ci] = readAt
    if list.de == "" then
        list.de = nil
    end
    local function Share()
        local newest = Events.CalendarList(event.ci)
        if Same(list, newest) or (newest and newest.by ~= ns.playerGUID and newest.at >= readAt) then
            return false
        end
        list.at = math.max(ns.Now(), newest and newest.at + 1 or 0)
        if Events.ShareList(event.ci, list) then
            Note("from the calendar", "shared its list of sign-ups: " .. tostring(event.ti))
            return true
        end
        return false
    end
    urgent = urgent or soon[event.ci]
    soon[event.ci] = nil
    if Same(list, Events.CalendarList(event.ci)) then
        return false
    elseif urgent or Lists.Elected(event.ci) then
        return Share()
    end
    -- Any other client waits a turn: the one whose turn it is (or the
    -- next) reads it too, and shares it if it changed.
    C_Timer.After(SHARE_WAIT, Share)
    return false
end

-- The next event whose list to read: to come, in the player's calendar,
-- and not read (by this client, or shared by anyone) for READ_EVERY when
-- it is the player's turn, else OTHERS_EVERY (counted from when it
-- first saw it, so that a new event is not read by everyone at once); the
-- longest overdue.
local function EventToRead()
    local best
    local now, eventsNow = ns.Now(), Events.Now()
    -- The events, and those made in the calendar whose creator is not
    -- known yet (their list says who).
    local candidates, known = {}, {}
    for _, event in pairs(Events.All()) do
        candidates[#candidates + 1] = event
        known[event.ci] = true
    end
    local used = Read.UsedIDs()
    for _, made in ipairs(Read.MadeThere()) do
        if not known[made.ci] and not used[made.ci] then
            candidates[#candidates + 1] = { key = "?/" .. made.ci, ci = made.ci, ti = made.ti, tm = made.tm, cal = true }
        end
    end
    for _, event in ipairs(candidates) do
        local entry = event.ci ~= 0 and event.tm > eventsNow and Read.Find(event.ci)
        if entry then
            local elected = Lists.Elected(event.ci)
            if not elected and not lastRead[event.ci] then
                lastRead[event.ci] = now
            end
            local newest = Events.CalendarList(event.ci)
            local last = math.max(lastRead[event.ci] or 0, newest and newest.at or 0)
            local late = soon[event.ci] and math.huge or now - last - (elected and READ_EVERY or OTHERS_EVERY)
            if late >= 0 and (not best or late > best.late) then
                best = { event = event, entry = entry, late = late }
            end
        end
    end
    return best
end

-- A step of the look at the calendar (Tick), while the game's calendar
-- window is closed (opening an event there would show it): reads the list
-- of the next event that needs it. Whether a step goes on.
function Lists.ReadNext()
    if Read.WindowShown() then
        return false
    end
    local item = EventToRead()
    if not item then
        return false
    end
    lastRead[item.event.ci] = ns.Now()
    Read.openKey = nil
    Read.busy = true
    Read.Open(item.entry, function(ok)
        if ok then
            Lists.Take(Events.Get(item.event.key) or item.event)
        end
        Read.Close()
        Read.Finish()
    end)
    return true
end
