-- The game's calendar kept in step (Calendar.lua), against the simulated
-- calendar of game.lua: the organizer's event goes in with the click that
-- creates it; answers and statuses go in with no click; changes and
-- deletions wait for the organizer's next click, and are refused outside
-- one.
local H = ...

local world = H.NewWorld({ seed = 17, senderFormat = "short", strictWhispers = true })
world.officerRanks = { [1] = true }
local organizer = world:NewClient("Organizer Name", { rank = "Officer", rankIndex = 1 })
local member = world:NewClient("Member Name", { rank = "Member", rankIndex = 3 })
local second = world:NewClient("Second Name", { rank = "Member", rankIndex = 3 })
for _, client in ipairs({ organizer, member, second }) do
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

local function CalendarEvents()
    local list = {}
    for _, event in pairs(world.calendar.events) do
        if not event.deleted then
            list[#list + 1] = event
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

local function Count(calls, name)
    local count = 0
    for _, call in ipairs(calls) do
        if call == name then
            count = count + 1
        end
    end
    return count
end

H.section("Calendar: creating an event with its click")
local ns = organizer.ns
ns.EventForm.Open(nil)
local form = ns.EventForm.Frame()
form.TitleBox:SetText("Molten Core")
H.MenuEntry(H.MenuOf(form.Type), "Raid").setSelected()
form.Auto:SetChecked(true)
form.Limit:SetChecked(true)
form.Tanks:SetText("1")
H.Click(form.Save)
world:RunFor(30)
local calendarEvents = CalendarEvents()
H.eq(#calendarEvents, 1, "the event is in the game's calendar")
H.eq(Count(organizer.calendarCalls, "AddEvent"), 1, "created once, inside the click")
local list = ns.Events.List("upcoming")
H.eq(#list, 1, "and in the addon")
local key = list[1].key
H.check(calendarEvents[1].title == "Molten Core" and calendarEvents[1].type == 0, "with its title and type")
H.eq(ns.Events.Get(key).ii, 836, "a raid starts with the lowest raid as its place")
local start = ns.Events.DateOf(list[1].tm)
H.check(calendarEvents[1].start.day == start.day and calendarEvents[1].start.hour == 21, "on its day, at 21:00")
H.eq(ns.Events.Get(key).ci, calendarEvents[1].id, "its calendar ID is in the organizer's record")
world:RunFor(30)
H.eq(member.ns.Events.Get(key).ci, calendarEvents[1].id, "and reaches everyone")
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), 1, "and nothing creates it again")
Errors("creating")

H.section("Calendar: answers go in with no click")
member.ns.Events.Answer(key, member.ns.Events.SIGNED, member.ns.Events.TANK)
second.ns.Events.Answer(key, second.ns.Events.SIGNED, second.ns.Events.TANK)
world:RunFor(60)
local invites = world.calendar.events[calendarEvents[1].id].invites
H.check(invites[member.guid] ~= nil and invites[second.guid] ~= nil, "both sign-ups are in the calendar")
H.eq(Count(member.calendarCalls, "EventSignUp"), 1, "signed up from a timer")
world:RunFor(150)
H.eq(invites[member.guid].status, 3, "the organizer's client confirms the first tank in the calendar")
H.eq(invites[second.guid].status, 5, "and puts the second on standby")
H.eq(Count(member.calendarCalls, "AddEvent") + Count(second.calendarCalls, "AddEvent"), 0, "members never create anything")

H.section("Calendar: a changed answer")
member.ns.Events.Answer(key, member.ns.Events.TENTATIVE, member.ns.Events.TANK)
world:RunFor(30)
H.eq(Count(member.calendarCalls, "RemoveEvent"), 1, "from signed up to tentative: the sign-up is taken back first")
H.eq(invites[member.guid], nil, "it is out of the calendar")
world:ShowHidden()
world:RunFor(320)
H.check(invites[member.guid] ~= nil and invites[member.guid].status == 8, "once the event is back, tentative goes in")
world:RunFor(150)
H.eq(invites[second.guid].status, 3, "and the second tank takes the place in the calendar too")
H.check(organizer.ns.Events.SetStatus(key, second.guid, organizer.ns.Events.STANDBY), "the organizer puts them on standby")
world:RunFor(20)
H.eq(invites[second.guid].status, 5, "a status given in the addon reaches the calendar at the next look")
Errors("answers")

H.section("Calendar: a change goes in with the click that saves it")
local calendarID = calendarEvents[1].id
local function InCalendar()
    return world.calendar.events[calendarID]
end
ns.EventView.Open(key)
ns.EventForm.Open(key)
world:RunFor(5)
form.TitleBox:SetText("Molten Core (21:30)")
H.MenuEntry(H.MenuOf(form.Minute), "30").setSelected()
local before = Count(organizer.calendarCalls, "UpdateEvent")
H.Click(form.Save)
H.eq(Count(organizer.calendarCalls, "UpdateEvent"), before + 1, "Save changes the calendar inside its click")
world:RunFor(1)
H.check(InCalendar().title == "Molten Core (21:30)" and InCalendar().start.minute == 30, "with the new title and time")
H.eq(ns.Events.Get(key).ti, "Molten Core (21:30)", "and the addon has it")
world:RunFor(30)
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")

H.section("Calendar: a change the game refuses changes nothing")
ns.EventForm.Open(key)
world:RunFor(5)
form.TitleBox:SetText("Molten Core (refused)")
local updateEvent = organizer.env.C_Calendar.UpdateEvent
organizer.env.C_Calendar.UpdateEvent = function()
    error("the game refused it")
end
H.Click(form.Save)
organizer.env.C_Calendar.UpdateEvent = updateEvent
H.check(form:IsShown() and form.Error:GetText() == "The game's calendar refused the change. Click again to retry.",
    "refused in the click: the form stays, and says so")
H.check(ns.Events.Get(key).ti == "Molten Core (21:30)" and InCalendar().title == "Molten Core (21:30)",
    "nothing changed, in the addon or in the calendar")
form.TitleBox:SetText("Molten Core (later)")
organizer.env.C_Calendar.UpdateEvent = function()
    world:Schedule(0.5, function()
        world:FireEvent(organizer, "CALENDAR_UPDATE_ERROR", "CALENDAR_ERROR_PERMISSIONS")
    end, organizer)
end
H.Click(form.Save)
organizer.env.C_Calendar.UpdateEvent = updateEvent
H.check(ns.Events.Get(key).ti == "Molten Core (later)" and not form:IsShown(), "taken in the click: the addon has it")
world:RunFor(2)
H.check(ns.Calendar.lastError ~= nil, "the calendar refuses it after: the window says so")
world:RunFor(75)
H.eq(ns.Events.Get(key).ti, "Molten Core (21:30)", "and the addon goes back to what the calendar has")
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
world.errors = {}

H.section("Calendar: moderators, as the game's calendar has them")
local officer = world:NewClient("Officer Name", { rank = "Officer", rankIndex = 1 })
world:Login(officer)
world:RunFor(60)
H.check(not officer.ns.Rights.MayIManage(officer.ns.Events.Get(key)), "an officer does not manage it by rank")
H.check(officer.ns.Events.Answer(key, officer.ns.Events.SIGNED, officer.ns.Events.HEALER), "they sign up")
world:RunFor(60)
H.check(ns.Events.SetModerator(key, officer.guid, true), "the organizer names them a moderator")
world:RunFor(30)
H.eq(InCalendar().invites[officer.guid].modStatus, "MODERATOR", "in the calendar too, with no click")
officer.ns.EventForm.Open(key)
world:RunFor(5)
local officerForm = officer.ns.EventForm.Frame()
H.check(officerForm.Save:IsEnabled(), "the moderator's Save is on")
officerForm.TitleBox:SetText("MC")
H.Click(officerForm.Save)
H.eq(InCalendar().title, "MC", "their change goes into the calendar in their own click")
world:RunFor(30)
H.eq(ns.Events.Get(key).ti, "MC", "and the organizer has it")
world:WindowModerator(calendarID, second.guid, true)
-- (The organizer's event is not open in their own window here: their next
-- look at its sign-ups finds it.)
world:RunFor(150)
H.check(ns.Events.Get(key).md[second.guid] and member.ns.Events.IsModerator(member.ns.Events.Get(key), second.guid),
    "a moderator named in the game's window comes into the addon, for everyone")
H.check(officer.ns.Events.SetModerator(key, member.guid, true), "a moderator names another")
world:RunFor(30)
H.eq(InCalendar().invites[member.guid].modStatus, "MODERATOR", "the calendar takes it from the organizer's client")
H.check(ns.Events.SetModerator(key, officer.guid, false), "the organizer takes the first back")
world:RunFor(30)
H.check(InCalendar().invites[officer.guid].modStatus ~= "MODERATOR" and not ns.Events.IsModerator(ns.Events.Get(key), officer.guid),
    "gone in both")
H.check(InCalendar().invites[member.guid].modStatus == "MODERATOR" and ns.Events.IsModerator(ns.Events.Get(key), member.guid),
    "the one they named stays, as in the game's calendar")
officer.ns.EventForm.Open(key)
world:RunFor(5)
H.check(not officerForm:IsShown() or not officerForm.Save:IsEnabled(), "no longer a moderator: their Save is off")
officerForm:Hide()
world.refuseRemove = true
member.ns.Calendar.Delete(key)
world:RunFor(10)
world.refuseRemove = nil
H.check(ns.Events.Get(key) ~= nil and member.ns.Events.Get(key) ~= nil and not member.ns.Calendar.Deleting(key)
    and not InCalendar().deleted, "Delete event, when the game does not let a moderator delete it: nothing changes")
H.eq(member.ns.Calendar.lastError, "The game's calendar does not let you delete this event.", "and the window says why")
for _, guid in ipairs({ second.guid, member.guid }) do
    ns.Events.SetModerator(key, guid, false)
end
world:RunFor(30)
Errors("moderators")

H.section("Calendar: changes made in the game's calendar window")
world:WindowEdit(calendarID, { title = "MC (moved)", hour = 22, minute = 0 })
world:RunFor(20)
event = ns.Events.Get(key)
H.check(event.ti == "MC (moved)" and ns.Events.DateOf(event.tm).hour == 22, "the organizer's client takes the new title and time")
world:RunFor(30)
H.eq(member.ns.Events.Get(key).ti, "MC (moved)", "and everyone has them")
world:WindowEdit(calendarID, { description = "Bring potions." })
world:RunFor(150)
H.eq(ns.Events.Get(key).de, "Bring potions.", "the description, once the organizer's client opens the event")
local calls = Count(organizer.calendarCalls, "UpdateEvent")
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "UpdateEvent"), calls, "nothing goes back to the calendar")
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
Errors("the calendar window's changes")

