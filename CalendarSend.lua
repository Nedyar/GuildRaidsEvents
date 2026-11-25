-- CalendarSend.lua: what the player's clicks send to the game's calendar
-- (see Calendar.lua): a new event (the form's Create), a change (Save), an
-- event cancelled (Cancel event) or restored (Restore event), and next
-- week's event of a weekly one (Create in calendar). The calendar first,
-- always: the addon takes a change only once the calendar has taken it,
-- and nothing when it refuses it. And the outbox: what was sent and has not
-- shown in the calendar yet.
local _, ns = ...
local L = ns.L

local Calendar, Read, Send, Organizer = ns.Calendar, ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer
local Events = ns.Events
local Note = Calendar.Note

local IN_FLIGHT = 60         -- seconds a change or deletion sent may take to show in the calendar
local ANSWER_TIMEOUT = 8     -- seconds the calendar may take to show a new, restored or cancelled event
local RECREATE_AFTER = 600   -- seconds before an event sent but never seen is created again

local REFUSED = "The game's calendar refused the change. Click again to retry."
local NO_ANSWER = "The game's calendar did not answer. Try again."

-- The outbox ------------------------------------------------------------------------------------
-- What was sent to the game's calendar and has not shown there yet, one
-- item per kind and event: { kind, key, at = GetTime(), ... }.
--   "new"      the form's new event (no key): fields, ti, tm, done, failed;
--   "restore"  a cancelled event of ours made again: ti, tm;
--   "create"   next week's event of a weekly one, sent with its button;
--   "cancel"   an event whose calendar event is being deleted (Cancel
--              event): ci, reads (Read.reads then), started;
--   "update"   a change of an event's calendar event;
--   "delete"   one of our calendar events deleted.
-- An item goes once the calendar shows it (Send.Landed). A new, restored or
-- cancelled event not shown after ANSWER_TIMEOUT is given up (TakePending);
-- the others stop counting after IN_FLIGHT. If the game refuses what was
-- sent, its item is taken back (Undo).

local items = {}
-- The item of the call going on (Send.Try): the game refuses a call while
-- it is made, so a refusal then takes that item back, and no other.
local current
local blocked = false  -- the game refused one of our calls (set during the call)

local WAITED = { new = true, restore = true, cancel = true }  -- given up after ANSWER_TIMEOUT, not IN_FLIGHT

local function Slot(kind, key)
    return kind .. "|" .. (key or "")
end

local function Expired(item)
    return not WAITED[item.kind] and GetTime() - item.at >= IN_FLIGHT
end

function Send.Put(kind, key, item)
    -- Those no longer counting go (a moderator's changes, which nothing
    -- looks at again).
    for slot, other in pairs(items) do
        if Expired(other) then
            items[slot] = nil
        end
    end
    item = item or {}
    item.kind, item.key, item.at = kind, key, GetTime()
    items[Slot(kind, key)] = item
    return item
end

-- The item of that kind for that event (key nil for "new"), or nil.
function Send.Item(kind, key)
    local slot = Slot(kind, key)
    local item = items[slot]
    if item and Expired(item) then
        items[slot] = nil
        return nil
    end
    return item
end

-- Whether a change ("update") or deletion ("delete") of the event was just
-- sent: either, when kind is nil. While it is, what the calendar shows of
-- it is not taken into the addon.
function Send.InFlight(key, kind)
    if kind then
        return Send.Item(kind, key) ~= nil
    end
    return Send.Item("update", key) ~= nil or Send.Item("delete", key) ~= nil
end

-- The calendar shows it.
function Send.Landed(kind, key)
    items[Slot(kind, key)] = nil
end

-- Whether a new, restored or cancelled event waits for the calendar.
function Send.Waiting()
    for _, item in pairs(items) do
        if WAITED[item.kind] then
            return true
        end
    end
    return false
end

-- Takes back what was sent (why: the game's words, for the form or the
-- window). A change taken back leaves the addon as it was; the calendar's
-- values come into it again if it already had the change (Organizer.Watch).
local function Undo(item, why)
    local slot = Slot(item.kind, item.key)
    if items[slot] ~= item then
        return
    end
    items[slot] = nil
    if item.kind == "create" then
        -- Sent with its button: it waits for it again.
        Read.State("created")[item.key] = nil
    elseif item.kind == "new" and item.failed then
        item.failed(why)
    end
    if WAITED[item.kind] or item.kind == "create" then
        Calendar.lastError = why or Calendar.lastError
        ns.Fire("CalendarPending")
    end
end
Send.Undo = Undo

-- Takes back every item of those kinds.
local function UndoAll(kinds, why)
    local list = {}
    for _, item in pairs(items) do
        if kinds[item.kind] then
            list[#list + 1] = item
        end
    end
    for _, item in ipairs(list) do
        Undo(item, why)
    end
end

-- Forgets every item of an event (deleted from the addon).
function Send.Forget(key)
    for _, kind in ipairs({ "restore", "create", "cancel", "update", "delete" }) do
        Send.Landed(kind, key)
    end
end

-- Calls to the calendar ---------------------------------------------------------------------------

-- Calls fn, a call to the game's calendar, as part of item (or nil):
-- whether the game took it. If not, the item is taken back.
function Send.Try(what, item, fn)
    blocked = false
    current = item
    local ok, err = pcall(fn)
    current = nil
    if ok and not blocked then
        Calendar.lastError = nil
        Note(what, "sent")
        return true
    end
    if not ok then
        Note(what, "error: " .. tostring(err))
        Calendar.lastError = L[REFUSED]
    end
    if item then
        Undo(item, Calendar.lastError)
    end
    return false
end

-- Whether the game refused the last call.
function Send.Blocked()
    return blocked
end

-- The game refused one of our calls (ADDON_ACTION_BLOCKED, during the
-- call): what it was part of, when it was one of Send.Try's, is taken back.
function Send.OnBlocked(action)
    blocked = true
    Note(tostring(action), "blocked by the game")
    Calendar.lastError = L[REFUSED]
    if current then
        Undo(current, Calendar.lastError)
    end
    ns.Fire("CalendarPending")
end

-- The calendar refused a change (CALENDAR_UPDATE_ERROR, text: its words;
-- count with CALENDAR_ERROR_EVENTS_EXCEEDED, its limit of events created):
-- what waits for the calendar is given up (the form or the window says
-- why). A change or deletion sent lands or stops counting as usual: if the
-- calendar did not take it, its values come into the addon again.
function Send.OnError(message, count, text)
    local why = text
    if message == "CALENDAR_ERROR_EVENTS_EXCEEDED" then
        -- Restore event stays off until one of the player's calendar
        -- events goes (Calendar.AtLimit).
        ns.Data.OwnState().limit = { count = count, created = Calendar.CreatedCount() }
        why = Calendar.LimitText()
        Note("create", "refused by the game: its limit of events created")
    end
    UndoAll({ new = true, restore = true, create = true, cancel = true }, why)
    ns.Fire("CalendarPending")
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

-- Whether an event has a calendar event to change: to come, not cancelled,
-- and in the player's calendar.
local function InCalendar(event)
    return not event.x and event.ci ~= 0 and event.tm > Events.Now() and Read.Find(event.ci) ~= nil
end

-- What the clicks send -----------------------------------------------------------------------------

-- In the click of the form's Create (EventForm.lua): the new event goes to
-- the game's calendar first, fields as Events.Create takes them. The addon
-- takes it once the calendar has it, then done(key); if the calendar
-- refuses it, failed(why), and the addon takes nothing. Returns whether it
-- was sent.
function Calendar.CreateFirst(fields, done, failed)
    if Read.ActionPending() then
        Note("create", "not sent: the calendar is busy with another change")
        return false
    end
    local event = { ti = fields.ti, tm = fields.tm, ty = fields.ty, de = fields.de ~= "" and fields.de or nil,
        lk = fields.lk == true }
    if not Send.Try("create", nil, function()
        Calendar.CreateNow(event)
    end) then
        return false
    end
    Send.Put("new", nil, { fields = fields, ti = fields.ti, tm = fields.tm - fields.tm % 60, done = done,
        failed = failed })
    return true
end

-- Whether a new event of the form's waits for the calendar's answer.
function Calendar.Creating()
    return Send.Item("new") ~= nil
end

-- The form changing an event (EventForm.lua) keeps its calendar event open,
-- so the click that saves it changes the calendar too: key, or nil once the
-- form closes; still(), whether the form still changes it.
local preparedKey, stillPrepared

function Calendar.Prepare(key, still)
    preparedKey, stillPrepared = key, still
    if key then
        Calendar.TickSoon()
    elseif Read.openKey and not Read.busy then
        -- Closed at once, as the game's window does.
        Read.openKey = nil
        Read.Close()
    end
end

-- A step of the look at the calendar (Tick): the event the form changes
-- stays open. Whether it is.
function Send.KeepPrepared()
    if preparedKey and stillPrepared and not stillPrepared() then
        preparedKey, stillPrepared = nil, nil
    end
    return preparedKey ~= nil and Organizer.KeepOpen(preparedKey)
end

-- Why the form's Save is off for a change of that event, or nil: its
-- calendar event is not open yet (the form opens it), or the game does not
-- let the player change it. An event with no calendar event to change
-- changes in the addon only.
function Calendar.EditBlocked(key)
    local event = Events.Get(key)
    if not event or not InCalendar(event) then
        return nil
    elseif Read.openKey ~= key or Read.OpenTitle() == nil or Read.ActionPending() then
        return L["Syncing the calendar..."]
    elseif event.owner ~= ns.playerGUID and Read.Plain(ns.Try(C_Calendar.EventCanEdit)) ~= true then
        return L["The game's calendar does not let you change this event."]
    end
end

-- In the click that saves a change (EventForm.lua), first thing: whether
-- the calendar took it (or has nothing to take), and why not. The addon
-- takes the change only if it did.
function Calendar.UpdateFirst(key, fields)
    local event = Events.Get(key)
    if not event then
        return false
    elseif not InCalendar(event) then
        return true
    end
    local why = Calendar.EditBlocked(key)
    if why then
        Note("update", "not sent: " .. why)
        return false, why
    end
    local new = { ti = fields.ti, tm = fields.tm, ty = fields.ty, de = fields.de or "", lk = fields.lk == true }
    local item = Send.Put("update", key)
    Read.State("known")[key] = new
    if Send.Try("update", item, function()
        Fill(new)
        C_Calendar.UpdateEvent()
    end) then
        return true
    end
    return false, Calendar.lastError
end

-- Starts deleting a cancelled event's calendar event (no click needed; it
-- is opened first when it is not open). Whether it started.
local function StartCancel(item)
    local event = Events.Get(item.key)
    local entry = event and Read.Find(item.ci)
    if not entry then
        return false
    end
    -- Started before the call: the calendar may answer during it.
    item.started = true
    local _, started = Organizer.Delete(item.key, entry, event.owner == ns.playerGUID, function(why)
        Undo(item, why)
    end)
    if items[Slot("cancel", item.key)] == item then
        item.started = started
    end
    return started
end

-- The click that cancels an event (EventView.lua): the calendar first. Its
-- calendar event is deleted, and the event is cancelled in the addon once
-- the calendar no longer has it; if the game refuses it, nothing changes
-- and the window says why. An event not in the calendar is cancelled in the
-- addon at once. Whether it was cancelled or sent.
function Calendar.Cancel(key)
    local event = Events.Get(key)
    if not event or event.x or Send.Item("cancel", key) then
        return false
    end
    local entry = Read.Find(event.ci)
    if event.ci == 0 or not entry then
        return Events.Cancel(key)
    end
    Read.State("byCalendar")[key] = nil
    Organizer.ForgetTried(entry.id)
    local item = Send.Put("cancel", key, { ci = event.ci, reads = Read.reads })
    StartCancel(item)
    ns.Fire("CalendarPending")
    return Send.Item("cancel", key) ~= nil
end

-- Whether that event waits for the calendar to delete it.
function Calendar.Cancelling(key)
    return Send.Item("cancel", key) ~= nil
end

-- Why the player cannot restore that cancelled event, or nil: it is made
-- again in the game's calendar, which only its organizer can do (one
-- over, or never in the calendar, is restored in the addon only).
function Calendar.RestoreBlocked(event)
    if event.owner ~= ns.playerGUID and event.ci ~= 0 and event.tm > Events.Now() then
        return L["Only its organizer can restore it: it is made again in the game's calendar."]
    end
