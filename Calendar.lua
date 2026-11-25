-- Calendar.lua: keeps the game's calendar and the guild's events in step,
-- both ways, wherever a change is made.
--
-- Each event is a guild sign-up event in the game's calendar, made by its
-- organizer's client. What WoW Forever lets an addon do there (found with
-- /gevents probe, build 71037):
--   - creating and changing an event only inside a click of the player (a
--     "hardware event"), with the call first in the click. The addon's
--     buttons do it in their own click: Create, Save, and Create in
--     calendar for next week's event of a weekly one;
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
-- The calendar first, always: a change made in the addon (a new event, a
-- change, an event deleted) comes into the addon only once the game's
-- calendar took it; when the game refuses it, nothing changes, and the
-- window says why. A deleted event is gone for everyone, as in the game's
-- calendar: there is no getting it back.
--
-- From the calendar to the addon: the clients of an event's organizer and
-- of its moderators take into the addon what was changed in the game's
-- calendar window (title, time, type, description, whether it is locked,
-- statuses, moderators), and delete it when it is deleted there; the
-- organizer's client adds the guild events its character created there;
-- each member's client takes their own sign-up made there. For each field, the
-- side that changed since both last agreed wins; when both did, the
-- calendar. A locked event takes no answers: a member's answer waits until
-- it is unlocked.
--
-- It works with the game's calendar window open, but opens nothing while
-- the player makes, edits or views an event in that window, so as not to
-- lose it.
--
-- The work is in parts, each in a file of its own:
--   CalendarRead.lua       reading the calendar, the one open event, and what
--                          this character knows of the calendar;
--   CalendarSend.lua       what the player's clicks send (create, save,
--                          delete), and the outbox: what was sent and has
--                          not shown in the calendar yet;
--   CalendarOrganizer.lua  the organizer's events: changes both ways, events
--                          made or deleted in the calendar window, those a
--                          moderator deleted, copies;
--   CalendarMember.lua     the player's own answers;
--   CalendarStatuses.lua   the statuses of the sign-ups of the organizer's
--                          events.
-- This file holds the look at the calendar every few seconds (Tick), which
-- runs the parts in order, and what the game says back.
local _, ns = ...

local Calendar = {}
ns.Calendar = Calendar
-- The parts, filled by their files (loaded after this one).
ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer, ns.CalendarMember, ns.CalendarStatuses = {}, {}, {}, {}, {}
local Read, Send, Organizer, Member, Statuses =
    ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer, ns.CalendarMember, ns.CalendarStatuses

local Events = ns.Events

local TICK = 10              -- seconds between looks at the calendar
local READ_EVERY = 600       -- seconds between two requests of the calendar's data

Calendar.lastError = nil     -- what the game last said went wrong
-- What became of the last change sent to the calendar (for /gevents
-- status): { what, at = server time, result }.
Calendar.lastSent = nil

function Calendar.Note(what, result)
    Calendar.lastSent = { what = what, at = ns.Now(), result = result }
    ns.Debug("calendar: %s: %s", what, result)
end

-- What the addon's window shows of the calendar, and what changes there
-- with time: whether a new event can be sent, what waits for its button,
-- what is hidden from the player, what is being deleted, the last error;
-- which events are to come or of the last week, and the player's level
-- (who may sign up). The window is told (CalendarPending) when it changes.
local shownSignature

local function WindowSignature()
    local now = Events.Now()
    local parts = {
        "s" .. tostring(Read.scanned), "c" .. tostring(ns.Rights.MayCreate()), "p" .. tostring(Read.ActionPending()),
        "l" .. tostring(Calendar.AtLimit()), "n" .. tostring(Calendar.Creating()), "e" .. (Calendar.lastError or ""),
        "v" .. tostring(UnitLevel("player")),
    }
    for key, event in pairs(Events.All()) do
        parts[#parts + 1] = ("k%s|%s|%s|%s|%s|%s"):format(key, tostring(Calendar.Unsent(event)),
            tostring(Calendar.HiddenFromMe(event)), tostring(Calendar.Deleting(key)),
            tostring(Events.IsUpcoming(event, now)), tostring(event.tm + Events.KEEP > now))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function TellWindow()
    local signature = WindowSignature()
    if signature ~= shownSignature then
        shownSignature = signature
        ns.Fire("CalendarPending")
    end
