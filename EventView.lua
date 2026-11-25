-- EventView.lua: one event in the Raids & Events tab (GuildTab.lua), in
-- place of the list: what it is, its sign-ups in three columns by role
-- (each name in its class colour, and its state in the game calendar's
-- colour; a note or a sign-up made outside the game in its tooltip),
-- confirmed first, then signed up, tentative and on standby;
-- under them, those left out; and, at the bottom, only signing up (a role,
-- a note, Sign up or Tentative) or Remove sign-up, as the game's calendar
-- offers them, and nothing for the organizer. Those who may manage the
-- event (Rights.lua) also change it (EventForm.lua), delete it (so may
-- officers), and give each sign-up (their own too) one of the game's
-- statuses and a role from its menu (a right-click on its name, in a
-- column or in those lines), or a role by dragging its name to another
-- column; any member changes their own role that way, and their note
-- from their name's menu.
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
-- The game calendar's marks of an event's creator and its moderators.
local LEADER_ICON = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t "
local MODERATOR_ICON = "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:12:12|t "

local view       -- the frame
local shownKey   -- the event shown
local EditNote   -- opens the note's window (below)

-- The role for the event shown: the player's sign-up's, or the one picked
-- in the menu; else their default role (Roles.lua).
local Roles = ns.Roles
local selectedRole
local knownRole  -- the player's sign-up's role last shown: changed since (by a manager), it is picked

-- A note in a sign-up's tooltip, as lines of about NOTE_WIDTH pixels in
-- the tooltip's font: words go on a line while they fit, and a word wider
-- than that (a long number, say) goes whole on a line of its own. The
-- tooltip cuts a wrapped line's word that does not fit with "...", but
-- never a line added unwrapped: each goes in unwrapped, and the tooltip
-- widens to the longest.
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
            line = word
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- A sign-up's tooltip: its answer, status, note, and where it was made;
-- what the player may do with it (draggable: a name in a column).
local function ShowTooltip(owner, signUp, draggable)
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
    if event and (ns.Rights.MayIManage(event) or signUp.guid == ns.playerGUID) then
        GameTooltip:AddLine(L["Right-click for its menu."], 0.5, 1, 0.5, true)
        if draggable then
            GameTooltip:AddLine(L["Drag it to another column to change its role."], 0.5, 1, 0.5, true)
        end
    end
    GameTooltip:Show()
end

local function NameOnEnter(button)
    if button.signUp then
        ShowTooltip(button, button.signUp, true)
    end
end

-- A sign-up's new role (Events.MayChangeRole). The player's own is their
-- choice: picked, and remembered (Roles.lua).
local function ChangeRole(signUp, role)
    local event = Events.Get(shownKey)
    if not event or (signUp.ro or Events.DAMAGE) == role or not Events.SetRole(event.key, signUp.guid, role) then
        return
    end
    if signUp.guid == ns.playerGUID then
        selectedRole = role
        Roles.Remember(role)
    end
end

-- The menu of a sign-up: its status, role and moderation for those who
-- manage the event; their own role for anyone else.
local function NameMenu(owner, signUp)
    local event = Events.Get(shownKey)
    local manager = event ~= nil and ns.Rights.MayIManage(event)
    if not signUp or not event or not (manager or Events.MayChangeRole(event, signUp.guid)) then
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(signUp.name or "?")
        if manager then
            for _, status in ipairs({ Events.CONFIRMED, Events.STANDBY, Events.OUT, Events.PROVISIONAL }) do
                root:CreateRadio(UI.StatusName(status), function()
                    return signUp.status == status and not (signUp.auto and status ~= Events.NONE)
                end, function()
                    Events.SetStatus(event.key, signUp.guid, status)
                end)
            end
            root:CreateDivider()
        end
        root:CreateTitle(L["Role"])
        for role = Events.TANK, Events.DAMAGE do
            root:CreateRadio(UI.RoleName(role), function()
                return (signUp.ro or Events.DAMAGE) == role
            end, function()
                ChangeRole(signUp, role)
            end)
        end
        -- The player's own note (not one brought in from outside the game).
        if signUp.guid == ns.playerGUID and not signUp.external then
            root:CreateDivider()
            root:CreateButton(L["Edit note"], function()
                EditNote(event.key)
            end)
        end
        -- Moderators, as the game's calendar names them: anyone in its list
        -- (not a sign-up made outside the game), never the organizer.
        if manager and signUp.guid ~= event.owner and not signUp.external then
            local moderator = event.md ~= nil and event.md[signUp.guid] == true
            root:CreateDivider()
            root:CreateButton(moderator and (CALENDAR_INVITELIST_CLEARMODERATOR or L["Clear moderator"])
                or (CALENDAR_INVITELIST_SETMODERATOR or L["Set moderator"]), function()
                Events.SetModerator(event.key, signUp.guid, not moderator)
            end)
        end
    end)
