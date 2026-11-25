-- CalendarRead.lua: reading the game's calendar, for the other calendar
-- files (see Calendar.lua): its guild events in the months looked at, the
-- guild's list of events, the one open event (opened with no click, one at
-- a time), and what this character knows of the calendar.
local _, ns = ...

local Calendar, Read = ns.Calendar, ns.CalendarRead
local Events = ns.Events

local MONTHS = 3             -- months looked at, this one first
local WAIT_STEP = 0.25
local OPEN_TIMEOUT = 8       -- seconds an event may take to open
local LOUD_AFTER = 1         -- seconds after our last open before the game's window hears it again

-- What the calendar holds: [event ID] = { id, offset, day, index, ev }.
local found = {}
local firstSeen = {}         -- [event ID] = GetTime() this client first saw it, this session
local SETTLE = 30            -- seconds a new calendar event takes to come in with its creator's record
local madeSignature          -- what MadeThere gave at the last look, as one text
local goneHere = {}          -- [event ID] = true: others' calendar events found gone (CalendarOrganizer.WatchOthers)
Read.scanned = false         -- the calendar's data came since we asked for it
Read.reads = 0               -- how many times the calendar's data came
Read.busy = false            -- a step with an open event goes on
Read.openKey = nil           -- what we keep open, so a click can change it: one of our events' key

local function Plain(value)
    return ns.Plain(value)
end
Read.Plain = Plain

-- Whether the game's calendar is busy with a change.
function Read.ActionPending()
    return Plain(ns.Try(C_Calendar.IsActionPending)) == true
end

-- Whether the game's calendar window shows.
function Read.WindowShown()
    return CalendarFrame ~= nil and CalendarFrame:IsShown() == true
end

-- Whether the player makes or edits an event in the game's calendar window
-- (one we did not open): nothing is opened then, so it is not lost.
function Read.Drafting()
    local function Shows(frame)
        return frame ~= nil and frame:IsShown() == true
    end
    return Read.WindowShown() and Read.openKey == nil
        and (Shows(CalendarCreateEventFrame) or Shows(CalendarViewEventFrame))
end

-- What this character knows of the calendar (never shared), one table of
-- its own state (Data.OwnState) each:
--   known[key] = { ti, tm, ty, de, lk }: one of its events as the calendar and
--     the addon last agreed on it;
--   created[key] = server time it was sent to the calendar, until seen there;
--   answers[key] = { ci, a = "signed", "tentative" or "none" }: the
--     player's answer as the calendar event ci and the addon last agreed on
--     it (another calendar event standing for the event agreed nothing);
--   statuses[key] = { [GUID] = calendar status }: likewise, the statuses of
--     its sign-ups (forgotten when another calendar event stands for it);
--   moderators[key] = { [GUID] = true or false }: likewise, its moderators;
--   strays[event ID] = start: calendar events of events deleted from the
--     addon, deleted from the calendar too and never taken into the addon.
function Read.State(name)
    local own = ns.Data.OwnState()
    own[name] = own[name] or {}
    return own[name]
end

-- Events ------------------------------------------------------------------------------------------

-- A start as the calendar gives it ({ year, month, monthDay, hour, minute }),
-- as the addon keeps it (Events.Naive).
function Read.StartOf(t)
    if type(t) ~= "table" then
        return nil
    end
    return Events.Naive(t.year, t.month, t.monthDay, t.hour, t.minute)
end

-- The calendar's event type as the addon's (Events.TYPES), "other" if new.
function Read.TypeOf(eventType)
    for _, known in ipairs(Events.TYPES) do
        if known == eventType then
            return known
        end
    end
    return Events.OTHER
end

-- Whether a calendar event (as GetDayEvent or GetEventInfo give it) is
-- locked: true, false, or nil when the game does not say.
function Read.IsLocked(info)
    local locked = Plain(info.isLocked)
    if locked == nil then
        return nil
    end
    return locked == true
end

-- Reads the guild events of the months looked at. Their offsets count from
-- the calendar's current month, which the game's calendar window moves:
-- this month is found from it, and left as the player has it.
function Read.Scan()
    wipe(found)
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local current = ns.Try(C_Calendar.GetMonthInfo, 0)
    if not ns.CanRead(current) then
        return
    end
    local first = (now.year - current.year) * 12 + (now.month - current.month)
    for offset = first, first + MONTHS - 1 do
        local month = ns.Try(C_Calendar.GetMonthInfo, offset)
        for day = 1, ns.CanRead(month) and month.numDays or 0 do
            for index = 1, Plain(ns.Try(C_Calendar.GetNumDayEvents, offset, day)) or 0 do
                local ev = ns.Try(C_Calendar.GetDayEvent, offset, day, index)
                local id = ns.CanRead(ev) and Plain(ev.eventID)
                if type(id) == "number" and id ~= 0 and Plain(ev.calendarType) == "GUILD_EVENT" then
                    found[id] = { id = id, offset = offset, day = day, index = index, ev = ev }
                end
            end
        end
    end
