-- Calendar.lua: keeps the game's calendar and the guild's events in step,
-- both ways, wherever a change is made.
--
-- Each event is a guild sign-up event in the game's calendar, made by its
-- organizer's client. What WoW Forever lets an addon do there (found with
-- /gevents probe, build 71037):
--   - creating and changing an event only inside a click of the player (a
--     "hardware event"), with the call first in the click. The addon's
--     buttons do it in their own click: Create, Save, Restore event, and
--     Create in calendar for next week's event of a weekly one. A new or
--     restored event comes into the addon once the calendar has it, and not
--     at all when the calendar refuses it (its limit of events created). A
--     change made with no click of the organizer's (an officer's) goes with
--     their next click anywhere in the addon;
--   - deleting an event, opening one, signing up, signing up as tentative,
--     taking a sign-up back, and giving a sign-up a status (confirmed,
--     standby, out) at any time, with no click. Each client does these by
--     itself, one at a time (the calendar has one open event).
-- The game's calendar does not let a sign-up go straight from signed up to
-- tentative or back: it is taken back first, and the event then leaves
-- that player's calendar for about an hour; the new answer goes in once it
-- is back. Guild events take sign-ups, not invitations, so those made
-- outside the game stay in the addon only.
--
-- From the calendar to the addon: the organizer's client takes into the
-- addon what was changed in the game's calendar window (title, time, type,
-- description, whether it is locked, statuses), cancels the events deleted
-- there, and adds the
-- guild events its character created there; each member's client takes
-- their own sign-up made there. For each field, the side that changed
-- since both last agreed wins; when both did, the calendar. A locked event
-- takes no answers: a member's answer waits until it is unlocked.
--
-- It works with the game's calendar window open, but opens nothing while
-- the player makes, edits or views an event in that window, so as not to
-- lose it. While that window shows, it would show its own panel for an
-- event we open (on CALENDAR_OPEN_EVENT), widening itself so that the
-- guild window is pushed off the screen and closed; so, only while ours
-- opens, that window does not hear the event (Quiet).
local _, ns = ...
local L = ns.L

local Calendar = {}
ns.Calendar = Calendar

local Events = ns.Events

local TICK = 10              -- seconds between looks at the calendar
local WAIT_STEP = 0.25
local OPEN_TIMEOUT = 8       -- seconds an event may take to open
local ACTION_TIMEOUT = 8
local RETRY = 300            -- seconds before the same answer is tried again
local MIRROR_EVERY = 120     -- seconds between two looks at one event's sign-ups
local READ_EVERY = 600       -- seconds between two requests of the calendar's data
local MONTHS = 3             -- months looked at, this one first
local IN_FLIGHT = 60         -- seconds a change sent may take to show in the calendar
local RECREATE_AFTER = 600   -- seconds before an event sent but never seen is created again
local DELETE_RETRY = 30      -- seconds between two tries to delete one calendar event

-- What the calendar holds: [event ID] = { id, offset, day, index, ev }.
local found = {}
local firstOffset = 0        -- the offset of this month from the calendar's current one
local scanned = false        -- the calendar's data came since we asked for it
local busy = false           -- a step with an open event goes on
local openKey                -- our event kept open, so a click can change it
local preparedKey            -- the event the form is changing (EventForm.lua)
local stillPrepared          -- function: whether the form still changes it
local tried = {}             -- [key] = { at = GetTime(), has, wanted } of the last answer sent
local lastUpdate             -- { key, previous } of the last change sent, until the game takes it
local lastCreate             -- the key of the last event created with a click, until the game takes it
local blocked = false        -- the game refused one of our calls (set during the call)
local mirrored = {}          -- [key] = { at = GetTime(), signature } of the last look at its sign-ups
local lastRead = 0
local sent = {}              -- [key] = { kind, at = GetTime() }: changes and deletions just sent
-- Our calendar events found missing: [key] = { at = GetTime(), reads }.
-- Deleted only if still missing once the calendar's data came again (asked
-- for at once), not while it is still loading.
local missing = {}
local reads = 0              -- how many times the calendar's data came
local seen = {}              -- [key] = true: its calendar event was seen in this session
local deleteTried = {}       -- [event ID] = GetTime() of the last try to delete it
local adoptTried = {}        -- [event ID] = true: taken into the addon once already
-- The game refused a deletion with no click: deletions then wait, with the
-- event kept open, for the organizer's next click.
local deleteNeedsClick = false
-- The last event of ours sent with its Create in calendar button (next
-- week's of a weekly one): { key, kind = "new", at }; if the calendar
-- refuses it, it waits again.
local creating
-- Sent to the calendar, not in the addon yet: a new event of the form's,
-- { fields, ti, tm, at, done, failed }, and a cancelled event of ours made
-- again, { key, ti, tm, at }. The addon takes each once the calendar has it.
local pendingNew, pendingRestore
local CREATE_TIMEOUT = 8     -- seconds the calendar may take to answer one
Calendar.lastError = nil     -- what the game last said went wrong
-- What became of the last change sent to the calendar (for /gevents
-- status): { what, at = server time, result }.
Calendar.lastSent = nil

local function Note(what, result)
    Calendar.lastSent = { what = what, at = ns.Now(), result = result }
    ns.Debug("calendar: %s: %s", what, result)
end
Calendar.Note = Note

local function Plain(value)
    return ns.Plain(value)
end

local function Pending()
    return Plain(ns.Try(C_Calendar.IsActionPending)) == true
end

-- Whether the game's calendar window shows.
local function WindowShown()
    return CalendarFrame ~= nil and CalendarFrame:IsShown() == true
end

-- Whether the player makes or edits an event in the game's calendar window
-- (one we did not open): nothing is opened then, so it is not lost.
local function Drafting()
    local function Shows(frame)
        return frame ~= nil and frame:IsShown() == true
    end
    return WindowShown() and openKey == nil and (Shows(CalendarCreateEventFrame) or Shows(CalendarViewEventFrame))
end

-- How many of our opens keep the game's calendar window from hearing
-- CALENDAR_OPEN_EVENT; it hears it again a moment after the last.
local quiet = 0
local LOUD_AFTER = 1

local function Quiet()
    if not WindowShown() or type(CalendarFrame.UnregisterEvent) ~= "function" then
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

-- What this character knows of the calendar (never shared):
--   known[key] = { ti, tm, ty, de, lk }: one of its events as the calendar and
--     the addon last agreed on it;
--   created[key] = server time it was sent to the calendar, until seen there;
--   gone[key] = true: its calendar event is gone while it was cancelled, so
--     restoring it creates it again;
--   byCalendar[key] = true: cancelled because its calendar event went; if
--     that comes back, the event is restored, never deleted;
--   answers[key] = { ci, a = "signed", "tentative" or "none" }: the
--     player's answer as the calendar event ci and the addon last agreed on
--     it (a calendar event made again, restoring the event, agreed nothing);
--   statuses[key] = { [GUID] = calendar status }: likewise, the statuses of
--     its sign-ups (forgotten when its calendar event is made again);
--   strays[event ID] = start: calendar events of events deleted from the
--     addon, deleted from the calendar too and never taken into the addon.
local function State(name)
    local own = ns.Data.OwnState()
    own[name] = own[name] or {}
    return own[name]
end

-- Reading the calendar ----------------------------------------------------------------------------

local function StartOf(t)
    if type(t) ~= "table" then
        return nil
    end
    return Events.Naive(t.year, t.month, t.monthDay, t.hour, t.minute)
end

-- The calendar's event type as the addon's (Events.TYPES), "other" if new.
local function TypeOf(eventType)
    for _, known in ipairs(Events.TYPES) do
        if known == eventType then
            return known
        end
    end
    return Events.OTHER
end

-- The month offsets count from the calendar's current month, which the
-- game's calendar window moves: this month is found from it, and left as
-- the player has it.
local function Scan()
    wipe(found)
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local current = ns.Try(C_Calendar.GetMonthInfo, 0)
    if not ns.CanRead(current) then
        return
    end
    firstOffset = (now.year - current.year) * 12 + (now.month - current.month)
    for offset = firstOffset, firstOffset + MONTHS - 1 do
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

-- Whether a start falls in the months looked at.
local function InRange(tm)
    local now = Events.DateOf(Events.Now())
    local date = Events.DateOf(tm)
    local months = (date.year - now.year) * 12 + (date.month - now.month)
    return months >= 0 and months < MONTHS
end

-- The guild's list of events (it keeps an event that left a member's own
-- calendar): its entry for the event, or nil.
local function GuildEntry(calendarID)
    for i = 1, Plain(ns.Try(C_Calendar.GetNumGuildEvents)) or 0 do
        local info = ns.Try(C_Calendar.GetGuildEventInfo, i)
        if ns.CanRead(info) and Plain(info.eventID) == calendarID then
            return info
        end
    end
