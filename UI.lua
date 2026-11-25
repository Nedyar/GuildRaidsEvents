-- UI.lua: what the addon's screens share: the names and icons of event
-- types, roles, answers and statuses (in the game's words when it has
-- them), dates, buttons, the notification mark, and which events the
-- player has not seen yet.
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local Events = ns.Events

-- The game's calendar icons of each event type.
UI.TYPE_ICONS = {
    [0] = "Interface\\LFGFrame\\LFGIcon-Raid",
    [1] = "Interface\\LFGFrame\\LFGIcon-Dungeon",
    [2] = "Interface\\Calendar\\UI-Calendar-Event-PVP",
    [3] = "Interface\\Calendar\\MeetingIcon",
    [4] = "Interface\\Calendar\\UI-Calendar-Event-Other",
}

function UI.TypeName(eventType)
    local names = {
        [0] = CALENDAR_TYPE_RAID or L["Raid"], [1] = CALENDAR_TYPE_DUNGEON or L["Dungeon"],
        [2] = CALENDAR_TYPE_PVP or L["PvP"], [3] = CALENDAR_TYPE_MEETING or L["Meeting"],
        [4] = CALENDAR_TYPE_OTHER or L["Other"],
    }
    return names[eventType] or names[4]
end

-- Where an event of each type takes place (Events ii): one of WoW
-- Forever's raids, dungeons or battlegrounds as its Group Finder lists them
-- (C_LFGList activities of the categories Raids 114, Dungeons 2 and PvP
-- 118), by activity ID, with the game's names in its language. The game's
-- calendar gives no list on WoW Forever (EventGetTextures came back empty,
-- and so did the Encounter Journal, build 71037). Activities that share a
-- name (a battleground's level brackets) are one; PvP also has world PvP
-- (UI.WORLD_PVP, no activity).
UI.WORLD_PVP = 999999
UI.CATEGORIES = { [0] = 114, [1] = 2, [2] = 118 }
local MAX_ACTIVITY = 4000  -- activity IDs looked at (WoW Forever's go up to about 2000)
local places               -- [event type] = { { id, name, level }... }, read once

local function ActivityName(info)
    local short, full = ns.Plain(info.shortName), ns.Plain(info.fullName)
    if type(short) == "string" and short ~= "" then
        return short
    end
    return type(full) == "string" and full ~= "" and full or nil
end

local function ReadPlaces()
    places = { [0] = {}, [1] = {}, [2] = {} }
    local byCategory, seen = {}, {}
    for eventType, category in pairs(UI.CATEGORIES) do
        byCategory[category] = eventType
        seen[eventType] = {}
    end
    for id = 1, C_LFGList and C_LFGList.GetActivityInfoTable and MAX_ACTIVITY or 0 do
        local info = ns.Try(C_LFGList.GetActivityInfoTable, id)
        local eventType = ns.CanRead(info) and byCategory[ns.Plain(info.categoryID)]
        local name = eventType and ActivityName(info)
        if name and not seen[eventType][name] then
            seen[eventType][name] = true
            local level = ns.Plain(info.minLevelSuggestion) or ns.Plain(info.minLevel) or 0
            table.insert(places[eventType], { id = id, name = name, level = type(level) == "number" and level or 0 })
        end
    end
    for eventType, list in pairs(places) do
        table.sort(list, function(a, b)
            if eventType ~= Events.PVP and a.level ~= b.level then
                return a.level < b.level
            end
            return a.name < b.name
        end)
    end
    table.insert(places[Events.PVP], 1, { id = UI.WORLD_PVP, name = L["World PvP"], level = 0 })
end

-- The places an event type offers, { id, name, level }, the lowest level
-- first (an empty list for meetings and others).
function UI.PlacesFor(eventType)
    if not places then
        ReadPlaces()
    end
    return places[eventType] or {}
end

-- Forgets the list, for the tests.
function UI.ForgetPlaces()
    places = nil
end

-- A place's name, or nil for none.
function UI.PlaceName(id)
    if not id or id == 0 then
        return nil
    elseif id == UI.WORLD_PVP then
        return L["World PvP"]
    end
    local info = C_LFGList and ns.Try(C_LFGList.GetActivityInfoTable, id)
    local name = ns.CanRead(info) and ActivityName(info)
    return name or tostring(id)
end

-- Text as a search compares it: in lower case, without the accents of
-- Latin letters.
local ACCENTS = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
    ["ë"] = "e", ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ó"] = "o", ["ò"] = "o", ["ô"] = "o",
    ["ö"] = "o", ["õ"] = "o", ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ñ"] = "n", ["ç"] = "c",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n", ["Ü"] = "u", ["ß"] = "ss",
}
function UI.SearchText(text)
    return (tostring(text):gsub("[\195][\128-\191]", ACCENTS):lower())
end

-- The places of a type whose name has the text searched (all of them for
-- an empty text).
function UI.FindPlaces(eventType, text)
    local wanted = UI.SearchText(strtrim(text or ""))
    local found = {}
    for _, place in ipairs(UI.PlacesFor(eventType)) do
        if wanted == "" or UI.SearchText(place.name):find(wanted, 1, true) then
            found[#found + 1] = place
        end
    end
    return found
end

-- An event's type, with its place: "Raid: Molten Core".
function UI.KindText(event)
    local place = UI.PlaceName(event.ii)
    if place then
        return ("%s: %s"):format(UI.TypeName(event.ty), place)
    end
    return UI.TypeName(event.ty)
end

function UI.RoleName(role)
    if role == Events.TANK then
        return TANK or L["Tank"]
    elseif role == Events.HEALER then
        return HEALER or L["Healer"]
    end
    return DAMAGER or L["Damage"]
end

-- The plural, for the columns of an event's sign-ups.
function UI.RolesName(role)
    if role == Events.TANK then
        return L["Tanks"]
    elseif role == Events.HEALER then
        return L["Healers"]
    end
    return L["Damage"]
end

function UI.AnswerName(answer)
    if answer == Events.SIGNED then
        return CALENDAR_STATUS_SIGNEDUP or L["Signed up"]
    elseif answer == Events.TENTATIVE then
        return CALENDAR_STATUS_TENTATIVE or L["Tentative"]
    end
    return L["Not coming"]
end

function UI.StatusName(status)
    if status == Events.CONFIRMED then
        return CALENDAR_STATUS_CONFIRMED or L["Confirmed"]
    elseif status == Events.STANDBY then
        return CALENDAR_STATUS_STANDBY or L["Standby"]
    elseif status == Events.OUT then
        return CALENDAR_STATUS_OUT or L["Out"]
    elseif status == Events.PROVISIONAL then
        return CALENDAR_STATUS_TENTATIVE or L["Tentative"]
    end
    return L["No status"]
end

-- A state's name (States.lua), as the game's calendar names it.
function UI.StateName(state)
    if state == "none" then
        return CALENDAR_STATUS_NOT_SIGNEDUP or L["Not signed up"]
    elseif state == "signed" then
        return UI.AnswerName(Events.SIGNED)
    elseif state == "tentative" then
        return UI.AnswerName(Events.TENTATIVE)
    end
    return UI.StatusName(ns.States.StatusOf(state))
end

-- Each state's colour, the game calendar's own (CALENDAR_INVITESTATUS_INFO)
-- when it has one; these where it does not.
local STATE_COLORS = {
    none = { 0.5, 0.5, 0.5 }, signed = { 0.1, 1, 0.1 }, tentative = { 1, 0.5, 0.25 }, confirmed = { 0.1, 1, 0.1 },
    standby = { 1, 0.5, 0.25 }, out = { 1, 0.1, 0.1 },
}

function UI.StateColor(state)
    local info = CALENDAR_INVITESTATUS_INFO and Enum.CalendarStatus
        and CALENDAR_INVITESTATUS_INFO[Enum.CalendarStatus[ns.States.CALENDAR_NAMES[state]]]
    local color = type(info) == "table" and info.color
    if type(color) == "table" and color.r then
        return { color.r, color.g, color.b }
    end
    return STATE_COLORS[state] or STATE_COLORS.signed
end

-- A title as the game's calendar shows a locked event's.
function UI.LockedTitle(title)
    local format = CALENDAR_VIEW_EVENTTITLE_LOCKED
    if type(format) ~= "string" or not format:find("%s", 1, true) then
        format = L["%s (Locked)"]
    end
    return format:format(title)
end

-- An event's title, as the game's calendar shows a locked one.
function UI.EventTitle(event)
    return event.lk and not event.x and UI.LockedTitle(event.ti) or event.ti
end

-- The state of a sign-up (or of none) by its name, in its colour.
function UI.StateText(signUp)
    local state = ns.States.Of(signUp)
    return UI.Colored(UI.StateName(state), UI.StateColor(state))
end

function UI.Colored(text, color)
    return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

function UI.ClassColored(name, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color and color.colorStr then
        return ("|c%s%s|r"):format(color.colorStr, name)
    end
    return name
end

local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
    "November", "December" }

function UI.WeekdayName(weekday)
    return _G["WEEKDAY_" .. WEEKDAYS[weekday]:upper()] or WEEKDAYS[weekday]
end

function UI.MonthName(month)
    return _G["MONTH_" .. MONTHS[month]:upper()] or MONTHS[month]
end

-- "Monday 24 November", from a time of the game's calendar.
function UI.DayText(naive)
    local date = Events.DateOf(naive)
    return L["%s %d %s"]:format(UI.WeekdayName(date.weekday), date.day, UI.MonthName(date.month))
end

-- "21:00".
function UI.HourText(naive)
    local date = Events.DateOf(naive)
    return ("%02d:%02d"):format(date.hour, date.minute)
end

-- "Monday 24 November, 21:00".
function UI.DateText(naive)
    return ("%s, %s"):format(UI.DayText(naive), UI.HourText(naive))
end

-- A button of the addon's window. Those that change the game's calendar
-- (Create, Save, Cancel event, Restore event, Create in calendar) call it
-- first thing in their click, the only time the game takes it.
function UI.Button(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(math.max(button:GetTextWidth() + 28, 80), 22)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", onClick)
    return button
end

function UI.SetTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 1, 1)
        local body = type(text) == "function" and text(self) or text
        if body then
            GameTooltip:AddLine(body, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- Blizzard's notification mark, as its Roster tab shows it for applicants:
-- centred on parent's top right corner (moved by x, y), on a frame of its
-- own, over parent. At the atlas's own size. Hidden at first.
function UI.NewMark(parent, x, y)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(1, 1)
    mark:SetPoint("CENTER", parent, "TOPRIGHT", x or 0, y or 0)
    mark.Icon = mark:CreateTexture(nil, "OVERLAY")
    mark.Icon:SetAtlas("communities-icon-notification", true)
    mark.Icon:SetPoint("CENTER")
    mark:Hide()
    return mark
end

-- Events the player has not seen ----------------------------------------------------------------

-- OwnState().seen = { [key] = true }: events whose row the player saw.
local function Seen()
    local own = ns.Data.OwnState()
    own.seen = own.seen or {}
    return own.seen
end

function UI.MeetsLevel(event)
    return (event.ml or 0) == 0 or (UnitLevel("player") or 0) >= event.ml
end

-- An upcoming event the player may go to, has not answered and has not
-- seen in the list.
function UI.IsUnseen(event)
    if not ns.playerGUID or not ns.db or event.x or not UI.MeetsLevel(event) or Seen()[event.key] then
        return false
    end
    return Events.Mine(event) == nil
end

function UI.MarkSeen(key)
    if ns.playerGUID and ns.db and not Seen()[key] then
        Seen()[key] = true
        return true
    end
    return false
end

-- Forgets the events no longer listed.
function UI.TidySeen()
    if not ns.playerGUID or not ns.db then
        return
    end
    local seen = Seen()
    for key in pairs(seen) do
        if not Events.Get(key) then
            seen[key] = nil
        end
    end
end

-- Cancelled events the player cleared from their list --------------------------------------

-- OwnState().cleared = { [key] = the event's start }: this character's own
-- (never shared, nor seen by the account's other characters), and only in
-- its list (the others and the API still have them). Forgotten once the
-- event is long past.
local function Cleared()
    -- 0.1.0's first builds kept one for the whole account: it hid an
    -- organizer's own event when another of their characters cleared it.
    ns.db.settings.cleared = nil
    local own = ns.Data.OwnState()
    own.cleared = own.cleared or {}
    return own.cleared
end

function UI.IsCleared(event)
    return event.x == true and ns.db ~= nil and ns.playerGUID ~= nil and Cleared()[event.key] ~= nil
end

-- How long a cancelled event stays in the list by itself (until Events.KEEP
-- after it starts), in the game's words: "6 Days", "5 Hours".
function UI.LeavesIn(event)
    local seconds = math.max(event.tm + Events.KEEP - Events.Now(), 60)
    local text = SecondsToTime(seconds, true, true, 1, true)
    if text == "" then
        text = SecondsToTime(seconds, true, true, 2, true)
    end
    return text
end

-- Clears the cancelled ones of events from the player's list: the player's
-- own are deleted, for everyone; the others' leave only this list.
function UI.Clear(events)
    local cleared, now = Cleared(), Events.Now()
    for key, start in pairs(cleared) do
        if start + Events.KEEP + 86400 < now then
            cleared[key] = nil
        end
    end
    for _, event in ipairs(events) do
        if event.x and event.owner == ns.playerGUID then
            ns.Calendar.Delete(event.key)
        elseif event.x then
            cleared[event.key] = event.tm
        end
    end
end

-- How many upcoming events wait for the player: those not seen.
function UI.Waiting()
    local unseen = 0
    for _, event in ipairs(Events.List("upcoming")) do
        if UI.IsUnseen(event) then
            unseen = unseen + 1
        end
    end
    return unseen
end