H.section("Calendar: sign-ups and statuses given in the game's calendar window")
local third = world:NewClient("Third Name", { rank = "Member", rankIndex = 3 })
world:Login(third)
world:RunFor(60)
world:WindowAnswer(third, calendarID, 6)
world:RunFor(30)
local thirdOwn = third.ns.Events.Mine(third.ns.Events.Get(key))
H.check(thirdOwn ~= nil and thirdOwn.st == 1, "a member's sign-up in the calendar reaches their addon")
world:RunFor(150)
world:WindowStatus(calendarID, third.guid, 4)
world:RunFor(150)
local signUp
for _, one in ipairs(ns.Events.SignUps(ns.Events.Get(key))) do
    if one.guid == third.guid then
        signUp = one
    end
end
H.eq(signUp and signUp.status, 3, "the organizer's status given there reaches the addon")
local function ThirdIn(client)
    for _, one in ipairs(client.ns.Events.SignUps(client.ns.Events.Get(key))) do
        if one.guid == third.guid then
            return one
        end
    end
end
H.check(ns.Events.SetStatus(key, third.guid, ns.Events.PROVISIONAL), "the organizer makes them tentative, as the game offers")
world:RunFor(5)
H.eq(InCalendar().invites[third.guid].status, 8, "Tentative in the calendar")
world:RunFor(30)
H.check(ns.States.IsTentative(ThirdIn(organizer)) and ns.States.IsTentative(ThirdIn(third)), "tentative in the addon, for everyone")
world:WindowStatus(calendarID, third.guid, 3)
world:RunFor(150)
H.check(ns.States.Goes(ThirdIn(organizer)) and ThirdIn(organizer).status == 1, "confirmed in the window: confirmed and going in the addon")
world:WindowStatus(calendarID, third.guid, 8)
world:RunFor(150)
H.check(ns.States.IsTentative(ThirdIn(organizer)), "made tentative in the window: tentative in the addon")
world:WindowAnswer(third, calendarID, nil)
world:RunFor(30)
H.eq(third.ns.Events.Mine(third.ns.Events.Get(key)), nil, "taking it back in the calendar takes it back in the addon")
world:ShowHidden()
world:RunFor(30)
Errors("the calendar window's answers")

