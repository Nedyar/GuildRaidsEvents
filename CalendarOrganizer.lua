-- CalendarOrganizer.lua: the events the player organizes or moderates, in
-- the game's calendar (see Calendar.lua). The clients of an event's
-- organizer and of its moderators keep each field in step both ways and
-- delete it from the addon when it is deleted in the game's calendar
-- window; only the organizer's, which created its calendar event, links
-- new events to their calendar event, adds those made in that window,
-- takes out of its record those a moderator deleted, deletes copies of an
-- event, and deletes calendar events with no click (only the open event
-- can be deleted).
local _, ns = ...
local L = ns.L

local Calendar, Read, Send, Organizer, Member, Statuses =
    ns.Calendar, ns.CalendarRead, ns.CalendarSend, ns.CalendarOrganizer, ns.CalendarMember, ns.CalendarStatuses
local Events = ns.Events
local Note = Calendar.Note
local Plain = Read.Plain

local DELETE_RETRY = 30      -- seconds between two tries to delete one calendar event
local BLOCKED_WAIT = 600     -- and more after the game refused it (it wanted a click)

-- The calendar events of the events we watch found missing: [key] = { at =
-- GetTime(), reads }. Deleted only if the calendar's data came again since
-- it last had them, and lacks them, not while it is still loading.
local missing = {}
local seen = {}              -- [key] = Read.reads when its calendar event was last seen, in this session
local deleteTried = {}       -- [event ID] = GetTime() of the last try to delete it
local adoptTried = {}        -- [event ID] = true: taken into the addon once already

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

-- One of our events linked to a calendar event (new, or a copy that stands
-- for it): the statuses go to it from the addon, as nothing was agreed
-- with it.
function Organizer.Linked(key, calendarID)
    Read.State("statuses")[key], Read.State("moderators")[key] = nil, nil
    Statuses.Forget(key)
    Events.SetCalendarID(key, calendarID)
end

-- Our new events, once in the calendar: their event IDs into the records.
function Organizer.Link()
    local used = Read.UsedIDs()
    local created = Read.State("created")
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and event.ci == 0 then
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

-- Brings an event the player organizes or moderates and its calendar event
-- together, field by field. cal: the calendar's values (de only once the
-- event was opened).
local function Reconcile(key, event, cal)
    local known = Read.State("known")
    local agreed = known[key]
    if not agreed then
        -- First look: what the addon has, so that what the calendar has
        -- otherwise comes into it (the calendar first: the addon changes
        -- only once the calendar took it).
        agreed = { ti = event.ti, tm = event.tm, ty = event.ty, de = event.de or "", lk = event.lk == true }
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

