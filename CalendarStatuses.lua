-- CalendarStatuses.lua: the statuses of the sign-ups of the organizer's
-- events in the game's calendar (see Calendar.lua), both ways, with no
-- click: the organizer's client opens an event and gives each sign-up the
-- addon's status, and takes into the addon a status given in the game's
-- calendar window (also the organizer's own line: the game keeps an
-- event's creator in it).
local _, ns = ...

local Calendar, Read, Organizer, Statuses = ns.Calendar, ns.CalendarRead, ns.CalendarOrganizer, ns.CalendarStatuses
local Events, States = ns.Events, ns.States
local Note = Calendar.Note
local Plain = Read.Plain

local MIRROR_EVERY = 120     -- seconds between two looks at one event's sign-ups

local mirrored = {}          -- [key] = { at = GetTime(), signature } of the last look at its sign-ups

-- The calendar status each sign-up of the event should have: [guid] =
-- status. The organizer's own line too.
local function WantedStatuses(event)
    local wanted, mine = {}, nil
    for _, signUp in ipairs(Events.SignUps(event)) do
        wanted[signUp.guid] = States.CalendarStatusOf(signUp)
        if signUp.guid == ns.playerGUID then
            mine = signUp
        end
    end
    if event.owner == ns.playerGUID then
        wanted[ns.playerGUID] = States.OrganizerCalendarStatus(mine)
    end
    return wanted
end

-- The organizer's own status given in the calendar, into the addon.
local function TakeOwnStatus(key, event, status)
    local state = States.FromCalendar(status)
    local mine = Events.Mine(event)
    if state then
        States.SetMine(key, state, mine and mine.ro or ns.Roles.Default(), mine and mine.no, true)
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
    local statuses = Read.State("statuses")
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

-- The organizer's next event whose sign-ups to look at: one whose
-- statuses changed in the addon since the last look, or, while the game's
-- calendar window is closed, not looked at for a while (a sign-up or a
-- change made in the calendar).
local function EventToMirror(now)
    local best
    local again = not Read.WindowShown()
    for key, event in pairs(Events.All()) do
        local entry = Read.Find(event.ci)
        if entry and event.owner == ns.playerGUID and not event.x and event.tm > Events.Now() then
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

-- Opens the event, takes in what was given in the calendar, and gives each
-- sign-up the addon's status, one at a time.
local function Mirror(item)
    Read.openKey = nil
    Read.busy = true
    mirrored[item.key] = { at = GetTime(), signature = item.signature }
    Read.Open(item.entry, function(ok)
        if not ok then
            Read.Close()
            Read.Finish()
            return
        end
        Organizer.ReconcileOpen(item.key)
        local changes = StatusChanges(item.key, Events.Get(item.key) or item.event)
        local step = 0
        local function NextChange()
            step = step + 1
            local change = changes[step]
            local index = change and InviteIndex(change.guid)
            if not change then
                Read.Close()
                Read.Finish()
                return
            end
            if index then
                C_Calendar.EventSetInviteStatus(index, change.status)
                Read.State("statuses")[item.key][change.guid] = change.status
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

-- The event open in the game's calendar window, when it is one of ours:
-- what is changed there comes into the addon at once (the description and
-- the statuses show only on the open event).
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
        if event.owner == ns.playerGUID and event.ci ~= 0 and not event.x and event.tm == start and event.ti == title then
            Organizer.ReconcileOpen(key)
            StatusChanges(key, Events.Get(key) or event)
            return
        end
    end
end

-- Its sign-ups are looked at again (its calendar event is new, or it was
-- deleted from the addon).
function Statuses.Forget(key)
    mirrored[key] = nil
end
