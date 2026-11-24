-- EventView.lua: one event in the Raids & Events tab (GuildTab.lua), in
-- place of the list: what it is, its sign-ups in three columns by role
-- (each name in its class colour, and its state in the game calendar's
-- colour; a note or a sign-up made outside the game in its tooltip),
-- confirmed first, then signed up, tentative and on standby;
-- under them, those left out; and the
-- player's own answer: their role, a note, and Sign up, Tentative or Remove
-- sign-up, as the game's calendar offers them. Those who may manage the
-- event (Rights.lua) also change it (EventForm.lua), cancel it, and give
-- each sign-up one of the game's statuses from its menu (a click on its
-- name, in a column or in those lines).
local _, ns = ...
local L = ns.L

local EventView = {}
ns.EventView = EventView

local Events, States, UI = ns.Events, ns.States, ns.UI

local COLUMN_WIDTH, COLUMN_GAP = 178, 8
local NAME_HEIGHT = 16
local MAX_NAMES = 7     -- names shown in a column; the rest as "+N more"
local NOTE_LETTERS = ns.Pack.LIMITS.noteLetters
local COLUMN_ORDER = { confirmed = 1, signed = 2, tentative = 3, standby = 4 }

local view       -- the frame
local shownKey   -- the event shown

-- The role for the event shown: the player's sign-up's, or the one picked
-- in the menu; else their default role (Roles.lua).
local Roles = ns.Roles
local selectedRole

-- A note in a sign-up's tooltip, as lines of at most NOTE_WIDTH pixels in
-- the tooltip's font: words go on a line while they fit, and a word wider
-- than a line (a long number, say) is cut where it reaches the edge. The
-- tooltip cuts a wrapped line's word that does not fit with "...", but
-- never a line added unwrapped, so each goes in unwrapped.
local NOTE_WIDTH = 220
local measure    -- a hidden font string in the tooltip's font

local function TextWidth(text)
    if not measure then
        measure = view:CreateFontString(nil, "ARTWORK", "GameTooltipText")
        measure:Hide()
    end
    measure:SetText(text)
    return measure:GetStringWidth()
end