end

function Calendar.Find(calendarID)
    return calendarID and calendarID ~= 0 and found[calendarID] or nil
end

-- Whether one of the guild's events is gone from the player's own calendar
-- for a while, as after they take their sign-up back (about an hour): the
-- game takes no answer from them until it shows there again.
function Calendar.HiddenFromMe(event)
    return scanned and event.ci ~= 0 and not event.x and InRange(event.tm) and found[event.ci] == nil
        and GuildEntry(event.ci) ~= nil
end

-- What the calendar must show of an event, to see whether it changed.
function Calendar.Signature(event)
    return table.concat({ event.ti, event.tm, event.ty, event.de or "" }, "|")
end

-- The calendar IDs our events are linked to.
local function UsedIDs()
    local used = {}
    for _, event in pairs(Events.All()) do
        if event.ci ~= 0 then
            used[event.ci] = true
        end
    end
    return used
end

-- The calendar events this character created that no event of ours is
-- linked to, with the title and start of an event: copies of it.
local function Copies(event, used)
    local list = {}
    used = used or UsedIDs()
    for id, entry in pairs(found) do
        local ev = entry.ev
        if not used[id] and id ~= event.ci and Plain(ev.modStatus) == "CREATOR" and Plain(ev.title) == event.ti
                and StartOf(ev.startTime) == event.tm then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

-- Whether a calendar event (as GetDayEvent or GetEventInfo give it) is
-- locked: true, false, or nil when the game does not say.
local function IsLocked(info)
    local locked = Plain(info.isLocked)
    if locked == nil then
        return nil
    end
    return locked == true
end

-- A field's value in the addon, and as both last agreed on it, the way the
-- calendar has it (lk: locked or not; what was agreed before it had none).
local function AddonValue(event, field)
    if field == "de" then
        return event.de or ""
    elseif field == "lk" then
        return event.lk == true
    end
    return event[field]
end

local function AgreedValue(agreed, field)
    if field == "lk" then
        return agreed.lk == true
    end
    return agreed[field]
end

local SYNCED = { "ti", "tm", "ty", "de", "lk" }

local function Agree(key, event)
    State("known")[key] = { ti = event.ti, tm = event.tm, ty = event.ty, de = event.de or "", lk = event.lk == true }
end

-- One of our events linked to a calendar event made anew (restoring it):
-- the statuses go to it from the addon, as nothing was agreed with it.
local function Linked(key, calendarID)
    State("statuses")[key] = nil
    mirrored[key] = nil
    Events.SetCalendarID(key, calendarID)
end

-- Our new events, once in the calendar: their event IDs into the records.
local function Link()
    local used = UsedIDs()
    local created = State("created")
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci == 0 and not event.x then
            local copy = Copies(event, used)[1]
            if copy then
                used[copy.id] = true
                created[key] = nil
                Agree(key, event)
                Linked(key, copy.id)
            end
        end
    end
end

-- Whether a change or deletion of the event was just sent.
local function InFlight(key, kind)
    local item = sent[key]
    return item ~= nil and (kind == nil or item.kind == kind) and GetTime() - item.at < IN_FLIGHT
end

-- Both ways -------------------------------------------------------------------------------------

-- Brings one of our events and its calendar event together, field by
-- field. cal: the calendar's values (de only once the event was opened).
local function Reconcile(key, event, cal)
    local known = State("known")
    local agreed = known[key]
    if not agreed then
        -- First look: what the calendar has, so a change made in the
        -- addon meanwhile goes there.
        agreed = { ti = cal.ti, tm = cal.tm, ty = cal.ty, de = cal.de or event.de or "", lk = cal.lk }
        if cal.lk == nil then
            agreed.lk = event.lk == true
        end
        known[key] = agreed
    end
    local adopt
    for _, field in ipairs(SYNCED) do
        local mine, theirs, was = AddonValue(event, field), cal[field], AgreedValue(agreed, field)
        if theirs ~= nil then
            if mine == theirs then
                agreed[field] = theirs
            elseif mine == was or theirs ~= was then
                -- Changed in the calendar (or on both sides): the calendar's.
                adopt = adopt or {}
                adopt[field] = theirs
            end
        end
    end
    if not adopt then
        return
    end
    local fields = {}
    for _, field in ipairs({ "ty", "ti", "tm", "de", "sl", "ml", "ii", "wk", "ac", "lk" }) do
        fields[field] = event[field]
    end
    for field, value in pairs(adopt) do
        fields[field] = value
    end
    if Events.Change(key, fields) then
        for field, value in pairs(adopt) do
            agreed[field] = value
        end
        Note("from the calendar", "took a change made there: " .. event.ti)
    end
