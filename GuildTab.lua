-- GuildTab.lua: a "Raids & Events" tab on the guild window, under Blizzard's
-- own side tabs (Chat, Roster, Guild Info...). Its subtabs list the
-- upcoming events, those of the last week and the cancelled ones
-- (EventList.lua); a click on one opens it (EventView.lua). Under the list:
-- New event (EventForm.lua), and in Cancelled, Clear cancelled.
--
-- It only hooks and reads Blizzard's frames. It never changes the guild
-- window's display mode, which would taint the window. Instead, it makes
-- Blizzard's view invisible while its panel is open, and closes as soon as
-- one of Blizzard's tabs is clicked.
--
-- Other addons' panels on the guild window. Every addon that adds a side
-- tab with a panel like this one registers in the shared list
-- GuildWindowAddonPanels: { { id, order, tab, Close }... }. Opening a
-- panel closes the others (Close returns the Blizzard tab that was
-- selected before them), and each tab goes under those of a lower order
-- (Guild Professions & Recipes is 10, Guild Bank Alts 20, this addon 30).
-- No addon needs the others: alone, each works the same.
local _, ns = ...
local L = ns.L

local GuildTab = {}
ns.GuildTab = GuildTab

local UI = ns.UI

local ID, ORDER = "GuildRaidsEvents", 30
local PANELS = "GuildWindowAddonPanels"
local ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
local TAB_GAP = 20          -- between Blizzard's tabs
local TAB_LEVEL = 510       -- Blizzard's tabs' frame level
local PAGE_LEVEL = 1250     -- over everything in the content (the chat's edit box is at 1200)
-- Blizzard's tabs, top to bottom.
local BLIZZARD_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }

local communities, tab, page
local microMark      -- on the micro menu's button (CreateMicroMark)
local remembered     -- the Blizzard tab that was selected when our panel opened
local hiddenChatBar  -- the chat's scroll bar, while our panel hides it
local faded = {}     -- [Blizzard frame] = its alpha, while our panel hides it
local SUBTABS = { "upcoming", "past", "cancelled" }
local selected = 1

-- The shared list -------------------------------------------------------------------

local function Panels()
    local panels = _G[PANELS]
    if type(panels) ~= "table" then
        panels = {}
        _G[PANELS] = panels
    end
    return panels
end

-- The tab ours goes under: another addon's of a lower order (the highest
-- of them), or the lowest of Blizzard's shown.
local function TabAbove()
    local above, aboveOrder
    for _, entry in ipairs(Panels()) do
        if entry.id ~= ID and type(entry.order) == "number" and entry.order < ORDER and entry.tab
                and (not aboveOrder or entry.order > aboveOrder) then
            above, aboveOrder = entry.tab, entry.order
        end
    end
    return above
end

-- Subtabs ---------------------------------------------------------------------------

local function UpdateSubTabs()
    local unseen = UI.Waiting()
    local texts = {
        unseen > 0 and ("%s (%d)"):format(L["Upcoming"], unseen) or L["Upcoming"],
        L["Last week"],
        L["Cancelled events"],
    }
    for i, subtab in ipairs(page.SubTabs.Tabs) do
        subtab:SetText(texts[i])
        PanelTemplates_TabResize(subtab, 0)
    end
    PanelTemplates_SetTab(page.SubTabs, selected)
end

local UpdateBadge

-- The buttons under the list are as the game's at the bottom of the guild
-- window (Guild Settings, Invite Member): 20 high, at least 130 wide, 2
-- apart, 5 from the window's corner.
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP, BUTTON_PADDING, BUTTON_INSET = 130, 20, 2, 40, 5

local function SizeAsTheGame(button)
    button:SetSize(math.max(BUTTON_WIDTH, math.ceil(button:GetTextWidth()) + BUTTON_PADDING), BUTTON_HEIGHT)
end