end

local function NameOnClick(button, mouse)
    if mouse == "RightButton" then
        NameMenu(button, button.signUp)
    end
end

-- Dragging a name to another column changes its role. While it is
-- dragged, the name follows the cursor, and the column under it lights up.
local dragged  -- the sign-up dragged, or nil
local ghost    -- the name under the cursor

-- The column the cursor is over, as a role, or nil.
local function ColumnUnderCursor()
    for role, column in ipairs(view.Columns) do
        if column:IsMouseOver() then
            return role
        end
    end
end

local function LightColumns()
    local under = dragged and ColumnUnderCursor()
    for role, column in ipairs(view.Columns) do
        column.Background:SetColorTexture(0, 0, 0, role == under and 0.5 or 0.25)
    end
end

local function FollowCursor(frame)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
    LightColumns()
end

local function NameOnDragStart(button)
    local event = Events.Get(shownKey)
    if not button.signUp or not Events.MayChangeRole(event, button.signUp.guid) then
        return
    end
    dragged = button.signUp
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetSize(1, 1)
        ghost.Text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ghost.Text:SetPoint("LEFT")
        ghost:SetScript("OnUpdate", FollowCursor)
    end
    ghost.Text:SetText(button.Text:GetText())
    FollowCursor(ghost)
    ghost:Show()
    GameTooltip_Hide()
end

local function NameOnDragStop()
    local signUp = dragged
    local role = signUp and ColumnUnderCursor()
    dragged = nil
    if ghost then
        ghost:Hide()
    end
    LightColumns()
    if role then
        ChangeRole(signUp, role)
    end
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
        button:RegisterForClicks("RightButtonUp")
        button:SetScript("OnClick", NameOnClick)
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", NameOnDragStart)
        button:SetScript("OnDragStop", NameOnDragStop)
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
    -- The organizer and the moderators marked as in the game's calendar.
    local event = Events.Get(shownKey)
    if event and signUp.guid == event.owner then
        name = LEADER_ICON .. name
    elseif event and Events.IsModerator(event, signUp.guid) then
        name = MODERATOR_ICON .. name
    end
    local state = States.Of(signUp)
    local mark = " " .. UI.Colored(("(%s)"):format(UI.StateName(state)), UI.StateColor(state))
    if signUp.no then
        mark = mark .. " |cff888888*|r"
    end
    return name .. mark
end

-- The player signs up (as tentative too), with the role and note chosen,
-- or removes their sign-up.
local function SetOwnState(state)
    local event = Events.Get(shownKey)
    if not event then
        return
    end
    local note = strtrim(view.Note:GetText() or "")
    States.SetMine(event.key, state, selectedRole or Roles.Default(), note, false)
end

-- The note of the player's own sign-up, changed from its name's menu: a
-- small window over the view.
local noteEditor

local function SaveNote()
    if noteEditor.key then
        Events.SetNote(noteEditor.key, strtrim(noteEditor.Box:GetText() or ""))
    end
    noteEditor:Hide()
end