-- The clients of an event's organizer and of its moderators: what the
-- calendar shows of it, into the addon. A calendar event missing for a
-- while: deleted there, so the event is deleted from the addon too.
function Organizer.Watch()
    local now, clock = Events.Now(), GetTime()
    local used = Read.UsedIDs()
    for key, event in pairs(Events.All()) do
        local mine = event.owner == ns.playerGUID
        local manages = event.ci ~= 0 and (mine or ns.Rights.MayIManage(event))
        if manages then
            Landed(key, Read.Find(event.ci))
        end
        -- (One made in the calendar is as the calendar has it, and goes
        -- when it goes from there.)
        if manages and not event.cal and event.tm > now and not Send.InFlight(key) then
            local entry = Read.Find(event.ci)
            -- The guild's list stands for events beyond the months looked
            -- at; it may still name one just deleted.
            local listed = not entry and not Read.InRange(event.tm) and Read.GuildEntry(event.ci)
            if entry then
                seen[key] = Read.reads
            end
            if entry or listed then
                missing[key] = nil
                local ev = entry and entry.ev
                Reconcile(key, event, {
                    ti = Plain(entry and ev.title or listed.title),
                    tm = entry and Read.StartOf(ev.startTime) or Events.Naive(listed.year, listed.month,
                        listed.monthDay, listed.hour, listed.minute),
                    ty = Read.TypeOf(Plain(entry and ev.eventType or listed.eventType)),
                    -- The guild's list does not say whether it is locked.
                    lk = entry and Read.IsLocked(ev),
                })
            elseif Read.InRange(event.tm) and not mine and (not seen[key] or Read.GuildEntry(event.ci)) then
                -- A moderator's client says nothing of one it has not seen
                -- in this session (the one it knows may be one a copy
                -- stands for since), nor of one still in the guild's list:
                -- only gone from their own calendar for a while.
                missing[key] = nil
            elseif Read.InRange(event.tm) then
                -- Gone from the calendar: deleted there, as the event will
                -- be for good. Only once the calendar's data came again
                -- since it last had it (the news of a deletion made in the
                -- game's window, or asked for here) and lacks it, so not
                -- while it is still loading. (Asking alone waited, in game,
                -- until the game's window was closed and opened again.)
                local first = missing[key] == nil
                if first then
                    missing[key] = { at = clock, reads = Read.reads }
                end
                local deleted = Read.reads > (seen[key] or missing[key].reads)
                if not deleted and (first or clock - missing[key].at > 3) then
                    missing[key].at = clock
                    ns.Try(C_Calendar.OpenCalendar)
                end
                if deleted then
                    missing[key], seen[key] = nil, nil
                    local copy = mine and Read.Copies(event, used)[1]
                    if copy then
                        -- Another of its copies stands for it.
                        used[copy.id] = true
                        Organizer.Linked(key, copy.id)
                    else
                        Note("from the calendar", "deleted there, so deleted from the addon: " .. event.ti)
                        Organizer.Remove(key)
                    end
                end
            end
        end
    end
end

-- Every client: someone else's event made in the addon whose calendar
-- event is gone (deleted in the game's window while its organizer's and
-- moderators' clients were away, which would delete it for everyone) is
-- no longer shown here, as the calendar no longer has it: once the
-- calendar's data came again since this client last saw it there, or
-- since it first found it missing, and lacks it (also in the guild's
-- list). Shown again should the calendar show it again; its organizer's
-- client deletes it for good when back.
local seenHere, missingHere = {}, {}  -- as seen and missing above, for others' events

function Organizer.WatchOthers()
    local clock, now = GetTime(), Events.Now()
    local hid = false
    for key, event in pairs(Events.All()) do
        if event.ci ~= 0 and not event.cal and event.owner ~= ns.playerGUID and event.tm > now and Read.InRange(event.tm) then
            if Read.Find(event.ci) or Read.GuildEntry(event.ci) then
                seenHere[key], missingHere[key] = Read.reads, nil
            else
                local first = missingHere[key] == nil
                if first then
                    missingHere[key] = { at = clock, reads = Read.reads }
                end
                if Read.reads > (seenHere[key] or missingHere[key].reads) then
                    missingHere[key], seenHere[key] = nil, nil
                    Read.HideGone(event.ci)
                    Note("from the calendar", "gone from it, so no longer shown: " .. event.ti)
                    hid = true
                elseif first or clock - missingHere[key].at > 3 then
                    missingHere[key].at = clock
                    ns.Try(C_Calendar.OpenCalendar)
                end
            end
        end
    end
    if Read.ShowBack() or hid then
        Events.Changed()
    end
end

-- The organizer's client: the guild events their character created in the
-- game's calendar window, into the addon as theirs, under the key everyone
-- knows it by while no record has it (Events.CalendarMadeID): what was
-- given to it meanwhile (answers, roles) stays. So too one they created
-- before they ran the addon.
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
            local key = Events.Create({ ty = Read.TypeOf(Plain(ev.eventType)), ti = Plain(ev.title), tm = start, ml = 0,
                lk = Read.IsLocked(ev) or nil }, Events.CalendarMadeID(id))
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
    if not event or event.cal or not ns.Rights.MayIManage(event) or Send.InFlight(key) or not ns.CanRead(info) then
        return
    end
    Reconcile(key, event, {
        ti = Plain(info.title), tm = Read.StartOf(info.time), ty = Read.TypeOf(Plain(info.eventType)),
        de = Plain(info.description) or "", lk = Read.IsLocked(info),
    })
end

-- Deleting ----------------------------------------------------------------------------------------

-- One of our calendar events to delete (no click needed): a copy of one of
-- our events, or one of an event deleted from the addon (a stray). key,
-- entry, whether it is the event's own (never, here).
local function ToDelete()
    local used = Read.UsedIDs()
    for key, event in pairs(Events.All()) do
        if event.owner == ns.playerGUID and not Send.InFlight(key, "delete") and Read.Find(event.ci) then
            local copy = Read.Copies(event, used)[1]
            if copy then
                return key, copy, false
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

-- Deletes the open event (main: one of our events, not a copy): whether it
-- was sent, and why not (the game's words).
local function RemoveOpen(key, entry, main)
    deleteTried[entry.id] = GetTime()
    local canRemove = ns.Try(C_Calendar.ContextMenuEventCanRemove, entry.offset, entry.day, entry.index)
    if Plain(canRemove) == false then
        local event = Events.Get(key)
        local why = event and event.owner ~= ns.playerGUID
            and L["The game's calendar does not let you delete this event."]
            or L["The game's calendar does not let this event be deleted now. Try again after /reload."]
        Note("delete", "not sent: the game says it cannot be deleted now")
        return false, why
    end
    local item = main and Send.Put("delete", key) or nil
    if Send.Try("delete", item, function()
        C_Calendar.ContextMenuSelectEvent(entry.offset, entry.day, entry.index)
        C_Calendar.ContextMenuEventRemove()
    end) then
        return true
    end
    if Send.Blocked() then
        -- Refused with no click: tried again a while later.
        deleteTried[entry.id] = GetTime() + BLOCKED_WAIT
    end
    return false, Calendar.lastError
end

-- Deletes one calendar event (no click needed): key, the event it is or a
-- copy of. The game deletes only the open event (as its own window does,
-- on the event selected): when it is not, it is opened first and deleted
-- a moment later. failed(why), when it was not deleted. Returns whether it
-- was deleted at once, and whether it was tried (not when another step has
-- the open event, or it was tried a moment ago).
function Organizer.Delete(key, entry, main, failed)
    local last = deleteTried[entry.id]
    if last and GetTime() - last < DELETE_RETRY then
        return false, false
    elseif Read.IsOpen(entry) then
        local sent, why = RemoveOpen(key, entry, main)
        if not sent and failed then
            failed(why)
        end
        return sent, true
    elseif Read.busy then
        return false, false
    end
    deleteTried[entry.id] = GetTime()
    Read.busy = true
    Read.openKey = nil
    Read.Open(entry, function(ok)
        local sent, why = false, L["The game's calendar did not answer. Try again."]
        if ok then
            sent, why = RemoveOpen(key, entry, main)
        end
        if not sent and failed then
            failed(why)
        end
        Read.WaitDone(function()
            Read.Close()
            Read.Finish()
        end)
    end)
    return false, true
end

-- A delete asked for in a click (Delete event) is tried at once.
function Organizer.ForgetTried(calendarID)
    deleteTried[calendarID] = nil
end

-- A step of the look at the calendar (Tick): deletes what is to delete.
-- Whether a step goes on.
function Organizer.DeleteNoClick()
    local key, entry, main = ToDelete()
    return key ~= nil and (Organizer.Delete(key, entry, main) or Read.busy)
end

-- Keeps an event's calendar event open (no click needed), so the click that
-- saves a change of it changes the calendar too (Read.openKey says which).
-- Whether it is, or is being opened.
function Organizer.KeepOpen(key)
    local event = Events.Get(key)
    local entry = event and Read.Find(event.ci)
    if not entry then
        return false
    end
    if Read.openKey ~= key or Read.OpenTitle() == nil then
        Read.busy = true
        Read.Open(entry, function(ok)
            Read.openKey = ok and key or nil
            if ok then
                Organizer.ReconcileOpen(key)
            end
            Read.Finish()
            ns.Fire("CalendarPending")
        end)
    end
    return true
end

-- An event deleted from the addon: what the calendar knew of it goes. The
-- calendar event of one of the player's own, if still there, is deleted
-- too (ToDelete), and never taken into the addon again (Adopt).
local function Forget(key, event)
    for _, name in ipairs({ "known", "created", "answers", "statuses", "moderators" }) do
        Read.State(name)[key] = nil
    end
    Send.Forget(key)
    Statuses.Forget(key)
    Member.Forget(key)
    missing[key], seen[key] = nil, nil
    if event.owner == ns.playerGUID and event.ci ~= 0 then
        Read.State("strays")[event.ci] = event.tm
    end
end

-- Deletes an event the player may manage from the addon, for everyone
-- (Events.Delete), once its calendar event is gone or when it has none.
-- Whether it did.
function Organizer.Remove(key)
    local event = Events.Get(key)
    if not event then
        return false
    end
    Forget(key, event)
    return Events.Delete(key)
end

-- A step of the look at the calendar (Tick), before any other: the
-- player's own events a moderator deleted go from their record too, and
-- their calendar events from the calendar (a moderator deletes them there
-- first; one still shown is a stray).
function Organizer.Purge()
    for key, event in pairs(Events.Deleted()) do
        if event.owner == ns.playerGUID then
            Forget(key, event)
            Events.Purge(key)
            Note("delete", "deleted, so out of the record: " .. tostring(event.ti))
        end
    end
end