-- Under the list, on the right as the game's and the other guild tabs'
-- buttons: New event, always there (off, with why, while the game's
-- calendar does not let the player add events yet), Clear cancelled to its
-- left; on the left, why the calendar refused the last change.
local function UpdateButtons()
    local viewing = ns.EventView.Shown() ~= nil
    local reason
    if not ns.Rights.MayCreate() then
        reason = L["Syncing the calendar..."]
    elseif ns.Calendar.AtLimit() then
        reason = ns.Calendar.LimitText()
    end
    page.New:SetShown(not viewing)
    page.New:SetEnabled(reason == nil)
    page.New.reason = reason
    page.Clear:SetShown(not viewing and SUBTABS[selected] == "cancelled" and #ns.EventList.Cancelled() > 0)
    page.Clear:ClearAllPoints()
    if page.New:IsShown() then
        page.Clear:SetPoint("RIGHT", page.New, "LEFT", -BUTTON_GAP, 0)
    else
        page.Clear:SetPoint("BOTTOMRIGHT", page.New, "BOTTOMRIGHT")
    end
    local first = page.Clear:IsShown() and page.Clear or page.New:IsShown() and page.New or nil
    page.Hint:ClearAllPoints()
    page.Hint:SetPoint("LEFT", page.Content, "BOTTOMLEFT", 4, -15)
    if first then
        page.Hint:SetPoint("RIGHT", first, "LEFT", -8, 0)
    else
        page.Hint:SetPoint("RIGHT", page.Content, "BOTTOMRIGHT", 0, -15)
    end
    page.Hint:SetText(ns.Calendar.lastError or "")
end

local function RefreshPage()
    if not page or not page:IsShown() then
        return
    end
    UpdateSubTabs()
    UpdateBadge()
    UpdateButtons()
    local viewing = ns.EventView.Shown() ~= nil
    page.List:SetShown(not viewing)
    page.SubTabs:SetShown(not viewing)
    if viewing then
        ns.EventView.Refresh()
    else
        ns.EventList.Show(page.List, SUBTABS[selected])
    end
end
GuildTab.Refresh = RefreshPage

local function SelectSubTab(index)
    if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end
    selected = index
    RefreshPage()
end

-- Above the window's inset, where Guild Info has its headings.
local function CreateSubTabs()
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints(page.Content)
    local tabs = {}
    for i in ipairs(SUBTABS) do
        local subtab = CreateFrame("Button", nil, holder, "PanelTopTabButtonTemplate")
        subtab:SetID(i)
        if i == 1 then
            subtab:SetPoint("BOTTOMLEFT", page.Content, "TOPLEFT", 4, -2)
        else
            subtab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 2, 0)
        end
        subtab:SetScript("OnClick", function(self)
            SelectSubTab(self:GetID())
        end)
        tabs[i] = subtab
    end
    holder.Tabs = tabs
    PanelTemplates_SetNumTabs(holder, #tabs)
    page.SubTabs = holder
end

-- The panel ------------------------------------------------------------------------

-- Blizzard's view is made invisible while our panel is open (SetAlpha runs
-- none of its code), so the window's own background, inset and borders show
-- around our panel exactly as in its other tabs. These are every piece its
-- views show, but the communities list.
local function ContentFrames()
    local names = { PostingExpirationText = true }
    for _, mode in pairs(COMMUNITIES_FRAME_DISPLAY_MODES or {}) do
        for _, name in ipairs(mode) do
            names[name] = true
        end
    end
    names.CommunitiesList, names.CommunitiesListDropdown = nil, nil
    local list = {}
    for name in pairs(names) do
        local subframe = communities[name]
        if type(subframe) == "table" and subframe.SetAlpha then
            list[#list + 1] = subframe
        end
    end
    return list
end

local function FadeContent()
    for _, subframe in ipairs(ContentFrames()) do
        if faded[subframe] == nil then
            faded[subframe] = subframe:GetAlpha()
            subframe:SetAlpha(0)
        end
    end
end

local function RestoreContent()
    for subframe, alpha in pairs(faded) do
        subframe:SetAlpha(alpha)
    end
    wipe(faded)
end

-- restore: put back the selection on Blizzard's tab that was selected; not
-- when one of Blizzard's tabs was just clicked, which marks itself, nor
-- when another addon's panel takes over.
local function HidePage(restore)
    if not page:IsShown() then
        return
    end
    page:Hide()
    tab:SetChecked(false)
    if restore and remembered then
        remembered:SetChecked(true)
    end
    remembered = nil
    if hiddenChatBar then
        hiddenChatBar:Show()
        hiddenChatBar = nil
    end
    RestoreContent()
end

-- For the shared list: closes our panel for another addon's, and gives it
-- the Blizzard tab that was selected before ours.
local function Close()
    if not page or not page:IsShown() then
        return nil
    end
    local before = remembered
    HidePage(false)
    return before
end

local function ShowPage()
    if page:IsShown() then
        return
    end
    remembered = nil
    for _, entry in ipairs(Panels()) do
        if entry.id ~= ID and type(entry.Close) == "function" then
            local ok, before = pcall(entry.Close)
            remembered = remembered or (ok and before or nil)
        end
    end
    for _, key in ipairs(BLIZZARD_TABS) do
        local other = communities[key]
        if other then
            if other:GetChecked() then
                remembered = remembered or other
            end
            other:SetChecked(false)
        end
    end
    tab:SetChecked(true)
    FadeContent()
    -- The chat's scroll bar is on a higher layer (HIGH strata) than the
    -- whole window: invisible with the chat, it would still take clicks.
    local chatBar = communities.Chat and communities.Chat.ScrollBar
    if chatBar and chatBar:IsShown() then
        chatBar:Hide()
        hiddenChatBar = chatBar
    end
    page:Show()
    RefreshPage()
end

local function CreatePage()
    -- It draws nothing of its own: it holds our frames and keeps the mouse
    -- off Blizzard's invisible view, from right of the communities list's
    -- scroll bar to the window's edges.
    page = CreateFrame("Frame", "GuildRaidsEventsGuildPanel", communities)
    page:SetFrameLevel(PAGE_LEVEL)
    page:SetPoint("TOPLEFT", communities.CommunitiesList, "TOPRIGHT", 18, 0)
    page:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -4, 4)
    page:EnableMouse(true)

    -- Inside the window's inset, where the game puts its Guild Info panel.
    page.Content = CreateFrame("Frame", nil, page)
    page.Content:SetPoint("TOPLEFT", communities.CommunitiesList, "TOPRIGHT", 24, -40)
    page.Content:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -12, 30)

    page.List = ns.EventList.Create(page.Content)
    page.View = ns.EventView.Create(page.Content)
    CreateSubTabs()

    -- Under the inset, where Guild Info has its buttons.
    page.New = UI.Button(page, L["New event"], function()
        ns.EventForm.Open(nil)
    end)
    SizeAsTheGame(page.New)
    page.New:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
    UI.SetTooltip(page.New, L["New event"], function(self)
        return self.reason
    end)
    page.Clear = UI.Button(page, L["Clear cancelled"], function()
        UI.Clear(ns.EventList.Cancelled())
        RefreshPage()
    end)
    SizeAsTheGame(page.Clear)
    UI.SetTooltip(page.Clear, L["Clear"], L["Deletes your cancelled events, for everyone; the others' leave only your list."])
    page.Hint = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.Hint:SetPoint("LEFT", page.Content, "BOTTOMLEFT", 4, -15)
    page.Hint:SetPoint("RIGHT", page.New, "LEFT", -8, 0)
    page.Hint:SetJustifyH("LEFT")
    page:Hide()
