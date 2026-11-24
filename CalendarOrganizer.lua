-- CalendarOrganizer.lua: the organizer's client and their events in the
-- game's calendar (see Calendar.lua): new events linked to their calendar
-- event, each field kept in step both ways, events deleted or made in the
-- game's calendar window, copies of an event, and deleting calendar events
-- (no click needed, but only the open event can be deleted).
local _, ns = ...
local L = ns.L

local Calendar, Read, Send, Organizer, Member, Statuses =
    ns.Calendar, ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer, ns.CalendarMember, ns.CalendarStatuses
local Events = ns.Events
local Note = Calendar.Note
local Plain = Read.Plain

local DELETE_RETRY = 30      -- seconds between two tries to delete one calendar event

-- Our calendar events found missing: [key] = { at = GetTime(), reads }.
-- Deleted only if still missing once the calendar's data came again (asked
-- for at once), not while it is still loading.
local missing = {}
local seen = {}              -- [key] = true: its calendar event was seen in this session
local deleteTried = {}       -- [event ID] = GetTime() of the last try to delete it
local adoptTried = {}        -- [event ID] = true: taken into the addon once already
-- The game refused a deletion with no click: deletions then wait, with the
-- event kept open, for the organizer's next click; one done in a click
-- lets them try with no click again.
Organizer.needsClick = false

-- Both ways ---------------------------------------------------------------------------------------

-- The fields kept in step, as the calendar has them.
local SYNCED = { "ti", "tm", "ty", "de", "lk" }

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

-- The calendar and the addon agree on the event as it is now.
function Organizer.Agree(key, event)
    Read.State("known")[key] = { ti = event.ti, tm = event.tm, ty = event.ty, de = event.de or "", lk = event.lk == true }
end

-- One of our events linked to a calendar event made anew (restoring it):
-- the statuses go to it from the addon, as nothing was agreed with it.
function Organizer.Linked(key, calendarID)
    Read.State("statuses")[key] = nil
    Statuses.Forget(key)
    Events.SetCalendarID(key, calendarID)
end

-- Our new events, once in the calendar: their event IDs into the records.
function Organizer.Link()
    local used = Read.UsedIDs()
    local created = Read.State("created")
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci == 0 and not event.x then
            local copy = Read.Copies(event, used)[1]
            if copy then
                used[copy.id] = true
                created[key] = nil
                Send.Landed("create", key)
                Organizer.Agree(key, event)
                Organizer.Linked(key, copy.id)
            end
        end
    end
end

-- Brings one of our events and its calendar event together, field by
-- field. cal: the calendar's values (de only once the event was opened).
local function Reconcile(key, event, cal)
    local known = Read.State("known")
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
    for _, field in ipairs(Events.FIELDS) do
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
function Organizer.NeedsUpdate(key, event)
    local agreed = Read.State("known")[key]
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

-- A change or deletion sent, once the calendar shows it (entry: the event
-- in the calendar, or nil).
local function Landed(key, entry)
    local agreed = Read.State("known")[key]
    if not entry and Send.Item("delete", key) then
        Send.Landed("delete", key)
    elseif entry and agreed and Send.Item("update", key) and Plain(entry.ev.title) == agreed.ti
            and Read.StartOf(entry.ev.startTime) == agreed.tm and Read.TypeOf(Plain(entry.ev.eventType)) == agreed.ty
            and (Read.IsLocked(entry.ev) == nil or Read.IsLocked(entry.ev) == AgreedValue(agreed, "lk")) then
        Send.Landed("update", key)
    end
end