end

-- The look at the calendar ------------------------------------------------------------------------

local lastRead = 0

-- What changed in the calendar into the addon, our new events' IDs,
-- deletions; then one step that opens an event (kept open for a change, an
-- answer, or the statuses of one event's sign-ups).
function Calendar.Tick()
    if Read.busy or not ns.playerGUID or not ns.Roster.ready then
        return
    end
    local now = GetTime()
    if now - lastRead > READ_EVERY then
        lastRead = now
        ns.Try(C_Calendar.OpenCalendar)
    end
    if not Read.scanned then
        return
    end
    Read.Scan()
    Organizer.Purge()
    Send.TakePending()
    Organizer.Link()
    Organizer.Watch()
    Organizer.Adopt()
    -- The player's answers given in the calendar come in at once, also while
    -- they view an event in its window: that opens nothing. Sending one does,
    -- so it waits below.
    local answer = Member.AnswerToSend(now)
    TellWindow()
    if Read.Drafting() then
        return
    end
    if Organizer.DeleteNoClick() then
        return
    end
    -- The event the form changes stays open for the click that saves it.
    if Send.KeepPrepared() then
        return
    end
    if answer then
        Member.SendAnswer(answer)
        return
    end
    if Statuses.MirrorNext(now) then
        return
    end
    Read.CloseKept()
end

function Calendar.TickSoon()
    ns.Debounce("CalendarTick", 0.1, Calendar.Tick)
end

function Calendar.Init()
    -- What 0.1.0's first builds kept: instead of known, and of cancelled
    -- events, which are deleted now.
    local own = ns.Data.OwnState()
    own.pushed, own.gone, own.byCalendar, own.cleared = nil, nil, nil, nil
    ns.db.settings.cleared = nil
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_GUILD_EVENTS",
        "CALENDAR_UPDATE_INVITE_LIST", "CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_ERROR",
        "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_ACTION_PENDING", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN")
    frame:SetScript("OnEvent", function(_, event, message, action)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            -- One of ours refused: it waits for the next click.
            if message == ns.ADDON_NAME and type(action) == "string" and (action:find("Event") or action:find("UNKNOWN")) then
                Send.OnBlocked(action)
            end
            return
        end
        if event == "CALENDAR_UPDATE_ERROR" or event == "CALENDAR_UPDATE_ERROR_WITH_COUNT" then
            local text = type(Read.Plain(message)) == "string" and (_G[message] or message) or nil
            local count = Read.Plain(action)
            if text and event == "CALENDAR_UPDATE_ERROR_WITH_COUNT" and type(count) == "number" then
                -- "You have reached your limit of %d events created."
                local ok, formatted = pcall(string.format, text, count)
                text = ok and formatted or text
            end
            Calendar.lastError = text
            Calendar.Note("calendar", "error: " .. tostring(Read.Plain(message)) .. (count and " " .. tostring(count) or ""))
            Send.OnError(Read.Plain(message), count, text)
            return
        end
        if event == "CALENDAR_NEW_EVENT" then
            Calendar.Note("create", "the game's calendar has a new event")
        elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
            Read.reads = Read.reads + 1
            -- Whether the player may add events comes with the calendar's data.
            ns.Fire("CalendarPending")
        elseif event == "CALENDAR_ACTION_PENDING" then
            -- And again once the calendar is done with a change, as the
            -- game's own Create button.
            ns.Fire("CalendarPending")
        elseif event == "CALENDAR_UPDATE_INVITE_LIST" or event == "CALENDAR_UPDATE_EVENT" then
            Statuses.ReadOpen()
        end
        Read.scanned = true
        if Send.Waiting() and event ~= "CALENDAR_UPDATE_INVITE_LIST" then
            -- At once, even while a step with an open event goes on.
            Read.Scan()
            Send.TakePending()
        end
        Calendar.TickSoon()
    end)
    ns.On("EventsChanged", Calendar.TickSoon)
    C_Timer.NewTicker(TICK, Calendar.Tick)
    lastRead = GetTime()
    ns.Try(C_Calendar.OpenCalendar)
end
