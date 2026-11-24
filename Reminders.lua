-- Reminders.lua: before an event the player signed up to (or is tentative
-- for, and not left out of), a raid warning on the screen, a line in the
-- chat and a sound. Each character chooses how long before (5, 15, 30 or
-- 60 minutes), or none, in the addon's options.
local _, ns = ...
local L = ns.L

local Reminders = {}
ns.Reminders = Reminders

local Events = ns.Events

Reminders.CHOICES = { 0, 5, 15, 30, 60 }  -- minutes before; 0: none
Reminders.DEFAULT = 15
local CHECK = 20  -- seconds between two looks

-- What this character keeps (never shared): reminder = minutes, reminded =
-- { [key] = the start it was reminded of }.
local function State()
    return ns.Data.OwnState()
end

function Reminders.Minutes()
    local minutes = ns.playerGUID and ns.db and State().reminder
    return minutes or Reminders.DEFAULT
end

function Reminders.SetMinutes(minutes)
    State().reminder = minutes
end

local function Show(event, left)
    local text = L["%s starts in %d |4minute:minutes;."]:format(event.ti, math.max(math.ceil(left / 60), 1))
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        ns.Try(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
    end
    ns.Print(text)
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

-- The events the player goes to that start within their minutes, not yet
-- reminded of.
function Reminders.Check()
    if not ns.playerGUID or not ns.db or not ns.Roster.ready then
        return
    end
    local minutes = Reminders.Minutes()
    local state = State()
    state.reminded = state.reminded or {}
    local now = Events.Now()
    for key, start in pairs(state.reminded) do
        if start + Events.DURATION < now then
            state.reminded[key] = nil
        end
    end
    if minutes == 0 then
        return
    end
    for _, event in ipairs(Events.List("upcoming")) do
        local left = event.tm - now
        if not event.x and left > 0 and left <= minutes * 60 and state.reminded[event.key] ~= event.tm then
            if ns.States.IsReminded(ns.States.Of(Events.Mine(event))) then
                state.reminded[event.key] = event.tm
                Show(event, left)
            end
        end
    end
end

function Reminders.Init()
    C_Timer.NewTicker(CHECK, Reminders.Check)
end
