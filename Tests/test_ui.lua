-- The Raids & Events tab on the guild window (GuildTab.lua), its list,
-- an event's view and the form, on the harness's stand-in for Blizzard's
-- guild window; and the rules that keep Blizzard's frames untainted.
local H = ...

local world = H.NewWorld({ seed = 27, senderFormat = "short", strictWhispers = true, communities = H.FakeCommunities })
world.officerRanks = { [1] = true }
local organizer = world:NewClient("Organizer Name", { rank = "Officer", rankIndex = 1 })
local member = world:NewClient("Member Name", { rank = "Member", rankIndex = 3, level = 60 })
for _, client in ipairs({ organizer, member }) do
    world:Login(client)
    world:RunFor(5)
end
world:RunFor(60)

local function Errors(label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end
Errors("logging in")

local function Tab(client)
    return client.env.GuildRaidsEventsGuildTab
end

local function Page(client)
    return client.env.GuildRaidsEventsGuildPanel
end

H.section("UI: the tab")
local communities = organizer.env.CommunitiesFrame
local tab = Tab(organizer)
H.check(tab ~= nil, "a tab on the guild window")
local panels = organizer.env.GuildWindowAddonPanels
H.check(panels and #panels == 1 and panels[1].id == "GuildRaidsEvents" and panels[1].order == 30 and panels[1].tab == tab,
    "registered in the shared list, order 30")
communities.UpdateCommunitiesTabs(communities)
H.check(tab:IsShown(), "shown while Guild Info shows")
H.check(tab._point and tab._point[2] == communities.GuildInfoTab and tab._point[5] == -20,
    "20 below the last of Blizzard's tabs, alone")
-- Another addon's tab of a lower order goes above ours.
local other = H.NewObject(organizer, "CheckButton")
table.insert(panels, { id = "Other", order = 20, tab = other, Close = function() return nil end })
communities.UpdateCommunitiesTabs(communities)
H.check(tab._point and tab._point[2] == other, "under another addon's tab of a lower order")
table.remove(panels, 2)
communities.UpdateCommunitiesTabs(communities)

H.section("UI: the panel")
local ns = organizer.ns
local key = ns.Events.Create({ ty = 0, ti = "Molten Core", tm = ns.Events.Now() + 2 * 86400, ml = 50, sl = { t = 1, h = 2, d = 3 } })
world:RunFor(5)
organizer.inClick = true
ns.Calendar.SendNow(key)
organizer.inClick = false
world:RunFor(30)
H.check(Tab(member).Badge:IsShown(), "the member's tab has the notification mark: an event not seen")
H.check(member.env.GuildMicroButton and true, "the micro menu's button is there")
local memberPage = Page(member)
H.Click(Tab(member))
H.check(memberPage:IsShown() and Tab(member):GetChecked(), "a click on the tab opens the panel")
H.eq(member.env.CommunitiesFrame.MemberList:GetAlpha(), 0, "Blizzard's view is made invisible")
H.eq(member.env.CommunitiesFrame.displayMode, "Roster", "the window's display mode is left as it was")
local list = memberPage.List
H.eq(#list.elements, 1, "the list shows the upcoming event")
local row = {}
setmetatable(row, getmetatable(H.NewObject(member, "Frame")))
for k, v in pairs(H.NewObject(member, "Frame")) do
    row[k] = v
end
member.ns.EventList.InitRow(row, list.elements[1])
H.check(row.Title:GetText() == "Molten Core", "a row has the title")
H.check(row.Mine:GetText():find("Not signed up", 1, true) ~= nil, "and the player's state")
H.check(row.Mark:IsShown(), "the mark on the row of an event not seen")
world:RunFor(2)
H.check(not Tab(member).Badge:IsShown(), "seen: the tab's mark goes")
member.ns.EventList.InitRow(row, list.elements[1])
H.check(row.Mark:IsShown(), "its row keeps the mark while the tab stays open: what is new shows")
row._scripts.OnEnter(row)
H.check(not row.Mark:IsShown(), "pointed at, its mark goes")
member.ns.EventList.InitRow(row, list.elements[1])
H.check(not row.Mark:IsShown(), "and stays gone")
member.ns.EventList.ForgetMarks()
member.ns.EventList.InitRow(row, list.elements[1])
H.check(not row.Mark:IsShown(), "the tab opened again, it is new no more")

H.section("UI: an event")
-- A column's names as its list shows them: a frame for each, made by the
-- column's own initializer (the test world makes none by itself).
local function Names(someView, role)
    local column = someView.Columns[role]
    local frames = {}
    for _, element in ipairs(column.ScrollBox._provider and column.ScrollBox._provider.elements or {}) do
        local frame = H.NewObject(someView._client, "Button")
        column.ScrollBox._view.init(frame, element)
        frames[#frames + 1] = frame
    end
    return frames
end
member.ns.EventView.Open(key)
world:RunFor(1)
local view = memberPage.View
H.check(view:IsShown() and not list:IsShown(), "a row's click opens the event in place of the list")
H.check(view.Title:GetText() == "Molten Core", "with its title")
H.check(not view.Edit:IsShown() and not view.Delete:IsShown(), "a member does not manage it")
member.level = 40
member.ns.EventView.Refresh()
H.check(not view.SignUp:IsEnabled() and view.SignUp.reason ~= nil, "below its minimum level, the member cannot sign up")
H.check(view.SignUp:IsShown() and view.Tentative:IsShown() and view.Role:IsShown() and view.Note:IsShown()
    and not view.Remove:IsShown(), "not signed up: their role, a note, Sign up and Tentative, nothing else")
H.check(view.SignUp._point[2] == view.Tentative and view.Tentative._point[1] == "BOTTOMRIGHT",
    "the buttons on the right")
H.check(view.Note._point[1] == "RIGHT" and view.Note._point[2] == view.SignUp, "the note's box as wide as there is room, up to them")
member.level = 60
member.ns.EventView.Refresh()
H.check(view.SignUp:IsEnabled(), "at the level, they can")
local roles = H.MenuOf(view.Role)
H.MenuEntry(roles, "Healer").setSelected()
view.Note:SetText("late 10 min")
H.Click(view.SignUp)
world:RunFor(30)
local mine = member.ns.Events.Mine(member.ns.Events.Get(key))
H.check(mine and mine.st == 1 and mine.ro == 2 and mine.no == "late 10 min", "Sign up, as healer, with the note")
H.eq(member.ns.Roles.Default(), 2, "the role picked is their default from now on, with that specialization")
member.ns.EventView.Refresh()
H.check(Names(view, 2)[1]:IsShown() and Names(view, 2)[1].Text:GetText():find("Member Name", 1, true),
    "the member shows in the healers' column")
H.check(Names(view, 2)[1].Text:GetText():find("(Signed up)", 1, true) ~= nil,
    "with their state by the name, signed up too, as every other state")
H.check(view.Remove:IsShown() and not view.SignUp:IsShown() and not view.Role:IsShown() and not view.Note:IsShown(),
    "signed up: only Remove sign-up under the columns")
H.check(view.Remove._point[1] == "BOTTOM", "in the middle")
local nameButton = Names(view, 2)[1]
nameButton:GetScript("OnEnter")(nameButton)
local tipLines = member.env.GameTooltip._lines
local function HasLine(lines, text)
    for _, line in ipairs(lines) do
        if line == text then
            return true
        end
    end
    return false
end
H.check(HasLine(tipLines, "Note: late 10 min"), "pointing at the name shows the note, after \"Note:\"")
H.check(HasLine(tipLines, "Right-click for its menu.") and HasLine(tipLines, "Drag it to another column to change its role."),
    "and, being their own, that they may change its role")
-- A long note with no spaces was cut short with "..." in the tooltip: a
-- word wider than a line goes whole on a line of its own, and the tooltip
-- widens to it (the tests measure 6 pixels a byte, so 36 in 220).
local NoteLines = member.ns.EventView.NoteLines
local digits = ("1234567890"):rep(6)
local wide = NoteLines("late " .. digits .. " ok")
H.check(#wide == 3 and wide[1] == "late" and wide[2] == digits and wide[3] == "ok",
    "a word wider than a line goes whole on its own line, nothing cut")
local words = NoteLines("I will be a bit late tonight, start without me please")
H.check(#words == 2 and words[1] == "I will be a bit late tonight, start" and words[2] == "without me please",
    "a note with spaces breaks between words")
local tooltip = member.env.GameTooltip
local addLine = tooltip.AddLine
local wrapped = {}
tooltip.AddLine = function(self, text, r, g, b, wrap)
    wrapped[text] = wrap
    return addLine(self, text)
end
member.ns.Events.Answer(key, 1, 2, digits)
member.ns.EventView.Refresh()
nameButton = Names(view, 2)[1]
nameButton:GetScript("OnEnter")(nameButton)
tooltip.AddLine = addLine
H.check(HasLine(tooltip._lines, digits) and not wrapped[digits],
    "in the tooltip, whole and unwrapped: the tooltip widens to it")
H.Click(view.Back)
H.check(not view:IsShown() and list:IsShown(), "Back shows the list again")

H.section("UI: the organizer manages the event")
local page = Page(organizer)
H.Click(tab)
ns.EventView.Open(key)
world:RunFor(1)
local orgView = page.View
H.check(orgView.Edit:IsShown() and orgView.Delete:IsShown(), "the organizer may change and delete it")
H.check(orgView.Delete:GetText() == "Delete event" and orgView.Delete._point[2] == orgView.Back
    and orgView.Edit._point[2] == orgView.Delete, "Delete event left of Back, Edit left of it")
local healer = Names(orgView, 2)[1]
H.check(healer.signUp ~= nil and healer.signUp.guid == member.guid, "the member's sign-up is in the healers' column")
organizer.contextMenu = nil
H.Click(healer)
H.eq(organizer.contextMenu, nil, "a left click opens nothing")
H.Click(healer, "RightButton")
local menu = organizer.contextMenu
H.check(menu ~= nil and H.MenuEntry(menu, "Confirmed") ~= nil, "a right-click on it opens its menu of statuses")
H.MenuEntry(menu, "Confirmed").setSelected()
world:RunFor(30)
local seen = member.ns.Events.Mine(member.ns.Events.Get(key))
H.eq(seen.status, 1, "the member is confirmed, for everyone")
H.Click(healer, "RightButton")
menu = organizer.contextMenu
H.check(H.MenuEntry(menu, "Set moderator") ~= nil, "the menu also names a moderator, as the game's calendar does")
H.MenuEntry(menu, "Set moderator").callback()
world:RunFor(30)
H.check(member.ns.Rights.MayIManage(member.ns.Events.Get(key)), "named: the member manages the event")
ns.EventView.Refresh()
H.check(Names(orgView, 2)[1].Text:GetText():find("UI-Group-AssistantIcon", 1, true) ~= nil,
    "marked as the game's calendar marks its moderators")
H.Click(healer, "RightButton")
H.MenuEntry(organizer.contextMenu, "Clear moderator").callback()
world:RunFor(30)
H.check(not member.ns.Rights.MayIManage(member.ns.Events.Get(key)), "taken back: no longer")
H.check(ns.Events.SetStatus(key, member.guid, ns.Events.OUT), "the organizer leaves them out")
world:RunFor(1)
ns.EventView.Refresh()
local inColumns = false
for role in ipairs(orgView.Columns) do
    for _, name in ipairs(Names(orgView, role)) do
        if name:IsShown() and name.signUp and name.signUp.guid == member.guid then
            inColumns = true
        end
    end
end
H.check(not inColumns and orgView.Others:GetText():find("|Hgre:" .. member.guid, 1, true) ~= nil,
    "left out: not among those who go, but in the Out line, as a link")
world:RunFor(30)
member.ns.EventView.Open(key)
H.check(not view.SignUp:IsShown() and view.Remove:IsShown() and view.Remove:IsEnabled(),
    "the member left out stays in its list, as in the game: they only remove their sign-up")
organizer.contextMenu = nil
orgView._scripts.OnHyperlinkClick(orgView, "gre:" .. member.guid, "Member Name", "LeftButton")
H.eq(organizer.contextMenu, nil, "a left click on the name there opens nothing")
orgView._scripts.OnHyperlinkClick(orgView, "gre:" .. member.guid, "Member Name", "RightButton")
H.check(organizer.contextMenu ~= nil and H.MenuEntry(organizer.contextMenu, "Confirmed") ~= nil,
    "a right-click on the name there opens its menu of statuses")
H.MenuEntry(organizer.contextMenu, "Confirmed").setSelected()
world:RunFor(30)
H.eq(member.ns.Events.Mine(member.ns.Events.Get(key)).status, 1, "confirmed again")
local function MineOf(client)
    return client.ns.Events.Mine(client.ns.Events.Get(key))
end
-- The organizer gives themselves a status from their own name's menu (in a
-- column, or in the Out line).
local function OwnStatus(status)
    ns.EventView.Refresh()
    organizer.contextMenu = nil
    for role in ipairs(orgView.Columns) do
        for _, name in ipairs(Names(orgView, role)) do
            if name:IsShown() and name.signUp and name.signUp.guid == organizer.guid then
                H.Click(name, "RightButton")
            end
        end
    end
    if not organizer.contextMenu then
        orgView._scripts.OnHyperlinkClick(orgView, "gre:" .. organizer.guid, "Organizer Name", "RightButton")
    end
    H.MenuEntry(organizer.contextMenu, status).setSelected()
    world:RunFor(2)
    ns.EventView.Refresh()
end
local function DamageName(guid)
    for _, name in ipairs(Names(orgView, 3)) do
        if name:IsShown() and name.signUp and name.signUp.guid == guid then
            return name
        end
    end
end
ns.EventView.Refresh()
H.check(not orgView.SignUp:IsShown() and not orgView.Tentative:IsShown() and not orgView.Remove:IsShown()
    and not orgView.Role:IsShown() and not orgView.Note:IsShown(),
    "nothing under the columns for the organizer, whom the game keeps in their event")
OwnStatus("Tentative")
H.check(ns.States.IsTentative(MineOf(organizer)) and DamageName(organizer.guid) ~= nil,
    "Tentative from their own name's menu: still in their role's column, as tentative")
H.check(DamageName(organizer.guid).Text:GetText():find("(Tentative)", 1, true) ~= nil, "with their state by the name")
OwnStatus("Confirmed")
local own = MineOf(organizer)
H.check(own.st == 1 and own.status == 1 and ns.States.Goes(own), "then Confirmed: signed up and confirmed")
H.check(DamageName(organizer.guid) ~= nil, "back in their role's column")
organizer.contextMenu = nil
for _, name in ipairs(Names(orgView, 2)) do
    if name:IsShown() and name.signUp and name.signUp.guid == member.guid then
        H.Click(name, "RightButton")
    end
end
H.MenuEntry(organizer.contextMenu, "Tentative").setSelected()
world:RunFor(30)
H.check(ns.States.IsTentative(MineOf(member)), "a member made tentative by the organizer is tentative for everyone")
member.ns.EventView.Open(key)
H.check(view.Remove:IsShown() and view.Remove:IsEnabled() and not view.SignUp:IsShown(),
    "made tentative, the member only removes their sign-up, as in the game")
H.Click(view.Remove)
member.ns.EventView.Refresh()
H.check(view.SignUp:IsShown() and not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled()
    and view.SignUp.reason == "Syncing the calendar...",
    "right after removing it, not signing up again while the game's calendar still has it")
world:RunFor(30)
H.eq(MineOf(member), nil, "removed")
H.check(member.ns.Calendar.HiddenFromMe(member.ns.Events.Get(key)), "the event left the member's calendar, as the game does")
member.ns.EventView.Refresh()
H.check(view.SignUp:IsShown() and not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled() and not view.Remove:IsShown(),
    "so they see Sign up and Tentative again, but cannot answer yet")
H.eq(view.SignUp.reason, "Wait for the event to show again in your calendar (about an hour after removing your sign-up, or when you log in again).", "and the buttons say to wait")
world:ShowHidden()
world:RunFor(15)
H.check(view.SignUp:IsEnabled() and view.Tentative:IsEnabled(), "back in their calendar: they answer again")
H.Click(view.SignUp)
world:RunFor(30)
H.check(MineOf(member).st == 1 and ns.States.Goes(MineOf(member)) and (MineOf(member).status == 0 or MineOf(member).auto),
    "signing up again after it: signed up, with no status of the organizer's, as in the game")
OwnStatus("Out")
H.check(MineOf(organizer).status == 3 and orgView.Others:GetText():find("|Hgre:" .. organizer.guid, 1, true),
    "the organizer Out: in the Out line")
OwnStatus("Confirmed")
H.check(MineOf(organizer).status == 1 and ns.States.Goes(MineOf(organizer)), "Confirmed from there: confirmed again")
OwnStatus("Tentative")
H.check(ns.States.IsTentative(MineOf(organizer)), "Tentative: tentative")
OwnStatus("Standby")
H.check(MineOf(organizer).status == 2 and ns.States.Goes(MineOf(organizer)), "Standby: on standby")
OwnStatus("Confirmed")

local sorted = ns.EventView.SortColumn({
    { st = 1, status = 2, order = 1, name = "standby" }, { st = 2, status = 0, order = 2, name = "tentative" },
    { st = 1, status = 0, order = 3, name = "signed" }, { st = 1, status = 1, order = 4, name = "confirmed" },
    { st = 1, status = 4, order = 5, name = "made tentative" }, { st = 1, status = 1, order = 6, name = "confirmed later" },
})
local names = {}
for _, one in ipairs(sorted) do
    names[#names + 1] = one.name
end
H.eq(table.concat(names, ", "), "confirmed, confirmed later, signed, tentative, made tentative, standby",
    "a column: confirmed, signed up, tentative, standby, each in the order they signed up")

H.section("UI: a locked event")
H.Click(orgView.Edit)
local form = ns.EventForm.Frame()
H.check(form.Lock ~= nil and not form.Lock:GetChecked(), "the form has the game's Lock event box, unticked")
H.check(not form.Save:IsEnabled() and form.Save.reason == "Syncing the calendar...",
    "Save is off until the form has the event open in the calendar")
world:RunFor(5)
H.check(form.Save:IsEnabled(), "then on")
form.Lock:SetChecked(true)
H.Click(form.Save)
world:RunFor(30)
H.check(ns.Events.Get(key).lk, "ticked and saved: the event is locked")
member.ns.EventView.Open(key)
H.eq(view.Title:GetText(), "Molten Core (Locked)", "its title says so, as the game's calendar does")
H.check(view.Remove:IsShown() and not view.Remove:IsEnabled(), "a member signed up cannot remove their sign-up")
H.eq(view.Remove.reason, "This event is locked: it takes no answers.", "and the button says why")
member.ns.EventList.InitRow(row, { event = member.ns.Events.Get(key) })
H.eq(row.Title:GetText(), "Molten Core (Locked)", "the list says so too")
ns.EventView.Open(key)
OwnStatus("Standby")
H.eq(MineOf(organizer).status, 2, "the organizer still changes their own state")
OwnStatus("Confirmed")
H.Click(orgView.Edit)
world:RunFor(5)
H.check(form.Lock:GetChecked(), "the form shows it locked")
form.Lock:SetChecked(false)
H.Click(form.Save)
world:RunFor(30)
member.ns.EventView.Open(key)
H.check(not member.ns.Events.Get(key).lk and view.Title:GetText() == "Molten Core" and view.Remove:IsEnabled(),
    "unlocked: members answer again")
Errors("a locked event")

H.section("UI: the form")
H.Click(orgView.Edit)
H.check(form:IsShown() and form.TitleBox:GetText() == "Molten Core", "Edit opens the form with the event")
world:RunFor(5)
form.TitleBox:SetText("Molten Core!")
H.Click(form.Save)
world:RunFor(5)
H.eq(ns.Events.Get(key).ti, "Molten Core!", "Save changes it")
H.check(not form:IsShown(), "and closes the form")
H.Click(orgView.Back)
H.check(page.New:IsShown(), "New event shows for a rank that may add guild events")
form.SetPortraitToAsset = function(self, path)
    self._portrait = path
end
H.Click(page.New)
H.check(form:IsShown() and form.TitleBox:GetText() == "", "it opens an empty form")
H.eq(form.Type._text, "Other", "an event of type Other by default")
H.eq(form._portrait, "Interface\\Calendar\\UI-Calendar-Event-Other", "the window's icon is its type's")
H.check(not form.PlaceBox:IsEnabled(), "with no place to pick")
H.Click(form.Save)
H.check(form:IsShown() and form.Error:GetText() ~= "", "without a title it says why and stays")
H.check(form.Hour._text == "21" and form.Minute._text == "00", "the time in two lists, 21:00 at first")
H.check(#H.MenuOf(form.Hour) == 24 and #H.MenuOf(form.Minute) == 12, "every hour of the day, and minutes five by five")
H.check(not form.AMPM:IsShown(), "no AM or PM with the game's 24-hour clock")
H.Click(form.DayButton)
local picker = ns.EventForm.Picker()
H.check(picker:IsShown(), "the day's button opens a month's calendar")
local pick, earlier
for _, button in ipairs(picker.Days) do
    if button:IsShown() and button.offset == 3 then
        pick = button
    elseif button:IsShown() and button.offset == -1 then
        earlier = button
    end
end
H.check(pick ~= nil and pick:IsEnabled(), "a day to come can be picked")
H.check(earlier == nil or not earlier:IsEnabled(), "a day gone by cannot")
H.Click(pick)
H.check(not picker:IsShown(), "picking a day closes the calendar")
local today = ns.Events.DateOf(ns.Events.Now())
local picked = ns.Events.DateOf(ns.Events.Naive(today.year, today.month, today.day, 0, 0) + 3 * 86400)
H.check(form.DayButton:GetText():find(tostring(picked.day), 1, true) ~= nil, "and the button shows the day picked")
H.MenuEntry(H.MenuOf(form.Type), "Dungeon").setSelected()
H.eq(form._portrait, "Interface\\LFGFrame\\LFGIcon-Dungeon", "and changes with it")
H.check(form.PlaceBox:IsEnabled() and form.PlaceBox:GetText() == "Sima Ígnea", "a dungeon starts with the lowest one")
form.PlaceBox._scripts.OnEditFocusGained(form.PlaceBox)
H.eq(#ns.EventForm.PlaceRows(), 5, "the place's box lists every dungeon")
form.PlaceBox:SetText("scho")
form.PlaceBox._scripts.OnTextChanged(form.PlaceBox, true)
local rows = ns.EventForm.PlaceRows()
H.check(#rows == 1 and rows[1].place.name == "Scholomance", "typing searches them")
form.PlaceBox:SetText("nothing like it")
form.PlaceBox._scripts.OnTextChanged(form.PlaceBox, true)
H.check(#ns.EventForm.PlaceRows() == 0 and form.PlaceList.Empty:IsShown(), "and says when nothing is found")
form.PlaceBox._scripts.OnEscapePressed(form.PlaceBox)
H.check(form.PlaceBox:GetText() == "Sima Ígnea" and not form.PlaceList:IsShown(), "Escape puts back the place picked")
H.MenuEntry(H.MenuOf(form.Type), "PvP").setSelected()
H.eq(form.PlaceBox:GetText(), "World PvP", "PvP starts with world PvP")
H.Click(form.PlaceArrow)
rows = ns.EventForm.PlaceRows()
H.check(#rows == 4 and rows[2].place.name == "Alterac Valley", "the arrow lists world PvP and each battleground once")
H.MenuEntry(H.MenuOf(form.Type), "Dungeon").setSelected()
form.PlaceBox:SetText("scholo")
form.PlaceBox._scripts.OnEnterPressed(form.PlaceBox)
H.eq(form.PlaceBox:GetText(), "Scholomance", "Enter picks the first found")
form.TitleBox:SetText("Scholomance")
H.MenuEntry(H.MenuOf(form.Hour), "20").setSelected()
H.MenuEntry(H.MenuOf(form.Minute), "35").setSelected()
local before = #organizer.calendarCalls
H.Click(form.Save)
H.eq(organizer.calendarCalls[before + 1], "CreateGuildSignUpEvent", "Create calls the calendar first thing in the click")
world:RunFor(30)
local scholo
for _, event in ipairs(ns.Events.List("upcoming")) do
    if event.ti == "Scholomance" then
        scholo = event
    end
end
H.check(scholo ~= nil and scholo.ty == 1 and scholo.ci ~= 0, "the new event, a dungeon, is in the calendar")
H.eq(scholo and scholo.ii, 797, "with the dungeon picked")
local when = scholo and ns.Events.DateOf(scholo.tm)
H.check(when and when.day == picked.day and when.month == picked.month and when.hour == 20 and when.minute == 35,
    "on the day picked, at the time picked")
organizer.twelveHour = true
ns.EventForm.Open()
H.check(form.AMPM:IsShown() and #H.MenuOf(form.Hour) == 12, "with the game's 12-hour clock, hours 1 to 12, then AM or PM")
H.check(form.Hour._text == "9" and form.AMPM._text == "PM", "21:00 shows as 9 PM")
H.MenuEntry(H.MenuOf(form.Hour), "12").setSelected()
H.MenuEntry(H.MenuOf(form.AMPM), "AM").setSelected()
H.eq(ns.EventForm.Chosen().hour, 0, "12 AM is midnight")
H.MenuEntry(H.MenuOf(form.Hour), "8").setSelected()
H.MenuEntry(H.MenuOf(form.AMPM), "PM").setSelected()
H.eq(ns.EventForm.Chosen().hour, 20, "8 PM is 20:00")
form:Hide()
organizer.twelveHour = nil
ns.EventForm.Open(scholo and scholo.key)
H.check(#H.MenuOf(form.Minute) == 12 and form.Minute._text == "35", "an event's own minutes show when it is changed")
form:Hide()
member.canAddEvent = false
member.ns.EventView.Close()
member.ns.GuildTab.Refresh()
H.check(memberPage.New:IsShown() and not memberPage.New:IsEnabled(),
    "New event stays where it is, off, while the game's calendar does not let the player add events")
H.eq(memberPage.New.reason, "Syncing the calendar...", "and says why")
member.canAddEvent = nil
member.world:FireEvent(member, "CALENDAR_UPDATE_EVENT_LIST")
world:RunFor(1)
H.check(memberPage.New:IsEnabled() and memberPage.New.reason == nil,
    "on as soon as the calendar's data says the player may add events")
member.canAddEvent = false
member.world:FireEvent(member, "CALENDAR_ACTION_PENDING")
world:RunFor(1)
H.check(not memberPage.New:IsEnabled(), "off while the calendar is busy with a change")
member.canAddEvent = nil
member.world:FireEvent(member, "CALENDAR_ACTION_PENDING")
world:RunFor(1)
H.check(memberPage.New:IsEnabled(), "and on again the moment it is done, as the game's own Create button")
local newPoint = memberPage.New._point
H.check(newPoint[1] == "BOTTOMRIGHT" and newPoint[4] == -5 and newPoint[5] == 5,
    "at the bottom right of the window, where the game has its buttons")
Errors("the panel")

H.section("UI: a weekly event's next one")
local weeklyKey = ns.Events.Create({ ty = 0, ti = "Weekly raid", tm = ns.Events.Now() + 2 * 86400, ml = 0, wk = true })
world:RunFor(5)
local nextWeekly
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ti == "Weekly raid" and one.key ~= weeklyKey then
        nextWeekly = one
    end
end
H.check(nextWeekly ~= nil and nextWeekly.ci == 0, "next week's is there at once, not in the calendar yet")
ns.EventView.Open(nextWeekly.key)
local sendPoint = orgView.Send._point
H.check(orgView.Send:IsShown() and orgView.Send:IsEnabled() and sendPoint[2] == orgView.Edit and sendPoint[3] == "LEFT",
    "its view has Create in calendar, left of Edit")
local callsBefore = #organizer.calendarCalls
H.Click(orgView.Send)
H.eq(organizer.calendarCalls[callsBefore + 1], "CreateGuildSignUpEvent", "its click creates it in the calendar")
world:RunFor(30)
H.check(ns.Events.Get(nextWeekly.key).ci ~= 0 and not orgView.Send:IsShown(), "in the calendar: the button goes")
ns.EventView.Close()
ns.GuildTab.Refresh()
local weeklyElement
for _, element in ipairs(page.List.elements) do
    if element.event.key == weeklyKey then
        weeklyElement = element
    end
end
local orgRow = {}
setmetatable(orgRow, getmetatable(H.NewObject(organizer, "Frame")))
for k, v in pairs(H.NewObject(organizer, "Frame")) do
    orgRow[k] = v
end
ns.EventList.InitRow(orgRow, weeklyElement)
H.check(orgRow.Send:IsShown() and orgRow.Send:IsEnabled(), "the row of one not in the calendar has the button too")
organizer.canAddEvent = false
organizer.world:FireEvent(organizer, "CALENDAR_ACTION_PENDING")
world:RunFor(1)
ns.EventList.InitRow(orgRow, weeklyElement)
H.check(not orgRow.Send:IsEnabled() and orgRow.Send.reason == "Syncing the calendar...",
    "off while the game takes no new event, as its own Create button")
organizer.canAddEvent = nil
organizer.world:FireEvent(organizer, "CALENDAR_ACTION_PENDING")
world:RunFor(1)
ns.EventList.InitRow(orgRow, weeklyElement)
H.Click(orgRow.Send)
world:RunFor(30)
H.check(ns.Events.Get(weeklyKey).ci ~= 0, "and its click creates it")
local function AddEvents()
    local count = 0
    for _, call in ipairs(organizer.calendarCalls) do
        if call == "AddEvent" then
            count = count + 1
        end
    end
    return count
end
local weeklyTwo = ns.Events.Create({ ty = 0, ti = "Weekly two", tm = ns.Events.Now() + 3 * 86400, ml = 0, wk = true })
world:RunFor(5)
local waitingKey
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ti == "Weekly two" and one.key ~= weeklyTwo then
        waitingKey = one.key
    end
end
ns.EventView.Open(waitingKey)
local addsThen = AddEvents()
organizer.confirm = nil
H.Click(orgView.Delete)
H.check(organizer.confirm ~= nil and ns.Events.Get(waitingKey) ~= nil, "Delete event asks first, and deletes nothing yet")
H.check(organizer.confirm.text_arg1:find("Weekly two", 1, true) and organizer.confirm.text_arg1:find("for everyone", 1, true),
    "naming the event, and that it goes for everyone")
organizer.confirm.callback()
H.eq(ns.Events.Get(waitingKey), nil, "accepted, one not in the calendar yet is deleted from the addon at once")
world:RunFor(5)
H.check(not orgView:IsShown(), "and the view goes back to the list")
H.eq(AddEvents(), addsThen, "nothing created in the calendar")
ns.EventView.Close()
Errors("weekly events")

H.section("UI: roles changed from the list")
local function NameIn(someView, role, guid)
    for _, name in ipairs(Names(someView, role)) do
        if name:IsShown() and name.signUp and name.signUp.guid == guid then
            return name
        end
    end
end
-- The cursor over one column (none: nil).
local function Over(someView, wanted)
    for role, column in ipairs(someView.Columns) do
        column.IsMouseOver = function()
            return role == wanted
        end
    end
end
local function Drag(name)
    name._scripts.OnDragStart(name)
    name._scripts.OnDragStop(name)
end
local function Picked(dropdown)
    for _, entry in ipairs(H.MenuOf(dropdown)) do
        if entry.isSelected(entry.data) then
            return entry.text
        end
    end
end
H.check(member.ns.Events.Answer(scholo.key, 1, 2), "a member signs up as healer")
world:RunFor(30)
member.ns.EventView.Open(scholo.key)
H.eq(Picked(view.Role), "Healer", "their view open, their role picked")
ns.EventView.Open(scholo.key)
local healerName = NameIn(orgView, 2, member.guid)
H.check(healerName ~= nil, "in the healers' column")
Over(orgView, nil)
Drag(healerName)
H.eq(member.ns.Events.Mine(member.ns.Events.Get(scholo.key)).ro, 2, "dropped over no column: nothing changes")
Over(orgView, 1)
Drag(healerName)
world:RunFor(30)
ns.EventView.Refresh()
H.check(NameIn(orgView, 1, member.guid) ~= nil, "the organizer drags the name to the tanks' column: a tank")
H.eq(member.ns.Events.Mine(member.ns.Events.Get(scholo.key)).ro, 1, "for everyone, the member too")
member.ns.EventView.Refresh()
H.eq(Picked(view.Role), "Tank", "the role picked in the member's open view follows it")
Over(view, 3)
Drag(NameIn(view, 1, member.guid))
world:RunFor(2)
H.eq(member.ns.Events.Mine(member.ns.Events.Get(scholo.key)).ro, 3, "the member drags their own name: damage")
H.eq(member.ns.Roles.Default(), 3, "their choice, remembered")
local organizerName
for role = 1, 3 do
    organizerName = organizerName or NameIn(view, role, organizer.guid)
end
member.contextMenu = nil
H.Click(organizerName, "RightButton")
H.eq(member.contextMenu, nil, "no menu on someone else's name for a member")
local organizerRole = ns.Events.Mine(ns.Events.Get(scholo.key)).ro
Over(view, organizerRole == 2 and 1 or 2)
Drag(organizerName)
world:RunFor(30)
H.eq(ns.Events.Mine(ns.Events.Get(scholo.key)).ro, organizerRole, "nor dragging it")
member.ns.EventView.Refresh()
H.Click(NameIn(view, 3, member.guid), "RightButton")
H.check(member.contextMenu ~= nil and H.MenuEntry(member.contextMenu, "Tank") ~= nil
    and H.MenuEntry(member.contextMenu, "Confirmed") == nil, "on their own, a menu with their role only")
H.MenuEntry(member.contextMenu, "Healer").setSelected()
world:RunFor(2)
H.eq(member.ns.Events.Mine(member.ns.Events.Get(scholo.key)).ro, 2, "which changes it")
for _, someView in ipairs({ view, orgView }) do
    for _, column in ipairs(someView.Columns) do
        column.IsMouseOver = nil
    end
end
Errors("roles")

H.section("UI: a moderator's own status, and anyone's note, from their name's menu")
local function Removes()
    local count = 0
    for _, call in ipairs(member.calendarCalls) do
        if call == "RemoveEvent" then
            count = count + 1
        end
    end
    return count
end
local function Invite(guid)
    local event = ns.Events.Get(scholo.key)
    return world.calendar.events[event.ci].invites[guid]
end
-- The member picks from their own name's menu.
local function OwnPick(text)
    member.ns.EventView.Refresh()
    member.contextMenu = nil
    for role = 1, 3 do
        local own = NameIn(view, role, member.guid)
        if own then
            H.Click(own, "RightButton")
        end
    end
    if not member.contextMenu then
        view._scripts.OnHyperlinkClick(view, "gre:" .. member.guid, "Member Name", "RightButton")
    end
    local entry = member.contextMenu and H.MenuEntry(member.contextMenu, text)
    if entry and entry.setSelected then
        entry.setSelected()
    elseif entry then
        entry.callback()
    end
    return entry ~= nil
end
H.check(ns.Events.SetModerator(scholo.key, member.guid, true), "the organizer names the member a moderator")
world:RunFor(30)
member.ns.EventView.Refresh()
H.check(view.Remove:IsShown() and not view.SignUp:IsShown(), "under the columns, a moderator only removes their sign-up")
H.eq(view.Remove.reason, "Takes your sign-up back: you are a moderator no more, as in the game's calendar.",
    "which says it ends their moderation")
local removesBefore = Removes()
H.check(OwnPick("Tentative"), "their own name's menu gives them a status")
world:RunFor(30)
local modMine = member.ns.Events.Mine(member.ns.Events.Get(scholo.key))
H.check(member.ns.States.IsTentative(modMine) and member.ns.Events.IsModerator(member.ns.Events.Get(scholo.key), member.guid),
    "Tentative: tentative, a moderator still")
H.check(Invite(member.guid) ~= nil and Invite(member.guid).status == 8 and Invite(member.guid).modStatus == "MODERATOR",
    "in the calendar too, given as a status: still in its list, a moderator")
OwnPick("Confirmed")
world:RunFor(30)
modMine = member.ns.Events.Mine(member.ns.Events.Get(scholo.key))
H.check(modMine ~= nil and modMine.status == 1 and Invite(member.guid) ~= nil and Invite(member.guid).status == 3
    and Invite(member.guid).modStatus == "MODERATOR", "Confirmed: confirmed, in both, a moderator still")
OwnPick("Out")
world:RunFor(30)
modMine = member.ns.Events.Mine(member.ns.Events.Get(scholo.key))
H.check(modMine ~= nil and modMine.status == 3 and member.ns.Events.IsModerator(member.ns.Events.Get(scholo.key), member.guid),
    "Out: out, in its list still, a moderator still, as in the game's calendar")
H.check(Invite(member.guid) ~= nil and Invite(member.guid).status == 4 and Invite(member.guid).modStatus == "MODERATOR",
    "in the calendar too")
H.eq(Removes(), removesBefore, "their sign-up never taken back in the calendar meanwhile")
OwnPick("Confirmed")
world:RunFor(30)
-- The note, from their own name's menu: its time (their place in the order
-- they signed up) stays.
local answeredAt = member.ns.Data.GetOwnRecord(false).su[scholo.key].at
H.check(OwnPick("Edit note"), "their own name's menu edits their note")
local editor = member.ns.EventView.NoteEditor()
local noteBox = editor and editor:IsShown() and editor.Box
H.check(noteBox and noteBox:GetText() == "", "in a small window, with their note (none yet)")
noteBox:SetText("  bring flasks  ")
noteBox._scripts.OnEnterPressed(noteBox)
world:RunFor(30)
modMine = member.ns.Events.Mine(member.ns.Events.Get(scholo.key))
H.check(modMine.no == "bring flasks" and member.ns.Data.GetOwnRecord(false).su[scholo.key].at == answeredAt,
    "Enter saves it, trimmed; the answer's time stays")
H.check(not editor:IsShown(), "and closes the window")
local forOrganizer
for _, signUp in ipairs(ns.Events.SignUps(ns.Events.Get(scholo.key))) do
    if signUp.guid == member.guid then
        forOrganizer = signUp
    end
end
H.check(forOrganizer ~= nil and forOrganizer.no == "bring flasks" and forOrganizer.status == 1,
    "for everyone, their status unchanged")
member.contextMenu = nil
local organizerName
for role = 1, 3 do
    organizerName = organizerName or NameIn(view, role, organizer.guid)
end
H.Click(organizerName, "RightButton")
H.check(member.contextMenu ~= nil and H.MenuEntry(member.contextMenu, "Edit note") == nil,
    "no one edits another's note")
H.Click(view.Remove)
world:RunFor(30)
H.check(member.ns.Events.Mine(member.ns.Events.Get(scholo.key)) == nil
    and not member.ns.Events.IsModerator(member.ns.Events.Get(scholo.key), member.guid),
    "Remove sign-up: out of its list, a moderator no more, as in the game")
member.ns.EventView.Refresh()
H.check(view.SignUp:IsShown() and view.Tentative:IsShown() and not view.Remove:IsShown(), "Sign up and Tentative again")
member.ns.EventView.Close()
ns.EventView.Close()
Errors("a moderator's status and notes")

H.section("UI: a long column scrolls")
local manyGuild = ns.Data.CurrentGuild(false)
local many = {}
for i = 1, 10 do
    local guid = ("Player-1-0000F%03d"):format(i)
    many[#many + 1] = guid
    manyGuild.members[guid] = { t = ns.Now(), av = 100, su = { [scholo.key] = { st = 1, ro = 1, at = ns.Now() + i } } }
end
ns.Events.Invalidate()
ns.EventView.Open(scholo.key)
local tanks = Names(orgView, 1)
local listed = {}
for _, name in ipairs(tanks) do
    listed[name.signUp.guid] = true
end
local all = true
for _, guid in ipairs(many) do
    all = all and listed[guid] == true
end
H.check(#tanks >= 10 and all, "every tank is in its column's list, which scrolls when they are more than it shows")
for _, guid in ipairs(many) do
    manyGuild.members[guid] = nil
end
ns.Events.Invalidate()
ns.EventView.Close()
Errors("a long column")

H.section("UI: the game's limit of events created")
local madeByOrganizer = 0
for _, one in pairs(world.calendar.events) do
    if not one.deleted and one.creator == organizer.guid then
        madeByOrganizer = madeByOrganizer + 1
    end
end
local LIMIT = ("You have reached your limit of %d events created."):format(madeByOrganizer)
organizer.env.CALENDAR_ERROR_EVENTS_EXCEEDED = "You have reached your limit of %d events created."
organizer.eventLimit = madeByOrganizer
ns.EventForm.Open(nil)
local limitForm = ns.EventForm.Frame()
limitForm.TitleBox:SetText("One too many")
H.Click(limitForm.Save)
world:RunFor(5)
H.check(limitForm:IsShown() and not limitForm.Save:IsEnabled() and limitForm.Save.reason == LIMIT,
    "refused by the game: the form stays, Create off with the game's words")
limitForm:Hide()
ns.GuildTab.Refresh()
H.check(not page.New:IsEnabled() and page.New.reason == LIMIT, "New event too")
organizer.eventLimit = nil
Errors("the limit")

H.section("UI: deleting an event")
local function Listed(listPage, wanted)
    for _, element in ipairs(listPage.List.elements) do
        if element.event.key == wanted then
            return element
        end
    end
end
H.check(#page.SubTabs.Tabs == 2 and page.SubTabs.Tabs[2]:GetText() == "Last week",
    "two subtabs, upcoming and last week: a deleted event is gone, with no subtab of its own")
H.Click(memberPage.SubTabs.Tabs[1])
H.check(Listed(memberPage, scholo.key) ~= nil, "an event in the member's list")
ns.EventView.Open(scholo.key)
H.check(orgView.Delete:IsEnabled() and orgView.Delete.reason == "Deletes this event, for everyone.",
    "Delete event says what it does")
H.check(orgView.Title._point[2] == orgView.Edit, "the title stops before Edit")
organizer.confirm = nil
H.Click(orgView.Delete)
organizer.confirm.callback()
ns.EventView.UpdateControls()
H.check(ns.Events.Get(scholo.key) == nil or not orgView.Delete:IsEnabled() and orgView.Delete.reason == "Syncing the calendar...",
    "off while the calendar deletes it")
world:RunFor(5)
H.eq(ns.Events.Get(scholo.key), nil, "deleted, the calendar first")
H.check(world.calendar.events[scholo.ci].deleted, "from the calendar too")
H.check(not orgView:IsShown(), "and the view goes back to the list")
world:RunFor(30)
member.ns.GuildTab.Refresh()
H.check(member.ns.Events.Get(scholo.key) == nil and Listed(memberPage, scholo.key) == nil, "gone from everyone's list")
ns.GuildTab.Refresh()
H.check(page.New:IsEnabled(), "one of theirs gone from the calendar: New event is on again")
Errors("deleting an event")

H.section("UI: an event that comes to its end, the window open")
H.Click(Tab(member))
local ending = ns.Events.Create({ ty = 4, ti = "Ending soon", tm = ns.Events.Now() - ns.Events.DURATION + 150, ml = 0 })
world:RunFor(30)
member.ns.EventView.Open(ending)
H.check(view:IsShown() and view.SignUp:IsEnabled(), "a member can sign up while it is still on")
-- Up to one look at the calendar (10 s) after it is over.
world:RunFor(member.ns.Events.Get(ending).tm + ns.Events.DURATION - member.ns.Events.Now() + 11)
H.check(not view.SignUp:IsEnabled() and view.SignUp.reason == "This event is over.",
    "once it is over its buttons say so, though nothing else changed")
member.ns.EventView.Close()
Errors("an event that ends")

H.section("UI: closing")
communities:SetDisplayMode("ROSTER")
H.check(not page:IsShown() and not tab:GetChecked(), "one of Blizzard's tabs closes the panel")
H.eq(communities.MemberList:GetAlpha(), 1, "and Blizzard's view shows again")

H.section("UI: options")
local main = ns.Options.Page("main")
H.check(main ~= nil, "the options' main page")
-- The game renders the plural markup: "30 |4minute:minutes; before".
for _, entry in ipairs(H.MenuOf(main.Reminder)) do
    if tostring(entry.text):find("^30 ") then
        entry.setSelected()
    end
end
H.eq(ns.Reminders.Minutes(), 30, "the reminder is chosen there")
H.eq(ns.Options.Page("bridges"), nil, "no page of bridge characters while no addon brings sign-ups in")
organizer.env.GuildRaidsEvents.RegisterBridge("A Bridge")
H.check(ns.Options.Page("bridges") ~= nil, "it shows once one registers")
local registered = organizer.settings and organizer.settings[1]
H.check(registered and registered.name == "Guild Raids & Events" and #registered.subcategories == 1,
    "under Options > AddOns > Guild Raids & Events")
Errors("the options")

H.section("UI: Blizzard's frames stay untainted")
for _, file in ipairs(H.FILES) do
    local handle = io.open(H.ADDON .. "/" .. file, "rb")
    local text = handle:read("*a")
    handle:close()
    local code = text:gsub("%-%-[^\n]*", "")
    H.check(not code:find("communities:HookScript", 1, true) and not code:find("CommunitiesFrame:HookScript", 1, true),
        file .. ": no HookScript on the guild window")
    H.check(not code:find(":SetDisplayMode%("), file .. ": never changes the guild window's display mode")
    H.check(not code:find("Menu.ModifyMenu", 1, true), file .. ": no changes to Blizzard's menus")
    H.check(not code:find("CalendarFrame:Show", 1, true) and not code:find("ToggleCalendar", 1, true)
        and not code:find("Calendar_Show", 1, true), file .. ": never opens Blizzard's calendar window")
    H.check(not code:find("MemberList", 1, true) or file == "GuildTab.lua", file .. ": does not touch the member list")
end
