-- CalendarSend.lua: what the player's clicks send to the game's calendar
-- (see Calendar.lua): a new event (the form's Create), a change (Save), a
-- cancelled event (Cancel event) or one restored (Restore event), next
-- week's event of a weekly one (Create in calendar), and the change of
-- their events that waits for a click (any click in the addon's window,
-- Calendar.OnClick). And the outbox: what was sent and has not shown in
-- the calendar yet.
local _, ns = ...
local L = ns.L

local Calendar, Read, Send, Organizer = ns.Calendar, ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer
local Events = ns.Events
local Note = Calendar.Note

local IN_FLIGHT = 60         -- seconds a change sent may take to show in the calendar
local CREATE_TIMEOUT = 8     -- seconds the calendar may take to answer a new or restored event
local RECREATE_AFTER = 600   -- seconds before an event sent but never seen is created again

local REFUSED = "The game's calendar refused the change. Click again to retry."

-- The outbox ------------------------------------------------------------------------------------
-- What was sent to the game's calendar and has not shown there yet, one
-- item per kind and event: { kind, key, at = GetTime(), ... }.
--   "new"      the form's new event (no key): fields, ti, tm, done, failed;
--   "restore"  a cancelled event of ours made again: ti, tm;
--   "create"   next week's event of a weekly one, sent with its button;
--   "update"   a change: previous = what the calendar and the addon had
--              agreed before it (mine: the event is the player's);
--   "delete"   its calendar event deleted.
-- An item goes once the calendar shows it (Send.Landed). A new or restored
-- event not shown after CREATE_TIMEOUT is given up (TakePending); the
-- others stop counting after IN_FLIGHT. If the game refuses what was sent,
-- its item is taken back (Undo): what it changed is put back.

local items = {}
local last       -- the item of the last call, which a refusal of the game takes back
local blocked = false  -- the game refused one of our calls (set during the call)

local function Slot(kind, key)
    return kind .. "|" .. (key or "")
end

local function Expired(item)
    return item.kind ~= "new" and item.kind ~= "restore" and GetTime() - item.at >= IN_FLIGHT
end

function Send.Put(kind, key, item)
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
-- sent: either, when kind is nil.
function Send.InFlight(key, kind)
    if kind then
        return Send.Item(kind, key) ~= nil
    end
    return Send.Item("update", key) ~= nil or Send.Item("delete", key) ~= nil
end

-- The calendar shows it.
function Send.Landed(kind, key)
    local slot = Slot(kind, key)
    if last == items[slot] then
        last = nil
    end
    items[slot] = nil
end

-- Whether a new or restored event waits for the calendar's answer.
function Send.Waiting()
    for _, item in pairs(items) do
        if item.kind == "new" or item.kind == "restore" then
            return true
        end
    end
    return false
end

-- Takes back what was sent (why: the game's words, for the form).
local function Undo(item, why)
    local slot = Slot(item.kind, item.key)
    if items[slot] ~= item then
        return
    end
    items[slot] = nil
    if last == item then
        last = nil
    end
    if item.kind == "update" and item.mine then
        Read.State("known")[item.key] = item.previous
    elseif item.kind == "create" then
        -- Sent with its button: it waits for it again.
        Read.State("created")[item.key] = nil
    elseif item.kind == "new" and item.failed then
        item.failed(why)
    end
end

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

-- A change of the event about to be sent: its item, with what was agreed
-- before (the first change's, while one is still on its way).
local function PutUpdate(key, mine)
    local earlier = Send.Item("update", key)
    return Send.Put("update", key, { mine = mine, previous = earlier and earlier.previous or Read.State("known")[key] })
end

-- Forgets every item of an event (deleted from the addon).
function Send.Forget(key)
    for _, kind in ipairs({ "restore", "create", "update", "delete" }) do
        Send.Landed(kind, key)
    end
end

-- Calls to the calendar ---------------------------------------------------------------------------

-- Calls fn, a call to the game's calendar, as part of item (or nil):
-- whether the game took it. If not, the item is taken back.
function Send.Try(what, item, fn)
    blocked = false
    last = item
    local ok, err = pcall(fn)
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

-- The game refused one of our calls (ADDON_ACTION_BLOCKED): what it was
-- part of is taken back, and the other changes sent wait again.
function Send.OnBlocked(action)
    blocked = true
    Note(tostring(action), "blocked by the game")
    Calendar.lastError = L[REFUSED]
    if last then
        Undo(last, Calendar.lastError)
    end
    UndoAll({ update = true, delete = true }, Calendar.lastError)
    ns.Fire("CalendarPending")
end

-- The calendar refused a change (CALENDAR_UPDATE_ERROR, text: its words;
-- count with CALENDAR_ERROR_EVENTS_EXCEEDED, its limit of events created):
-- what waits to be created is given up (the form or the event says why),
-- and the changes and deletions sent wait again.
function Send.OnError(message, count, text)
    local why = text
    if message == "CALENDAR_ERROR_EVENTS_EXCEEDED" then
        -- Restore event stays off until one of the player's calendar
        -- events goes (Calendar.AtLimit).
        ns.Data.OwnState().limit = { count = count, created = Calendar.CreatedCount() }
        why = Calendar.LimitText()
        Note("create", "refused by the game: its limit of events created")
    end
    UndoAll({ new = true, restore = true, create = true }, why)
    UndoAll({ update = true, delete = true }, why)
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
    last = Send.Put("new", nil, { fields = fields, ti = fields.ti, tm = fields.tm - fields.tm % 60, done = done,
        failed = failed })
    return true
end

-- Whether a new event of the form's waits for the calendar's answer.
function Calendar.Creating()
    return Send.Item("new") ~= nil
end

-- The form changing one of our events (EventForm.lua) keeps it open, so
-- the click that saves it changes the calendar too: key, or nil once the
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

-- In the click that saves a change (EventForm.lua), before our record has
-- it: whether the calendar took it. If not, it goes with a later click
-- (the organizer's, for an officer the game does not let change it).
function Calendar.UpdateFirst(key, fields)
    local event = Events.Get(key)
    if not event or event.ci == 0 or Read.openKey ~= key or Read.OpenTitle() == nil or Read.ActionPending() then
        Note("update", "not sent: the event was not open yet")
        return false
    end
    local mine = event.owner == ns.playerGUID
    if not mine and Read.Plain(ns.Try(C_Calendar.EventCanEdit)) ~= true then
        return false
    end
    local new = { ti = fields.ti, tm = fields.tm, ty = fields.ty, de = fields.de or "", lk = fields.lk == true }
    local item = PutUpdate(key, mine)
    if mine then
        Read.State("known")[key] = new
    end
    return Send.Try("update", item, function()
        Fill(new)
        C_Calendar.UpdateEvent()
    end)
end

-- The click that cancels an event (EventView.lua): its calendar event goes
-- first, inside the click when it is open, then the event is cancelled in
-- the addon. If the game does not take it, it is tried again by itself, and
-- the organizer's client deletes it when an officer cannot. Returns whether
-- the calendar event went inside the click.
function Calendar.Cancel(key)
    Read.State("byCalendar")[key] = nil
    local event = Events.Get(key)
    local entry = event and Read.Find(event.ci)
    local deleted = false
    if entry then
        Organizer.ForgetTried(entry.id)
        deleted = Organizer.Delete(key, entry, true)
    end
    Events.Cancel(key)
    return deleted
end

-- The click that restores a cancelled event (EventView.lua): for its
-- organizer, the calendar first; the event is restored in the addon once
-- the calendar has it again, and stays cancelled if it refuses it. Whether
-- it was sent (or, for someone else's or a past one, restored).
function Calendar.Restore(key)
    local event = Events.Get(key)
    if not event then
        return false
    end
    if event.owner ~= ns.playerGUID or event.tm <= Events.Now() or event.ci == 0 then
        -- Not the player's to create, over, or never in the calendar (it
        -- waits for its Create in calendar button again): the addon only.
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
    last = Send.Put("restore", key, { ti = event.ti, tm = event.tm })
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

-- What waits for the organizer ---------------------------------------------------------------------

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

-- The changes the player's own events wait for in the calendar, in order:
-- { kind = "create", "update" or "delete", key, event }. A creation waits
-- for its own button (Calendar.SendNow); the others go with any click.
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

-- Does the first change the player's own events wait for that can go now:
-- call it first thing in a click of the player. Returns what it did (the
-- pending item), or nil.
function Calendar.RunPending()
    if not Read.scanned or Read.ActionPending() then
        return nil
    end
    -- Where the events are now: the player may have moved the calendar's month.
    Read.Scan()
    for _, item in ipairs(Calendar.Pending()) do
        local event = item.event
        -- A creation waits for its own button (Calendar.SendNow): with any
        -- click, the game would refuse so many so fast.
        if item.kind == "update" and Read.openKey == item.key and Read.OpenTitle() ~= nil then
            -- The event opened beforehand, with no click (Tick).
            local sent = PutUpdate(item.key, true)
            Organizer.Agree(item.key, event)
            if Send.Try("update", sent, function()
                Fill(event)
                C_Calendar.UpdateEvent()
            end) then
                return item
            end
            return nil
        elseif item.kind == "delete" then
            local entry = Read.Find(event.ci)
            if entry and Organizer.Delete(item.key, entry, true) then
                Organizer.needsClick = false
                return item
            end
        end
    end
    -- A copy of an event, kept open because the game refused deleting it
    -- with no click.
    return Organizer.DeleteKept()
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

-- For the clicks of the addon's window (UI.Clicked): the first thing they
-- do, so a change waiting for the organizer goes out with them.
function Calendar.OnClick()
    local ok, done = pcall(Calendar.RunPending)
    if ok and done then
        ns.Fire("CalendarPending")
    end
end

-- New and restored events -----------------------------------------------------------------------

-- The events sent to be created (Create, Restore event), into the addon
-- once the calendar has them; given up after a while, the addon unchanged.
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
        elseif clock - item.at > CREATE_TIMEOUT then
            Send.Landed("new")
            Calendar.lastError = L["The game's calendar did not answer. Try again."]
            if item.failed then
                item.failed(Calendar.lastError)
            end
        end
    end
    local restores = {}
    for _, other in pairs(items) do
        if other.kind == "restore" then
            restores[#restores + 1] = other
        end
    end
    for _, restore in ipairs(restores) do
        local key = restore.key
        local id = Read.Landing(restore.ti, restore.tm, used)
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
        elseif clock - restore.at > CREATE_TIMEOUT then
            Send.Landed("restore", key)
            Calendar.lastError = L["The game's calendar did not answer. Try again."]
            ns.Fire("CalendarPending")
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