end

-- The click that restores a cancelled event (EventView.lua): for its
-- organizer, the calendar first; the event is restored in the addon once
-- the calendar has it again, and stays cancelled if it refuses it. Whether
-- it was sent (or, for a past one or one never in the calendar, restored).
function Calendar.Restore(key)
    local event = Events.Get(key)
    if not event then
        return false
    end
    local why = Calendar.RestoreBlocked(event)
    if why then
        Calendar.lastError = why
        return false
    elseif event.tm <= Events.Now() or event.ci == 0 then
        -- Over, or never in the calendar (it waits for its Create in
        -- calendar button again): the addon only.
        return Events.Cancel(key, false)
    end
    if Read.ActionPending() then
        Calendar.lastError = L[REFUSED]
        return false
    end
    if not Send.Try("create", nil, function()
        Calendar.CreateNow(event)
    end) then
        return false
    end
    Send.Put("restore", key, { ti = event.ti, tm = event.tm })
    ns.Fire("CalendarPending")
    return true
end

-- Whether that event waits for the calendar to have it again.
function Calendar.Restoring(key)
    return Send.Item("restore", key) ~= nil
end

-- Deletes one of the player's own cancelled events, for everyone (Clear
-- cancelled, Delete): what the calendar knew of it goes, and its calendar
-- event, if still there, is deleted too and never taken into the addon
-- again. Whether it did.
function Calendar.Delete(key)
    local event = Events.Get(key)
    if not event or not event.x or event.owner ~= ns.playerGUID then
        return false
    end
    Organizer.Forget(key, event)
    return Events.Delete(key)