function EditNote(key)
    local event = Events.Get(key)
    local mine = event and Events.Mine(event)
    if not mine then
        return
    end
    if not noteEditor then
        noteEditor = CreateFrame("Frame", nil, view, "TooltipBackdropTemplate")
        noteEditor:SetSize(260, 84)
        noteEditor:SetPoint("CENTER")
        -- Over everything in the view, and not see-through.
        noteEditor:SetFrameStrata("FULLSCREEN_DIALOG")
        noteEditor:EnableMouse(true)
        local background = noteEditor:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetPoint("TOPLEFT", 3, -3)
        background:SetPoint("BOTTOMRIGHT", -3, 3)
        background:SetColorTexture(0.06, 0.06, 0.08, 1)
        noteEditor.Title = noteEditor:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        noteEditor.Title:SetPoint("TOPLEFT", 12, -10)
        noteEditor.Title:SetText(L["Note"])
        noteEditor.Box = CreateFrame("EditBox", nil, noteEditor, "InputBoxTemplate")
        noteEditor.Box:SetSize(228, 20)
        noteEditor.Box:SetPoint("TOPLEFT", 18, -28)
        noteEditor.Box:SetAutoFocus(false)
        noteEditor.Box:SetMaxLetters(NOTE_LETTERS)
        noteEditor.Box:SetScript("OnEnterPressed", SaveNote)
        noteEditor.Box:SetScript("OnEscapePressed", function()
            noteEditor:Hide()
        end)
        noteEditor.Cancel = UI.Button(noteEditor, CANCEL or L["Cancel"], function()
            noteEditor:Hide()
        end)
        noteEditor.Cancel:SetPoint("BOTTOMRIGHT", -8, 8)
        noteEditor.Save = UI.Button(noteEditor, L["Save"], SaveNote)
        noteEditor.Save:SetPoint("RIGHT", noteEditor.Cancel, "LEFT", -4, 0)
    end
    noteEditor.key = key
    noteEditor.Box:SetText(mine.no or "")
    noteEditor:Show()
    noteEditor.Box:SetFocus()
    noteEditor.Box:HighlightText()
end

local function CloseNoteEditor()
    if noteEditor then
        noteEditor.key = nil
        noteEditor:Hide()
    end
end

