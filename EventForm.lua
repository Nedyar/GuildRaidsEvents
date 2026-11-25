-- EventForm.lua: the window to create an event, or change one the player
-- may manage: its title, type and place (the raid, dungeon or battleground),
-- day and time, description, places per role,
-- minimum level, whether it repeats every week and whether it confirms by
-- itself. The place is typed to search the game's list, or picked from it
-- under its box; the day is picked in a month's calendar under its button,
-- the time from two lists, hours and minutes (and AM or PM, on a 12-hour
-- clock). Creating or saving it puts it in the game's calendar with the
-- same click (Calendar.lua: the game allows it only inside a click); a
-- change the game does not take then goes with the organizer's next click
-- in the addon's window.
local _, ns = ...
local L = ns.L

local EventForm = {}
ns.EventForm = EventForm

local Events, UI = ns.Events, ns.UI

local DAYS = 365                -- days ahead that can be picked, when the game does not say
local TITLE_LETTERS = 31        -- as the game's calendar allows
local DESCRIPTION_LETTERS = 255
local DEFAULT_HOUR = 21
local CELL = 28                 -- a day's square in the month's calendar
local PLACE_ROW = 18            -- a place's row in the list under its box
local PLACE_ROWS = 8            -- rows the list shows at once

local form
local UpdatePlace
local editing      -- the key of the event changed, or nil for a new one
local chosen = { hour = DEFAULT_HOUR, minute = 0 }  -- { ty, ii (its place), day (days from today), hour, minute }
local waiting      -- a token while a new event of the form's waits for the calendar's answer

-- The form's grid: x from its left edge, y from its top. Labels sit over
-- what they name; an edit box's frame starts a little right of where its
-- border shows, so it is moved by BOX_INSET to line up with the rest.
local LEFT, RIGHT_COLUMN = 24, 296
local BOX_INSET = 6

local function Place(widget, x, y)
    widget:SetPoint("TOPLEFT", form, "TOPLEFT", x, y)
    return widget
end

local function Label(text, x, y, template)
    local label = form:CreateFontString(nil, "ARTWORK", template or "GameFontNormalSmall")
    label:SetText(text)
    return Place(label, x, y)
end

local function Box(width, letters, numeric)
    local box = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(letters)
    if numeric then
        box:SetNumeric(true)
    end
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

local function Check(text, y, x)
    local check = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    Place(check, (x or LEFT) - 4, y)
    check.Label = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    check.Label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.Label:SetText(text)
    return check
end

