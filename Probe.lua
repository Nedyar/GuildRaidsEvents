-- Probe.lua: /gevents probe, an automatic test of what WoW Forever lets an
-- addon do with the guild calendar. It has one button, Start, and works in
-- three turns, with two characters of the same player in the guild:
--
--   1. The organizer presses Start: it creates a test event for tomorrow at
--      21:00, inside the click (the game needs one for that).
--   2. The other character presses Start: it opens the test event and signs
--      up, from timers, out of any click.
--   3. The organizer presses Start again: it opens the event, gives the
--      other character the statuses Confirmed, Standby and Out, and deletes
--      the event, all from timers, out of any click.
--
-- It finds the turn by itself from the calendar, and after each turn it says
-- in plain words what to do next. A few seconds after each step it reads
-- the calendar again and says whether the step worked, and what the game
-- said meanwhile (its calendar events, an addon action blocked).
--
-- It acts only on its own events ("GRE test ..." and the older "GRE probe
-- ..."), never on the guild's real ones, and it refuses to start while the
-- game's calendar window is shown, since both share the one open event.
--
-- It is meant for the addon's author, so it is in English and not
-- translated.
local _, ns = ...
local Plain = ns.Plain

local Probe = {}
ns.Probe = Probe

local DELAY = 1        -- seconds between a step's result and the next step
local SETTLE = 3       -- seconds after a step before its result is read
local WAIT_MORE = 10   -- seconds a step may wait for its result to show
local DAYS_AHEAD = 35  -- how far ahead events are looked for
local MAX_OLD = 5      -- old test events deleted in one turn
local TITLE = "GRE test"
local TEST_TITLES = { "GRE test", "GRE probe" }
local MANAGE_STATUSES = { "Confirmed", "Standby", "Out" }

local GAME_EVENTS = {
    "CALENDAR_ACTION_PENDING", "CALENDAR_CLOSE_EVENT", "CALENDAR_NEW_EVENT", "CALENDAR_OPEN_EVENT",
    "CALENDAR_UPDATE_ERROR", "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_UPDATE_ERROR_WITH_PLAYER_NAME",
    "CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_GUILD_EVENTS",
    "CALENDAR_UPDATE_INVITE_LIST", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}
-- Too frequent to be worth a line.
local QUIET = { CALENDAR_ACTION_PENDING = true }

local lines = {}       -- what the window shows
local said             -- what the game says during the current step, or nil
local blocked          -- whether the game blocked an action during it
local turn             -- the turn going on: { steps, step, number, title, other, ... }
local window
local listening = false
local gameEvents = CreateFrame("Frame")

-- Text -------------------------------------------------------------------------------------

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A value as text, control bytes as \ddd (an edit box refuses, whole and
-- with no error, a text holding one) and | doubled (not a code).
local function Show(value)
    if IsSecret(value) then
        return "secret"
    end
    local text = tostring(value):gsub("%c", function(c)
        return ("\\%d"):format(c:byte())
    end)
    return (text:gsub("|", "||"))
end

local function StatusName(status)
    if IsSecret(status) then
        return "secret"
    end
    for name, number in pairs(Enum.CalendarStatus) do
        if number == status then
            return name
        end
    end
    return Show(status)
end

local function Update()
    if window and window:IsShown() then
        window.Edit:SetText(table.concat(lines, "\n"))
    end
end

local function Write(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    lines[#lines + 1] = text
    Update()
end

local function PlayerName()
    local name, surname = UnitName("player")
    return surname and surname ~= "" and name .. " " .. surname or name
end

-- The calendar -----------------------------------------------------------------------------

local function CalendarShown()
    return CalendarFrame ~= nil and CalendarFrame:IsShown() == true
end

local function Title(ev)
    local title = ev and Plain(ev.title)
    return type(title) == "string" and title or nil
end

local function IsTestTitle(title)
    for _, prefix in ipairs(TEST_TITLES) do
        if title and title:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function SameName(a, b)
    a, b = Plain(a), Plain(b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    return a:gsub("%-.*$", ""):lower() == b:gsub("%-.*$", ""):lower()
end

-- Days since 1970 of a date, at noon (so no clock change moves it).
local function DayNumber(year, month, day)
    return math.floor(time({ year = year, month = month, day = day, hour = 12 }) / 86400)
end

-- The events in the player's calendar from today to DAYS_AHEAD days ahead,
-- each with its place: { offset, day, index, title, mine, status }. mine:
-- the player made it. The month offsets count from the current month,
-- which Command sets.
local function DayEvents()
    local found = {}
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local today = DayNumber(now.year, now.month, now.monthDay)
    for offset = 0, 2 do
        local ok, month = pcall(C_Calendar.GetMonthInfo, offset)
        if ok and type(month) == "table" and not IsSecret(month) then
            for day = 1, month.numDays do
                local distance = DayNumber(month.year, month.month, day) - today
                if distance >= 0 and distance <= DAYS_AHEAD then
                    local okCount, count = pcall(C_Calendar.GetNumDayEvents, offset, day)
                    for index = 1, okCount and Plain(count) or 0 do
                        local okEvent, ev = pcall(C_Calendar.GetDayEvent, offset, day, index)
                        local title = okEvent and Title(ev)
                        if title then
                            found[#found + 1] = {
                                offset = offset, day = day, index = index, title = title,
                                mine = Plain(ev.modStatus) == "CREATOR" or SameName(ev.invitedBy, PlayerName()),
                                status = Plain(ev.inviteStatus),
                            }
                        end
                    end
                end
            end
        end
    end
    return found
end

local function FindDayEvent(title)
    for _, entry in ipairs(DayEvents()) do
        if entry.title == title then
            return entry
        end
    end
end

-- The test events in the calendar: the first made by the player, and the
-- first made by someone else.
local function TestEvents()
    local mine, others
    for _, entry in ipairs(DayEvents()) do
        if IsTestTitle(entry.title) then
            if entry.mine then
                mine = mine or entry
            else
                others = others or entry
            end
        end
    end
    return mine, others
end

local function InGuildList(title)
    local ok, count = pcall(C_Calendar.GetNumGuildEvents)
    for i = 1, ok and Plain(count) or 0 do
        local okInfo, info = pcall(C_Calendar.GetGuildEventInfo, i)
        if okInfo and Title(info) == title then
            return true
        end
    end
    return false
end

local function OpenInfo()
    if Plain(C_Calendar.IsEventOpen()) ~= true then
        return nil
    end
    local ok, info = pcall(C_Calendar.GetEventInfo)
    return ok and type(info) == "table" and not IsSecret(info) and info or nil
end

local function OpenTitle()
    return Title(OpenInfo())
end

-- The open event's sign-ups: { index, name, status, mine }.
local function Invites()
    local list = {}
    if Plain(C_Calendar.IsEventOpen()) ~= true then
        return list
    end
    local ok, count = pcall(C_Calendar.GetNumInvites)
    for index = 1, ok and Plain(count) or 0 do
        local okInvite, info = pcall(C_Calendar.EventGetInvite, index)
        if okInvite and type(info) == "table" and not IsSecret(info) then
            list[#list + 1] = { index = index, name = Plain(info.name), status = Plain(info.inviteStatus),
                mine = Plain(info.inviteIsMine) == true or SameName(info.name, PlayerName()) }
        end
    end
    return list
end

local function FindInvite(name)
    for _, invite in ipairs(Invites()) do
        if SameName(invite.name, name) then
            return invite
        end
    end
end

-- Selects the event on its day (as a right click on it does) and deletes it.
-- turn.canRemove: what the game said beforehand, as Blizzard's day menu asks
-- it before offering Delete.
local function DeleteOnDay(entry)
    local ok, canRemove = pcall(C_Calendar.ContextMenuEventCanRemove, entry.offset, entry.day, entry.index)
    turn.canRemove = "the game said it can be deleted: " .. (ok and Show(canRemove) or "unknown")
    C_Calendar.ContextMenuSelectEvent(entry.offset, entry.day, entry.index)
    return C_Calendar.ContextMenuEventRemove()
end

local function Tomorrow()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local t = date("*t", time({ year = now.year, month = now.month, day = now.monthDay + 1, hour = 12 }))
    return t.year, t.month, t.day
end

-- The steps --------------------------------------------------------------------------------
-- text: what it does. run: does it (an error is shown). check: whether it
-- worked, true or nil (nil while it may still show up), and a detail.
-- skip: a reason not to run it.

local CREATE = {
    text = function() return "Create a test event for tomorrow at 21:00 (in the click)" end,
    run = function()
        local year, month, day = Tomorrow()
        C_Calendar.CreateGuildSignUpEvent()
        C_Calendar.EventSetTitle(turn.title)
        C_Calendar.EventSetType(Enum.CalendarEventType.Other)
        C_Calendar.EventSetDate(month, day, year)
        C_Calendar.EventSetTime(21, 0)
        C_Calendar.EventSetDescription("Guild Raids & Events test. It deletes itself.")
        return C_Calendar.AddEvent()
    end,
    check = function()
        if FindDayEvent(turn.title) then
            return true
        end
        return nil, "it is not in the calendar"
    end,
    -- The draft would stay open otherwise.
    failed = function()
        C_Calendar.CloseEvent()
    end,
}

local OPEN = {
    text = function() return "Open the test event" end,
    skip = function()
        return not FindDayEvent(turn.title) and "the test event is not in the calendar"
    end,
    run = function()
        local entry = FindDayEvent(turn.title)
        return C_Calendar.OpenEvent(entry.offset, entry.day, entry.index)
    end,
    check = function()
        if OpenTitle() == turn.title then
            return true
        end
        return nil, "it is not open"
    end,
}

local SIGN_UP = {
    text = function() return "Sign up" end,
    skip = function()
        local info = OpenInfo()
        if not info or Title(info) ~= turn.title then
            return "the test event is not open"
        elseif Plain(info.inviteStatus) ~= Enum.CalendarStatus.NotSignedup then
            return "already answered: " .. StatusName(Plain(info.inviteStatus))
        end
    end,
    run = function()
        return C_Calendar.EventSignUp()
    end,
    check = function()
        local info = OpenInfo()
        local status = info and Plain(info.inviteStatus)
        if status == Enum.CalendarStatus.Signedup then
            return true
        end
        return nil, "your answer: " .. StatusName(status)
    end,
}

-- The other character found among the sign-ups, once the event is open.
local FIND_OTHER = {
    text = function() return "Find your other character among the sign-ups" end,
    skip = function()
        return OpenTitle() ~= turn.title and "the test event is not open"
    end,
    run = function()
        for _, invite in ipairs(Invites()) do
            if not invite.mine and invite.name then
                turn.other = invite.name
                return
            end
        end
    end,
    check = function()
        local invite = turn.other and FindInvite(turn.other)
        if invite then
            return true, ("%s, %s"):format(Show(turn.other), StatusName(invite.status))
        end
        turn.nobody = true
        return false, "nobody else has signed up"
    end,
}

local function StatusStep(statusName)
    return {
        text = function() return ("Give %s the status %s"):format(Show(turn.other or "them"), statusName) end,
        skip = function()
            return not (turn.other and FindInvite(turn.other)) and "your other character has not signed up"
        end,
        run = function()
            return C_Calendar.EventSetInviteStatus(FindInvite(turn.other).index, Enum.CalendarStatus[statusName])
        end,
        check = function()
            local invite = FindInvite(turn.other)
            local status = invite and invite.status
            if status == Enum.CalendarStatus[statusName] then
                return true
            end
            return nil, "their status: " .. StatusName(status)
        end,
    }
end

-- Deleting it right after closing it gave CALENDAR_ERROR_PERMISSIONS (build
-- 71037), so it is closed first, in a step of its own.
local CLOSE = {
    text = function() return "Close the test event" end,
    skip = function()
        if turn.nobody then
            return "it is kept until your other character signs up"
        end
        return OpenTitle() ~= turn.title and "it is not open"
    end,
    run = function()
        return C_Calendar.CloseEvent()
    end,
    check = function()
        if OpenTitle() ~= turn.title then
            return true
        end
        return nil, "it is still open"
    end,
}

local DELETE = {
    text = function() return "Delete the test event" end,
    skip = function()
        if turn.nobody then
            return "it is kept until your other character signs up"
        end
        return not FindDayEvent(turn.title) and "the test event is not in the calendar"
    end,
    run = function()
        return DeleteOnDay(FindDayEvent(turn.title))
    end,
    check = function()
        if not FindDayEvent(turn.title) and not InGuildList(turn.title) then
            return true, turn.canRemove
        end
        return nil, ("it is still in the calendar; %s"):format(turn.canRemove)
    end,
}

-- The player's other test events (earlier runs), one step each.
local function OldEvent()
    for _, entry in ipairs(DayEvents()) do
        if entry.mine and IsTestTitle(entry.title) and entry.title ~= turn.title and not turn.tried[entry.title] then
            return entry
        end
    end
end

local DELETE_OLD = {
    text = function() return ("Delete the old test event \"%s\""):format(Show(turn.old.title)) end,
    run = function()
        return DeleteOnDay(turn.old)
    end,
    check = function()
        if not FindDayEvent(turn.old.title) and not InGuildList(turn.old.title) then
            return true, turn.canRemove
        end
        return nil, ("it is still in the calendar; %s"):format(turn.canRemove)
    end,
}

-- The "Delete test events" button: the player's first test event, inside
-- the click, as the addon would delete one when its organizer asks.
local DELETE_IN_CLICK = {
    text = function() return ("Delete your test event \"%s\" (in the click)"):format(Show(turn.title)) end,
    run = function()
        return DeleteOnDay(FindDayEvent(turn.title))
    end,
    check = DELETE.check,
}

-- The three turns: their steps and what to do next.
local TURNS = {
    delete = {
        name = "deleting a test event",
        steps = { DELETE_IN_CLICK },
    },
    create = {
        name = "turn 1 of 3, the organizer creates the test event",
        steps = { CREATE },
        next = "Next: log in with your other character in the guild, type /gevents probe and press Start.",
    },
    signUp = {
        name = "turn 2 of 3, your other character signs up",
        steps = { OPEN, SIGN_UP },
        next = "Next: log back in with the organizer, type /gevents probe and press Start.",
    },
    manage = {
        name = "turn 3 of 3, the organizer gives statuses and deletes the test event",
        steps = { OPEN, FIND_OTHER, StatusStep(MANAGE_STATUSES[1]), StatusStep(MANAGE_STATUSES[2]),
            StatusStep(MANAGE_STATUSES[3]), CLOSE, DELETE },
        deleteOld = true,
        next = "The test is over.",
    },
}

-- Running them -----------------------------------------------------------------------------

local RunStep

local function Finish()
    Write("")
    if turn.kind == TURNS.create and not FindDayEvent(turn.title) then
        Write("The test event could not be created, so the test stops here.")
    elseif turn.kind == TURNS.delete then
        Write(FindDayEvent(turn.title) and "It is still in the calendar." or "It is deleted.")
    elseif turn.nobody then
        Write("Your other character has not signed up yet. Log in with it, type /gevents probe and press Start.")
    else
        Write(turn.kind.next)
        if turn.kind == TURNS.manage and FindDayEvent(turn.title) then
            Write("The test event is still in the calendar: delete it by hand (right click on it, Delete).")
        end
    end
    Write("Copy this text (click it, Ctrl+A, Ctrl+C) and paste it.")
    turn = nil
    window.Start:Enable()
    window.Delete:Enable()
end

local function Next()
    turn.step = turn.step + 1
    C_Timer.After(DELAY, RunStep)
end

local function Report(step, worked, detail, err)
    local verdict
    if err then
        verdict = "ERROR: " .. Show(tostring(err):gsub("^.-:%d+: ", ""):sub(1, 100))
    elseif blocked then
        verdict = "BLOCKED by the game"
    elseif worked then
        verdict = "works"
    elseif worked == false then
        verdict = "no"
    else
        verdict = "did nothing"
    end
    Write("%d. %s: %s", turn.number, step.text(), verdict)
    local notes = {}
    if detail then
        notes[#notes + 1] = detail
    end
    if #said > 0 then
        notes[#notes + 1] = "the game said " .. table.concat(said, ", ")
    end
    if #notes > 0 then
        Write("     (%s)", table.concat(notes, "; "))
    end
    said, blocked = nil, false
    if not worked and step.failed then
        step.failed()
    end
end

-- Reads the step's result SETTLE seconds after its call, or up to
-- WAIT_MORE seconds while it may still show up.
local function Await(step)
    local waited = SETTLE
    local function Check()
        local worked, detail = step.check()
        if worked == nil and waited < WAIT_MORE and not blocked then
            waited = waited + 1
            C_Timer.After(1, Check)
            return
        end
        Report(step, worked, detail)
        Next()
    end
    C_Timer.After(SETTLE, Check)
end

-- Runs the step's call and reads its result.
local function Do(step)
    said, blocked = {}, false
    local ok, err = pcall(step.run)
    if not ok then
        Report(step, false, nil, err)
        Next()
        return
    end
    Await(step)
end

function RunStep()
    local step = turn.steps[turn.step]
    if not step then
        -- Then the player's old test events, when the turn deletes them.
        turn.old = turn.kind.deleteOld and not turn.nobody and turn.oldCount < MAX_OLD and OldEvent()
        if not turn.old then
            Finish()
            return
        end
        turn.tried[turn.old.title] = true
        turn.oldCount = turn.oldCount + 1
        step = DELETE_OLD
    end
    turn.number = turn.number + 1
    if CalendarShown() then
        Write("%d. %s: not done, the game's calendar was opened. Close it and press Start again.", turn.number, step.text())
        Finish()
        return
    end
    local reason = step.skip and step.skip()
    if reason then
        Write("%d. %s: skipped, %s.", turn.number, step.text(), reason)
        Next()
        return
    end
    Do(step)
end

local function Header()
    local version, build = GetBuildInfo()
    Write("Guild Raids & Events calendar test, %s, client %s (%s)", date("%Y-%m-%d %H:%M"), Show(version), Show(build))
    Write("%s, guild %s: %s", Show(PlayerName()), Show(GetGuildInfo("player")), turn.kind.name)
    Write("")
end

local function NewTurn(kind, title)
    turn = { kind = kind, steps = kind.steps, step = 1, number = 0, oldCount = 0, tried = {}, title = title }
end

local function Begin()
    wipe(lines)
    Header()
    window.Start:Disable()
    window.Delete:Disable()
end

-- The turn's first step, first thing in the click: an action blocked
-- inside a click once the handler had done other work with the window
-- first (build 71037).
local function FirstInClick(kind, title)
    NewTurn(kind, title)
    turn.number = 1
    local step = kind.steps[1]
    said, blocked = {}, false
    local ok, err = pcall(step.run)
    Begin()
    if not ok then
        Report(step, false, nil, err)
        Next()
        return
    end
    Await(step)
end

local function Refused()
    if turn then
        return true
    end
    if CalendarShown() then
        wipe(lines)
        Write("Close the game's calendar first, then press the button again.")
        return true
    end
end

local function Start()
    if Refused() then
        return
    end
    local mine, others = TestEvents()
    if not mine and not others then
        FirstInClick(TURNS.create, ("%s %s"):format(TITLE, date("%H:%M:%S")))
        return
    end
    NewTurn(mine and TURNS.manage or TURNS.signUp, (mine or others).title)
    Begin()
    C_Timer.After(DELAY, RunStep)
end

local function DeleteTestEvent()
    if Refused() then
        return
    end
    local mine = TestEvents()
    if not mine then
        wipe(lines)
        Write("You have no test events in the calendar.")
        return
    end
    FirstInClick(TURNS.delete, mine.title)
end

-- What the game says -----------------------------------------------------------------------

gameEvents:SetScript("OnEvent", function(_, event, ...)
    if not said then
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        blocked = true
        said[#said + 1] = ("%s (%s, %s)"):format(event, Show((...)), Show(select(2, ...)))
        return
    end
    if not QUIET[event] then
        local text = event:gsub("^CALENDAR_", "")
        if event:find("ERROR") and select("#", ...) > 0 then
            text = ("%s %s"):format(text, Show((...)))
        end
        if said[#said] ~= text then
            said[#said + 1] = text
        end
    end
end)

-- The window -------------------------------------------------------------------------------

local function CreateWindow()
    window = CreateFrame("Frame", "GuildRaidsEventsProbe", UIParent, "PortraitFrameTemplate")
    window:SetSize(620, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Head_Dragon_01")
    window:SetTitle("Guild Raids & Events - calendar test")
    tinsert(UISpecialFrames, window:GetName())
    -- An addon window's close button does nothing in combat on WoW Forever
    -- (HideUIPanel), so it hides itself.
    window.onCloseCallback = function()
        window:Hide()
        return false
    end

    window.Start = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.Start:SetSize(120, 22)
    window.Start:SetPoint("TOPLEFT", 70, -32)
    window.Start:SetText("Start")
    window.Start:SetScript("OnClick", Start)
    window.Delete = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.Delete:SetSize(160, 22)
    window.Delete:SetPoint("LEFT", window.Start, "RIGHT", 8, 0)
    window.Delete:SetText("Delete test events")
    window.Delete:SetScript("OnClick", DeleteTestEvent)
    local hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("LEFT", window.Delete, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", -20, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Then wait: the text below says what to do next.")

    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -66)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetWidth(560)
    pcall(edit.SetMaxLetters, edit, 0)
    pcall(edit.SetMaxBytes, edit, 0)
    edit:SetScript("OnEscapePressed", function()
        window:Hide()
    end)
    scroll:SetScrollChild(edit)
    window.Edit = edit
end

function Probe.Command()
    if not window then
        CreateWindow()
    end
    if not listening then
        listening = true
        for _, event in ipairs(GAME_EVENTS) do
            pcall(gameEvents.RegisterEvent, gameEvents, event)
        end
    end
    -- The month offsets count from the current month, as the game's
    -- calendar sets it when it opens; not while it is shown.
    if not CalendarShown() then
        local now = C_DateAndTime.GetCurrentCalendarTime()
        C_Calendar.SetAbsMonth(now.month, now.year)
    end
    C_Calendar.OpenCalendar()
    if #lines == 0 then
        Write("Press Start. With no test event in the calendar, it creates one (the organizer's turn).")
    end
    window:Show()
    Update()
end