local function CreateControls()
    -- Under the columns, only to sign up or remove a sign-up: a member not
    -- signed up picks their role and a note on the left, and signs up or
    -- signs up as tentative on the right; one signed up (a moderator too)
    -- removes their sign-up, in the middle; the organizer, whom the game
    -- keeps in their event, has nothing there. Statuses, roles and notes
    -- change from each name's menu (a right-click).
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
    local function StateButton(state, text)
        local button = UI.Button(view, text or UI.StateName(state), function()
            SetOwnState(state)
        end)
        button:SetWidth(math.max(button:GetTextWidth() + 20, 90))
        UI.SetTooltip(button, function(self)
            return self:GetText()
        end, function(self)
            return self.reason
        end)
        return button
    end
    view.Tentative = StateButton("tentative")
    view.Tentative:SetPoint("BOTTOMRIGHT", -4, 7)
    view.SignUp = StateButton("signed")
    view.SignUp:SetPoint("RIGHT", view.Tentative, "LEFT", -4, 0)
    view.Remove = StateButton("none", L["Remove sign-up"])
    view.Remove:SetPoint("BOTTOM", 0, 7)
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
    -- Deleted for everyone, as the game's calendar deletes an event, once
    -- the player confirms it: the calendar first, then our records.
    view.Delete = UI.Button(view, L["Delete event"], function()
        local event = Events.Get(shownKey)
        if not event then
            return
        end
        local key = event.key
        StaticPopup_ShowCustomGenericConfirmation({
            text = "%s",
            text_arg1 = L["Delete %s for everyone? There is no getting it back."]:format(("|cffffd200%s|r"):format(event.ti)),
            showAlert = true,
            callback = function()
                ns.Calendar.Delete(key)
            end,
        })
    end)
    view.Delete:SetPoint("RIGHT", view.Back, "LEFT", -4, 0)
    UI.SetTooltip(view.Delete, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)
    view.Edit = UI.Button(view, L["Edit"], function()
        ns.EventForm.Open(shownKey)
    end)
    view.Edit:SetPoint("RIGHT", view.Delete, "LEFT", -4, 0)
    -- Next week's event of a weekly one, not in the game's calendar yet: its
    -- click creates it there (restricted: the call goes first in the click).
    view.Send = UI.Button(view, L["Create in calendar"], function()
        ns.Calendar.SendNow(shownKey)
    end)
    view.Send:SetPoint("RIGHT", view.Edit, "LEFT", -4, 0)
    UI.SetTooltip(view.Send, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)

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
    view:SetScript("OnHyperlinkClick", function(self, link, _, mouse)
        local signUp = LinkedSignUp(link)
        if signUp and mouse == "RightButton" then
            NameMenu(self, signUp)
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
    view.Delete:SetShown(ns.Rights.MayIDelete(event))
    local mine = Events.Mine(event, signUps)
    if mine and mine.ro and mine.ro ~= knownRole then
        -- Changed since (by a manager, or dragged): picked.
        selectedRole = mine.ro
    end
    knownRole = mine and mine.ro

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

-- What shows under the columns (see CreateControls), and why a button is
-- off. Signed up in any way, a member only removes their sign-up, as the
-- game's calendar lets them; the event then leaves their calendar for
-- about an hour, and they sign up again once it is back.
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
    local first = unsent and view.Send or view.Edit:IsShown() and view.Edit or view.Delete:IsShown() and view.Delete
        or view.Back
    view.Title:ClearAllPoints()
    view.Title:SetPoint("TOPLEFT", view.Icon, "TOPRIGHT", 8, -2)
    view.Title:SetPoint("RIGHT", first, "LEFT", -8, 0)
    -- Delete event: off while the calendar deletes it.
    local deleting = ns.Calendar.Deleting(event.key)
    view.Delete:SetEnabled(not deleting)
    view.Delete.reason = deleting and L["Syncing the calendar..."] or L["Deletes this event, for everyone."]
    local signing = not organizer and state == "none"
    local removing = not organizer and state ~= "none"
    for _, widget in ipairs({ view.RoleLabel, view.Role, view.NoteLabel, view.Note, view.SignUp, view.Tentative }) do
        widget:SetShown(signing)
    end
    view.Remove:SetShown(removing)
    -- Over, or locked (no answers from members, nor their sign-ups back).
    local reason
    if not Events.IsUpcoming(event) then
        reason = L["This event is over."]
    elseif event.lk then
        reason = L["This event is locked: it takes no answers."]
    end
    if signing then
        if not reason and not UI.MeetsLevel(event) then
            reason = L["This event is for level %d or higher."]:format(event.ml)
        elseif not reason and ns.Calendar.HiddenFromMe(event) then
            reason = L["Wait for the event to show again in your calendar (about an hour after removing your sign-up, or when you log in again)."]
        end
        for _, button in ipairs({ view.SignUp, view.Tentative }) do
            button:SetEnabled(reason == nil)
            button.reason = reason
        end
    elseif removing then
        -- A moderator's sign-up taken back ends their moderation.
        view.Remove:SetEnabled(reason == nil)
        view.Remove.reason = reason or (Events.IsModerator(event, ns.playerGUID)
            and L["Takes your sign-up back: you are a moderator no more, as in the game's calendar."]) or nil
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
        CloseNoteEditor()
        selectedRole = nil
        local mine = Events.Mine(event)
        view.Note:SetText(mine and mine.no or "")
        if mine and mine.ro then
            selectedRole = mine.ro
        end
        knownRole = mine and mine.ro
    end
    shownKey = key
    view:Show()
    ns.Fire("ViewChanged")
    EventView.Refresh()
end

function EventView.Close()
    shownKey = nil
    CloseNoteEditor()
    if view then
        view:Hide()
    end
    ns.Fire("ViewChanged")
end

function EventView.Shown()
    return view ~= nil and view:IsShown() and shownKey or nil
end

-- The note's window (EditNote), for the tests.
function EventView.NoteEditor()
    return noteEditor
end