local function Dropdown(width, x, y, generator)
    local dropdown = CreateFrame("DropdownButton", nil, form, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    Place(dropdown, x, y)
    dropdown:SetupMenu(generator)
    return dropdown
end

-- Today in the game's calendar, at midnight (Events.Naive).
local function Today()
    local now = Events.DateOf(Events.Now())
    return Events.Naive(now.year, now.month, now.day, 0, 0)
end

local function ChosenTime()
    return Today() + chosen.day * 86400 + chosen.hour * 3600 + chosen.minute * 60
end

-- The day's calendar ------------------------------------------------------------------------
-- A month's days in weeks, as the game's calendar starts them
-- (CALENDAR_FIRST_WEEKDAY: 1 Sunday, 2 Monday). Days before today, or more
-- after the last day the game's calendar takes new events on
-- (C_Calendar.GetMaxCreateDate), cannot be picked (but the day an event has).

local picker      -- the calendar, under the day's button
local shownMonth  -- { year, month } it shows

-- How many days, from today, can be picked.
local function Days()
    local last = ns.Try(C_Calendar.GetMaxCreateDate)
    if ns.CanRead(last) and type(last.year) == "number" then
        local days = math.floor((Events.Naive(last.year, last.month, last.monthDay, 0, 0) - Today()) / 86400) + 1
        if days > 0 then
            return days
        end
    end
    return DAYS
end

local function FirstWeekday()
    return CALENDAR_FIRST_WEEKDAY or 1
end

-- A weekday's name cut to two letters, or one ideograph.
function EventForm.ShortName(name)
    local letters = {}
    for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        letters[#letters + 1] = char
        if #char >= 3 or #letters == 2 then
            break
        end
    end
    return table.concat(letters)
end

local function DaysIn(year, month)
    local nextYear, nextMonth = month == 12 and year + 1 or year, month % 12 + 1
    return (Events.Naive(nextYear, nextMonth, 1, 0, 0) - Events.Naive(year, month, 1, 0, 0)) / 86400
end

local function UpdateDayButton()
    form.DayButton:SetText(UI.DayText(Today() + chosen.day * 86400))
end

local function RefreshPicker()
    local year, month = shownMonth.year, shownMonth.month
    picker.Month:SetText(L["%s %d"]:format(UI.MonthName(month), year))
    local first = Events.Naive(year, month, 1, 0, 0)
    local lead = (Events.DateOf(first).weekday - FirstWeekday()) % 7
    local today, count, days = Today(), DaysIn(year, month), Days()
    for index, button in ipairs(picker.Days) do
        local day = index - lead
        if day >= 1 and day <= count then
            local offset = (first + (day - 1) * 86400 - today) / 86400
            local allowed = (offset >= 0 and offset < days) or offset == chosen.day
            button.offset = offset
            button.Text:SetText(tostring(day))
            button:SetEnabled(allowed)
            local shade = allowed and 1 or 0.4
            button.Text:SetTextColor(shade, shade, shade)
            button.Selected:SetShown(offset == chosen.day)
            button.Today:SetShown(offset == 0)
            button:Show()
        else
            button:Hide()
        end
    end
    local now, last = Events.DateOf(today), Events.DateOf(today + (days - 1) * 86400)
    local shown = year * 12 + month
    picker.Previous:SetEnabled(shown > now.year * 12 + now.month)
    picker.Next:SetEnabled(shown < last.year * 12 + last.month)
end

local function MoveMonth(step)
    local index = shownMonth.year * 12 + shownMonth.month - 1 + step
    shownMonth = { year = math.floor(index / 12), month = index % 12 + 1 }
    RefreshPicker()
end

local function TogglePicker()
    if picker:IsShown() then
        picker:Hide()
        return
    end
    local date = Events.DateOf(Today() + chosen.day * 86400)
    shownMonth = { year = date.year, month = date.month }
    RefreshPicker()
    picker:Show()
end

local function PickDay(button)
    chosen.day = button.offset
    UpdateDayButton()
    picker:Hide()
end

local function CreatePicker()
    picker = CreateFrame("Frame", nil, form, "TooltipBackdropTemplate")
    picker:SetSize(CELL * 7 + 16, CELL * 6 + 58)
    picker:SetPoint("TOPLEFT", form.DayButton, "BOTTOMLEFT", 0, -2)
    -- Over everything in the form, and not see-through.
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:EnableMouse(true)
    local background = picker:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0.06, 0.06, 0.08, 1)
    picker.Previous = UI.Button(picker, "<", function()
        MoveMonth(-1)
    end)
    picker.Previous:SetSize(26, 20)
    picker.Previous:SetPoint("TOPLEFT", 8, -8)
    picker.Next = UI.Button(picker, ">", function()
        MoveMonth(1)
    end)
    picker.Next:SetSize(26, 20)
    picker.Next:SetPoint("TOPRIGHT", -8, -8)
    picker.Month = picker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    picker.Month:SetPoint("TOP", 0, -11)
    for column = 1, 7 do
        local weekday = (column - 2 + FirstWeekday()) % 7 + 1
        local label = picker:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        label:SetPoint("TOP", picker, "TOPLEFT", 8 + (column - 0.5) * CELL, -34)
        label:SetText(EventForm.ShortName(UI.WeekdayName(weekday)))
    end
    picker.Days = {}
    for index = 1, 42 do
        local row, column = math.floor((index - 1) / 7), (index - 1) % 7
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(CELL - 2, CELL - 2)
        button:SetPoint("TOPLEFT", 9 + column * CELL, -48 - row * CELL)
        button.Today = button:CreateTexture(nil, "BACKGROUND")
        button.Today:SetAllPoints()
        button.Today:SetColorTexture(1, 1, 1, 0.12)
        button.Selected = button:CreateTexture(nil, "BORDER")
        button.Selected:SetAllPoints()
        button.Selected:SetColorTexture(1, 0.82, 0, 0.35)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.15)
        button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        button.Text:SetPoint("CENTER")
        button:SetScript("OnClick", PickDay)
        picker.Days[index] = button
    end
    picker:Hide()