end

-- The guild events read: [event ID] = { id, offset, day, index, ev }.
function Read.Found()
    return found
end

function Read.Find(calendarID)
    return calendarID and calendarID ~= 0 and found[calendarID] or nil
end
Calendar.Find = Read.Find

-- Whether a start falls in the months looked at.
function Read.InRange(tm)
    local now = Events.DateOf(Events.Now())
    local date = Events.DateOf(tm)
    local months = (date.year - now.year) * 12 + (date.month - now.month)
    return months >= 0 and months < MONTHS
end

-- The guild's list of events (it keeps an event that left a member's own
-- calendar): its entry for the event, or nil.
function Read.GuildEntry(calendarID)
    for i = 1, Plain(ns.Try(C_Calendar.GetNumGuildEvents)) or 0 do
        local info = ns.Try(C_Calendar.GetGuildEventInfo, i)
        if ns.CanRead(info) and Plain(info.eventID) == calendarID then
            return info
        end
    end
end

-- Whether one of the guild's events is gone from the player's own calendar
-- for a while, as after they take their sign-up back (about an hour): the
-- game takes no answer from them until it shows there again.
function Calendar.HiddenFromMe(event)
    return Read.scanned and event.ci ~= 0 and Read.InRange(event.tm) and found[event.ci] == nil
        and Read.GuildEntry(event.ci) ~= nil
end

-- Whether the player's own calendar still has them signed up in one of the
-- guild's events (in any way) while the addon no longer does: their sign-up
-- taken back a moment ago, not taken back there yet. They sign up again
-- only once it is (and the event shows again, Calendar.HiddenFromMe).
function Calendar.StillSignedThere(event)
    local entry = Read.scanned and event.ci ~= 0 and found[event.ci] or nil
    return entry ~= nil and ns.States.CalendarAnswer(Plain(entry.ev.inviteStatus)) ~= "none"
end