end

-- Whether the calendar should take a change of one of our events.
local function NeedsUpdate(key, event)
    local agreed = State("known")[key]
    if not agreed then
        return false
    end
    for _, field in ipairs(SYNCED) do
        if AddonValue(event, field) ~= AgreedValue(agreed, field) then
            return true
        end
    end
    return false
end

-- The organizer's client: what the calendar shows of each of their events,
-- into the addon. A calendar event missing for a while: deleted there, so
-- the event is cancelled (or, when we deleted it ourselves and the event
-- was restored since, created again).
local function Landed(key, entry)
    local item, agreed = sent[key], State("known")[key]
    if not item then
        return
    elseif item.kind == "delete" and not entry then
        sent[key] = nil
    elseif item.kind == "update" and entry and agreed and Plain(entry.ev.title) == agreed.ti
            and StartOf(entry.ev.startTime) == agreed.tm and TypeOf(Plain(entry.ev.eventType)) == agreed.ty
            and (IsLocked(entry.ev) == nil or IsLocked(entry.ev) == AgreedValue(agreed, "lk")) then
        sent[key] = nil
    end
end

local function Watch()
    local now, clock = Events.Now(), GetTime()
    local gone, known, byCalendar = State("gone"), State("known"), State("byCalendar")
    local used = UsedIDs()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci ~= 0 then
            Landed(key, Calendar.Find(event.ci))
        end
        if event.owner == ns.playerGUID and event.ci ~= 0 and event.tm > now and not InFlight(key) then
            local entry = Calendar.Find(event.ci)
            -- The guild's list stands for events beyond the months looked
            -- at; it may still name one just deleted.
            local listed = not entry and not InRange(event.tm) and GuildEntry(event.ci)
            if entry then
                seen[key] = true
            end
            if entry and event.x and byCalendar[key] then
                -- Back in the calendar: it was not deleted after all.
                byCalendar[key], gone[key] = nil, nil
                Events.Cancel(key, false)
            elseif entry or listed then
                missing[key] = nil
                if not event.x then
                    local ev = entry and entry.ev
                    Reconcile(key, event, {
                        ti = Plain(entry and ev.title or listed.title),
                        tm = entry and StartOf(ev.startTime) or Events.Naive(listed.year, listed.month, listed.monthDay,
                            listed.hour, listed.minute),
                        ty = TypeOf(Plain(entry and ev.eventType or listed.eventType)),
                        -- The guild's list does not say whether it is locked.
                        lk = entry and IsLocked(ev),
                    })
                end
            elseif event.x and InRange(event.tm) then
                gone[key] = true
            elseif InRange(event.tm) then
                -- Gone from its creator's calendar: deleted there. At once
                -- if it was seen in this session; else once the calendar's
                -- data came again, so not while it is still loading.
                local deleted = seen[key]
                if not deleted and not missing[key] then
                    missing[key] = { at = clock, reads = reads }
                    ns.Try(C_Calendar.OpenCalendar)
                elseif not deleted and reads > missing[key].reads then
                    deleted = true
                elseif not deleted and clock - missing[key].at > 3 then
                    missing[key].at = clock
                    ns.Try(C_Calendar.OpenCalendar)
                end
                if deleted then
                    missing[key], seen[key] = nil, nil
                    local copy = Copies(event, used)[1]
                    if copy then
                        -- Another of its copies stands for it.
                        used[copy.id] = true
                        Linked(key, copy.id)
                    elseif gone[key] then
                        gone[key], known[key] = nil, nil
                        Events.SetCalendarID(key, 0)
                    else
                        gone[key], byCalendar[key] = true, true
                        Note("from the calendar", "deleted there, so cancelled: " .. event.ti)
                        Events.Cancel(key)
                    end
                end
            end
        end
    end
end

-- The organizer's client: the guild events their character created in the
-- game's calendar window, into the addon as theirs.
local function Adopt()
    local used, now, strays = UsedIDs(), Events.Now(), State("strays")
    local mine = {}
    for _, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID then
            mine[(event.ti or "") .. "|" .. tostring(event.tm)] = true
        end
    end
    for id, entry in pairs(found) do
        local ev = entry.ev
        local start = StartOf(ev.startTime)
        local sentByForm = pendingNew ~= nil and Plain(ev.title) == pendingNew.ti and start == pendingNew.tm
        if not used[id] and not adoptTried[id] and not strays[id] and not sentByForm and Plain(ev.modStatus) == "CREATOR"
                and start and start > now
                and not mine[tostring(Plain(ev.title)) .. "|" .. tostring(start)] then
            adoptTried[id] = true
            local key = Events.Create({ ty = TypeOf(Plain(ev.eventType)), ti = Plain(ev.title), tm = start, ml = 0 })
            if key then
                Events.SetCalendarID(key, id)
                Agree(key, Events.Get(key))
                Note("from the calendar", "added an event made there: " .. tostring(Plain(ev.title)))
            end
        end
    end
end

-- The open event, read as the calendar has it, into the addon (its
-- description shows only there).
local function ReconcileOpen(key)
    local event = Events.Get(key)
    local info = ns.Try(C_Calendar.GetEventInfo)
    if not event or event.owner ~= ns.playerGUID or event.x or InFlight(key) or not ns.CanRead(info) then
        return
    end
    Reconcile(key, event, {
        ti = Plain(info.title), tm = StartOf(info.time), ty = TypeOf(Plain(info.eventType)),
        de = Plain(info.description) or "", lk = IsLocked(info),
    })
end

-- What waits for the organizer -------------------------------------------------------------------

-- What one of the player's own events needs in the calendar: "create",
-- "update", "delete" or nil.
local function KindOf(key, event, now)
    local entry = Calendar.Find(event.ci)
    if event.x then
        return entry and not State("byCalendar")[key] and "delete" or nil
    elseif event.tm <= now then
        return nil
    elseif event.ci == 0 then
        local created = State("created")
        if created[key] and ns.Now() - created[key] > RECREATE_AFTER and InRange(event.tm) then
            created[key] = nil
        end
        return not created[key] and "create" or nil
    elseif entry and NeedsUpdate(key, event) then
        return "update"
    end
end

-- The changes the player's own events wait for in the calendar, in order:
-- { kind = "create", "update" or "delete", key, event }.
function Calendar.Pending()
    local list = {}
    if not ns.playerGUID or not ns.Roster.ready or not scanned then
        return list
    end
    local now = Events.Now()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID then
            local kind = KindOf(key, event, now)
            if kind and not InFlight(key, kind) then
                list[#list + 1] = { kind = kind, key = key, event = event }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.event.tm ~= b.event.tm then
            return a.event.tm < b.event.tm
        end
        return a.key < b.key
    end)
    return list