H.section("Calendar: the organizer's own line")
local function OwnLine()
    return InCalendar().invites[organizer.guid].status
end
H.eq(OwnLine(), 3, "the organizer is Confirmed in the calendar")
H.check(ns.Events.SetStatus(key, organizer.guid, ns.Events.STANDBY), "they put themselves on standby in the addon")
world:RunFor(5)
H.eq(OwnLine(), 5, "and the calendar has it")
local mineNow = ns.Events.Mine(ns.Events.Get(key))
H.check(ns.Events.Answer(key, ns.Events.TENTATIVE, mineNow.ro), "they answer Tentative in the addon")
world:RunFor(5)
H.eq(OwnLine(), 8, "Tentative in the calendar")
H.check(ns.Events.Answer(key, ns.Events.DECLINED, mineNow.ro), "Not coming")
world:RunFor(5)
H.eq(OwnLine(), 4, "Out in the calendar (it offers its creator no Declined)")
world:WindowStatus(calendarID, organizer.guid, 3)
world:RunFor(150)
mineNow = ns.Events.Mine(ns.Events.Get(key))
H.check(mineNow.st == 1 and mineNow.status == 1, "Confirmed in the calendar: signed up and confirmed in the addon")
world:WindowStatus(calendarID, organizer.guid, 8)
world:RunFor(150)
H.eq(ns.Events.Mine(ns.Events.Get(key)).st, 2, "Tentative in the calendar: tentative in the addon")
world:WindowStatus(calendarID, organizer.guid, 3)
world:RunFor(150)
-- The organizer has the event open in the game's window and changes it there.
organizer.env.CalendarFrame = H.NewObject(organizer, "Frame")
organizer.env.CalendarFrame:Show()
organizer.env.CalendarCreateEventFrame = H.NewObject(organizer, "Frame")
organizer.env.CalendarCreateEventFrame:Show()
local C = organizer.env.C_Calendar
local now = H.CalendarTime(world)
local s = InCalendar().start
local offset = (s.year - now.year) * 12 + s.month - now.month
for index = 1, C.GetNumDayEvents(offset, s.day) do
    if C.GetDayEvent(offset, s.day, index).eventID == calendarID then
        C.OpenEvent(offset, s.day, index)
    end
end
world:RunFor(1)
world:WindowStatus(calendarID, organizer.guid, 5)
world:RunFor(1)
H.eq(ns.Events.Mine(ns.Events.Get(key)).status, 2, "a status given in the window, the event open there: in the addon at once")
world:WindowEdit(calendarID, { description = "Flasks too." })
organizer.world:FireEvent(organizer, "CALENDAR_UPDATE_EVENT")
world:RunFor(1)
H.eq(ns.Events.Get(key).de, "Flasks too.", "and so is its description")
C.CloseEvent()
organizer.env.CalendarCreateEventFrame:Hide()
organizer.env.CalendarFrame:Hide()
H.check(ns.Events.Answer(key, nil), "the organizer left with no answer of their own (as an earlier build let them)")
world:RunFor(150)
mineNow = ns.Events.Mine(ns.Events.Get(key))
H.check(OwnLine() == 4 and mineNow and mineNow.st == 1 and mineNow.status == 3,
    "the game keeps its creator, out: the addon shows them out too")
world:WindowStatus(calendarID, organizer.guid, 3)
world:RunFor(150)
Errors("the organizer's own line")