-- The calendar IDs our events are linked to (those deleted too, until
-- their organizer's record lets them go); not those made in the calendar,
-- which no record has.
function Read.UsedIDs()
    local used = {}
    for _, list in ipairs({ Events.All(), Events.Deleted() }) do
        for _, event in pairs(list) do
            if event.ci ~= 0 and not event.cal then
                used[event.ci] = true
            end
        end
    end
    return used
end

-- The guild events in the player's calendar (and in the guild's list,
-- those gone from it for a while), for Events.lua to take in those no
-- record has: { { ci, ti, tm, ty, lk, invitedBy (their creator's name, or
-- nil), settled (seen for a while) } }. Not those the player created:
-- their own client takes them in (CalendarOrganizer.lua's Adopt).
function Read.MadeThere()
    local made = {}
    if not Read.scanned then
        return made
    end
    local now = GetTime()
    local function Add(id, fields)
        firstSeen[id] = firstSeen[id] or now
        fields.ci, fields.settled = id, now - firstSeen[id] >= SETTLE
        made[#made + 1] = fields
    end
    for id, entry in pairs(found) do
        local ev = entry.ev
        local start = Read.StartOf(ev.startTime)
        local title = Plain(ev.title)
        if Plain(ev.modStatus) ~= "CREATOR" and start and type(title) == "string" then
            local invitedBy = Plain(ev.invitedBy)
            Add(id, { ti = title, tm = start, ty = Read.TypeOf(Plain(ev.eventType)), lk = Read.IsLocked(ev),
                invitedBy = type(invitedBy) == "string" and invitedBy ~= "" and invitedBy or nil })
        end
    end
    for i = 1, Plain(ns.Try(C_Calendar.GetNumGuildEvents)) or 0 do
        local info = ns.Try(C_Calendar.GetGuildEventInfo, i)
        local id = ns.CanRead(info) and Plain(info.eventID)
        local title = id and Plain(info.title)
        if type(id) == "number" and id ~= 0 and not found[id] and type(title) == "string"
                and (Plain(info.calendarType) == nil or Plain(info.calendarType) == "GUILD_EVENT") then
            local year, month, day = Plain(info.year), Plain(info.month), Plain(info.monthDay)
            if type(year) == "number" and type(month) == "number" and type(day) == "number" then
                Add(id, { ti = title, tm = Events.Naive(year, month, day, Plain(info.hour) or 0, Plain(info.minute) or 0),
                    ty = Read.TypeOf(Plain(info.eventType)) })
            end
        end
    end
    return made
end

-- Calendar events of others' events this client found gone from the
-- calendar (deleted in the game's window while their organizer's client
-- was away): their events are not shown here (Events.lua), until the
-- calendar shows them again.
function Read.GoneThere(calendarID)
    return goneHere[calendarID] == true
end

function Read.HideGone(calendarID)
    goneHere[calendarID] = true
end

-- Those the calendar shows again are shown again. Whether any was.
function Read.ShowBack()
    local back = false
    for id in pairs(goneHere) do
        if found[id] or Read.GuildEntry(id) then
            goneHere[id], back = nil, true
        end
    end
    return back
end

-- Whether what MadeThere gives changed since the last look (the events are
-- then worked out again, Events.Changed).
function Read.MadeChanged()
    local parts = {}
    for _, entry in ipairs(Read.MadeThere()) do
        parts[#parts + 1] = table.concat({ entry.ci, entry.ti, entry.tm, entry.ty, tostring(entry.lk),
            tostring(entry.invitedBy), tostring(entry.settled) }, "|")
    end
    table.sort(parts)
    local signature = table.concat(parts, "\n")
    local changed = signature ~= madeSignature
    madeSignature = signature
    return changed
end

-- The calendar events this character created, linked to none of ours
-- (used), with a title and a start: the first one's ID, or nil.
function Read.Landing(title, start, used)
    for id, entry in pairs(found) do
        local ev = entry.ev
        if not used[id] and Plain(ev.modStatus) == "CREATOR" and Plain(ev.title) == title
                and Read.StartOf(ev.startTime) == start then
            return id
        end
    end
end

-- The calendar events this character created that no event of ours is
-- linked to, with the title and start of an event: copies of it, oldest
-- first.
function Read.Copies(event, used)
    local list = {}
    used = used or Read.UsedIDs()
    for id, entry in pairs(found) do
        local ev = entry.ev
        if not used[id] and id ~= event.ci and Plain(ev.modStatus) == "CREATOR" and Plain(ev.title) == event.ti
                and Read.StartOf(ev.startTime) == event.tm then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

-- What /gevents status says: whether the calendar's data was read, and how
-- many guild events in the months read the player created.
function Calendar.Scanned()
    return Read.scanned
end

function Calendar.CreatedCount()
    local count = 0
    for _, entry in pairs(found) do
        if Plain(entry.ev.modStatus) == "CREATOR" then
            count = count + 1
        end
    end
    return count
end

-- The open event ----------------------------------------------------------------------------------
-- The calendar has one open event, shared with the game's calendar window.
-- A step that opens one sets Read.busy until it is done (Finish).

-- While the game's calendar window shows, it would show its own panel for
-- an event we open (on CALENDAR_OPEN_EVENT), widening itself so that the
-- guild window is pushed off the screen and closed; so, only while ours
-- opens, that window does not hear the event. How many of our opens keep
-- it from hearing it; it hears it again a moment after the last.
local quiet = 0

local function Quiet()
    if not Read.WindowShown() or type(CalendarFrame.UnregisterEvent) ~= "function" then
        return false
    end
    if quiet == 0 then
        CalendarFrame:UnregisterEvent("CALENDAR_OPEN_EVENT")
    end
    quiet = quiet + 1
    return true
end

local function Loud()
    quiet = quiet - 1
    if quiet <= 0 then
        quiet = 0
        if CalendarFrame then
            CalendarFrame:RegisterEvent("CALENDAR_OPEN_EVENT")
        end
    end
end

-- The open event's title, or nil when none is open.
function Read.OpenTitle()
    if Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return nil
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    return ns.CanRead(info) and Plain(info.title) or nil
end

-- Whether the calendar's open event is that one (an entry of Read.Found).
function Read.IsOpen(entry)
    if Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return false
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    return ns.CanRead(info) and Plain(info.title) == Plain(entry.ev.title)
        and Read.StartOf(info.time) == Read.StartOf(entry.ev.startTime)
end

-- Calls done(true) once check() is true, or done(false) after timeout
-- seconds.
function Read.Wait(check, timeout, done)
    local waited = 0
    local function Look()
        if check() then
            done(true)
        elseif waited >= timeout then
            done(false)
        else
            waited = waited + WAIT_STEP
            C_Timer.After(WAIT_STEP, Look)
        end
    end
    Look()
end

-- Waits until the calendar is done with the change just made, then calls
-- done().
function Read.WaitDone(done)
    Read.Wait(function()
        return not Read.ActionPending()
    end, OPEN_TIMEOUT, done)
end

-- Opens a calendar event (no click needed); done(ok) once it is open, or
-- not after a while.
function Read.Open(entry, done)
    local quieted = Quiet()
    C_Calendar.OpenEvent(entry.offset, entry.day, entry.index)
    Read.Wait(function()
        return Read.OpenTitle() == Plain(entry.ev.title) and not Read.ActionPending()
    end, OPEN_TIMEOUT, function(ok)
        if quieted then
            C_Timer.After(LOUD_AFTER, Loud)
        end
        done(ok)
    end)
end

function Read.Close()
    if Plain(ns.Try(C_Calendar.IsEventOpen)) == true then
        C_Calendar.CloseEvent()
    end
end

-- The end of a step with an open event: the next one may start.
function Read.Finish()
    Read.busy = false
end

-- Closes the event kept open for a click, if any.
function Read.CloseKept()
    if Read.openKey then
        Read.openKey = nil
        Read.Close()
    end
end