end

-- The tab ---------------------------------------------------------------------------

-- The notification mark (UI.NewMark): while upcoming events wait for the
-- player, not seen nor answered (UI.Waiting). On our tab, and on the micro
-- menu's button that opens the guild window.
function UpdateBadge()
    local shown = UI.Waiting() > 0
    if tab then
        tab.Badge:SetShown(shown)
    end
    if microMark then
        microMark:SetShown(shown)
    end
end

-- The mark on the micro menu's Guild & Communities button, as the game
-- shows its own there (unread messages, invitations): of its template, on
-- a frame of our own, which the game's updates leave alone.
local function CreateMicroMark()
    if GuildMicroButton then
        microMark = CreateFrame("Frame", nil, GuildMicroButton, "MainMenuBarMicroButtonNotificationTemplate")
        microMark:Hide()
    end
end

function GuildTab.UpdateMarks()
    if page and page:IsShown() then
        UpdateSubTabs()
        UpdateButtons()
        -- Whether the game's calendar takes the player's answer, or a new
        -- event, now.
        ns.EventView.UpdateControls()
        if not ns.EventView.Shown() then
            ns.EventList.Show(page.List, SUBTABS[selected])
        end
    end
    UpdateBadge()
end

-- Runs after Blizzard lays out its tabs. Ours goes under the lowest one
-- (or another addon's), and only while Guild Info shows: on the guild, in
-- the views with tabs.
local function Update()
    local last
    for _, key in ipairs(BLIZZARD_TABS) do
        local other = communities[key]
        if other and other:IsShown() then
            last = other
        end
    end
    local guildInfo = communities.GuildInfoTab
    local show = last ~= nil and guildInfo ~= nil and guildInfo:IsShown()
    tab:SetShown(show)
    if show then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", TabAbove() or last, "BOTTOMLEFT", 0, -TAB_GAP)
    else
        HidePage(true)
    end
end

local function Setup()
    communities = CommunitiesFrame
    if tab or not (communities and communities.UpdateCommunitiesTabs and communities.CommunitiesList) then
        return
    end
    CreatePage()
    tab = CreateFrame("CheckButton", "GuildRaidsEventsGuildTab", communities, "RightSideTabTemplate")
    tab:SetFrameLevel(TAB_LEVEL)
    tab.Icon:SetTexture(ICON)
    tab.tooltip = L["Raids & Events"]
    tab.Badge = UI.NewMark(tab)
    -- After the template's own click (its sound, and marking itself).
    tab:HookScript("OnClick", ShowPage)
    tab:Hide()
    table.insert(Panels(), { id = ID, order = ORDER, tab = tab, Close = Close })
    hooksecurefunc(communities, "UpdateCommunitiesTabs", Update)
    -- One of Blizzard's tabs was clicked (or the window changed its view).
    hooksecurefunc(communities, "SetDisplayMode", function()
        HidePage(false)
    end)
    -- A secure hook of the window's own OnHide (its XML calls the method by
    -- name), never HookScript: a hooked script runs in the same execution
    -- as the scripts of the window's children that follow it, and taints
    -- them (the roster's rows, from which the game then refuses to change a
    -- member's notes or rank).
    if type(communities.OnHide) == "function" then
        hooksecurefunc(communities, "OnHide", function()
            HidePage(true)
        end)
    end
    Update()
    UpdateBadge()
end

function GuildTab.Init()
    -- The micro menu's mark from the start; the tab once the guild window
    -- is loaded (when first opened).
    CreateMicroMark()
    local function Refresh()
        ns.Debounce("GuildTabRefresh", 0.3, function()
            UpdateBadge()
            RefreshPage()
        end)
    end
    ns.On("EventsChanged", Refresh)
    ns.On("ViewChanged", RefreshPage)
    ns.On("MarksChanged", function()
        ns.Debounce("GuildTabMarks", 0.1, GuildTab.UpdateMarks)
    end)
    ns.On("CalendarPending", function()
        ns.Debounce("GuildTabMarks", 0.1, GuildTab.UpdateMarks)
    end)
    UpdateBadge()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