H.section("Calendar: copies of an event are deleted")
local original = ns.Events.Get(key)
world:WindowCreate(organizer, { title = original.ti, at = original.tm, type = original.ty })
world:WindowCreate(organizer, { title = original.ti, at = original.tm, type = original.ty })
world:RunFor(60)
H.check(#CalendarEvents() == 1 and CalendarEvents()[1].id == original.ci, "the copies go, the event stays")
H.eq(#ns.Events.List("upcoming"), 1, "and none comes into the addon")
Errors("copies")

H.section("Calendar: deleted in the game's calendar window")
-- Missing from a look at the calendar, and no new data of it says so (the
-- calendar's data incomplete for a moment): kept.
local OpenCalendar = organizer.env.C_Calendar.OpenCalendar
organizer.env.C_Calendar.OpenCalendar = function() end
world.calendar.events[calendarID].deleted = true
world:RunFor(35)
world.calendar.events[calendarID].deleted = nil
world:RunFor(12)
organizer.env.C_Calendar.OpenCalendar = OpenCalendar
world:RunFor(20)
H.check(ns.Events.Get(key) ~= nil and not InCalendar().deleted, "missing for a moment, no new data saying so: kept")
ns.EventForm.Open(key)
world:RunFor(5)
H.check(form:IsShown(), "the organizer changing it in the form")
-- Deleted in the game's window, open: asking for the calendar's data then
-- brought nothing in game (the addon waited until the window opened again).
organizer.env.C_Calendar.OpenCalendar = function() end
world:WindowDelete(calendarID)
world:RunFor(1)
organizer.env.C_Calendar.OpenCalendar = OpenCalendar
H.eq(ns.Events.Get(key), nil, "deleted there: deleted from the addon at once, on the calendar's own news of it")
H.check(not form:IsShown(), "the form changing it closes")
world:RunFor(30)
H.eq(member.ns.Events.Get(key), nil, "for everyone")
local creates = Count(organizer.calendarCalls, "AddEvent")
world:RunFor(60)
H.eq(Count(organizer.calendarCalls, "AddEvent"), creates, "nothing creates it again")
H.eq(#CalendarEvents(), 0, "no copies")
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
Errors("deleted in the calendar window")

H.section("Calendar: an event made in the game's calendar window")
local function MadeThere(title, days, type)
    local id = world:WindowCreate(organizer, { title = title, at = ns.Events.Now() + days * 86400 - (ns.Events.Now() % 60),
        type = type })
    world:RunFor(20)
    for _, one in ipairs(ns.Events.List("upcoming")) do
        if one.ci == id then
            return one, id
        end
    end
end
local adopted, made = MadeThere("Zul'Gurub", 3, 0)
H.check(adopted ~= nil and adopted.ti == "Zul'Gurub" and adopted.ty == 0 and adopted.owner == organizer.guid,
    "its creator's client brings it into the addon")
world:RunFor(30)
H.check(member.ns.Events.Get(adopted.key) ~= nil, "for everyone")
H.check(#CalendarEvents() == 1 and CalendarEvents()[1].id == made, "and makes no copy")
Errors("made in the calendar window")

H.section("Calendar: Delete event deletes it, for everyone, with no getting it back")
local doomed, doomedID = MadeThere("Doomed", 4, 1)
world:RunFor(30)
H.check(doomed ~= nil and member.ns.Events.Get(doomed.key) ~= nil, "an event of the organizer's, everyone's")
ns.EventForm.Open(doomed.key)
world:RunFor(5)
form:Hide()
organizer.inClick = true
ns.Calendar.Delete(doomed.key)
organizer.inClick = false
H.check(world.calendar.events[doomedID].deleted, "the event was open (the form had just opened it): deleted inside the click")
H.check(ns.Events.Get(doomed.key) ~= nil and ns.Calendar.Deleting(doomed.key), "the addon waits for the calendar")
world:RunFor(1)
H.check(ns.Events.Get(doomed.key) == nil and not ns.Calendar.Deleting(doomed.key),
    "the calendar no longer has it: deleted from the addon")
world:RunFor(30)
H.eq(member.ns.Events.Get(doomed.key), nil, "for everyone")
creates = Count(organizer.calendarCalls, "AddEvent")
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), creates, "nothing creates it again")
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
local closed, closedID = MadeThere("Doomed too", 5, 1)
H.check(ns.Calendar.Delete(closed.key) and ns.Calendar.Deleting(closed.key) and ns.Events.Get(closed.key) ~= nil,
    "deleting an event not open: the calendar first, the addon waits for it")
world:RunFor(5)
H.check(world.calendar.events[closedID].deleted and ns.Events.Get(closed.key) == nil and not ns.Calendar.Deleting(closed.key),
    "opened, deleted a moment later, then deleted from the addon")
world:RunFor(30)
local back = false
for _, one in ipairs(member.ns.Events.List("upcoming")) do
    back = back or one.key == doomed.key or one.key == closed.key or one.ti == "Doomed" or one.ti == "Doomed too"
end
H.check(not back, "and never taken back into the addon")
Errors("Delete event")

H.section("Calendar: a weekly event's next one")
local weekly = ns.Events.Create({ ty = 1, ti = "Dungeon night", tm = ns.Events.Now() - 4 * 3600, ml = 0, wk = true })
world:RunFor(5)
ns.Events.Tidy()
world:RunFor(20)
pending = ns.Calendar.Pending()
H.check(#pending == 2 and pending[1].kind == "create" and pending[1].event.ti == "Dungeon night" and pending[1].event.wk
    and pending[2].event.tm == pending[1].event.tm + ns.Events.WEEK,
    "this week's started: next week's and the one after wait for the organizer's clicks")
H.check(pending[1].key ~= weekly and pending[2].key ~= weekly, "each an event of its own")
local nextKey, laterKey = pending[1].key, pending[2].key
local addsBefore = Count(organizer.calendarCalls, "AddEvent")
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), addsBefore, "nothing creates them by itself (the game refuses so many so fast)")
H.check(ns.Calendar.Unsent(ns.Events.Get(nextKey)) and ns.Calendar.SendBlocked() == nil, "each has its own button, on")
organizer.inClick = true
H.check(ns.Calendar.SendNow(nextKey), "its button creates it in the calendar")
organizer.inClick = false
world:RunFor(30)
local nextEvent = ns.Events.Get(nextKey)
H.check(nextEvent.ci ~= 0 and world.calendar.events[nextEvent.ci].title == "Dungeon night", "linked once the calendar has it")
H.check(not ns.Calendar.Unsent(nextEvent), "and its button goes")
H.eq(#ns.Calendar.Pending(), 1, "the other waits for its own")
organizer.inClick = true
ns.Calendar.SendNow(laterKey)
organizer.inClick = false
world:RunFor(30)
H.eq(#ns.Calendar.Pending(), 0, "nothing waits any more")
Errors("weekly events")

H.section("Calendar: the game's calendar window open")
organizer.env.CalendarFrame = H.NewObject(organizer, "Frame")
local windowHeard = 0
organizer.env.CalendarFrame:RegisterEvent("CALENDAR_OPEN_EVENT")
organizer.env.CalendarFrame:SetScript("OnEvent", function(_, event)
    if event == "CALENDAR_OPEN_EVENT" then
        windowHeard = windowHeard + 1
    end
end)
organizer.env.CalendarFrame:Show()
ns.EventForm.Open(nextKey)
world:RunFor(5)
form.TitleBox:SetText("Dungeon night!")
H.Click(form.Save)
world:RunFor(10)
H.eq(world.calendar.events[nextEvent.ci].title, "Dungeon night!", "a change goes in with the window open")
H.eq(windowHeard, 0, "the window does not show its own panel for the event we open (it would close the guild window)")
H.check(organizer.eventFrames.CALENDAR_OPEN_EVENT[organizer.env.CalendarFrame], "and hears that event again right after")
organizer.env.CalendarCreateEventFrame = H.NewObject(organizer, "Frame")
organizer.env.CalendarCreateEventFrame:Show()
local opened = Count(organizer.calendarCalls, "OpenEvent")
H.check(organizer.ns.Events.SetStatus(nextKey, member.guid, 1) ~= nil, "a status given meanwhile")
world:RunFor(60)
H.eq(Count(organizer.calendarCalls, "OpenEvent"), opened, "nothing is opened while the player makes an event there")
organizer.env.CalendarCreateEventFrame:Hide()
organizer.env.CalendarFrame:Hide()
world:RunFor(30)
Errors("the calendar window")

H.section("Calendar: a locked event")
local lockID = ns.Events.Get(nextKey).ci
local function Locked()
    return world.calendar.events[lockID].locked == true
end
ns.EventForm.Open(nextKey)
world:RunFor(5)
H.check(not form.Lock:GetChecked(), "the form shows it unlocked")
form.Lock:SetChecked(true)
H.Click(form.Save)
H.check(Locked(), "Lock event and Save: locked in the calendar inside the click")
H.check(ns.Events.Get(nextKey).lk, "and in the addon")
world:RunFor(30)
H.check(member.ns.Events.Get(nextKey).lk, "for everyone")
H.check(Locked() and ns.Events.Get(nextKey).lk, "still locked once the calendar's data came again")
local signUps = Count(member.calendarCalls, "EventSignUp")
H.check(member.ns.Events.Answer(nextKey, member.ns.Events.SIGNED, member.ns.Events.TANK),
    "a member's answer made anyway (a client that knows nothing of locks)")
world:RunFor(60)
H.eq(Count(member.calendarCalls, "EventSignUp"), signUps, "a locked event takes no answers: nothing is sent")
H.eq(world.calendar.events[lockID].invites[member.guid], nil, "the calendar has none")
world:WindowEdit(lockID, { locked = false })
world:RunFor(20)
H.check(not ns.Events.Get(nextKey).lk, "unlocked in the game's calendar window: unlocked in the addon")
world:RunFor(60)
H.check(world.calendar.events[lockID].invites[member.guid] ~= nil, "the member's answer goes in then")
world:WindowEdit(lockID, { locked = true })
world:RunFor(20)
H.check(ns.Events.Get(nextKey).lk, "locked there: locked in the addon")
local updates = Count(organizer.calendarCalls, "UpdateEvent")
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "UpdateEvent"), updates, "nothing goes back to the calendar")
ns.EventForm.Open(nextKey)
world:RunFor(5)
H.check(form.Lock:GetChecked(), "the form shows it locked")
form.Lock:SetChecked(false)
H.Click(form.Save)
H.check(not Locked() and not ns.Events.Get(nextKey).lk, "unlocked from the form: in both")
world:RunFor(30)
H.check(not Locked() and not ns.Events.Get(nextKey).lk, "and it stays so")
Errors("a locked event")

H.section("Calendar: a member signs up in the game's calendar window, the event open there")
third.env.CalendarFrame = H.NewObject(third, "Frame")
third.env.CalendarFrame:Show()
third.env.CalendarViewEventFrame = H.NewObject(third, "Frame")
third.env.CalendarViewEventFrame:Show()
local opens = Count(third.calendarCalls, "OpenEvent")
world:WindowAnswer(third, lockID, 6)
world:RunFor(1)
local thirdMine = third.ns.Events.Mine(third.ns.Events.Get(nextKey))
H.check(thirdMine ~= nil and thirdMine.st == 1, "their addon takes it at once, the event still open in the window")
H.eq(Count(third.calendarCalls, "OpenEvent"), opens, "opening nothing meanwhile")
world:RunFor(30)
local seenByOrganizer
for _, one in ipairs(ns.Events.SignUps(ns.Events.Get(nextKey))) do
    if one.guid == third.guid then
        seenByOrganizer = one
    end
end
H.check(seenByOrganizer ~= nil and seenByOrganizer.st == 1, "and the organizer has it too")
third.env.CalendarViewEventFrame:Hide()
third.env.CalendarFrame:Hide()
world:RunFor(30)
Errors("a member's answer in the window")

H.section("Calendar: a moderator's deletion reaching the organizer before the calendar's")
ns.EventForm.Open(nil)
form.TitleBox:SetText("To clear")
H.Click(form.Save)
world:RunFor(20)
local toClear
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ti == "To clear" then
        toClear = one
    end
end
H.check(toClear ~= nil and toClear.ci ~= 0, "an event of the organizer's, in the calendar")
local clearKey, clearID = toClear.key, toClear.ci
H.check(member.ns.Events.Answer(clearKey, 1, 3), "a member signs up")
world:RunFor(60)
H.check(ns.Events.SetModerator(clearKey, member.guid, true), "and is named a moderator")
world:RunFor(30)
-- Their client's deletion, as it travels when the calendar did not have it.
H.check(member.ns.Events.Delete(clearKey) and member.ns.Events.Get(clearKey) == nil, "the moderator deletes it")
world:RunFor(30)
H.eq(ns.Events.Get(clearKey), nil, "the organizer has it deleted too")
local inRecord = false
for _, base in ipairs(ns.Data.GetOwnRecord(false).ev or {}) do
    inRecord = inRecord or organizer.guid .. "/" .. base.id == clearKey
end
H.check(not inRecord, "and their client takes it out of their record")
H.check(world.calendar.events[clearID].deleted, "its calendar event, still there, goes too")
local takenBack = false
for _, one in ipairs(ns.Events.List("upcoming")) do
    takenBack = takenBack or one.ci == clearID or one.ti == "To clear"
end
H.check(not takenBack, "and is never taken back into the addon")
Errors("a moderator's deletion first")

H.section("Calendar: the game's own limit of events created")
local function MadeInCalendar()
    local made = 0
    for _, one in pairs(world.calendar.events) do
        if not one.deleted and one.creator == organizer.guid then
            made = made + 1
        end
    end
    return made
end
organizer.env.CALENDAR_ERROR_EVENTS_EXCEEDED = "You have reached your limit of %d events created."
local limitNow = MadeInCalendar()
organizer.eventLimit = limitNow
local LIMIT_TEXT = ("You have reached your limit of %d events created."):format(limitNow)
local function Titled(title)
    for _, one in ipairs(ns.Events.List("upcoming")) do
        if one.ti == title then
            return one
        end
    end
end
ns.EventForm.Open(nil)
form.TitleBox:SetText("Over the limit")
H.Click(form.Save)
H.check(Titled("Over the limit") == nil, "Create tries the calendar first: nothing in the addon yet")
H.check(form:IsShown() and not form.Save:IsEnabled(), "the form waits for the calendar's answer")
world:RunFor(5)
H.check(Titled("Over the limit") == nil, "the game refuses it: nothing comes into the addon")
H.check(form:IsShown() and not form.Save:IsEnabled() and form.Save.reason == LIMIT_TEXT,
    "the form stays, Create off with the game's words as its tooltip")
H.eq(form.Error:GetText(), LIMIT_TEXT, "and the form says it")
H.eq(ns.Calendar.lastError, LIMIT_TEXT, "so does the tab, with the game's count")
H.check(ns.Calendar.AtLimit(), "the addon knows the player is at the limit")
form:Hide()
organizer.eventLimit = nil
world.calendar.events[lockID].deleted = true
world:RunFor(20)
H.check(not ns.Calendar.AtLimit(), "one of theirs gone from the calendar: no longer at the limit")
H.eq(ns.Events.Get(nextKey), nil, "(and gone from the addon)")
H.check(ns.Calendar.CreatedCount() > 0, "and /gevents status counts the events the player created in the calendar")
ns.EventForm.Open(nil)
H.check(form.Save:IsEnabled(), "Create is on again")
form.TitleBox:SetText("Under the limit")
H.Click(form.Save)
world:RunFor(5)
local under = Titled("Under the limit")
H.check(under ~= nil and under.ci ~= 0 and world.calendar.events[under.ci].title == "Under the limit" and not form:IsShown(),
    "a new event comes into the addon once the calendar has it, linked, and the form closes")
local weeklyKey = ns.Events.Create({ ty = 0, ti = "Weekly over", tm = ns.Events.Now() + 2 * 86400, ml = 0, wk = true })
local limitThen = MadeInCalendar()
organizer.eventLimit = limitThen
organizer.inClick = true
H.check(ns.Calendar.SendNow(weeklyKey), "a weekly event's button sends it")
organizer.inClick = false
world:RunFor(5)
local stays = ns.Events.Get(weeklyKey)
H.check(stays ~= nil and stays.ci == 0 and ns.Calendar.Unsent(stays), "refused by the game: the event stays, waiting, never deleted")
H.eq(ns.Calendar.SendBlocked(), ("You have reached your limit of %d events created."):format(limitThen),
    "its button off, with the game's words")
organizer.eventLimit = nil
Errors("the game's limit")

H.section("Calendar: a deletion the game refuses with no click is tried again a while later")
ns.EventForm.Frame():Hide()
local function CopiesOf(event)
    local count = 0
    for _, other in ipairs(CalendarEvents()) do
        if other.id ~= event.ci and other.title == event.ti and ns.Events.Naive(other.start.year, other.start.month,
                other.start.day, other.start.hour, other.start.minute) == event.tm then
            count = count + 1
        end
    end
    return count
end
local kept = ns.Events.Get(adopted.key)
local keptID = kept.ci
world.restrictRemove = true
world:WindowCreate(organizer, { title = kept.ti, at = kept.tm, type = kept.ty })
world:RunFor(30)
H.eq(CopiesOf(kept), 1, "a copy the game does not let go with no click stays")
world.restrictRemove = nil
world:RunFor(120)
H.eq(CopiesOf(kept), 1, "not tried again at once")
world:RunFor(600)
H.eq(CopiesOf(kept), 0, "a while later it goes, with no click")
H.check(ns.Events.Get(kept.key).ci == keptID and not world.calendar.events[keptID].deleted, "the event itself stays")
world.errors = {}

H.section("Calendar: the window is told only what changed")
world:RunFor(150)
local told = 0
ns.On("CalendarPending", function()
    told = told + 1
end)
world:RunFor(60)
H.check(told <= 1, ("a quiet minute (six looks at the calendar) tells the window almost nothing (%d)"):format(told))
local toldBefore = told
local toldKey = ns.Events.Create({ ty = 4, ti = "Told", tm = ns.Events.Now() + 5 * 86400, ml = 0 })
world:RunFor(15)
H.check(told > toldBefore and ns.Calendar.Unsent(ns.Events.Get(toldKey)), "an event waiting for its button is told")
told = 0
H.check(ns.Calendar.Delete(toldKey) and ns.Events.Get(toldKey) == nil, "not in the calendar yet: deleted from the addon at once")
world:RunFor(10)
H.check(told > 0, "and the window is told")
Errors("the window told")

H.section("Calendar: the game refusing another call leaves a deletion or a new event alone")
kept = ns.Events.Get(adopted.key)
ns.EventForm.Open(kept.key)
world:RunFor(5)
ns.EventForm.Frame():Hide()
ns.Calendar.Delete(kept.key)
world:FireEvent(organizer, "ADDON_ACTION_BLOCKED", "GuildRaidsEvents", "EventSetInviteStatus()")
world:RunFor(30)
H.check(ns.Events.Get(kept.key) == nil and world.calendar.events[keptID].deleted,
    "another call refused meanwhile: the event is deleted all the same, from both")
ns.EventForm.Open(nil)
form.TitleBox:SetText("Onyxia (resist gear)")
form.Limit:SetChecked(true)
form.Tanks:SetText("1")
H.Click(form.Save)
world:FireEvent(organizer, "ADDON_ACTION_BLOCKED", "GuildRaidsEvents", "OpenEvent()")
world:RunFor(30)
local onyxia
for _, event in ipairs(ns.Events.List("upcoming")) do
    if event.ti == "Onyxia (resist gear)" then
        onyxia = event
    end
end
H.check(onyxia ~= nil and onyxia.sl ~= nil and onyxia.sl.t == 1 and onyxia.ci ~= 0 and not form:IsShown(),
    "a new event too: it comes in whole from the form, which closes")
world.errors = {}

H.section("Calendar: a moderator's client keeps the event in step while its organizer is away")
ns.EventForm.Open(nil)
form.TitleBox:SetText("Away raid")
H.Click(form.Save)
world:RunFor(10)
local away
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ti == "Away raid" then
        away = one
    end
end
H.check(away ~= nil and away.ci ~= 0, "an event in the calendar")
local awayKey, awayID = away.key, away.ci
local function AwayInvite(guid)
    return world.calendar.events[awayID].invites[guid]
end
H.check(member.ns.Events.Answer(awayKey, 1, 2), "a member signs up")
world:RunFor(60)
H.check(ns.Events.SetModerator(awayKey, member.guid, true), "and is named a moderator")
world:RunFor(30)
H.eq(AwayInvite(member.guid).modStatus, "MODERATOR", "in the calendar too")
world:Logout(organizer)
world:WindowEdit(awayID, { title = "Away raid (moved)" })
world:RunFor(20)
H.eq(member.ns.Events.Get(awayKey).ti, "Away raid (moved)",
    "the organizer away, a change made in the calendar window comes in through the moderator's client")
world:RunFor(30)
H.eq(second.ns.Events.Get(awayKey).ti, "Away raid (moved)", "for everyone")
H.check(second.ns.Events.Answer(awayKey, 1, 1), "another member signs up")
world:RunFor(60)
H.check(member.ns.Events.SetStatus(awayKey, second.guid, 2), "the moderator puts them on standby")
world:RunFor(30)
H.eq(AwayInvite(second.guid).status, 5, "it reaches the calendar through the moderator's client")
H.check(member.ns.Events.SetStatus(awayKey, organizer.guid, 2), "the moderator puts the organizer on standby too")
world:RunFor(30)
H.eq(AwayInvite(organizer.guid).status, 5, "the organizer's line in the calendar too, as the game lets a moderator")
world:WindowStatus(awayID, organizer.guid, 8)
world:RunFor(150)
local creatorLine
for _, signUp in ipairs(member.ns.Events.SignUps(member.ns.Events.Get(awayKey))) do
    if signUp.guid == organizer.guid then
        creatorLine = signUp
    end
end
H.check(creatorLine ~= nil and member.ns.States.IsTentative(creatorLine),
    "the organizer made tentative in the game's window comes into the addon through the moderator's client")
world:Login(organizer)
world:RunFor(60)
ns = organizer.ns
H.eq(ns.Events.Get(awayKey).ti, "Away raid (moved)", "the organizer, back, has it all")
H.check(ns.States.IsTentative(ns.Events.Mine(ns.Events.Get(awayKey))) and AwayInvite(organizer.guid).status == 8,
    "their own state too, as the calendar has it")
world.errors = {}

H.section("Calendar: a moderator who takes their sign-up back is one no more")
H.check(member.ns.Rights.MayIManage(member.ns.Events.Get(awayKey)), "a moderator")
H.check(member.ns.Events.Answer(awayKey, nil), "takes their sign-up back")
world:RunFor(30)
H.check(not member.ns.Rights.MayIManage(member.ns.Events.Get(awayKey)) and not ns.Events.Get(awayKey).md[member.guid],
    "and is a moderator no more, for everyone")
world:ShowHidden()
H.check(member.ns.Events.Answer(awayKey, 1, 2), "signs up again")
world:RunFor(320)
H.check(AwayInvite(member.guid) ~= nil and AwayInvite(member.guid).modStatus ~= "MODERATOR"
    and not member.ns.Rights.MayIManage(member.ns.Events.Get(awayKey)),
    "and is not one again, in the addon or in the calendar, as in the game")
world.errors = {}

H.section("Calendar: a moderator deletes an event, for everyone")
H.check(ns.Events.SetModerator(awayKey, second.guid, true), "another moderator")
world:RunFor(30)
H.check(third.ns.Events.Answer(awayKey, 1, 3), "a third member signs up")
world:RunFor(60)
H.check(ns.Events.SetModerator(awayKey, third.guid, true), "and is named a moderator too")
world:RunFor(30)
H.check(third.ns.Rights.MayIManage(third.ns.Events.Get(awayKey)), "they manage it")
-- Gone from their own calendar for a while, still in the guild's list.
world.calendar.hidden[third.guid] = { [awayID] = true }
world:FireEvent(third, "CALENDAR_UPDATE_EVENT_LIST")
world:RunFor(30)
H.check(ns.Events.Get(awayKey) ~= nil and third.ns.Events.Get(awayKey) ~= nil,
    "an event gone from a moderator's own calendar for a while, still the guild's: not deleted")
world.calendar.hidden[third.guid] = nil
world:FireEvent(third, "CALENDAR_UPDATE_EVENT_LIST")
world:RunFor(10)
world:WindowAnswer(third, awayID, nil)
world:RunFor(60)
H.check(ns.Events.Get(awayKey) ~= nil and not world.calendar.events[awayID].deleted,
    "they take their sign-up back in the game's window: gone from their calendar for a while, the event is not deleted")
H.check(not ns.Events.IsModerator(ns.Events.Get(awayKey), third.guid), "and they are a moderator no more")
H.check(second.ns.Calendar.Delete(awayKey), "the other moderator deletes the event")
world:RunFor(10)
H.check(world.calendar.events[awayID].deleted and second.ns.Events.Get(awayKey) == nil,
    "the calendar first, then gone from their addon")
world:RunFor(30)
H.check(ns.Events.Get(awayKey) == nil and member.ns.Events.Get(awayKey) == nil and third.ns.Events.Get(awayKey) == nil,
    "for everyone")
local stillOwned = false
for _, base in ipairs(ns.Data.GetOwnRecord(false).ev or {}) do
    stillOwned = stillOwned or organizer.guid .. "/" .. base.id == awayKey
end
H.check(not stillOwned, "and the organizer's client takes it out of their record")
world.errors = {}

H.section("Calendar: an officer deletes any event, as the game's calendar lets them")
ns.EventForm.Open(nil)
local laterForm = ns.EventForm.Frame()
laterForm.TitleBox:SetText("For an officer to delete")
H.Click(laterForm.Save)
world:RunFor(30)
local forOfficer
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ti == "For an officer to delete" then
        forOfficer = one
    end
end
H.check(forOfficer ~= nil and forOfficer.ci ~= 0, "an event of the organizer's, in the calendar")
local officerSees = officer.ns.Events.Get(forOfficer.key)
H.check(officerSees ~= nil and not officer.ns.Rights.MayIManage(officerSees) and officer.ns.Rights.MayIDelete(officerSees),
    "an officer does not manage it, but may delete it")
H.check(officer.ns.Calendar.Delete(forOfficer.key), "the officer deletes it")
world:RunFor(10)
H.check(world.calendar.events[forOfficer.ci].deleted and officer.ns.Events.Get(forOfficer.key) == nil,
    "the calendar first, then gone from their addon")
world:RunFor(30)
H.check(ns.Events.Get(forOfficer.key) == nil and member.ns.Events.Get(forOfficer.key) == nil, "for everyone")
world.errors = {}