-- The organizer's client: what the calendar shows of each of their events,
-- into the addon. A calendar event missing for a while: deleted there, so
-- the event is cancelled (or, when we deleted it ourselves and the event
-- was restored since, created again).
function Organizer.Watch()
    local now, clock = Events.Now(), GetTime()
    local gone, known, byCalendar = Read.State("gone"), Read.State("known"), Read.State("byCalendar")
    local used = Read.UsedIDs()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci ~= 0 then
            Landed(key, Read.Find(event.ci))
        end
        if event.owner == ns.playerGUID and event.ci ~= 0 and event.tm > now and not Send.InFlight(key) then
            local entry = Read.Find(event.ci)
            -- The guild's list stands for events beyond the months looked
            -- at; it may still name one just deleted.
            local listed = not entry and not Read.InRange(event.tm) and Read.GuildEntry(event.ci)
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
                        tm = entry and Read.StartOf(ev.startTime) or Events.Naive(listed.year, listed.month,
                            listed.monthDay, listed.hour, listed.minute),
                        ty = Read.TypeOf(Plain(entry and ev.eventType or listed.eventType)),
                        -- The guild's list does not say whether it is locked.
                        lk = entry and Read.IsLocked(ev),
                    })
                end
            elseif event.x and Read.InRange(event.tm) then
                gone[key] = true
            elseif Read.InRange(event.tm) then
                -- Gone from its creator's calendar: deleted there. At once
                -- if it was seen in this session; else once the calendar's
                -- data came again, so not while it is still loading.
                local deleted = seen[key]
                if not deleted and not missing[key] then
                    missing[key] = { at = clock, reads = Read.reads }
                    ns.Try(C_Calendar.OpenCalendar)
                elseif not deleted and Read.reads > missing[key].reads then
                    deleted = true
                elseif not deleted and clock - missing[key].at > 3 then
                    missing[key].at = clock
                    ns.Try(C_Calendar.OpenCalendar)
                end
                if deleted then
                    missing[key], seen[key] = nil, nil
                    local copy = Read.Copies(event, used)[1]
                    if copy then
                        -- Another of its copies stands for it.
                        used[copy.id] = true
                        Organizer.Linked(key, copy.id)
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
function Organizer.Adopt()
    local used, now, strays = Read.UsedIDs(), Events.Now(), Read.State("strays")
    local mine = {}
    for _, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID then
            mine[(event.ti or "") .. "|" .. tostring(event.tm)] = true
        end
    end
    -- Not the form's new event, which comes in once the calendar has it.
    local new = Send.Item("new")
    for id, entry in pairs(Read.Found()) do
        local ev = entry.ev
        local start = Read.StartOf(ev.startTime)
        local sentByForm = new ~= nil and Plain(ev.title) == new.ti and start == new.tm
        if not used[id] and not adoptTried[id] and not strays[id] and not sentByForm and Plain(ev.modStatus) == "CREATOR"
                and start and start > now
                and not mine[tostring(Plain(ev.title)) .. "|" .. tostring(start)] then
            adoptTried[id] = true
            local key = Events.Create({ ty = Read.TypeOf(Plain(ev.eventType)), ti = Plain(ev.title), tm = start, ml = 0 })
            if key then
                Events.SetCalendarID(key, id)
                Organizer.Agree(key, Events.Get(key))
                Note("from the calendar", "added an event made there: " .. tostring(Plain(ev.title)))
            end
        end
    end
end

-- The open event, read as the calendar has it, into the addon (its
-- description shows only there).
function Organizer.ReconcileOpen(key)
    local event = Events.Get(key)
    local info = ns.Try(C_Calendar.GetEventInfo)
    if not event or event.owner ~= ns.playerGUID or event.x or Send.InFlight(key) or not ns.CanRead(info) then
        return
    end
    Reconcile(key, event, {
        ti = Plain(info.title), tm = Read.StartOf(info.time), ty = Read.TypeOf(Plain(info.eventType)),
        de = Plain(info.description) or "", lk = Read.IsLocked(info),
    })
end

-- Deleting ----------------------------------------------------------------------------------------

-- One of our calendar events to delete (no click needed): a cancelled
-- event's, or a copy of one of our events. key, entry, whether it is the
-- event's own.
local function ToDelete()
    local used = Read.UsedIDs()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and not Send.InFlight(key, "delete") and not Read.State("byCalendar")[key]
                and not Calendar.Restoring(key) then
            local entry = Read.Find(event.ci)
            if event.x and entry then
                return key, entry, true
            elseif event.x or entry then
                local copy = Read.Copies(event, used)[1]
                if copy then
                    return key, copy, false
                end
            end
        end
    end
    local strays, now, found = Read.State("strays"), Events.Now(), Read.Found()
    for id, start in pairs(strays) do
        if found[id] then
            return "stray:" .. id, found[id], false
        elseif start < now then
            strays[id] = nil
        end
    end
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
    local item
    if main then
        item = Send.Put("delete", key)
        Read.State("gone")[key] = true
    end
    return Send.Try("delete", item, function()
        C_Calendar.ContextMenuSelectEvent(entry.offset, entry.day, entry.index)
        C_Calendar.ContextMenuEventRemove()
    end)
end

