-- Options.lua: the addon's options, under Options > AddOns > Guild Raids &
-- Events (or /gevents options):
--   - Guild Raids & Events: this character's own, how long before an event
--     it is reminded (Reminders.lua), and the language of the addon's texts;
--   - Bridge characters: the guild's, shared with every member, which only
--     the guild master changes: the characters that may bring in sign-ups
--     made outside the game (API.lua). The page shows only while an addon
--     that brings them in is loaded (API.RegisterBridge).
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local PAGE_WIDTH = 620
local ROW_HEIGHT = 24
local MAX_ROWS = ns.Pack.LIMITS.bridges
local NATIVE_NAMES = {
    enUS = "English", deDE = "Deutsch", esES = "Español (España)", esMX = "Español (México)", frFR = "Français",
    itIT = "Italiano", koKR = "한국어", ptBR = "Português", ruRU = "Русский", zhCN = "简体中文", zhTW = "繁體中文",
}

local category, bridgeCategory
local pages = {}

local function Button(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(math.max(button:GetTextWidth() + 32, 90), 22)
    button:SetScript("OnClick", onClick)
    return button
end

-- A page: its heading and what it is about. page.Refresh copies the
-- options into its widgets; the settings panel calls it on showing it.
local function CreatePage(name, title, intro)
    local page = CreateFrame("Frame")
    page:Hide()
    page.Title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    page.Title:SetPoint("TOPLEFT", 16, -16)
    page.Title:SetText(title)
    page.Intro = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.Intro:SetPoint("TOPLEFT", page.Title, "BOTTOMLEFT", 0, -8)
    page.Intro:SetWidth(PAGE_WIDTH)
    page.Intro:SetJustifyH("LEFT")
    page.Intro:SetText(intro)
    page.name = name
    function page:OnRefresh()
        self:Refresh()
    end
    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)
    pages[#pages + 1] = page
    return page
end

local function Dropdown(page, anchor, label, width, generator)
    local text = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    text:SetText(label)
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    dropdown:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    dropdown:SetupMenu(generator)
    return dropdown
end

-- Guild Raids & Events: the reminder and the language --------------------------------------

local function MinutesText(minutes)
    if minutes == 0 then
        return L["No reminder"]
    end
    return L["%d |4minute:minutes; before"]:format(minutes)
end

local function CreateMainPage()
    local page = CreatePage("main", "Guild Raids & Events",
        L["The reminder and the language are this character's own. The guild's options are shared with every member, and only the guild master changes them."])
    page.Reminder = Dropdown(page, page.Intro, L["Remind me of the events I go to"], 220, function(_, root)
        for _, minutes in ipairs(ns.Reminders.CHOICES) do
            root:CreateRadio(MinutesText(minutes), function()
                return ns.Reminders.Minutes() == minutes
            end, function()
                ns.Reminders.SetMinutes(minutes)
            end)
        end
    end)
    page.Language = Dropdown(page, page.Reminder, L["Language"], 220, function(_, root)
        local function IsSelected(code)
            return code == (ns.db.settings.locale or "auto")
        end
        local function SetSelected(code)
            ns.db.settings.locale = code ~= "auto" and code or nil
            ns.SetLocale(ns.db.settings.locale)
            ns.Print(L["language set to %s."], ns.LOCALE)
        end
        root:CreateRadio(L["The client's language"], IsSelected, SetSelected, "auto")
        for _, code in ipairs(ns.LOCALES) do
            root:CreateRadio(NATIVE_NAMES[code] or code, IsSelected, SetSelected, code)
        end
    end)
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", page.Language, "BOTTOMLEFT", 0, -6)
    note:SetText(L["Texts already on screen change once shown again, or after /reload."])
    function page:Refresh()
        self.Reminder:GenerateMenu()
        self.Language:GenerateMenu()
    end
    return page
end

-- Bridge characters ---------------------------------------------------------------------------

-- Why a bridge character could not be added (Rights.AddBridge).
local function AddError(why)
    if why == "notMaster" then
        return L["Only the guild master changes the guild's options."]
    elseif why == "already" then
        return L["That character is already one."]
    elseif why == "full" then
        return L["There are as many as there can be."]
    end
    return L["No guild member has that name."]
end

local function CreateBridgePage()
    local page = CreatePage("bridges", L["Bridge characters"],
        L["Another addon can bring in sign-ups made outside the game, through these characters only: their clients add them, by the name of the guild member who signed up. Shared with the whole guild; only the guild master changes them."])
    page.Status = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    page.Status:SetPoint("TOPLEFT", page.Intro, "BOTTOMLEFT", 0, -10)
    page.Status:SetWidth(PAGE_WIDTH)
    page.Status:SetJustifyH("LEFT")
    page.Bridges = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    page.Bridges:SetPoint("TOPLEFT", page.Status, "BOTTOMLEFT", 0, -6)
    page.Bridges:SetWidth(PAGE_WIDTH)
    page.Bridges:SetJustifyH("LEFT")

    page.Name = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.Name:SetSize(200, 20)
    page.Name:SetPoint("TOPLEFT", page.Bridges, "BOTTOMLEFT", 6, -14)
    page.Name:SetAutoFocus(false)
    page.Name:SetMaxLetters(64)
    local function Add()
        local ok, why = ns.Rights.AddBridge(page.Name:GetText())
        if ok then
            page.Name:SetText("")
            page.Error:SetText("")
        else
            page.Error:SetText(AddError(why))
        end
        page:Refresh()
    end
    page.Name:SetScript("OnEnterPressed", Add)
    page.Name:SetScript("OnEscapePressed", page.Name.ClearFocus)
    page.Add = Button(page, L["Add"], Add)
    page.Add:SetPoint("LEFT", page.Name, "RIGHT", 8, 0)
    page.Error = page:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    page.Error:SetPoint("LEFT", page.Add, "RIGHT", 10, 0)

    page.Rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(360, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", page.Name, "BOTTOMLEFT", -6, -12 - (index - 1) * ROW_HEIGHT)
        row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.Name:SetPoint("LEFT", 4, 0)
        row.Name:SetWidth(240)
        row.Name:SetJustifyH("LEFT")
        row.Remove = Button(row, L["Remove"], function()
            ns.Rights.RemoveBridge(row.guid)
            page:Refresh()
        end)
        row.Remove:SetPoint("RIGHT", 0, 0)
        row:Hide()
        page.Rows[index] = row
    end

    function page:Refresh()
        local editable = ns.Rights.MayEditOptions()
        local options = ns.Rights.Options()
        local who = editable and L["You are the guild master: your changes reach every member."]
            or L["Shared with the whole guild: only the guild master can change them."]
        local when = options and L["Last changed %s ago."]:format(ns.Ago(options.t))
            or L["The guild master has not chosen any yet."]
        self.Status:SetText(who .. " " .. when)
        self.Bridges:SetText(L["Addons that bring them in: %s."]:format(table.concat(ns.Rights.bridges, ", ")))
        self.Name:SetShown(editable)
        self.Add:SetShown(editable)
        local list = ns.Rights.BridgeCharacters()
        for index, row in ipairs(self.Rows) do
            local guid = list[index]
            row.guid = guid
            row:SetShown(guid ~= nil)
            if guid then
                row.Name:SetText(ns.Events.MemberName(guid) or guid)
                row.Remove:SetShown(editable)
            end
        end
    end
    return page
end

-- The panel ------------------------------------------------------------------------------

function Options.Refresh()
    for _, page in ipairs(pages) do
        if page:IsShown() then
            page:Refresh()
        end
    end
end

-- The pages, by name, for the tests.
function Options.Page(name)
    for _, page in ipairs(pages) do
        if page.name == name then
            return page
        end
    end
end

-- The page of bridge characters, once an addon that brings sign-ups in
-- has registered.
local function AddBridgePage()
    if category and not bridgeCategory and #ns.Rights.bridges > 0 then
        bridgeCategory = Settings.RegisterCanvasLayoutSubcategory(category, CreateBridgePage(), L["Bridge characters"])
    end
end

function Options.Init()
    if category or not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    category = Settings.RegisterCanvasLayoutCategory(CreateMainPage(), "Guild Raids & Events")
    AddBridgePage()
    Settings.RegisterAddOnCategory(category)
    ns.On("BridgesChanged", AddBridgePage)
    -- The guild master's changes, or a new roster, while a page shows.
    ns.On("DataChanged", function()
        ns.Debounce("OptionsRefresh", 0.3, Options.Refresh)
    end)
    ns.On("RosterUpdated", function()
        ns.Debounce("OptionsRefresh", 0.3, Options.Refresh)
    end)
end

function Options.Open()
    -- Settings.OpenToCategory may go through a restricted call on this
    -- client, so success is checked a moment later.
    local ok = category and pcall(Settings.OpenToCategory, category:GetID())
    C_Timer.After(0.3, function()
        if not ok or not (SettingsPanel and SettingsPanel:IsShown()) then
            ns.Print(L["open the game menu, then Options > AddOns > Guild Raids & Events."])
        end
    end)
end