function EventView.NoteLines(note)
    local lines, line = {}, ""
    for word in note:gmatch("%S+") do
        local joined = line == "" and word or line .. " " .. word
        if TextWidth(joined) <= NOTE_WIDTH then
            line = joined
        else
            if line ~= "" then
                lines[#lines + 1] = line
            end
            -- On a line of its own, cut where it reaches the edge.
            line = ""
            for letter in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if line ~= "" and TextWidth(line .. letter) > NOTE_WIDTH then
                    lines[#lines + 1] = line
                    line = letter
                else
                    line = line .. letter
                end
            end
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- A sign-up's tooltip: its answer, status, note, and where it was made.
local function ShowTooltip(owner, signUp)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(UI.ClassColored(signUp.name or "?", signUp.class), 1, 1, 1)
    local status = UI.StateName(States.Of(signUp))
    if signUp.auto then
        status = ("%s (%s)"):format(status, L["automatically"])
    end
    GameTooltip:AddLine(("%s · %s"):format(UI.RoleName(signUp.ro), status), 1, 0.82, 0, true)
    if signUp.level then
        GameTooltip:AddLine(L["Level %d"]:format(signUp.level), 0.8, 0.8, 0.8)
    end
    if signUp.no then
        for _, line in ipairs(EventView.NoteLines(signUp.no)) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
    end
    if signUp.external then
        GameTooltip:AddLine(L["Signed up outside the game."], 0.6, 0.8, 1, true)
    end
    local event = Events.Get(shownKey)
    if event and ns.Rights.MayIManage(event) then
        GameTooltip:AddLine(L["Click to give a status."], 0.5, 1, 0.5, true)
    end
    GameTooltip:Show()
end

local function NameOnEnter(button)
    if button.signUp then
        ShowTooltip(button, button.signUp)
    end
end

-- The menu of a sign-up, for those who may manage the event.
local function StatusMenu(owner, signUp)
    local event = Events.Get(shownKey)
    if not signUp or not event or not ns.Rights.MayIManage(event) then
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(signUp.name or "?")
        for _, status in ipairs({ Events.CONFIRMED, Events.STANDBY, Events.OUT, Events.PROVISIONAL }) do
            root:CreateRadio(UI.StatusName(status), function()
                return signUp.status == status and not (signUp.auto and status ~= Events.NONE)
            end, function()
                Events.SetStatus(event.key, signUp.guid, status)
            end)
        end
    end)
end

local function NameOnClick(button)
    StatusMenu(button, button.signUp)
end

-- The names in the lines under the columns are links (|Hgre:GUID|h):
-- the sign-ups they stand for, by GUID.
local linked = {}

local function LinkedSignUp(link)
    local guid = type(link) == "string" and link:match("^gre:(.+)$")
    return guid and linked[guid]
end

-- A column's sign-ups: confirmed, signed up, tentative, standby; then in
-- the order they signed up (order).
function EventView.SortColumn(list)
    table.sort(list, function(a, b)
        local ra, rb = COLUMN_ORDER[States.Of(a)] or 9, COLUMN_ORDER[States.Of(b)] or 9
        if ra ~= rb then
            return ra < rb
        end
        return a.order < b.order
    end)
    return list
end

local function CreateColumn(index)
    local column = CreateFrame("Frame", nil, view)
    column:SetSize(COLUMN_WIDTH, NAME_HEIGHT * (MAX_NAMES + 2))
    column:SetPoint("TOPLEFT", view.Description, "BOTTOMLEFT", (index - 1) * (COLUMN_WIDTH + COLUMN_GAP), -10)
    column.Background = column:CreateTexture(nil, "BACKGROUND")
    column.Background:SetAllPoints()
    column.Background:SetColorTexture(0, 0, 0, 0.25)
    column.Header = column:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    column.Header:SetPoint("TOPLEFT", 6, -3)
    column.Header:SetPoint("RIGHT", -6, 0)
    column.Header:SetJustifyH("LEFT")
    column.Names = {}
    for row = 1, MAX_NAMES do
        local button = CreateFrame("Button", nil, column)
        button:SetSize(COLUMN_WIDTH - 12, NAME_HEIGHT)
        button:SetPoint("TOPLEFT", 6, -3 - row * NAME_HEIGHT)
        button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        button.Text:SetAllPoints()
        button.Text:SetJustifyH("LEFT")
        button.Text:SetWordWrap(false)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        button:SetScript("OnEnter", NameOnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:SetScript("OnClick", UI.Clicked(NameOnClick))
        column.Names[row] = button
    end
    column.More = column:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    column.More:SetPoint("TOPLEFT", 6, -3 - (MAX_NAMES + 1) * NAME_HEIGHT)
    return column
end

-- A sign-up's line: its name in its class colour, with its one state (the
-- member's answer or a status given), in the game's colour for it.
local function NameText(signUp)
    local name = UI.ClassColored(signUp.name or "?", signUp.class)
    local state = States.Of(signUp)
    local mark = " " .. UI.Colored(("(%s)"):format(UI.StateName(state)), UI.StateColor(state))
    if signUp.no then
        mark = mark .. " |cff888888*|r"
    end
    return name .. mark
end

-- The player gives themselves a state with one of their buttons, with the
-- role and note chosen: a member answers; the organizer (the event's
-- creator, whom the game keeps in it) answers and sets their own status.
local function SetOwnState(state)
    local event = Events.Get(shownKey)
    if not event then
        return
    end
    local note = strtrim(view.Note:GetText() or "")
    States.SetMine(event.key, state, selectedRole or Roles.Default(), note, event.owner == ns.playerGUID)
end

local function CreateControls()
    -- The player's own answer, under the columns.
    view.RoleLabel = view:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    view.RoleLabel:SetPoint("BOTTOMLEFT", 4, 34)
    view.RoleLabel:SetText(L["Your role"])
    view.Role = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    view.Role:SetWidth(120)
    view.Role:SetPoint("BOTTOMLEFT", 2, 6)
    view.Role:SetupMenu(function(_, root)
        for role = Events.TANK, Events.DAMAGE do
            root:CreateRadio(UI.RoleName(role), function()
                return (selectedRole or Roles.Default()) == role
            end, function()
                selectedRole = role
                Roles.Remember(role)
                EventView.UpdateControls()
            end)
        end
    end)
    view.NoteLabel = view:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    view.NoteLabel:SetPoint("BOTTOMLEFT", view.RoleLabel, "BOTTOMLEFT", 132, 0)
    view.NoteLabel:SetText(L["Note"])
    view.Note = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    view.Note:SetSize(100, 20)
    view.Note:SetPoint("BOTTOMLEFT", 138, 8)
    view.Note:SetAutoFocus(false)
    view.Note:SetMaxLetters(NOTE_LETTERS)
    view.Note:SetScript("OnEnterPressed", view.Note.ClearFocus)
    view.Note:SetScript("OnEscapePressed", view.Note.ClearFocus)
    view.Note:SetScript("OnTextChanged", function()
        EventView.UpdateControls()
    end)
    -- One button per state the player can give themselves, as the game's
    -- calendar offers them: a member signs up, signs up as tentative or
    -- removes their sign-up; the organizer (the event's creator, whom the
    -- game keeps in it) is confirmed, on standby, tentative or out.
    local function StateButton(state, text)
        return { state = state, button = UI.Button(view, text or UI.StateName(state), function()
            SetOwnState(state)
        end) }
    end
    view.States = {
        member = { StateButton("signed"), StateButton("tentative"), StateButton("none", L["Remove sign-up"]) },
        organizer = {},
    }
    for _, state in ipairs({ "confirmed", "standby", "tentative", "out" }) do
        table.insert(view.States.organizer, StateButton(state))
    end
    view.SignUp, view.Tentative, view.Remove = view.States.member[1].button, view.States.member[2].button,
        view.States.member[3].button
    view.Confirm, view.Standby, view.OwnTentative, view.Out = view.States.organizer[1].button,
        view.States.organizer[2].button, view.States.organizer[3].button, view.States.organizer[4].button
    view.Mine = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.Mine:SetPoint("BOTTOMLEFT", view.Note, "TOPRIGHT", 8, 7)
    view.Mine:SetPoint("RIGHT", -4, 0)
    view.Mine:SetJustifyH("LEFT")
    for _, set in pairs(view.States) do
        for _, item in ipairs(set) do
            UI.SetTooltip(item.button, function(self)
                return self:GetText()
            end, function(self)
                return self.reason
            end)
        end
    end
end

function EventView.Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    view.Icon = view:CreateTexture(nil, "ARTWORK")
    view.Icon:SetSize(40, 40)
    view.Icon:SetPoint("TOPLEFT", 4, -4)
    view.Title = view:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    view.Title:SetPoint("TOPLEFT", view.Icon, "TOPRIGHT", 8, -2)
    view.Title:SetPoint("RIGHT", -230, 0)
    view.Title:SetJustifyH("LEFT")
    view.Title:SetWordWrap(false)
    view.When = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.When:SetPoint("TOPLEFT", view.Title, "BOTTOMLEFT", 0, -10)
    view.When:SetPoint("RIGHT", -8, 0)
    view.When:SetJustifyH("LEFT")
    view.When:SetWordWrap(false)
    view.Details = view:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    view.Details:SetPoint("TOPLEFT", view.Icon, "BOTTOMLEFT", 0, -9)
    view.Details:SetPoint("RIGHT", -8, 0)
    view.Details:SetJustifyH("LEFT")
    view.Details:SetWordWrap(false)
    view.Description = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.Description:SetPoint("TOPLEFT", view.Details, "BOTTOMLEFT", 0, -4)
    view.Description:SetPoint("RIGHT", -8, 0)
    view.Description:SetHeight(26)
    view.Description:SetJustifyH("LEFT")
    view.Description:SetJustifyV("TOP")
    view.Description:SetMaxLines(2)

    -- At the top right: back to the list, and what managers do.
    view.Back = UI.Button(view, L["Back"], function()
        EventView.Close()
    end)
    view.Back:SetPoint("TOPRIGHT", -4, -4)
    -- The game's calendar first, inside the click, then our record.
    view.Cancel = UI.Button(view, L["Cancel event"], function()
        local event = Events.Get(shownKey)
        if not event then
            return
        elseif event.x then
            ns.Calendar.Restore(event.key)
        else
            ns.Calendar.Cancel(event.key)
        end
    end, true)
    view.Cancel:SetPoint("RIGHT", view.Back, "LEFT", -4, 0)
    UI.SetTooltip(view.Cancel, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)
    view.Edit = UI.Button(view, L["Edit"], function()
        ns.EventForm.Open(shownKey)
    end)
    view.Edit:SetPoint("RIGHT", view.Cancel, "LEFT", -4, 0)
    -- A cancelled event of one's own is deleted, for everyone (and from the
    -- game's calendar, if still there), as clearing it does.
    view.Delete = UI.Button(view, DELETE or L["Delete"], function()
        if ns.Calendar.Delete(shownKey) then
            EventView.Close()
        end
    end)
    view.Delete:SetPoint("RIGHT", view.Edit, "LEFT", -4, 0)
    -- Next week's event of a weekly one, not in the game's calendar yet: its
    -- click creates it there (restricted: the call goes first in the click).
    view.Send = UI.Button(view, L["Create in calendar"], function()
        ns.Calendar.SendNow(shownKey)
    end, true)
    view.Send:SetPoint("RIGHT", view.Edit, "LEFT", -4, 0)
    UI.SetTooltip(view.Send, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)
    UI.SetTooltip(view.Delete, function(self)
        return self:GetText()
    end, L["Deletes this cancelled event, for everyone."])

    view.Columns = {}
    for role = Events.TANK, Events.DAMAGE do
        view.Columns[role] = CreateColumn(role)
    end
    view.Others = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.Others:SetPoint("TOPLEFT", view.Columns[1], "BOTTOMLEFT", 0, -6)
    view.Others:SetPoint("RIGHT", -8, 0)
    view.Others:SetJustifyH("LEFT")
    view.Others:SetJustifyV("TOP")
    view.Others:SetMaxLines(2)
    -- Its names: a tooltip, and the status menu on a click.
    view:SetHyperlinksEnabled(true)
    view:SetScript("OnHyperlinkEnter", function(self, link)
        local signUp = LinkedSignUp(link)
        if signUp then
            ShowTooltip(self, signUp)
        end
    end)
    view:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
    local menu = UI.Clicked(StatusMenu)
    view:SetScript("OnHyperlinkClick", function(self, link)
        local signUp = LinkedSignUp(link)
        if signUp then
            menu(self, signUp)
        end
    end)
    CreateControls()
    return view
end

-- The details line: places, minimum level, weekly, confirms by itself.
local function DetailsText(event)
    local parts = {}
    if (event.ml or 0) > 0 then
        parts[#parts + 1] = L["Level %d or higher"]:format(event.ml)
    end
    if event.wk then
        parts[#parts + 1] = L["Every week"]
    end
    parts[#parts + 1] = event.ac and L["Confirms sign-ups automatically"] or L["The organizer confirms"]
    if event.x then
        parts[#parts + 1] = "|cffff4040" .. L["Cancelled"] .. "|r"
    end
    return table.concat(parts, "  ·  ")
end

-- A line's names, each a link to its sign-up when links is set.
local function Names(list, links)
    local names = {}
    for _, signUp in ipairs(list) do
        local name = UI.ClassColored(signUp.name or "?", signUp.class)
        if links then
            linked[signUp.guid] = signUp
            name = ("|Hgre:%s|h%s|h"):format(signUp.guid, name)
        end
        names[#names + 1] = name
    end
    return #names > 0 and table.concat(names, ", ") or L["nobody"]
end

function EventView.Refresh()
    if not view or not view:IsShown() then
        return
    end
    local event = Events.Get(shownKey)
    if not event then
        EventView.Close()
        return
    end
    local manager = ns.Rights.MayIManage(event)
    local signUps = Events.SignUps(event)
    view.Icon:SetTexture(UI.TYPE_ICONS[event.ty])
    view.Title:SetText(UI.EventTitle(event))
    view.When:SetText(L["%s  ·  %s  ·  by %s"]:format(UI.DateText(event.tm), UI.KindText(event),
        Events.MemberName(event.owner) or "?"))
    view.Details:SetText(DetailsText(event))
    view.Description:SetText(event.de or "")
    view.Edit:SetShown(manager)
    view.Cancel:SetShown(manager)
    view.Delete:SetShown(event.x == true and event.owner == ns.playerGUID)
    view.Cancel:SetText(event.x and L["Restore event"] or L["Cancel event"])
    view.Cancel:SetWidth(math.max(view.Cancel:GetTextWidth() + 28, 80))

    -- By role, all but those left out, who go under the columns. Each
    -- column: confirmed, signed up, tentative, standby; then in the order
    -- they signed up.
    local byRole, out = { {}, {}, {} }, {}
    for index, signUp in ipairs(signUps) do
        signUp.order = index
        if States.Goes(signUp) or States.IsTentative(signUp) then
            table.insert(byRole[signUp.ro or Events.DAMAGE], signUp)
        elseif signUp.st == Events.SIGNED then
            out[#out + 1] = signUp
        end
    end
    for _, list in ipairs(byRole) do
        EventView.SortColumn(list)
    end
    local counts = Events.Counts(signUps)
    for role, column in ipairs(view.Columns) do
        local places = event.sl and event.sl[Events.ROLE_FIELD[role]]
        column.Header:SetText(places and ("%s %d/%d"):format(UI.RolesName(role), counts[role], places)
            or ("%s %d"):format(UI.RolesName(role), counts[role]))
        local list = byRole[role]
        for row, button in ipairs(column.Names) do
            local signUp = list[row]
            button.signUp = signUp
            button.Text:SetText(signUp and NameText(signUp) or "")
            button:SetShown(signUp ~= nil)
        end
        local more = #list - MAX_NAMES
        column.More:SetText(more > 0 and L["+%d more"]:format(more) or "")
    end
    wipe(linked)
    view.Others:SetText(("%s: %s"):format(UI.StatusName(Events.OUT), Names(out, manager)))

    EventView.UpdateControls(signUps)
    view.Role:GenerateMenu()
end

-- The player's buttons and state line: a button is off while the player
-- already is in its state, with the role and note chosen. A member answers
-- as the game's calendar lets them: signed up in any way, they only remove
-- their sign-up (or change their role or note, which the calendar does not
-- have); the event then leaves their calendar for about an hour, and they
-- answer again once it is back.
function EventView.UpdateControls(signUps)
    local event = view and view:IsShown() and Events.Get(shownKey)
    if not event then
        return
    end
    local mine = Events.Mine(event, signUps)
    local state = States.Of(mine)
    local organizer = event.owner == ns.playerGUID
    -- Create in calendar, for one of the player's events not there yet, as
    -- the game lets it now; then the title up to the first button.
    local unsent = ns.Calendar.Unsent(event)
    local blocked = unsent and ns.Calendar.SendBlocked() or nil
    view.Send:SetShown(unsent)
    view.Send:SetEnabled(unsent and not blocked)
    view.Send.reason = blocked or L["Not in the game's calendar yet: this click creates it there."]
    local first = view.Delete:IsShown() and view.Delete or unsent and view.Send or view.Edit:IsShown() and view.Edit
        or view.Back
    view.Title:ClearAllPoints()
    view.Title:SetPoint("TOPLEFT", view.Icon, "TOPRIGHT", 8, -2)
    view.Title:SetPoint("RIGHT", first, "LEFT", -8, 0)
    -- Restore event: off while the calendar makes it again, and at the game's
    -- limit of events created (it would be created again).
    local restoring = event.x and ns.Calendar.Restoring(event.key)
    local atLimit = event.x and organizer and ns.Calendar.AtLimit()
    view.Cancel:SetEnabled(not restoring and not atLimit)
    view.Cancel.reason = restoring and L["Syncing the calendar..."] or atLimit and ns.Calendar.LimitText() or nil
    -- A locked event takes no answers from members; its creator still
    -- changes their own, as the game's calendar lets them.
    local locked = event.lk and not organizer
    local open = Events.IsUpcoming(event) and not event.x and not locked
    local reason
    if event.x then
        reason = L["This event is cancelled."]
    elseif not Events.IsUpcoming(event) then
        reason = L["This event is over."]
    elseif locked then
        reason = L["This event is locked: it takes no answers."]
    elseif not UI.MeetsLevel(event) then
        reason = L["This event is for level %d or higher."]:format(event.ml)
    end
    local role = selectedRole or Roles.Default()
    local note = strtrim(view.Note:GetText() or "")
    local same = mine ~= nil and mine.ro == role and (mine.no or "") == note
    local hidden = not organizer and state == "none" and ns.Calendar.HiddenFromMe(event)
    local shown = organizer and view.States.organizer or view.States.member
    for _, set in pairs(view.States) do
        for _, item in ipairs(set) do
            item.button:SetShown(set == shown)
        end
    end
    local last
    for _, item in ipairs(shown) do
        local button = item.button
        button:ClearAllPoints()
        if last then
            button:SetPoint("LEFT", last, "RIGHT", 4, 0)
        else
            button:SetPoint("BOTTOMLEFT", view.Note, "BOTTOMRIGHT", 8, -1)
        end
        last = button
        button:SetWidth(math.max(button:GetTextWidth() + 20, 70))
        local current = state == item.state
        if item.state == "signed" then
            -- Signed up includes the statuses the organizer gives.
            current = States.IsSignedUp(state)
        end
        if item.state == "none" then
            -- Removing: while there is a sign-up and the event is to come.
            button:SetEnabled(open and state ~= "none")
            button.reason = not open and reason or (state == "none" and L["You are not signed up."]) or nil
        elseif not organizer and state ~= "none" and (state == "out" or not current) then
            -- Another answer: removing the sign-up first, and waiting.
            button:SetEnabled(false)
            button.reason = reason
                or L["To change your answer, remove your sign-up and wait for the event to show again in your calendar (about an hour, or when you log in again)."]
        elseif hidden then
            button:SetEnabled(false)
            button.reason = reason
                or L["Wait for the event to show again in your calendar (about an hour after removing your sign-up, or when you log in again)."]
        elseif current and (same or item.state == "out") then
            button:SetEnabled(false)
            button.reason = L["You are already in this state."]
        else
            button:SetEnabled(reason == nil)
            button.reason = reason
        end
    end
    if state == "none" then
        view.Mine:SetText(L["Your status: %s."]:format(UI.StateText(mine)))
    else
        view.Mine:SetText(L["Your status: %s, as %s."]:format(UI.StateText(mine), UI.RoleName(mine.ro)))
    end
end

function EventView.Open(key)
    if not view then
        return
    end
    local event = Events.Get(key)
    if not event then
        return
    end
    if shownKey ~= key then
        selectedRole = nil
        local mine = Events.Mine(event)
        view.Note:SetText(mine and mine.no or "")
        if mine and mine.ro then
            selectedRole = mine.ro
        end
    end
    shownKey = key
    view:Show()
    ns.Fire("ViewChanged")
    EventView.Refresh()
end

function EventView.Close()
    shownKey = nil
    if view then
        view:Hide()
    end
    ns.Fire("ViewChanged")
end

function EventView.Shown()
    return view ~= nil and view:IsShown() and shownKey or nil
end
