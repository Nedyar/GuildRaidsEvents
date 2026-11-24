-- States.lua: a sign-up's one state, as the game's calendar keeps one, and
-- how it stands in the addon's data and in the game's calendar. Every rule
-- that turns one into the other is here, and only here.
--
-- The addon keeps two things of a sign-up (Events.lua): the member's answer
-- (Events SIGNED, TENTATIVE, DECLINED) and the status given by those who
-- manage the event (Events NONE, CONFIRMED, STANDBY, OUT, PROVISIONAL). The
-- game's calendar keeps one status, and so does the addon's window: "none"
-- (not signed up), "signed", "tentative", "confirmed", "standby" or "out".
local _, ns = ...

local States = {}
ns.States = States

local Events = ns.Events

-- Each state as the addon keeps it: the member's answer, and the status
-- the organizer gives it ("signed": none given).
local DATA = {
    none = {},
    signed = { st = Events.SIGNED, status = Events.NONE },
    tentative = { st = Events.TENTATIVE, status = Events.PROVISIONAL },
    confirmed = { st = Events.SIGNED, status = Events.CONFIRMED },
    standby = { st = Events.SIGNED, status = Events.STANDBY },
    out = { st = Events.SIGNED, status = Events.OUT },
}

-- The state each status given stands for.
local OF_STATUS = {
    [Events.CONFIRMED] = "confirmed", [Events.STANDBY] = "standby", [Events.OUT] = "out",
    [Events.PROVISIONAL] = "tentative",
}

-- Each state's name in the game's calendar (Enum.CalendarStatus).
States.CALENDAR_NAMES = {
    none = "NotSignedup", signed = "Signedup", tentative = "Tentative", confirmed = "Confirmed", standby = "Standby",
    out = "Out",
}

-- The answer each state stands for, as a member gives it in the game's
-- calendar: signed up (in any way), tentative, or none.
local ANSWER = {
    none = "none", signed = "signed", tentative = "tentative", confirmed = "signed", standby = "signed", out = "signed",
}

-- The addon's data -------------------------------------------------------------------------------

-- A sign-up's answer and the status given in it, made one, as the game's
-- calendar keeps one: the newer wins where they disagree. Confirmed,
-- standby or out given to someone tentative signs them up; someone made
-- tentative who signs up again is signed up with no status; and so on.
-- answer: { st, at }; status: { st, at } or nil. Returns st, status.
function States.Merge(answer, status)
    if not status or status.st == Events.NONE or answer.st == Events.DECLINED then
        return answer.st, Events.NONE
    end
    local given = status.st
    local tentative = given == Events.PROVISIONAL
    local agree = (answer.st == Events.TENTATIVE) == tentative
    if agree or status.at >= (answer.at or 0) then
        return tentative and answer.st or Events.SIGNED, given
    end
    return answer.st, Events.NONE
end

-- Whether a sign-up (as Events.SignUps gives it) is tentative: by its
-- answer, or made so by the organizer.
function States.IsTentative(signUp)
    return signUp.st == Events.TENTATIVE or (signUp.st == Events.SIGNED and signUp.status == Events.PROVISIONAL)
end

-- Whether it goes: signed up, not left out nor made tentative.
function States.Goes(signUp)
    return signUp.st == Events.SIGNED and signUp.status ~= Events.OUT and signUp.status ~= Events.PROVISIONAL
end

-- A sign-up's one state (nil: none).
function States.Of(signUp)
    if not signUp or signUp.st == Events.DECLINED then
        return "none"
    elseif States.IsTentative(signUp) then
        return "tentative"
    end
    return OF_STATUS[signUp.status] or "signed"
end

-- The status given that a state stands for (Events.NONE for "signed"), or
-- nil.
function States.StatusOf(state)
    return DATA[state] and DATA[state].status
end

-- Whether a state is signed up in some way (signed up, confirmed, on
-- standby or out), as the calendar counts a member's answer.
function States.IsSignedUp(state)
    return ANSWER[state] == "signed"
end

-- Whether the player is reminded of an event in that state: they go, or
-- may (tentative), and are not left out.
function States.IsReminded(state)
    return state ~= "none" and state ~= "out"
end

-- The player gives themselves a state in an event: their answer (with a
-- role and a note) and, as its organizer, the status of their own sign-up
-- (the game's calendar keeps its creator in the event, with one of its
-- statuses). A member's "none" takes their answer back. Whether it could.
function States.SetMine(key, state, role, note, asOrganizer)
    local data = DATA[state]
    if not data or not Events.Answer(key, data.st, role, note) then
        return false
    end
    if asOrganizer and data.status then
        return Events.SetStatus(key, ns.playerGUID, data.status)
    end
    return true
end

-- The game's calendar ----------------------------------------------------------------------------

local function CalendarStatus(state)
    local name = States.CALENDAR_NAMES[state]
    return name and Enum.CalendarStatus[name]
end

-- The state a status of the game's calendar stands for: "signed",
-- "tentative", "confirmed", "standby" or "out"; nil for any other (not
-- signed up, invited, declined...).
function States.FromCalendar(status)
    for state, name in pairs(States.CALENDAR_NAMES) do
        if state ~= "none" and Enum.CalendarStatus[name] == status then
            return state
        end
    end
end

-- A member's answer as the calendar holds it: "signed" (a status the
-- organizer gave counts as signed up), "tentative" or "none".
function States.CalendarAnswer(status)
    return ANSWER[States.FromCalendar(status) or "none"]
end

-- The answer the calendar should hold of the player's sign-up (from
-- Events.SignUps, or nil), by their answer alone: "signed", "tentative" or
-- "none".
function States.WantedAnswer(signUp)
    if signUp and signUp.st == Events.SIGNED then
        return "signed"
    elseif signUp and signUp.st == Events.TENTATIVE then
        return "tentative"
    end
    return "none"
end

-- The calendar status a member's sign-up should have, or nil when it has
-- none to give (not signed up, or only tentative by their own answer).
function States.CalendarStatusOf(signUp)
    if signUp.st == Events.SIGNED or signUp.status ~= Events.NONE then
        return CalendarStatus(OF_STATUS[signUp.status]) or Enum.CalendarStatus.Signedup
    end
end

-- The calendar status of the organizer's own line: the game offers its
-- creator Confirmed, Standby, Out and Tentative (not Signed up nor
-- Declined), so signed up with no status is Confirmed, and not coming (or
-- no answer) is Out.
function States.OrganizerCalendarStatus(signUp)
    if not signUp or signUp.st == Events.DECLINED then
        return Enum.CalendarStatus.Out
    elseif signUp.st == Events.TENTATIVE then
        return Enum.CalendarStatus.Tentative
    end
    return CalendarStatus(OF_STATUS[signUp.status]) or Enum.CalendarStatus.Confirmed
end