end

-- What the player's own events need in the calendar ---------------------------------------------

-- What one of the player's own events needs in the calendar: "create",
-- "update", "delete" or nil.
local function KindOf(key, event, now)
    local entry = Read.Find(event.ci)
    if event.x then
        return entry and not Read.State("byCalendar")[key] and "delete" or nil
    elseif event.tm <= now then
        return nil
    elseif event.ci == 0 then
        local created = Read.State("created")
        if created[key] and ns.Now() - created[key] > RECREATE_AFTER and Read.InRange(event.tm) then
            created[key] = nil
        end
        return not created[key] and "create" or nil
    elseif entry and Organizer.NeedsUpdate(key, event) then
        return "update"
    end
end

-- What the player's own events and the calendar do not agree on yet, in
-- order: { kind = "create", "update" or "delete", key, event }. A creation
-- waits for its own button (Calendar.SendNow); a deletion goes by itself
-- (Organizer.DeleteNoClick); a change is only on its way (Calendar.UpdateFirst).
function Calendar.Pending()
    local list = {}
    if not ns.playerGUID or not ns.Roster.ready or not Read.scanned then
        return list
    end
    local now = Events.Now()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID then
            local kind = KindOf(key, event, now)
            if kind and not (kind ~= "create" and Send.InFlight(key, kind)) then
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