end

-- The calendar under the day's button, for the tests.
function EventForm.Picker()
    return picker
end

-- The time: an hour and minutes in steps of five, picked from lists as
-- in the game's calendar, with its clock: 24 hours, or 12 with AM and PM.
local TIME_WIDTH, AMPM_WIDTH = 52, 64
local TWELVE_SHIFT = 60    -- the time moves left, and the day's button shrinks, to fit AM and PM

local function Military()
    return GetCVarBool("timeMgrUseMilitaryTime") == true
end

local function TwoDigits(pattern, value)
    return (pattern or "%02d"):format(value)
end

local function CreateTimeRow()
    form.TimeLabel = Label(L["Time"], RIGHT_COLUMN, -168)
    form.Hour = Dropdown(TIME_WIDTH, RIGHT_COLUMN, -183, function(_, root)
        if Military() then
            for hour = 0, 23 do
                root:CreateRadio(TwoDigits(TIMEMANAGER_24HOUR, hour), function()
                    return chosen.hour == hour
                end, function()
                    chosen.hour = hour
                end)
            end
        else
            for shown = 1, 12 do
                root:CreateRadio(tostring(shown), function()
                    return (chosen.hour + 11) % 12 + 1 == shown
                end, function()
                    chosen.hour = shown % 12 + (chosen.hour >= 12 and 12 or 0)
                end)
            end
        end
    end)
    local colon = form:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    colon:SetPoint("LEFT", form.Hour, "RIGHT", 3, 0)
    colon:SetText(":")
    form.Minute = CreateFrame("DropdownButton", nil, form, "WowStyle1DropdownTemplate")
    form.Minute:SetWidth(TIME_WIDTH)
    form.Minute:SetPoint("LEFT", colon, "RIGHT", 3, 0)
    form.Minute:SetupMenu(function(_, root)
        local minutes = {}
        for minute = 0, 55, 5 do
            minutes[#minutes + 1] = minute
        end
        -- An event's time set elsewhere keeps its own minutes.
        if chosen.minute and chosen.minute % 5 ~= 0 then
            table.insert(minutes, math.floor(chosen.minute / 5) + 2, chosen.minute)
        end
        for _, minute in ipairs(minutes) do
            root:CreateRadio(TwoDigits(TIMEMANAGER_MINUTE, minute), function()
                return chosen.minute == minute
            end, function()
                chosen.minute = minute
            end)
        end
    end)
    form.AMPM = CreateFrame("DropdownButton", nil, form, "WowStyle1DropdownTemplate")
    form.AMPM:SetWidth(AMPM_WIDTH)
    form.AMPM:SetPoint("LEFT", form.Minute, "RIGHT", 4, 0)
    form.AMPM:SetupMenu(function(_, root)
        root:CreateRadio(TIMEMANAGER_AM or "AM", function()
            return chosen.hour < 12
        end, function()
            chosen.hour = chosen.hour % 12
        end)
        root:CreateRadio(TIMEMANAGER_PM or "PM", function()
            return chosen.hour >= 12
        end, function()
            chosen.hour = chosen.hour % 12 + 12
        end)
    end)
end

-- Lays the time out for the game's clock, read each time the form opens.
local function ShowTime()
    local military = Military()
    local x = military and RIGHT_COLUMN or RIGHT_COLUMN - TWELVE_SHIFT
    form.TimeLabel:ClearAllPoints()
    Place(form.TimeLabel, x, -168)
    form.Hour:ClearAllPoints()
    Place(form.Hour, x, -183)
    form.DayButton:SetWidth(military and 240 or 240 - TWELVE_SHIFT)
    form.AMPM:SetShown(not military)
    form.Hour:GenerateMenu()
    form.Minute:GenerateMenu()
    form.AMPM:GenerateMenu()
end

-- What the form has picked, for the tests.
function EventForm.Chosen()
    return chosen
end

local function Number(box, max)
    local value = tonumber(box:GetText() or "") or 0
    return math.max(0, math.min(math.floor(value), max))
end

-- The form's fields as Events.Create takes them, or nil and why not.
local function Collect()
    local title = strtrim(form.TitleBox:GetText() or "")
    if title == "" then
        return nil, L["Give the event a title."]
    end
    local start = ChosenTime()
    if start <= Events.Now() then
        return nil, L["Choose a day and time still to come."]
    end
    local fields = {
        ty = chosen.ty, ti = title, tm = start, de = strtrim(form.Description.EditBox:GetText() or ""),
        ml = Number(form.MinLevel, ns.Pack.LIMITS.level), wk = form.Weekly:GetChecked() == true or nil,
        ii = #UI.PlacesFor(chosen.ty) > 0 and chosen.ii or nil,
        ac = form.Auto:GetChecked() == true or nil,
        lk = form.Lock:GetChecked() == true or nil,
    }
    if form.Limit:GetChecked() then
        local max = ns.Pack.LIMITS.slots
        fields.sl = { t = Number(form.Tanks, max), h = Number(form.Healers, max), d = Number(form.Damage, max) }
    end
    if not ns.Data.CleanFields({ ty = fields.ty, ti = fields.ti, tm = fields.tm, de = fields.de ~= "" and fields.de or nil,
            sl = fields.sl, ml = fields.ml, ii = fields.ii, at = ns.Now() }) then
        return nil, L["Some text has characters the game does not allow."]
    end
    return fields
end

-- Create or Save: off, with why, while the game's calendar would not take
-- it: a new event while it is not ready, busy with the last one, or at its
-- limit of events created; a change while its event is not open yet, or
-- when the game does not let the player change it.
local function UpdateSave()
    if not form then
        return
    end
    local reason
    if editing and not Events.Get(editing) then
        -- Deleted meanwhile (by a moderator, or in the game's calendar
        -- window): nothing left to change.
        if form:IsShown() then
            form:Hide()
        end
        return
    elseif editing then
        reason = ns.Calendar.EditBlocked(editing)
    elseif ns.Calendar.Creating() or not ns.Rights.MayCreate() then
        reason = L["Syncing the calendar..."]
    elseif ns.Calendar.AtLimit() then
        reason = ns.Calendar.LimitText()
    end
    form.Save:SetEnabled(reason == nil)
    form.Save.reason = reason
end

local function Save()
    local fields, why = Collect()
    if not fields then
        form.Error:SetText(why)
        return
    end
    if editing then
        -- The game's calendar first, inside the click: the change goes into
        -- the addon only if the calendar takes it.
        local sent, refused = ns.Calendar.UpdateFirst(editing, fields)
        if not sent then
            form.Error:SetText(refused or L["The game's calendar refused the change. Click again to retry."])
            UpdateSave()
            return
        end
        if not Events.Change(editing, fields) then
            form.Error:SetText(L["The event could not be changed."])
            return
        end
    else
        if not ns.Rights.MayCreate() then
            form.Error:SetText(L["Your guild rank cannot add events to the game's calendar."])
            return
        end
        -- The game's calendar first, inside the click: the event comes into
        -- the addon once the calendar has it, and not at all if it refuses it.
        local token = {}
        waiting = token
        local sent = ns.Calendar.CreateFirst(fields, function(key)
            if waiting ~= token then
                return
            end
            waiting = nil
            if key then
                form:Hide()
                ns.EventView.Open(key)
            else
                form.Error:SetText(L["The event could not be created."])
                UpdateSave()
            end
        end, function(reason)
            if waiting == token then
                waiting = nil
                form.Error:SetText(reason or "")
            end
            UpdateSave()
        end)
        if sent then
            form.Error:SetText("")
        else
            waiting = nil
            form.Error:SetText(ns.Calendar.lastError or L["The game's calendar refused the change. Click again to retry."])
        end
        UpdateSave()
        return
    end
    form:Hide()
end

-- The place ---------------------------------------------------------------------------------
-- A box to type in, which searches the places of the event's type and
-- lists those found under it; the arrow beside it lists them all. A click
-- on one, or Enter for the first, picks it. Leaving the box without
-- picking one puts back the one picked before.

local function ShowPlaceText()
    form.PlaceBox:SetText(UI.PlaceName(chosen.ii) or "")
end

local function HidePlaces()
    form.PlaceList:Hide()
    ShowPlaceText()
end

local function ShowPlaces(text)
    local elements = {}
    for _, place in ipairs(UI.FindPlaces(chosen.ty, text)) do
        elements[#elements + 1] = { place = place }
    end
    local list = form.PlaceList
    list.elements = elements
    list.ScrollBox:SetDataProvider(CreateDataProvider(elements))
    list.Empty:SetShown(#elements == 0)
    list:Show()
end

local function PickPlace(place)
    chosen.ii = place.id
    form.PlaceList:Hide()
    ShowPlaceText()
    form.PlaceBox:ClearFocus()
end

local function InitPlaceRow(row, element)
    if not row.Text then
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", 6, 0)
        row.Text:SetPoint("RIGHT", -6, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetWordWrap(false)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.15)
        row:SetScript("OnClick", function(self)
            PickPlace(self.place)
        end)
    end
    row.place = element.place
    local text = element.place.name
    if element.place.level > 0 then
        text = ("%s |cff888888(%d)|r"):format(text, element.place.level)
    end
    row.Text:SetText(text)
end

local function CreatePlaceRow()
    form.PlaceLabel = Label(L["Instance"], LEFT, -116)
    local box = Place(Box(214, 64), LEFT + BOX_INSET, -133)
    form.PlaceBox = box
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            ShowPlaces(self:GetText())
        end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        ShowPlaces("")
    end)
    box:SetScript("OnEnterPressed", function(self)
        local first = UI.FindPlaces(chosen.ty, self:GetText())[1]
        if first then
            PickPlace(first)
        else
            HidePlaces()
            self:ClearFocus()
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        HidePlaces()
        self:ClearFocus()
    end)
    -- Left for somewhere else: the list goes, unless a click on it is on
    -- its way.
    box:SetScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function()
            if form.PlaceList:IsShown() and not form.PlaceList:IsMouseOver() then
                HidePlaces()
            end
        end)
    end)

    local arrow = CreateFrame("Button", nil, form)
    arrow:SetSize(24, 24)
    arrow:SetPoint("LEFT", box, "RIGHT", 2, 0)
    arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    arrow:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
    arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    arrow:SetScript("OnClick", function()
        if form.PlaceList:IsShown() then
            HidePlaces()
        else
            ShowPlaces("")
        end
    end)
    form.PlaceArrow = arrow

    local list = CreateFrame("Frame", nil, form, "TooltipBackdropTemplate")
    list:SetSize(250, PLACE_ROW * PLACE_ROWS + 12)
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -BOX_INSET, -2)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:EnableMouse(true)
    local background = list:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0.06, 0.06, 0.08, 1)
    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -6)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 6)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
    view:SetElementExtent(PLACE_ROW)
    view:SetElementInitializer("Button", InitPlaceRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    list.ScrollBox = scrollBox
    list.Empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    list.Empty:SetPoint("CENTER")
    list.Empty:SetText(L["Nothing found."])
    list:Hide()
    form.PlaceList = list
end

-- The place's row follows the type: its label, and nothing to pick for a
-- meeting or another event.
UpdatePlace = function()
    local pvp = chosen.ty == Events.PVP
    local any = #UI.PlacesFor(chosen.ty) > 0
    form.PlaceLabel:SetText(pvp and L["Battleground"] or L["Instance"])
    form.PlaceBox:SetEnabled(any)
    form.PlaceBox:SetAlpha(any and 1 or 0.5)
    form.PlaceArrow:SetEnabled(any)
    form.PlaceList:Hide()
    ShowPlaceText()
end

-- The rows the place's list shows, for the tests.
function EventForm.PlaceRows()
    return form.PlaceList:IsShown() and form.PlaceList.elements or {}
end

function EventForm.PickPlace(place)
    PickPlace(place)
end

local function UpdateLimit()
    local on = form.Limit:GetChecked() == true
    for _, box in ipairs({ form.Tanks, form.Healers, form.Damage }) do
        box:SetEnabled(on)
        box:SetAlpha(on and 1 or 0.5)
    end
end

local function Create()
    form = CreateFrame("Frame", "GuildRaidsEventsForm", UIParent, "PortraitFrameTemplate")
    form:SetSize(440, 520)
    form:SetPoint("CENTER")
    form:SetFrameStrata("DIALOG")
    form:SetMovable(true)
    form:EnableMouse(true)
    form:SetClampedToScreen(true)
    form:RegisterForDrag("LeftButton")
    form:SetScript("OnDragStart", form.StartMoving)
    form:SetScript("OnDragStop", form.StopMovingOrSizing)
    form:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Head_Dragon_01")
    tinsert(UISpecialFrames, form:GetName())
    -- An addon window's close button does nothing in combat on WoW Forever
    -- (HideUIPanel), so it hides itself.
    form.onCloseCallback = function()
        form:Hide()
        return false
    end
    -- Title and type.
    Label(L["Title"], LEFT, -64)
    form.TitleBox = Place(Box(250, TITLE_LETTERS), LEFT + BOX_INSET, -82)
    Label(L["Type"], RIGHT_COLUMN, -64)
    form.Type = Dropdown(120, RIGHT_COLUMN, -79, function(_, root)
        for _, eventType in ipairs(Events.TYPES) do
            root:CreateRadio(UI.TypeName(eventType), function()
                return chosen.ty == eventType
            end, function()
                chosen.ty = eventType
                local first = UI.PlacesFor(eventType)[1]
                chosen.ii = first and first.id or nil
                UpdatePlace()
            end)
        end
    end)

    -- Where: the raid, the dungeon or the battleground.
    CreatePlaceRow()

    -- Day and time.
    Label(L["Day"], LEFT, -168)
    form.DayButton = UI.Button(form, "", TogglePicker)
    form.DayButton:SetSize(240, 24)
    Place(form.DayButton, LEFT, -183)
    CreateTimeRow()

    -- Description.
    Label(L["Description"], LEFT, -220)
    form.Description = CreateFrame("ScrollFrame", nil, form, "InputScrollFrameTemplate")
    form.Description:SetSize(384, 60)
    Place(form.Description, LEFT + BOX_INSET, -240)
    form.Description.EditBox:SetMaxLetters(DESCRIPTION_LETTERS)
    form.Description.EditBox:SetWidth(378)
    if form.Description.CharCount then
        form.Description.CharCount:Hide()
    end

    -- Places per role, in three columns under their box.
    form.Limit = Check(L["Limit the places of each role"], -314)
    form.Limit:SetScript("OnClick", UpdateLimit)
    for index, field in ipairs({ "Tanks", "Healers", "Damage" }) do
        local x = LEFT + (index - 1) * 130
        local label = Label(UI.RolesName(index), x, -349, "GameFontHighlightSmall")
        local box = Box(36, 2, true)
        box:SetPoint("LEFT", label, "RIGHT", 10 + BOX_INSET, 0)
        form[field] = box
    end

    -- Minimum level, then the two boxes.
    local levelLabel = Label(L["Minimum level (0: any)"], LEFT, -381)
    form.MinLevel = Box(40, 3, true)
    form.MinLevel:SetPoint("LEFT", levelLabel, "RIGHT", 10 + BOX_INSET, 0)
    form.Weekly = Check(L["Repeat every week"], -404)
    -- The game's own box, with its texts: members cannot answer a locked event.
    local lockText = CALENDAR_LOCK_EVENT or L["Lock event"]
    form.Lock = Check(lockText, -404, LEFT + 200)
    UI.SetTooltip(form.Lock, lockText, CALENDAR_TOOLTIP_LOCKEVENT or L["If checked, members cannot answer this event."])
    form.Auto = Check(L["Confirm sign-ups automatically: the first in each role, the rest on standby"], -430)
    form.Auto.Label:SetWidth(360)
    form.Auto.Label:SetJustifyH("LEFT")

    form.Error = form:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    form.Error:SetPoint("BOTTOMLEFT", 20, 44)
    form.Error:SetPoint("RIGHT", -20, 0)
    form.Error:SetJustifyH("LEFT")
    form.Save = UI.Button(form, L["Save"], Save)
    UI.SetTooltip(form.Save, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)
    ns.On("CalendarPending", UpdateSave)
    form.Save:SetPoint("BOTTOMRIGHT", -16, 14)
    form.Close = UI.Button(form, CANCEL or L["Cancel"], function()
        form:Hide()
    end)
    form.Close:SetPoint("RIGHT", form.Save, "LEFT", -6, 0)
    form.Hint = form:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    form.Hint:SetPoint("BOTTOMLEFT", 20, 20)
    form.Hint:SetPoint("RIGHT", form.Close, "LEFT", -8, 0)
    form.Hint:SetJustifyH("LEFT")
    CreatePicker()
    form:SetScript("OnHide", function()
        picker:Hide()
        form.PlaceList:Hide()
        ns.Calendar.Prepare(nil)
        waiting = nil
    end)
    form:Hide()
end

-- key: the event to change, or nil for a new one.
function EventForm.Open(key)
    if not form then
        Create()
    end
    local event = key and Events.Get(key)
    editing = event and event.key or nil
    form.Error:SetText("")
    if event then
        form:SetTitle(L["Change event"])
        local start = Events.DateOf(event.tm)
        local day = Events.Naive(start.year, start.month, start.day, 0, 0)
        chosen = { ty = event.ty, ii = event.ii, day = math.max(math.floor((day - Today()) / 86400), 0), hour = start.hour,
            minute = start.minute }
        form.TitleBox:SetText(event.ti)
        form.Description.EditBox:SetText(event.de or "")
        form.Limit:SetChecked(event.sl ~= nil)
        form.Tanks:SetText(tostring(event.sl and event.sl.t or 2))
        form.Healers:SetText(tostring(event.sl and event.sl.h or 3))
        form.Damage:SetText(tostring(event.sl and event.sl.d or 5))
        form.MinLevel:SetText(tostring(event.ml or 0))
        form.Weekly:SetChecked(event.wk == true)
        form.Auto:SetChecked(event.ac == true)
        form.Lock:SetChecked(event.lk == true)
        form.Save:SetText(L["Save"])
        form.Hint:SetText(L["It goes to the game's calendar when you save it."])
        -- Opened now, so the click that saves it changes the calendar too.
        ns.Calendar.Prepare(event.key, function()
            return form:IsShown() and editing == event.key
        end)
    else
        form:SetTitle(L["New event"])
        chosen = { ty = Events.OTHER, day = 1, hour = DEFAULT_HOUR, minute = 0 }
        form.TitleBox:SetText("")
        form.Description.EditBox:SetText("")
        form.Limit:SetChecked(false)
        form.Tanks:SetText("2")
        form.Healers:SetText("3")
        form.Damage:SetText("5")
        form.MinLevel:SetText("0")
        form.Weekly:SetChecked(false)
        form.Auto:SetChecked(false)
        form.Lock:SetChecked(false)
        form.Save:SetText(L["Create"])
        form.Hint:SetText(L["It goes to the game's calendar when you create it."])
    end
    form.Save:SetWidth(math.max(form.Save:GetTextWidth() + 28, 80))
    form.Type:GenerateMenu()
    UpdatePlace()
    ShowTime()
    UpdateDayButton()
    picker:Hide()
    UpdateLimit()
    UpdateSave()
    form:Show()
end

function EventForm.Frame()
    return form
end