end

local function OpenTitle()
    if Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return nil
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    return ns.CanRead(info) and Plain(info.title) or nil
end

-- Fills the calendar's open event (a new one, or ours opened) with the
-- event's fields.
local function Fill(event)
    local date = Events.DateOf(event.tm)
    C_Calendar.EventSetTitle(event.ti)
    C_Calendar.EventSetType(event.ty)
    C_Calendar.EventSetDate(date.month, date.day, date.year)
    C_Calendar.EventSetTime(date.hour, date.minute)
    C_Calendar.EventSetDescription(event.de or "")
    local lock = event.lk and C_Calendar.EventSetLocked or C_Calendar.EventClearLocked
    if lock then
        lock()
    end
end

-- Creates an event in the calendar: inside a click, first thing.
function Calendar.CreateNow(event)
    C_Calendar.CreateGuildSignUpEvent()
    Fill(event)
    C_Calendar.AddEvent()
end

-- Calls fn, a call to the game's calendar; whether the game took it.
local function Try(what, fn)
    blocked = false
    local ok, err = pcall(fn)
    if not ok then
        Note(what, "error: " .. tostring(err))
        Calendar.lastError = L["The game's calendar refused the change. Click again to retry."]
        return false
    end
    if blocked then
        return false
    end
    Calendar.lastError = nil
    Note(what, "sent")
    return true
end

-- In the click of the form's Create (EventForm.lua): the new event goes to
-- the game's calendar first, fields as Events.Create takes them. The addon
-- takes it once the calendar has it, then done(key); if the calendar
-- refuses it, failed(why), and the addon takes nothing. Returns whether it
-- was sent.
function Calendar.CreateFirst(fields, done, failed)
    if Pending() then
        Note("create", "not sent: the calendar is busy with another change")
        return false
    end
    local event = { ti = fields.ti, tm = fields.tm, ty = fields.ty, de = fields.de ~= "" and fields.de or nil,
        lk = fields.lk == true }
    if not Try("create", function()
        Calendar.CreateNow(event)
    end) then
        return false
    end
    pendingNew = { fields = fields, ti = fields.ti, tm = fields.tm - fields.tm % 60, at = GetTime(), done = done,
        failed = failed }
    return true
end

-- Whether a new event of the form's waits for the calendar's answer.
function Calendar.Creating()
    return pendingNew ~= nil
end

-- The form changing one of our events (EventForm.lua) keeps it open, so
-- the click that saves it changes the calendar too: key, or nil once the
-- form closes; still(), whether the form still changes it.
function Calendar.Prepare(key, still)
    preparedKey, stillPrepared = key, still
    if key then
        Calendar.TickSoon()
    elseif openKey and not busy then
        -- Closed at once, as the game's window does.
        openKey = nil
        if Plain(ns.Try(C_Calendar.IsEventOpen)) == true then
            C_Calendar.CloseEvent()
        end
    end
end

