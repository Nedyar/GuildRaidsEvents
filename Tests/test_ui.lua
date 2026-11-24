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

H.section("UI: an event")
member.ns.EventView.Open(key)
world:RunFor(1)
local view = memberPage.View
H.check(view:IsShown() and not list:IsShown(), "a row's click opens the event in place of the list")
H.check(view.Title:GetText() == "Molten Core", "with its title")
H.check(not view.Edit:IsShown() and not view.Cancel:IsShown(), "a member does not manage it")
member.level = 40
member.ns.EventView.Refresh()
H.check(not view.SignUp:IsEnabled() and view.SignUp.reason ~= nil, "below its minimum level, the member cannot sign up")
H.check(not view.Remove:IsEnabled(), "and, not signed up, has no sign-up to remove")
H.check(view.SignUp:IsShown() and view.Tentative:IsShown() and view.Remove:IsShown() and not view.Confirm:IsShown(),
    "a member's buttons are the game's: sign up, tentative, remove the sign-up")
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
H.check(view.Columns[2].Names[1]:IsShown() and view.Columns[2].Names[1].Text:GetText():find("Member Name", 1, true),
    "the member shows in the healers' column")
H.check(view.Columns[2].Names[1].Text:GetText():find("(Signed up)", 1, true) ~= nil,
    "with their state by the name, signed up too, as every other state")
