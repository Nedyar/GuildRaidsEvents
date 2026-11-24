-- CalendarMember.lua: the player's own answers to the guild's events in the
-- game's calendar (see Calendar.lua), both ways: an answer given there
-- comes into the addon, and one given in the addon goes there, with no
-- click. The game does not let a sign-up go straight from signed up to
-- tentative or back: it is taken back first, and the new answer goes in once
-- the event is back in the player's calendar (about an hour later).
local _, ns = ...

local Calendar, Read, Member = ns.Calendar, ns.CalendarRead, ns.CalendarMember
local Events, States = ns.Events, ns.States
local Note = Calendar.Note
local Plain = Read.Plain

local IN_FLIGHT = 60         -- seconds an answer sent may take to show in the calendar
local RETRY = 300            -- seconds before the same answer is tried again

local tried = {}             -- [key] = { at = GetTime(), has, wanted } of the last answer sent

-- The answer the calendar should have, and whether the player's sign-up
-- has a status in the addon.
local function WantedAnswer(event)
    local mine = Events.Mine(event)
    local wanted = States.WantedAnswer(mine)
    return wanted, wanted ~= "none" and mine.status ~= Events.NONE
end

-- An answer given in the game's calendar ("signed", "tentative" or
-- "none"), into the addon, as the player's own.
local function TakeAnswer(key, event, has)
    local mine = Events.Mine(event)
    States.SetMine(key, has, mine and mine.ro or Events.LastRole(), mine and mine.no, false)
    Note("from the calendar", "took your answer given there: " .. event.ti)
end

-- The player's answers given in the calendar, into the addon; then the
-- first of their answers the calendar does not have yet: { key, entry (its
-- calendar event), has (the answer it has), wanted }, or nil.
function Member.AnswerToSend(now)
    local answers = Read.State("answers")
    for key, event in pairs(Events.All()) do
        if event.owner ~= ns.playerGUID and event.ci ~= 0 and not event.x and event.tm > Events.Now() then
            local entry = Read.Find(event.ci)
            local listed = not entry and Read.GuildEntry(event.ci)
            local status = entry and Plain(entry.ev.inviteStatus) or listed and Plain(listed.inviteStatus)
            if status ~= nil then
                local has = States.CalendarAnswer(status)
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
                local locked = event.lk or (entry and Read.IsLocked(entry.ev))
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
                        return { key = key, entry = entry, has = has, wanted = wanted }
                    end
                end
            end
        end
    end
end

-- A step of the look at the calendar (Tick): sends that answer, opening its
-- event (no click needed).
function Member.SendAnswer(answer)
    Read.openKey = nil
    Read.busy = true
    tried[answer.key] = { at = GetTime(), has = answer.has, wanted = answer.wanted }
    Read.Open(answer.entry, function(ok)
        if not ok then
            Read.Close()
            Read.Finish()
            return
        end
        if answer.has ~= "none" then
            -- Taken back first: the new answer goes in once the event is
            -- back in the player's calendar.
            C_Calendar.RemoveEvent()
        elseif answer.wanted == "signed" then
            C_Calendar.EventSignUp()
        else
            C_Calendar.EventTentative()
        end
        Read.WaitDone(function()
            Read.Close()
            Read.Finish()
        end)
    end)
end

-- An event deleted from the addon (Organizer.Forget).
function Member.Forget(key)
    tried[key] = nil
end
