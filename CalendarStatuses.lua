-- CalendarStatuses.lua: the statuses of an event's sign-ups in the game's
-- calendar (see Calendar.lua), and its moderators, both ways, with no
-- click: the clients of its organizer and of its moderators open the event
-- and give each sign-up the addon's status and moderation, and take into
-- the addon a status or a moderator given in the game's calendar window.
-- The organizer's line too (the game keeps an event's creator in it, and
-- lets its moderators give it a status). In an event made in the game's
-- calendar (no record of anyone's has it), what its creator's or a
-- moderator's client gives goes there only (Calendar.GiveThere), and comes
-- back with its list read there (CalendarLists.lua).
local _, ns = ...

local Calendar, Read, Organizer, Statuses, Lists =
    ns.Calendar, ns.CalendarRead, ns.CalendarOrganizer, ns.CalendarStatuses, ns.CalendarLists
local Events, States = ns.Events, ns.States
local Note = Calendar.Note
local Plain = Read.Plain

local MIRROR_EVERY = 120     -- seconds between two looks at one event's sign-ups

local mirrored = {}          -- [key] = { at = GetTime(), signature } of the last look at its sign-ups
-- What the player gave in events made in the calendar, to give there
-- (Calendar.GiveThere): [key] = { [guid] = { status } or { moderator } }.
local there = {}

-- The calendar status each sign-up of the event should have: [guid] =
-- status; the organizer's line too. And the organizer's sign-up, or nil
-- (none, or one taken back).
local function WantedStatuses(event)
    local wanted, creator = {}, nil
    for _, signUp in ipairs(Events.SignUps(event)) do
        wanted[signUp.guid] = States.CalendarStatusOf(signUp)
        if signUp.guid == event.owner and States.Of(signUp) ~= "none" then
            creator = signUp
        end
    end
    wanted[event.owner] = States.OrganizerCalendarStatus(creator)
    return wanted, creator
end

-- The organizer's status given in the calendar, into the addon: as their
-- own state on their client; as a status given them on a moderator's.
local function TakeCreatorStatus(key, event, status)
    local state = States.FromCalendar(status)
    if not state then
        return
    elseif event.owner == ns.playerGUID then
        local mine = Events.Mine(event)
        States.SetMine(key, state, mine and mine.ro or ns.Roles.Default(), mine and mine.no, true)
    elseif States.StatusOf(state) then
        Events.SetStatus(key, event.owner, States.StatusOf(state))
    end
end

-- The same wanted statuses, and the moderators, as one text, to tell when
-- they changed.
local function StatusSignature(event)
    local parts = {}
    for guid, status in pairs(WantedStatuses(event)) do
        parts[#parts + 1] = guid .. "=" .. status
    end
    for guid in pairs(event.md or {}) do
        parts[#parts + 1] = "m:" .. guid
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Whether the organizer's own record names that moderator (on), takes it
-- back (off), or says nothing (nil).
local function OwnNaming(key, guid)
    local record = ns.Data.GetOwnRecord(false)
    local naming = record and record.mo and record.mo[key] and record.mo[key][guid]
    return naming and naming.on
end

-- One line of the open event's list: its moderation as the calendar has it
-- and as the addon wants it (agreed: as both last agreed, the moderators of
-- the event as the calendar and the addon last agreed on them). A change
-- made in the calendar comes into the addon, as the player's; a change made
-- in the addon (perhaps by a moderator) is returned to send. The
-- organizer's client names in its own record whatever is so (perhaps
-- named by a moderator, perhaps sent by a moderator's client), so it stays
-- should its maker stop being a moderator, as in the game's calendar.
local function ModeratorChange(key, event, guid, has, agreedOf)
    local want = event.md ~= nil and event.md[guid] == true
    local agreed = agreedOf[guid] == true
    local change
    if has == want then
        agreedOf[guid] = has
    elseif want == agreed then
        agreedOf[guid] = has
        want = has
        Events.SetModerator(key, guid, has)
        Note("from the calendar", "took a moderator named there: " .. event.ti)
    else
        change = { guid = guid, moderator = want }
    end
    if event.owner == ns.playerGUID then
        local own = OwnNaming(key, guid)
        if (want and own ~= true) or (not want and own == true) then
            Events.SetModerator(key, guid, want)
        end
    end
    return change
end

-- The open event's sign-ups: statuses given in the calendar into the
-- addon; then those whose calendar status or moderation is not the
-- addon's: { guid, status } or { guid, moderator = true or false }.
local function StatusChanges(key, event)
    local wanted, creator = WantedStatuses(event)
    local statuses, moderators = Read.State("statuses"), Read.State("moderators")
    statuses[key] = statuses[key] or {}
    moderators[key] = moderators[key] or {}
    local agreedOf = statuses[key]
    local changes = {}
    for index = 1, Plain(ns.Try(C_Calendar.GetNumInvites)) or 0 do
        local invite = ns.Try(C_Calendar.EventGetInvite, index)
        local isCreator = ns.CanRead(invite) and (Plain(invite.modStatus) == "CREATOR" or Plain(invite.guid) == event.owner
            or (event.owner == ns.playerGUID and Plain(invite.inviteIsMine) == true))
        if isCreator then
            -- The organizer's line (they created the event): theirs, or one
            -- their moderators give a status too.
            local owner = event.owner
            local status, target = Plain(invite.inviteStatus), wanted[owner]
            local agreed = agreedOf[owner] or Enum.CalendarStatus.Confirmed
            if status == target and not creator then
                -- No answer of theirs in the addon, while the game keeps its
                -- creator in the event: the calendar's line comes in.
                agreedOf[owner] = status
                TakeCreatorStatus(key, event, status)
            elseif status == target then
                agreedOf[owner] = status
            elseif target == agreed then
                agreedOf[owner] = status
                TakeCreatorStatus(key, event, status)
                Note("from the calendar", "took the organizer's status given there: " .. event.ti)
            elseif target then
                changes[#changes + 1] = { guid = owner, status = target }
            end
        elseif ns.CanRead(invite) then
            local status, guid = Plain(invite.inviteStatus), Plain(invite.guid)
            -- Anyone in the list may moderate, whatever their status.
            local moderation = guid and ModeratorChange(key, event, guid, Plain(invite.modStatus) == "MODERATOR",
                moderators[key])
            if moderation then
                changes[#changes + 1] = moderation
            end
            local target = guid and wanted[guid]
            local signedUp = status ~= Enum.CalendarStatus.NotSignedup and status ~= Enum.CalendarStatus.Declined
            if target and signedUp then
                local agreed = agreedOf[guid] or Enum.CalendarStatus.Signedup
                local given = States.StatusOf(States.FromCalendar(status))
                if status == target then
                    agreedOf[guid] = status
                elseif target == agreed and given then
                    -- Given in the calendar since: the addon takes it.
                    agreedOf[guid] = status
                    Events.SetStatus(key, guid, given)
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

-- The next event the player organizes or moderates whose sign-ups to look
-- at: one whose
-- statuses changed in the addon since the last look, or, while the game's
-- calendar window is closed, not looked at for a while (a sign-up or a
-- change made in the calendar).
local function EventToMirror(now)
    local best
    local again = not Read.WindowShown()
    for key, event in pairs(Events.All()) do
        local entry = Read.Find(event.ci)
        if entry and event.cal and there[key] then
            -- What the player gave in one made in the calendar goes there
            -- first of all.
            return { key = key, event = event, entry = entry, there = there[key] }
        elseif entry and not event.cal and ns.Rights.MayIManage(event) and event.tm > Events.Now() then
            local last = mirrored[key]
            local signature = StatusSignature(event)
            if not last or last.signature ~= signature or (again and now - last.at > MIRROR_EVERY) then
                if not best or event.tm < best.event.tm then
                    best = { key = key, event = event, entry = entry, signature = signature }
                end
            end
        end
    end
    return best
end

-- What the player gave in an event made in the calendar, as changes to
-- make there: { guid, status } or { guid, moderator = true or false }.
local function ThereChanges(item)
    there[item.key] = nil
    local changes = {}
    for guid, change in pairs(item.there) do
        if change.moderator ~= nil then
            changes[#changes + 1] = { guid = guid, moderator = change.moderator }
        end
        if change.status then
            changes[#changes + 1] = { guid = guid, status = change.status }
        end
    end
    return changes
end

-- Opens the event, takes in what was given in the calendar, and gives each
-- sign-up the addon's status and moderation, one at a time. In one made in
-- the calendar, gives what the player gave in it, then reads its list
-- again (that is where its statuses come from).
local function Mirror(item)
    Read.openKey = nil
    Read.busy = true
    if not item.there then
        mirrored[item.key] = { at = GetTime(), signature = item.signature }
    end
    Read.Open(item.entry, function(ok)
        if not ok then
            Read.Close()
            Read.Finish()
            return
        end
        local changes
        if item.there then
            changes = ThereChanges(item)
        else
            Organizer.ReconcileOpen(item.key)
            -- Its list read too: sign-ups made in the calendar come in first.
            Lists.Take(Events.Get(item.key) or item.event)
            changes = StatusChanges(item.key, Events.Get(item.key) or item.event)
        end
        local step = 0
        local function NextChange()
            step = step + 1
            local change = changes[step]
            local index = change and InviteIndex(change.guid)
            if not change then
                if item.there then
                    Lists.Take(Events.Get(item.key) or item.event, true)
                end
                Read.Close()
                Read.Finish()
                return
            end
            -- (What was agreed with the calendar, for those made in the
            -- addon only.)
            local agreed = not item.there and Read.State(change.moderator ~= nil and "moderators" or "statuses")[item.key]
            if index and change.moderator ~= nil then
                if change.moderator then
                    C_Calendar.EventSetModerator(index)
                else
                    C_Calendar.EventClearModerator(index)
                end
                if agreed then
                    agreed[change.guid] = change.moderator
                end
            elseif index then
                C_Calendar.EventSetInviteStatus(index, change.status)
                if agreed then
                    agreed[change.guid] = change.status
                end
            end
            Read.WaitDone(function()
                C_Timer.After(0.5, NextChange)
            end)
        end
        NextChange()
    end)
end

-- A step of the look at the calendar (Tick): the statuses of the next
-- event that needs a look. Whether a step goes on.
function Statuses.MirrorNext(now)
    local item = EventToMirror(now)
    if item then
        Mirror(item)
        return true
    end
    return false
end

-- The event open in the game's calendar window: its list is read (any
-- player's); when the player organizes or moderates it, what is changed
-- there comes into the addon at once (the description and the statuses
-- show only on the open event).
function Statuses.ReadOpen()
    if Read.busy or Plain(ns.Try(C_Calendar.IsEventOpen)) ~= true then
        return
    end
    local info = ns.Try(C_Calendar.GetEventInfo)
    if not ns.CanRead(info) then
        return
    end
    local start, title = Read.StartOf(info.time), Plain(info.title)
    for key, event in pairs(Events.All()) do
        if event.ci ~= 0 and event.tm == start and event.ti == title then
            Lists.Take(event)
            if not event.cal and ns.Rights.MayIManage(event) then
                Organizer.ReconcileOpen(key)
                StatusChanges(key, Events.Get(key) or event)
            end
            return
        end
    end
end

-- The player gives a status (calendar status) or takes a moderator
-- (moderator true or false) in an event made in the game's calendar, as
-- its creator or one of its moderators: given there first, with no click;
-- it shows once the list read there afterwards has it. Whether it goes.
function Calendar.GiveThere(key, guid, change)
    local event = Events.Get(key)
    if not event or not event.cal or not guid or not ns.Rights.MayIManage(event)
            or (change.moderator ~= nil and guid == event.owner) then
        return false
    end
    there[key] = there[key] or {}
    local waiting = there[key][guid] or {}
    if change.status then
        waiting.status = change.status
    end
    if change.moderator ~= nil then
        waiting.moderator = change.moderator
    end
    there[key][guid] = waiting
    Calendar.TickSoon()
    return true
end

-- Whether something the player gave in that event waits to go there.
function Calendar.GivingThere(key)
    return there[key] ~= nil
end

-- Its sign-ups are looked at again (its calendar event is new, or it was
-- deleted from the addon).
function Statuses.Forget(key)
    mirrored[key] = nil
end