-- In the click that saves a change (EventForm.lua), before our record has
-- it: whether the calendar took it. If not, it goes with a later click
-- (the organizer's, for an officer the game does not let change it).
function Calendar.UpdateFirst(key, fields)
    local event = Events.Get(key)
    if not event or event.ci == 0 or openKey ~= key or OpenTitle() == nil or Pending() then
        Note("update", "not sent: the event was not open yet")
        return false
    end
    local mine = event.owner == ns.playerGUID
    if not mine and Plain(ns.Try(C_Calendar.EventCanEdit)) ~= true then
        return false
    end
    local new = { ti = fields.ti, tm = fields.tm, ty = fields.ty, de = fields.de or "", lk = fields.lk == true }
    sent[key] = { kind = "update", at = GetTime() }
    if mine then
        lastUpdate = { key = key, previous = State("known")[key] }
        State("known")[key] = new
    end
    if Try("update", function()
        Fill(new)
        C_Calendar.UpdateEvent()
    end) then
        return true
    end
    sent[key] = nil
    return false
end

local Wait, Finish, Open, Close    -- steps with an open event (below)

-- Whether the calendar's open event is that one.
local function IsOpen(entry)
    if Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return false
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    return ns.CanRead(info) and Plain(info.title) == Plain(entry.ev.title)
        and StartOf(info.time) == StartOf(entry.ev.startTime)
end

-- Deletes the open event: whether it was sent.
local function RemoveOpen(key, entry, main)
    deleteTried[entry.id] = GetTime()
    local canRemove = ns.Try(C_Calendar.ContextMenuEventCanRemove, entry.offset, entry.day, entry.index)
    if Plain(canRemove) == false then
        if main then
            Calendar.lastError = L["The game's calendar does not let this event be deleted now. Try again after /reload."]
        end
        Note("delete", "not sent: the game says it cannot be deleted now")
        return false
    end
    if main then
        sent[key] = { kind = "delete", at = GetTime() }
        State("gone")[key] = true
    end
    return Try("delete", function()
        C_Calendar.ContextMenuSelectEvent(entry.offset, entry.day, entry.index)
        C_Calendar.ContextMenuEventRemove()
    end)
end

-- Deletes one calendar event (no click needed): key, the event it is or a
-- copy of. The game deletes only the open event (as its own window does,
-- on the event selected): when it is not, it is opened first and deleted
-- a moment later. Whether it was deleted at once.
local function Delete(key, entry, main)
    local last = deleteTried[entry.id]
    if last and GetTime() - last < DELETE_RETRY then
        return false
    elseif IsOpen(entry) then
        return RemoveOpen(key, entry, main)
    elseif busy then
        return false
    end
    deleteTried[entry.id] = GetTime()
    busy = true
    openKey = nil
    Open(entry, function(ok)
        if ok and not RemoveOpen(key, entry, main) and blocked then
            deleteNeedsClick = true
        end
        Wait(function()
            return not Pending()
        end, ACTION_TIMEOUT, function()
            Close()
            Finish()
        end)
    end)
    return false
end

-- In the click that cancels an event (EventView.lua), before our record has
-- it. If the game does not take it, it is tried again by itself, and the
-- organizer's client deletes it when an officer cannot.
function Calendar.DeleteFirst(key)
    State("byCalendar")[key] = nil
    local event = Events.Get(key)
    local entry = event and Calendar.Find(event.ci)
    if not entry then
        return false
    end
    deleteTried[entry.id] = nil
    return Delete(key, entry, true)
end

-- The click that restores a cancelled event (EventView.lua): for its
-- organizer, the calendar first; the event is restored in the addon once
-- the calendar has it again, and stays cancelled if it refuses it. Whether
-- it was sent (or, for someone else's or a past one, restored).
function Calendar.RestoreFirst(key)
    local event = Events.Get(key)
    if not event then
        return false
    end
    if event.owner ~= ns.playerGUID or event.tm <= Events.Now() or event.ci == 0 then
        -- Not the player's to create, over, or never in the calendar (it
        -- waits for its Create in calendar button again): the addon only.
        return Events.Cancel(key, false)
    end
    if Pending() then
        Calendar.lastError = L["The game's calendar refused the change. Click again to retry."]
        return false
    end
    if not Try("create", function()
        Calendar.CreateNow(event)
    end) then
        return false
    end
    pendingRestore = { key = key, ti = event.ti, tm = event.tm, at = GetTime() }
    ns.Fire("CalendarPending")
    return true
end

-- Whether that event waits for the calendar to have it again.
function Calendar.Restoring(key)
    return pendingRestore ~= nil and pendingRestore.key == key
end

-- Does the first change the player's own events wait for that can go now:
-- call it first thing in a click of the player. Returns what it did (the
-- pending item), or nil.
function Calendar.RunPending()
    if not scanned or Pending() then
        return nil
    end
    -- Where the events are now: the player may have moved the calendar's month.
    Scan()
    for _, item in ipairs(Calendar.Pending()) do
        local event = item.event
        -- A creation waits for its own button (Calendar.SendNow): with any
        -- click, the game would refuse so many so fast.
        if item.kind == "update" and openKey == item.key and OpenTitle() ~= nil then
            -- The event opened beforehand, with no click (Tick).
            lastUpdate = { key = item.key, previous = State("known")[item.key] }
            Agree(item.key, event)
            sent[item.key] = { kind = "update", at = GetTime() }
            if Try("update", function()
                Fill(event)
                C_Calendar.UpdateEvent()
            end) then
                return item
            end
            return nil
        elseif item.kind == "delete" then
            local entry = Calendar.Find(event.ci)
            if entry and Delete(item.key, entry, true) then
                return item
            end
        end
    end
    return nil
end

-- Whether one of the player's events waits to be created in the calendar
-- with its own button (next week's of a weekly one).
function Calendar.Unsent(event)
    return event ~= nil and event.owner == ns.playerGUID and scanned and KindOf(event.key, event, Events.Now()) == "create"
end

-- Why that button is off now, or nil: the game does not take a new event
-- yet (as its own Create button, C_Calendar.CanAddEvent), or it reported
-- its limit of events created.
function Calendar.SendBlocked()
    if Calendar.AtLimit() then
        return Calendar.LimitText()
    elseif not ns.Rights.MayCreate() or Pending() then
        return L["Syncing the calendar..."]
    end
end

-- The click of that button: creates the event in the calendar. Whether it
-- was sent; it comes linked once the calendar has it.
function Calendar.SendNow(key)
    local event = Events.Get(key)
    if not Calendar.Unsent(event) or Calendar.SendBlocked() then
        return false
    end
    State("created")[key] = ns.Now()
    lastCreate = key
    creating = { key = key, kind = "new", at = GetTime() }
    if Try("create", function()
        Calendar.CreateNow(event)
    end) then
        ns.Fire("CalendarPending")
        return true
    end
    State("created")[key] = nil
    creating = nil
    return false
end

-- For the buttons of the addon's window: the first thing their click
-- does, so a change waiting for the organizer goes out with it.
function Calendar.OnClick()
    local ok, done = pcall(Calendar.RunPending)
    if ok and done then
        ns.Fire("CalendarPending")
    end
end

-- Steps with no click ----------------------------------------------------------------------------

-- Calls done(true) once check() is true, or done(false) after timeout
-- seconds.
function Wait(check, timeout, done)
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

function Finish()
    busy = false
end

function Open(entry, done)
    local quieted = Quiet()
    C_Calendar.OpenEvent(entry.offset, entry.day, entry.index)
    Wait(function()
        return OpenTitle() == Plain(entry.ev.title) and not Pending()
    end, OPEN_TIMEOUT, function(ok)
        if quieted then
            C_Timer.After(LOUD_AFTER, Loud)
        end
        done(ok)
    end)
end

function Close()
    if Plain(ns.Try(C_Calendar.IsEventOpen)) == true then
        C_Calendar.CloseEvent()
    end
end

-- The player's answer in the calendar, as the addon has it: "signed",
-- "tentative" or "none". In the calendar, a status the organizer gave
-- counts as signed up.
local function CalendarAnswer(status)
    local enum = Enum.CalendarStatus
    if status == enum.Signedup or status == enum.Confirmed or status == enum.Standby or status == enum.Out then
        return "signed"
    elseif status == enum.Tentative then
        return "tentative"
    end
    return "none"
end

-- The answer the calendar should have, and whether the player's sign-up
-- has a status in the addon.
local function WantedAnswer(event)
    local mine = Events.Mine(event)
    local managed = mine ~= nil and mine.status ~= Events.NONE
    if mine and mine.st == Events.SIGNED then
        return "signed", managed
    elseif mine and mine.st == Events.TENTATIVE then
        return "tentative", managed
    end
    return "none", false
end

-- An answer given in the game's calendar, into the addon.
local function TakeAnswer(key, event, has)
    local mine = Events.Mine(event)
    if has == "signed" then
        Events.Answer(key, Events.SIGNED, mine and mine.ro or Events.LastRole(), mine and mine.no)
    elseif has == "tentative" then
        Events.Answer(key, Events.TENTATIVE, mine and mine.ro or Events.LastRole(), mine and mine.no)
    else
        Events.Answer(key, nil)
    end
    Note("from the calendar", "took your answer given there: " .. event.ti)
end

-- The player's answers given in the calendar, into the addon; then the
-- first of their answers the calendar does not have yet: key, its
-- calendar entry, the answer it has and the one wanted.
local function AnswerToSend(now)
    local answers = State("answers")
    for key, event in pairs(Events.All()) do
        if event.owner ~= ns.playerGUID and event.ci ~= 0 and not event.x and event.tm > Events.Now() then
            local entry = Calendar.Find(event.ci)
            local listed = not entry and GuildEntry(event.ci)
            local status = entry and Plain(entry.ev.inviteStatus) or listed and Plain(listed.inviteStatus)
            if status ~= nil then
                local has = CalendarAnswer(status)
                local wanted, managed = WantedAnswer(event)
                local stored = answers[key]
                local agreed = type(stored) == "table" and stored.ci == event.ci and stored.a or nil
                if agreed == nil then
                    -- First look at this calendar event: an answer in the
                    -- addon goes to it; with none, its answer comes to the addon.
                    agreed = Events.Mine(event) and has or wanted
                end
                local last = tried[key]
                local taken = false
                if has == wanted then
                    agreed = has
                elseif wanted == agreed and not (last and now - last.at < IN_FLIGHT) then
                    -- Answered in the calendar since: the addon takes it.
                    agreed, taken = has, true
                    TakeAnswer(key, event, has)
                end
                answers[key] = { ci = event.ci, a = agreed }
                -- A locked event takes no answers: the addon's waits.
                local locked = event.lk or (entry and IsLocked(entry.ev))
                if has ~= wanted and not taken and entry and not locked then
                    -- The same answer is not sent again for a while.
                    if last and last.has == has and last.wanted == wanted and now - last.at < RETRY then
                        wanted = has
                    end
                    local given = status == Enum.CalendarStatus.Confirmed or status == Enum.CalendarStatus.Standby
                        or status == Enum.CalendarStatus.Out
                    -- A status the organizer gave in the calendar stays while the
                    -- addon gives one too (a tentative member may be confirmed),
                    -- unless the player is not coming.
                    if has ~= wanted and not (given and managed and wanted ~= "none") then
                        return key, entry, has, wanted
                    end
                end
            end
        end
    end
end

local function SendAnswer(key, entry, has, wanted)
    busy = true
    tried[key] = { at = GetTime(), has = has, wanted = wanted }
    Open(entry, function(ok)
        if not ok then
            Close()
            Finish()
            return
        end
        if has ~= "none" then
            -- Taken back first: the new answer goes in once the event is
            -- back in the player's calendar.
            C_Calendar.RemoveEvent()
        elseif wanted == "signed" then
            C_Calendar.EventSignUp()
        else
            C_Calendar.EventTentative()
        end
        Wait(function()
            return not Pending()
        end, ACTION_TIMEOUT, function()
            Close()
            Finish()
        end)
    end)
end

-- The calendar status each status of the addon stands for, and back.
local function CalendarStatus(status)
    local enum = Enum.CalendarStatus
    return ({ [Events.CONFIRMED] = enum.Confirmed, [Events.STANDBY] = enum.Standby, [Events.OUT] = enum.Out,
        [Events.PROVISIONAL] = enum.Tentative })[status]
end

local function AddonStatus(status)
    local enum = Enum.CalendarStatus
    return ({ [enum.Confirmed] = Events.CONFIRMED, [enum.Standby] = Events.STANDBY, [enum.Out] = Events.OUT,
        [enum.Tentative] = Events.PROVISIONAL, [enum.Signedup] = Events.NONE })[status]
end

-- The calendar status each sign-up of the event should have: [guid] = status.
-- The organizer's own line in the calendar: the game offers its creator
-- Confirmed, Standby, Out and Tentative (not Signed up nor Declined), so
-- signed up with no status is Confirmed, and not coming is Out.
local function OwnStatus(event)
    local enum = Enum.CalendarStatus
    local mine = Events.Mine(event)
    if not mine or mine.st == Events.DECLINED then
        return enum.Out
    elseif mine.st == Events.TENTATIVE then
        return enum.Tentative
    end
    return CalendarStatus(mine.status) or enum.Confirmed
end

-- The calendar status each sign-up of the event should have: [guid] =
-- status. The organizer's own line too.
local function WantedStatuses(event)
    local wanted = {}
    for _, signUp in ipairs(Events.SignUps(event)) do
        if signUp.st == Events.SIGNED or signUp.status ~= Events.NONE then
            wanted[signUp.guid] = CalendarStatus(signUp.status) or Enum.CalendarStatus.Signedup
        end
    end
    if event.owner == ns.playerGUID then
        wanted[ns.playerGUID] = OwnStatus(event)
    end
    return wanted
end

-- The organizer's own status given in the calendar, into the addon.
local function TakeOwnStatus(key, event, status)
    local enum = Enum.CalendarStatus
    local mine = Events.Mine(event)
    local role, note = mine and mine.ro or Events.LastRole(), mine and mine.no
    if status == enum.Tentative then
        Events.Answer(key, Events.TENTATIVE, role, note)
        Events.SetStatus(key, ns.playerGUID, Events.PROVISIONAL)
    elseif AddonStatus(status) then
        if not mine or mine.st ~= Events.SIGNED then
            Events.Answer(key, Events.SIGNED, role, note)
        end
        Events.SetStatus(key, ns.playerGUID, AddonStatus(status))
    end
end

-- The same wanted statuses as one text, to tell when they changed.
local function StatusSignature(event)
    local parts = {}
    for guid, status in pairs(WantedStatuses(event)) do
        parts[#parts + 1] = guid .. "=" .. status
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- The open event's sign-ups: statuses given in the calendar into the
-- addon; then those whose calendar status is not the addon's: { guid,
-- status }.
local function StatusChanges(key, event)
    local wanted = WantedStatuses(event)
    local statuses = State("statuses")
    statuses[key] = statuses[key] or {}
    local agreedOf = statuses[key]
    local changes = {}
    for index = 1, Plain(ns.Try(C_Calendar.GetNumInvites)) or 0 do
        local invite = ns.Try(C_Calendar.EventGetInvite, index)
        local own = ns.CanRead(invite) and (Plain(invite.inviteIsMine) == true or Plain(invite.guid) == ns.playerGUID)
        if own then
            -- The organizer's own line (they created the event).
            local status, target = Plain(invite.inviteStatus), wanted[ns.playerGUID]
            local agreed = agreedOf[ns.playerGUID] or Enum.CalendarStatus.Confirmed
            if status == target and not Events.Mine(event) then
                -- No answer of theirs in the addon, while the game keeps its
                -- creator in the event: the calendar's line comes in.
                agreedOf[ns.playerGUID] = status
                TakeOwnStatus(key, event, status)
            elseif status == target then
                agreedOf[ns.playerGUID] = status
            elseif target == agreed then
                agreedOf[ns.playerGUID] = status
                TakeOwnStatus(key, event, status)
                Note("from the calendar", "took your status given there: " .. event.ti)
            elseif target then
                changes[#changes + 1] = { guid = ns.playerGUID, status = target }
            end
        elseif ns.CanRead(invite) and Plain(invite.modStatus) ~= "CREATOR" then
            local status, guid = Plain(invite.inviteStatus), Plain(invite.guid)
            local target = guid and wanted[guid]
            local signedUp = status ~= Enum.CalendarStatus.NotSignedup and status ~= Enum.CalendarStatus.Declined
            if target and signedUp then
                local agreed = agreedOf[guid] or Enum.CalendarStatus.Signedup
                if status == target then
                    agreedOf[guid] = status
                elseif target == agreed and AddonStatus(status) then
                    -- Given in the calendar since: the addon takes it.
                    agreedOf[guid] = status
                    Events.SetStatus(key, guid, AddonStatus(status))
                    Note("from the calendar", "took a status given there: " .. event.ti)
                else
                    changes[#changes + 1] = { guid = guid, status = target }
                end
            end
        end
    end
    return changes
end

local function InviteIndex(guid)
    for index = 1, Plain(ns.Try(C_Calendar.GetNumInvites)) or 0 do
        local invite = ns.Try(C_Calendar.EventGetInvite, index)
        if ns.CanRead(invite) and Plain(invite.guid) == guid then
            return index
        end
    end
end

-- The organizer's next event whose sign-ups to look at: one whose
-- statuses changed in the addon since the last look, or, while the game's
-- calendar window is closed, not looked at for a while (a sign-up or a
-- change made in the calendar).
local function EventToMirror(now)
    local best
    local shown = WindowShown()
    for key, event in pairs(Events.All()) do
        local entry = Calendar.Find(event.ci)
        if entry and event.owner == ns.playerGUID and not event.x and event.tm > Events.Now() then
            local last = mirrored[key]
            local signature = StatusSignature(event)
            if not last or last.signature ~= signature or (not shown and now - last.at > MIRROR_EVERY) then
                if not best or event.tm < best.event.tm then
                    best = { key = key, event = event, entry = entry, signature = signature }
                end
            end
        end
    end
    return best
end

local function Mirror(item)
    busy = true
    mirrored[item.key] = { at = GetTime(), signature = item.signature }
    Open(item.entry, function(ok)
        if not ok then
            Close()
            Finish()
            return
        end
        ReconcileOpen(item.key)
        local changes = StatusChanges(item.key, Events.Get(item.key) or item.event)
        local step = 0
        local function NextChange()
            step = step + 1
            local change = changes[step]
            local index = change and InviteIndex(change.guid)
            if not change then
                Close()
                Finish()
                return
            end
            if index then
                C_Calendar.EventSetInviteStatus(index, change.status)
                State("statuses")[item.key][change.guid] = change.status
            end
            Wait(function()
                return not Pending()
            end, ACTION_TIMEOUT, function()
                C_Timer.After(0.5, NextChange)
            end)
        end
        NextChange()
    end)
end

-- One of our calendar events to delete (no click needed): a cancelled
-- event's, or a copy of one of our events. key, entry, whether it is the
-- event's own.
local function ToDelete()
    local used = UsedIDs()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and not InFlight(key, "delete") and not State("byCalendar")[key]
                and not Calendar.Restoring(key) then
            local entry = Calendar.Find(event.ci)
            if event.x and entry then
                return key, entry, true
            elseif event.x or entry then
                local copy = Copies(event, used)[1]
                if copy then
                    return key, copy, false
                end
            end
        end
    end
    local strays, now = State("strays"), Events.Now()
    for id, start in pairs(strays) do
        if found[id] then
            return "stray:" .. id, found[id], false
        elseif start < now then
            strays[id] = nil
        end
    end
end

-- Keeps one of our events open, so a click can change it: whether it is.
local function KeepOpen(key)
    local event = Events.Get(key)
    local entry = event and Calendar.Find(event.ci)
    if not entry then
        return false
    end
    if openKey ~= key or OpenTitle() == nil then
        busy = true
        Open(entry, function(ok)
            openKey = ok and key or nil
            if ok then
                ReconcileOpen(key)
            end
            Finish()
            ns.Fire("CalendarPending")
        end)
    end
    return true
end

-- One of the player's events deleted from the addon (Events.Delete): what
-- the calendar knew of it goes; its calendar event, if still there, is
-- deleted too (ToDelete), and never taken into the addon again (Adopt).
function Calendar.Forget(key, event)
    for _, name in ipairs({ "known", "created", "gone", "byCalendar", "answers", "statuses" }) do
        State(name)[key] = nil
    end
    mirrored[key], sent[key], missing[key], seen[key], tried[key] = nil, nil, nil, nil, nil
    if event.ci ~= 0 then
        State("strays")[event.ci] = event.tm
    end
end

-- The calendar event a pending one became: the player's, linked to no
-- event of ours, with its title and start.
local function Landing(item, used)
    for id, entry in pairs(found) do
        local ev = entry.ev
        if not used[id] and Plain(ev.modStatus) == "CREATOR" and Plain(ev.title) == item.ti
                and StartOf(ev.startTime) == item.tm then
            return id
        end
    end
end

-- The events sent to be created, into the addon once the calendar has them;
-- given up after a while, the addon unchanged.
local function TakePending()
    local used, clock = UsedIDs(), GetTime()
    local item = pendingNew
    if item then
        local id = Landing(item, used)
        if id then
            pendingNew = nil
            used[id] = true
            local key = Events.Create(item.fields)
            if key then
                Events.SetCalendarID(key, id)
                Agree(key, Events.Get(key))
                Note("create", "in the calendar, so in the addon: " .. item.ti)
            end
            if item.done then
                item.done(key)
            end
        elseif clock - item.at > CREATE_TIMEOUT then
            pendingNew = nil
            Calendar.lastError = L["The game's calendar did not answer. Try again."]
            if item.failed then
                item.failed(Calendar.lastError)
            end
        end
    end
    item = pendingRestore
    if item then
        local id = Landing(item, used)
        if id then
            pendingRestore = nil
            local key = item.key
            State("gone")[key], State("known")[key], State("byCalendar")[key], State("created")[key] = nil, nil, nil, nil
            Events.Cancel(key, false)
            Linked(key, id)
            Agree(key, Events.Get(key))
            Note("create", "made again in the calendar, so restored in the addon")
        elseif clock - item.at > CREATE_TIMEOUT then
            pendingRestore = nil
            Calendar.lastError = L["The game's calendar did not answer. Try again."]
            ns.Fire("CalendarPending")
        end
    end
end

-- The calendar refused what it was sent for another reason (text, its own
-- words): a new event or a restore waiting for it is given up.
local function Failed(text)
    local item = pendingNew
    pendingNew = nil
    if item and item.failed then
        item.failed(text)
    end
    if pendingRestore then
        pendingRestore = nil
    end
    if creating then
        -- Sent with its button: it waits for it again.
        State("created")[creating.key] = nil
        creating = nil
    end
    ns.Fire("CalendarPending")
end

-- The game refused the last event sent for its limit of events created
-- (count): it goes from the addon too (a restored one is cancelled again),
-- and Restore event stays off until one of the player's calendar events goes.
local function Refused(count)
    local own = ns.Data.OwnState()
    own.limit = { count = count, created = Calendar.CreatedCount() }
    if pendingNew or pendingRestore then
        -- Nothing of it came into the addon: the form or the event says so.
        local new = pendingNew
        pendingNew, pendingRestore = nil, nil
        if new and new.failed then
            new.failed(Calendar.LimitText())
        end
        ns.Fire("CalendarPending")
        return
    end
    -- Sent with its button: it stays, waiting for it again (off at the
    -- limit).
    local item = creating
    creating = nil
    if item then
        State("created")[item.key] = nil
    end
    ns.Fire("CalendarPending")
    Note("create", "refused by the game: its limit of events created")
end

-- Whether the player is at the game's limit of events created: it refused
-- one, and none of theirs left the calendar since.
function Calendar.AtLimit()
    local own = ns.Data.OwnState()
    if not own.limit then
        return false
    elseif scanned and Calendar.CreatedCount() < own.limit.created then
        own.limit = nil
        return false
    end
    return true
end

-- The game's words for it: "You have reached your limit of %d events created."
function Calendar.LimitText()
    local limit = ns.Data.OwnState().limit
    local text = CALENDAR_ERROR_EVENTS_EXCEEDED
    if type(text) == "string" and limit and type(limit.count) == "number" then
        local ok, formatted = pcall(string.format, text, limit.count)
        if ok then
            return formatted
        end
    end
    return L["You organize as many events as you can at once."]
end

-- What /gevents status says: whether the calendar's data was read.
function Calendar.Scanned()
    return scanned
end

-- And how many guild events in the months read the player created.
function Calendar.CreatedCount()
    local count = 0
    for _, entry in pairs(found) do
        if Plain(entry.ev.modStatus) == "CREATOR" then
            count = count + 1
        end
    end
    return count
end

-- One look at the calendar: what changed there into the addon, our new
-- events' IDs, deletions; then one step that opens an event (kept open for
-- a change, an answer, or the statuses of one event's sign-ups).
function Calendar.Tick()
    if busy or not ns.playerGUID or not ns.Roster.ready then
        return
    end
    local now = GetTime()
    if now - lastRead > READ_EVERY then
        lastRead = now
        ns.Try(C_Calendar.OpenCalendar)
    end
    if not scanned then
        return
    end
    Scan()
    TakePending()
    Link()
    Watch()
    Adopt()
    -- The player's answers given in the calendar come in at once, also while
    -- they view an event in its window: that opens nothing. Sending one does,
    -- so it waits below.
    local answerKey, answerEntry, has, wanted = AnswerToSend(now)
    ns.Fire("CalendarPending")
    if Drafting() then
        return
    end
    local key, entry, main = ToDelete()
    if key and not deleteNeedsClick and (Delete(key, entry, main) or busy) then
        return
    end
    -- The event the form changes stays open for the click that saves it.
    if preparedKey and stillPrepared and not stillPrepared() then
        preparedKey, stillPrepared = nil, nil
    end
    if preparedKey and KeepOpen(preparedKey) then
        return
    end
    if answerKey then
        openKey = nil
        SendAnswer(answerKey, answerEntry, has, wanted)
        return
    end
    local item = EventToMirror(now)
    if item then
        openKey = nil
        Mirror(item)
        return
    end
    -- Then one whose change waits for a click, so the next one sends it.
    for _, pending in ipairs(Calendar.Pending()) do
        if (pending.kind == "update" or pending.kind == "delete" and deleteNeedsClick) and KeepOpen(pending.key) then
            return
        end
    end
    if openKey then
        openKey = nil
        Close()
    end
end

function Calendar.TickSoon()
    ns.Debounce("CalendarTick", 0.1, Calendar.Tick)
end

-- The event open in the game's calendar window, when it is one of ours:
-- what is changed there comes into the addon at once (the description and
-- the statuses show only on the open event).
local function ReadOpen()
    if busy or Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    if not ns.CanRead(info) then
        return
    end
    local start, title = StartOf(info.time), Plain(info.title)
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci ~= 0 and not event.x and event.tm == start and event.ti == title then
            ReconcileOpen(key)
            StatusChanges(key, Events.Get(key) or event)
            return
        end
    end
end

function Calendar.Init()
    local own = ns.Data.OwnState()
    own.pushed = nil  -- what 0.1.0's first builds kept instead of known
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_GUILD_EVENTS",
        "CALENDAR_UPDATE_INVITE_LIST", "CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_ERROR",
        "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_ACTION_PENDING", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN")
    frame:SetScript("OnEvent", function(_, event, message, action)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            -- One of ours refused: it waits for the next click.
            if message == ns.ADDON_NAME and type(action) == "string" and (action:find("Event") or action:find("UNKNOWN")) then
                blocked = true
                wipe(sent)
                Note(tostring(action), "blocked by the game")
                if lastUpdate then
                    State("known")[lastUpdate.key] = lastUpdate.previous
                    lastUpdate = nil
                end
                if lastCreate then
                    State("created")[lastCreate] = nil
                    lastCreate = nil
                end
                Calendar.lastError = L["The game's calendar refused the change. Click again to retry."]
                ns.Fire("CalendarPending")
            end
            return
        end
        if event == "CALENDAR_UPDATE_ERROR" or event == "CALENDAR_UPDATE_ERROR_WITH_COUNT" then
            local text = type(Plain(message)) == "string" and (_G[message] or message) or nil
            local count = Plain(action)
            if text and event == "CALENDAR_UPDATE_ERROR_WITH_COUNT" and type(count) == "number" then
                -- "You have reached your limit of %d events created."
                local ok, formatted = pcall(string.format, text, count)
                text = ok and formatted or text
            end
            Calendar.lastError = text
            Note("calendar", "error: " .. tostring(Plain(message)) .. (count and " " .. tostring(count) or ""))
            if Plain(message) == "CALENDAR_ERROR_EVENTS_EXCEEDED" then
                Refused(count)
            else
                Failed(text)
            end
            -- A change or deletion it refused waits again.
            wipe(sent)
            ns.Fire("CalendarPending")
            return
        end
        if event == "CALENDAR_NEW_EVENT" then
            Note("create", "the game's calendar has a new event")
        elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
            reads = reads + 1
            -- Whether the player may add events comes with the calendar's data.
            ns.Fire("CalendarPending")
        elseif event == "CALENDAR_ACTION_PENDING" then
            -- And again once the calendar is done with a change, as the
            -- game's own Create button.
            ns.Fire("CalendarPending")
        elseif event == "CALENDAR_UPDATE_INVITE_LIST" or event == "CALENDAR_UPDATE_EVENT" then
            ReadOpen()
        end
        scanned = true
        if (pendingNew or pendingRestore) and event ~= "CALENDAR_UPDATE_INVITE_LIST" then
            -- At once, even while a step with an open event goes on.
            Scan()
            TakePending()
        end
        Calendar.TickSoon()
    end)
    ns.On("EventsChanged", Calendar.TickSoon)
    C_Timer.NewTicker(TICK, Calendar.Tick)
    lastRead = GetTime()
    ns.Try(C_Calendar.OpenCalendar)
end