-- Deletes one calendar event (no click needed): key, the event it is or a
-- copy of. The game deletes only the open event (as its own window does,
-- on the event selected): when it is not, it is opened first and deleted
-- a moment later. Whether it was deleted at once.
function Organizer.Delete(key, entry, main)
    local last = deleteTried[entry.id]
    if last and GetTime() - last < DELETE_RETRY then
        return false
    elseif Read.IsOpen(entry) then
        return RemoveOpen(key, entry, main)
    elseif Read.busy then
        return false
    end
    deleteTried[entry.id] = GetTime()
    Read.busy = true
    Read.openKey = nil
    Read.Open(entry, function(ok)
        if ok and not RemoveOpen(key, entry, main) and Send.Blocked() then
            Organizer.needsClick = true
        end
        Read.WaitDone(function()
            Read.Close()
            Read.Finish()
        end)
    end)
    return false
end

-- A delete asked for in a click (Cancel event) is tried at once.
function Organizer.ForgetTried(calendarID)
    deleteTried[calendarID] = nil
end

-- A step of the look at the calendar (Tick): deletes what is to delete,
-- unless the game wants a click for it. Whether a step goes on.
function Organizer.DeleteNoClick()
    if Organizer.needsClick then
        return false
    end
    local key, entry, main = ToDelete()
    return key ~= nil and (Organizer.Delete(key, entry, main) or Read.busy)
end

-- Keeps a calendar event open, so a click can change or delete it: openAs
-- is what Read.openKey says while it is (our event's key, or "copy:" and
-- the event ID for a copy). Whether it is.
local function KeepOpenEntry(openAs, entry, onOpen)
    if Read.openKey ~= openAs or Read.OpenTitle() == nil then
        Read.busy = true
        Read.Open(entry, function(ok)
            Read.openKey = ok and openAs or nil
            if ok and onOpen then
                onOpen()
            end
            Read.Finish()
            ns.Fire("CalendarPending")
        end)
    end
    return true
end

-- Keeps one of our events open, so a click can change it: whether it is.
function Organizer.KeepOpen(key)
    local event = Events.Get(key)
    local entry = event and Read.Find(event.ci)
    if not entry then
        return false
    end
    return KeepOpenEntry(key, entry, function()
        Organizer.ReconcileOpen(key)
    end)
end

-- What the next click would send that needs its event open: the first of
-- our events whose change waits for a click (a deletion too, when the game
-- wants a click for it, a copy's as well). { openAs, entry, onOpen }, or
-- nil.
function Organizer.ToKeepOpen()
    for _, pending in ipairs(Calendar.Pending()) do
        if pending.kind == "update" or pending.kind == "delete" and Organizer.needsClick then
            local entry = Read.Find(pending.event.ci)
            if entry then
                local key = pending.key
                return { openAs = key, entry = entry, onOpen = function()
                    Organizer.ReconcileOpen(key)
                end }
            end
        end
    end
    if Organizer.needsClick then
        local key, entry, main = ToDelete()
        if key and not main then
            return { openAs = "copy:" .. entry.id, entry = entry }
        end
    end
end

-- A step of the look at the calendar (Tick): keeps that event open, so the
-- next click sends its change. Whether it is.
function Organizer.KeepOpenFor(target)
    return KeepOpenEntry(target.openAs, target.entry, target.onOpen)
end

-- In a click (Calendar.RunPending): deletes the copy kept open, when the
-- game wanted a click for it. The pending item it did, or nil.
function Organizer.DeleteKept()
    if not Organizer.needsClick then
        return nil
    end
    local key, entry, main = ToDelete()
    if key and not main and Read.openKey == "copy:" .. entry.id and Read.IsOpen(entry)
            and RemoveOpen(key, entry, false) then
        Organizer.needsClick = false
        Read.openKey = nil
        return { kind = "delete", key = key }
    end
end

-- One of the player's events deleted from the addon (Calendar.Delete):
-- what the calendar knew of it goes; its calendar event, if still there, is
-- deleted too (ToDelete), and never taken into the addon again (Adopt).
function Organizer.Forget(key, event)
    for _, name in ipairs({ "known", "created", "gone", "byCalendar", "answers", "statuses" }) do
        Read.State(name)[key] = nil
    end
    Send.Forget(key)
    Statuses.Forget(key)
    Member.Forget(key)
    missing[key], seen[key] = nil, nil
    if event.ci ~= 0 then
        Read.State("strays")[event.ci] = event.tm
    end
end