-- Whether one of the player's events waits to be created in the calendar
-- with its own button (next week's of a weekly one).
function Calendar.Unsent(event)
    return event ~= nil and event.owner == ns.playerGUID and Read.scanned
        and KindOf(event.key, event, Events.Now()) == "create"
end

-- Why that button is off now, or nil: the game does not take a new event
-- yet (as its own Create button, C_Calendar.CanAddEvent), or it reported
-- its limit of events created.
function Calendar.SendBlocked()
    if Calendar.AtLimit() then
        return Calendar.LimitText()
    elseif not ns.Rights.MayCreate() or Read.ActionPending() then
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
    Read.State("created")[key] = ns.Now()
    local item = Send.Put("create", key)
    if Send.Try("create", item, function()
        Calendar.CreateNow(event)
    end) then
        ns.Fire("CalendarPending")
        return true
    end
    return false
end

-- What waits for the calendar -----------------------------------------------------------------

-- The events sent to be created (Create, Restore event) into the addon,
-- and those cancelled, once the calendar has them or no longer has them;
-- given up after a while, the addon unchanged.
function Send.TakePending()
    local used, clock = Read.UsedIDs(), GetTime()
    local item = Send.Item("new")
    if item then
        local id = Read.Landing(item.ti, item.tm, used)
        if id then
            Send.Landed("new")
            used[id] = true
            local key = Events.Create(item.fields)
            if key then
                Events.SetCalendarID(key, id)
                Organizer.Agree(key, Events.Get(key))
                Note("create", "in the calendar, so in the addon: " .. item.ti)
            end
            if item.done then
                item.done(key)
            end
        elseif clock - item.at > ANSWER_TIMEOUT then
            Undo(item, L[NO_ANSWER])
        end
    end
    local waiting = {}
    for _, other in pairs(items) do
        if other.kind == "restore" or other.kind == "cancel" then
            waiting[#waiting + 1] = other
        end
    end
    for _, other in ipairs(waiting) do
        local key = other.key
        if other.kind == "restore" then
            local id = Read.Landing(other.ti, other.tm, used)
            if id then
                Send.Landed("restore", key)
                used[id] = true
                for _, name in ipairs({ "gone", "known", "byCalendar", "created" }) do
                    Read.State(name)[key] = nil
                end
                Events.Cancel(key, false)
                Organizer.Linked(key, id)
                Organizer.Agree(key, Events.Get(key))
                Note("create", "made again in the calendar, so restored in the addon")
            elseif clock - other.at > ANSWER_TIMEOUT then
                Undo(other, L[NO_ANSWER])
            end
        elseif not Events.Get(key) then
            Send.Landed("cancel", key)
        elseif Read.reads > other.reads and Read.Find(other.ci) == nil then
            -- Gone from the calendar (its data came again since): cancelled.
            Send.Landed("cancel", key)
            Events.Cancel(key)
            Note("delete", "gone from the calendar, so cancelled in the addon")
            ns.Fire("CalendarPending")
        elseif not other.started then
            -- Another step had the open event: started now.
            if not StartCancel(other) and not Read.busy then
                Undo(other, L[REFUSED])
            end
        elseif clock - other.at > ANSWER_TIMEOUT + 8 then
            Undo(other, L[NO_ANSWER])
        end
    end
end

-- The game's limit of events created ------------------------------------------------------------

-- Whether the player is at the game's limit of events created: it refused
-- one, and none of theirs left the calendar since.
function Calendar.AtLimit()
    local own = ns.Data.OwnState()
    if not own.limit then
        return false
    elseif Read.scanned and Calendar.CreatedCount() < own.limit.created then
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