H.check(view.Mine:GetText():find("Healer", 1, true) ~= nil, "and their answer under it")
local nameButton = view.Columns[2].Names[1]
nameButton:GetScript("OnEnter")(nameButton)
local tipLines = member.env.GameTooltip._lines
H.check(tipLines[#tipLines] == "late 10 min", "pointing at the name shows the note")
-- A long note with no spaces was cut short with "..." in the tooltip: it
-- goes in lines that fit (the tests measure 6 pixels a byte, so 36 in 220).
local NoteLines = member.ns.EventView.NoteLines
local digits = ("1234567890"):rep(6)
local cutLines = NoteLines(digits)
H.check(#cutLines == 2 and #cutLines[1] == 36 and table.concat(cutLines) == digits,
    "a word wider than the tooltip is cut where it reaches the edge, nothing lost")
local words = NoteLines("I will be a bit late tonight, start without me please")
H.check(#words == 2 and words[1] == "I will be a bit late tonight, start" and words[2] == "without me please",
    "a note with spaces breaks between words")
local enes = ("ñ"):rep(25)
local eneLines = NoteLines(enes)
H.check(#eneLines == 2 and eneLines[1] == ("ñ"):rep(18) and table.concat(eneLines) == enes,
    "letters of two bytes are never split")
H.Click(view.Back)
H.check(not view:IsShown() and list:IsShown(), "Back shows the list again")

H.section("UI: the organizer manages the event")
local page = Page(organizer)
H.Click(tab)
ns.EventView.Open(key)
world:RunFor(1)
local orgView = page.View
H.check(orgView.Edit:IsShown() and orgView.Cancel:IsShown(), "the organizer may change and cancel it")
H.check(not orgView.Delete:IsShown(), "no Delete while it is not cancelled")
local healer = orgView.Columns[2].Names[1]
H.check(healer.signUp ~= nil and healer.signUp.guid == member.guid, "the member's sign-up is in the healers' column")
H.Click(healer)
local menu = organizer.contextMenu
H.check(menu ~= nil and H.MenuEntry(menu, "Confirmed") ~= nil, "a click on it opens its menu of statuses")
H.MenuEntry(menu, "Confirmed").setSelected()
world:RunFor(30)
local seen = member.ns.Events.Mine(member.ns.Events.Get(key))
H.eq(seen.status, 1, "the member is confirmed, for everyone")
H.check(ns.Events.SetStatus(key, member.guid, ns.Events.OUT), "the organizer leaves them out")
world:RunFor(1)
ns.EventView.Refresh()
local inColumns = false
for _, column in ipairs(orgView.Columns) do
    for _, name in ipairs(column.Names) do
        if name:IsShown() and name.signUp and name.signUp.guid == member.guid then
            inColumns = true
        end
    end
end
H.check(not inColumns and orgView.Others:GetText():find("|Hgre:" .. member.guid, 1, true) ~= nil,
    "left out: not among those who go, but in the Out line, as a link")
world:RunFor(30)
member.ns.EventView.Open(key)
H.check(not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled() and view.Remove:IsEnabled(),
    "the member left out cannot sign up again nor answer tentative (as in the game), only remove it")
H.eq(view.Tentative.reason, "To change your answer, remove your sign-up and wait for the event to show again in your calendar (about an hour, or when you log in again).", "and the buttons say so")
H.check(view.Mine:GetText():find("Out", 1, true) ~= nil, "and reads Out")
organizer.contextMenu = nil
orgView._scripts.OnHyperlinkClick(orgView, "gre:" .. member.guid)
H.check(organizer.contextMenu ~= nil and H.MenuEntry(organizer.contextMenu, "Confirmed") ~= nil,
    "a click on the name there opens its menu of statuses")
H.MenuEntry(organizer.contextMenu, "Confirmed").setSelected()
world:RunFor(30)
H.eq(member.ns.Events.Mine(member.ns.Events.Get(key)).status, 1, "confirmed again")
local function MineOf(client)
    return client.ns.Events.Mine(client.ns.Events.Get(key))
end
H.Click(orgView.OwnTentative)
world:RunFor(2)
ns.EventView.Refresh()
local function DamageName(guid)
    for _, name in ipairs(orgView.Columns[3].Names) do
        if name:IsShown() and name.signUp and name.signUp.guid == guid then
            return name
        end
    end
end
H.check(ns.States.IsTentative(MineOf(organizer)) and DamageName(organizer.guid) ~= nil,
    "the organizer answers Tentative: still in their role's column, as tentative")
H.check(DamageName(organizer.guid).Text:GetText():find("(Tentative)", 1, true) ~= nil,
    "with their state by the name, though it is their answer and not a status given")
organizer.contextMenu = nil
H.Click(DamageName(organizer.guid))
H.MenuEntry(organizer.contextMenu, "Confirmed").setSelected()
world:RunFor(2)
ns.EventView.Refresh()
local own = MineOf(organizer)
H.check(own.st == 1 and own.status == 1 and ns.States.Goes(own), "then Confirmed from the menu: signed up and confirmed")
local inDamage = false
for _, name in ipairs(orgView.Columns[3].Names) do
    inDamage = inDamage or (name:IsShown() and name.signUp and name.signUp.guid == organizer.guid)
end
H.check(inDamage, "back in their role's column")
H.Click(orgView.OwnTentative)
world:RunFor(2)
H.check(ns.States.IsTentative(MineOf(organizer)), "answering Tentative again after it makes them tentative")
ns.EventView.Refresh()
organizer.contextMenu = nil
H.Click(DamageName(organizer.guid))
H.MenuEntry(organizer.contextMenu, "Confirmed").setSelected()
world:RunFor(2)
organizer.contextMenu = nil
for _, name in ipairs(orgView.Columns[2].Names) do
    if name:IsShown() and name.signUp and name.signUp.guid == member.guid then
        H.Click(name)
    end
end
H.MenuEntry(organizer.contextMenu, "Tentative").setSelected()
world:RunFor(30)
H.check(ns.States.IsTentative(MineOf(member)), "a member made tentative by the organizer is tentative for everyone")
member.ns.EventView.Open(key)
H.check(not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled() and view.Remove:IsEnabled(),
    "made tentative, the member only removes their sign-up, as in the game")
H.eq(view.SignUp.reason, "To change your answer, remove your sign-up and wait for the event to show again in your calendar (about an hour, or when you log in again).", "and Sign up says how to change it")
H.Click(view.Remove)
world:RunFor(30)
H.eq(MineOf(member), nil, "removed")
H.check(member.ns.Calendar.HiddenFromMe(member.ns.Events.Get(key)), "the event left the member's calendar, as the game does")
H.check(not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled(), "so they cannot answer yet")
H.eq(view.SignUp.reason, "Wait for the event to show again in your calendar (about an hour after removing your sign-up, or when you log in again).", "and the buttons say to wait")
world:ShowHidden()
world:RunFor(15)
H.check(view.SignUp:IsEnabled() and view.Tentative:IsEnabled(), "back in their calendar: they answer again")
H.Click(view.SignUp)
world:RunFor(30)
H.check(MineOf(member).st == 1 and ns.States.Goes(MineOf(member)) and (MineOf(member).status == 0 or MineOf(member).auto),
    "signing up again after it: signed up, with no status of the organizer's, as in the game")
H.check(orgView.Confirm:IsShown() and orgView.Standby:IsShown() and orgView.OwnTentative:IsShown() and orgView.Out:IsShown()
    and not orgView.SignUp:IsShown() and not orgView.Remove:IsShown(),
    "the organizer's buttons are the states the game lets its creator have: confirmed, standby, tentative, out")
H.check(not orgView.Confirm:IsEnabled(), "Confirmed is off while they are confirmed in that role")
H.Click(orgView.Out)
world:RunFor(2)
ns.EventView.Refresh()
H.check(MineOf(organizer).status == 3 and orgView.Others:GetText():find("|Hgre:" .. organizer.guid, 1, true),
    "Out: in the Out line")
H.check(not orgView.Out:IsEnabled() and orgView.Confirm:IsEnabled(), "Out is off now, Confirmed on")
H.check(orgView.Mine:GetText():find("Out", 1, true) ~= nil and not orgView.Mine:GetText():find("Signed up", 1, true),
    "and their state reads Out, nothing else")
H.Click(orgView.Confirm)
world:RunFor(2)
H.check(MineOf(organizer).status == 1 and ns.States.Goes(MineOf(organizer)), "Confirmed: confirmed again, not left out")
H.Click(orgView.OwnTentative)
world:RunFor(2)
H.check(ns.States.IsTentative(MineOf(organizer)), "Tentative: tentative")
H.Click(orgView.Standby)
world:RunFor(2)
H.check(MineOf(organizer).status == 2 and ns.States.Goes(MineOf(organizer)), "Standby: on standby")
H.Click(orgView.Confirm)
world:RunFor(2)
H.Click(orgView.Cancel)
world:RunFor(5)
H.check(ns.Events.Get(key).x and orgView.Cancel:GetText() == "Restore event", "Cancel event cancels it, and the button restores it")
H.Click(orgView.Cancel)
world:RunFor(5)
H.check(not ns.Events.Get(key).x, "restored")

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
form.Lock:SetChecked(true)
H.Click(form.Save)
world:RunFor(30)
H.check(ns.Events.Get(key).lk, "ticked and saved: the event is locked")
member.ns.EventView.Open(key)
H.eq(view.Title:GetText(), "Molten Core (Locked)", "its title says so, as the game's calendar does")
H.check(not view.SignUp:IsEnabled() and not view.Tentative:IsEnabled() and not view.Remove:IsEnabled(),
    "a member can neither sign up, nor answer tentative, nor remove their sign-up")
H.eq(view.Remove.reason, "This event is locked: it takes no answers.", "and the buttons say why")
member.ns.EventList.InitRow(row, { event = member.ns.Events.Get(key) })
H.eq(row.Title:GetText(), "Molten Core (Locked)", "the list says so too")
ns.EventView.Open(key)
H.check(orgView.Standby:IsEnabled() and orgView.OwnTentative:IsEnabled(), "the organizer still changes their own state")
H.Click(orgView.Edit)
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
form.TitleBox:SetText("Molten Core!")
H.Click(form.Save)
world:RunFor(5)
H.eq(ns.Events.Get(key).ti, "Molten Core!", "Save changes it")
H.check(not form:IsShown(), "and closes the form")
H.Click(orgView.Back)
H.check(page.New:IsShown(), "New event shows for a rank that may add guild events")
H.Click(page.New)
H.check(form:IsShown() and form.TitleBox:GetText() == "", "it opens an empty form")
H.eq(form.Type._text, "Other", "an event of type Other by default")
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
H.Click(orgView.Cancel)
world:RunFor(5)
H.check(ns.Events.Get(waitingKey).x, "one not in the calendar yet, cancelled")
local addsThen = AddEvents()
H.Click(orgView.Cancel)
world:RunFor(5)
local back = ns.Events.Get(waitingKey)
H.check(not back.x and back.ci == 0 and orgView.Send:IsShown(), "restored as it was: waiting for its own button")
H.eq(AddEvents(), addsThen, "nothing created in the calendar by restoring it")
ns.EventView.Close()
Errors("weekly events")

H.section("UI: cancelled events, in their own subtab")
H.check(ns.Events.Cancel(key), "the organizer cancels an event")
world:RunFor(30)
member.ns.GuildTab.Refresh()
local function Listed(listPage, wanted)
    for _, element in ipairs(listPage.List.elements) do
        if element.event.key == wanted then
            return element
        end
    end
end
H.check(Listed(memberPage, key) == nil, "a cancelled event leaves Upcoming")
H.check(not memberPage.Clear:IsShown(), "where Clear cancelled does not show")
local cancelledTab = memberPage.SubTabs.Tabs[3]
H.check(cancelledTab ~= nil and cancelledTab:GetText() == "Cancelled events", "a subtab of its own for the cancelled ones")
H.Click(cancelledTab)
local cancelledRow = Listed(memberPage, key)
H.check(cancelledRow ~= nil, "which lists it")
H.check(memberPage.Clear:IsShown(), "with Clear cancelled")
local clearPoint = memberPage.Clear._point
H.check(clearPoint[1] == "RIGHT" and clearPoint[2] == memberPage.New and clearPoint[3] == "LEFT" and clearPoint[4] == -2,
    "left of New event, 2 apart as the game's buttons, never over it")
member.ns.EventList.InitRow(row, cancelledRow)
H.check(row.Clear:IsShown(), "and its row has its own button to clear it")
H.Click(row.Clear)
H.check(Listed(memberPage, key) == nil and not memberPage.Clear:IsShown(), "it goes from the member's list")
H.check(member.ns.Events.Get(key) ~= nil, "the event itself stays")
ns.EventView.Close()
H.Click(page.SubTabs.Tabs[3])
H.check(page.Clear:IsShown(), "and stays in the others' lists")
H.check(ns.Events.Cancel(scholo.key), "the organizer cancels the other one")
world:RunFor(30)
member.ns.GuildTab.Refresh()
H.Click(memberPage.Clear)
H.check(#memberPage.List.elements == 0 and not memberPage.Clear:IsShown(), "Clear cancelled clears every cancelled one")
H.check(memberPage.List.Empty:IsShown() and memberPage.List.Empty:GetText() == "No cancelled events.",
    "and the subtab says it has none")
H.check(member.ns.Events.Cancel(scholo.key, false) == false, "a member may not restore it")
H.check(ns.Events.Cancel(scholo.key, false), "once restored by the organizer")
world:RunFor(30)
H.Click(memberPage.SubTabs.Tabs[1])
H.check(Listed(memberPage, scholo.key) ~= nil, "it is in Upcoming again")
H.check(ns.Events.Get(key) ~= nil and ns.Events.Get(key).x, "the organizer still has their other cancelled event")
ns.GuildTab.Refresh()
H.Click(page.Clear)
H.eq(ns.Events.Get(key), nil, "their Clear cancelled deletes their own cancelled events")
world:RunFor(30)
H.eq(member.ns.Events.Get(key), nil, "for everyone")
H.check(ns.Events.Get(scholo.key) ~= nil, "and nothing else")
H.check(ns.Events.Cancel(scholo.key), "the organizer cancels their other event")
world:RunFor(5)
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
ns.EventView.Open(scholo.key)
H.check(not orgView.Cancel:IsEnabled() and orgView.Cancel:GetText() == "Restore event",
    "and Restore event")
H.eq(orgView.Cancel.reason, LIMIT, "saying why")
organizer.eventLimit = nil
local deletePoint = orgView.Delete._point
H.check(orgView.Delete:IsShown() and deletePoint[1] == "RIGHT" and deletePoint[2] == orgView.Edit and deletePoint[3] == "LEFT",
    "a cancelled event of one's own: Delete, left of Edit")
H.check(orgView.Title._point[2] == orgView.Delete, "the title stops before it")
member.ns.EventView.Open(scholo.key)
H.check(member.ns.EventView.Shown() == scholo.key and not view.Delete:IsShown(), "not for others")
H.Click(orgView.Delete)
H.eq(ns.Events.Get(scholo.key), nil, "Delete deletes it")
H.check(not orgView:IsShown(), "and goes back to the list")
world:RunFor(30)
H.eq(member.ns.Events.Get(scholo.key), nil, "for everyone")
ns.EventView.Close()
Errors("cancelled events")

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
