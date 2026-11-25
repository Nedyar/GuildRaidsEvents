-- EventList.lua: the list of the guild's events in the Raids & Events tab
-- (GuildTab.lua): upcoming ones, the soonest first, or those of the last
-- week, the latest first. Each row: the event type's icon, the title, when
-- it is, its type and organizer, how many signed up in each role, and the
-- player's answer. The notification mark shows on the rows of upcoming
-- events the player had not seen when the tab opened, until they point at
-- the row or answer; showing a row sees it. A click on a row opens the
-- event (EventView.lua).
local _, ns = ...
local L = ns.L

local EventList = {}
ns.EventList = EventList

local Events, UI = ns.Events, ns.UI

local ROW_HEIGHT = 50

-- The events whose rows showed them new (not seen) since the tab opened:
-- [key] = true. They keep the mark until it opens again.
local marked = {}

function EventList.ForgetMarks()
    wipe(marked)
end

-- The places of a role in a count: "3/5", or "3" with no limit.
local function Places(count, places)
    if places then
        return ("%d/%d"):format(count, places)
    end
    return tostring(count)
end

function EventList.CountsText(event, signUps)
    local counts = Events.Counts(signUps)
    local parts = {}
    for role = Events.TANK, Events.DAMAGE do
        local places = event.sl and event.sl[Events.ROLE_FIELD[role]]
        parts[#parts + 1] = ("%s %s"):format(UI.RolesName(role), Places(counts[role], places))
    end
    return table.concat(parts, "  ·  ")
end

-- The player's one state in the event, as the game names it: "Confirmed",
-- "Not signed up"...
function EventList.MineText(mine)
    return UI.StateText(mine)
end

local function CreateRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(38, 38)
    row.Icon:SetPoint("LEFT", 6, 0)
    row.Mark = UI.NewMark(row, -6, -6)
    row.Mark:ClearAllPoints()
    row.Mark:SetPoint("CENTER", row.Icon, "TOPRIGHT", -2, -2)
    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, 0)
    row.Title:SetPoint("RIGHT", -170, 0)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)
    row.When = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.When:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    row.When:SetPoint("RIGHT", -170, 0)
    row.When:SetJustifyH("LEFT")
    row.When:SetWordWrap(false)
    row.Counts = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Counts:SetPoint("TOPLEFT", row.When, "BOTTOMLEFT", 0, -3)
    row.Counts:SetPoint("RIGHT", -30, 0)
    row.Counts:SetJustifyH("LEFT")
    row.Counts:SetWordWrap(false)
    row.Mine = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Mine:SetPoint("TOPRIGHT", -10, -6)
    row.Mine:SetWidth(160)
    row.Mine:SetJustifyH("RIGHT")
    row.Mine:SetWordWrap(false)
    -- Next week's event of a weekly one, not in the calendar yet: its button.
    row.Send = UI.Button(row, L["Create in calendar"], function()
        if row.event then
            ns.Calendar.SendNow(row.event.key)
        end
    end)
    row.Send:SetHeight(20)
    row.Send:SetFrameLevel(row:GetFrameLevel() + 2)
    row.Send:SetPoint("BOTTOMRIGHT", -6, 4)
    UI.SetTooltip(row.Send, function(self)
        return self:GetText()
    end, function(self)
        return self.reason
    end)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("PetList-ButtonHighlight")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    row:EnableMouse(true)
    -- Pointed at, it is new no more: its mark goes.
    row:SetScript("OnEnter", function(self)
        if self.event and marked[self.event.key] then
            marked[self.event.key] = nil
            self.Mark:Hide()
        end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.event then
            ns.EventView.Open(self.event.key)
        end
    end)
end

local function InitRow(row, element)
    if not row.Title then
        CreateRow(row)
    end
    local event = element.event
    row.event = event
    local signUps = Events.SignUps(event)
    row.Icon:SetTexture(UI.TYPE_ICONS[event.ty])
    row.Title:SetText(UI.EventTitle(event))
    row.When:SetText(L["%s  ·  %s  ·  by %s"]:format(UI.DateText(event.tm), UI.KindText(event),
        Events.MemberName(event.owner) or "?"))
    row.Counts:SetText(EventList.CountsText(event, signUps))
    local mine = Events.Mine(event, signUps)
    row.Mine:SetText(EventList.MineText(mine))
    local unsent = ns.Calendar.Unsent(event)
    local blocked = unsent and ns.Calendar.SendBlocked() or nil
    row.Send:SetShown(unsent)
    row.Send:SetEnabled(unsent and not blocked)
    row.Send.reason = blocked or L["Not in the game's calendar yet: this click creates it there."]
    row.Counts:SetPoint("RIGHT", unsent and row.Send or row, unsent and "LEFT" or "RIGHT", unsent and -6 or -30, 0)
    -- Shown, so seen: the mark goes from the tab at once, and stays on the
    -- row while the tab stays open, until it is pointed at or answered.
    if UI.IsUnseen(event) then
        marked[event.key] = true
    end
    row.Mark:SetShown(marked[event.key] == true and mine == nil)
    if UI.MarkSeen(event.key) then
        ns.Fire("MarksChanged")
    end
end

function EventList.Create(parent)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints()
    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 2)
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    list.ScrollBox = scrollBox
    list.Empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.Empty:SetPoint("CENTER")
    return list
end

-- The events a list shows: which, "upcoming" or "past".
function EventList.Events(which)
    return Events.List(which)
end

function EventList.Show(list, which)
    local elements = {}
    for _, event in ipairs(EventList.Events(which)) do
        elements[#elements + 1] = { event = event }
    end
    list.ScrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    list.Empty:SetText(which == "past" and L["No events in the last week."] or L["No upcoming events."])
    list.Empty:SetShown(#elements == 0)
    list.elements = elements
end

-- The rows' initializer, for the tests.
EventList.InitRow = InitRow
