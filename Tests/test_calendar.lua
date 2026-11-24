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

-- A click of the organizer somewhere in the addon's window.
local function ClickSomewhere(client)
    client.inClick = true
    client.ns.Calendar.OnClick()
    client.inClick = false
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
H.eq(#ns.Calendar.Pending(), 0, "nothing waits for a click")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), 1, "a later click does not create it again")
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

H.section("Calendar: a change made with no click goes with the next one")
local event = ns.Events.Get(key)
H.check(ns.Events.Change(key, { ty = 0, ti = event.ti, tm = event.tm, de = "Moved.", ml = 0, sl = event.sl, ac = true }),
    "a change with no click (another addon, say)")
world:RunFor(20)
local pending = ns.Calendar.Pending()
H.check(#pending == 1 and pending[1].kind == "update", "it waits for a click")
ns.Calendar.RunPending()
world:RunFor(5)
H.eq(InCalendar().description, "", "outside a click the game refuses it")
H.check(ns.Calendar.lastError ~= nil, "and the window says so")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(InCalendar().description, "Moved.", "the organizer's next click anywhere in the addon puts it in")
world:RunFor(20)
H.eq(#ns.Calendar.Pending(), 0, "nothing waits any more")

H.section("Calendar: an officer's change goes in with the organizer's click")
local officer = world:NewClient("Officer Name", { rank = "Officer", rankIndex = 1 })
world:Login(officer)
world:RunFor(60)
event = officer.ns.Events.Get(key)
H.check(officer.ns.Events.Change(key, { ty = 0, ti = "MC", tm = event.tm, de = event.de, ml = 0, sl = event.sl, ac = true }),
    "an officer changes it")
world:RunFor(30)
H.eq(#officer.ns.Calendar.Pending(), 0, "nothing waits for the officer's click")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(InCalendar().title, "MC", "the organizer's click puts it in the calendar")
Errors("changes")

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
ClickSomewhere(organizer)
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

H.section("Calendar: cancelling deletes it with the same click")
ns.EventForm.Open(key)
world:RunFor(5)
form:Hide()
organizer.inClick = true
ns.Calendar.Cancel(key)
organizer.inClick = false
H.check(InCalendar().deleted, "the event was open (the form had just changed it): deleted inside the click")
H.check(ns.Events.Get(key).x, "the addon keeps it, marked cancelled")
world:RunFor(30)
H.eq(#ns.Calendar.Pending(), 0, "nothing waits")
local creates = Count(organizer.calendarCalls, "AddEvent")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), creates, "and nothing creates it again")
organizer.inClick = true
H.check(ns.Calendar.Restore(key), "restoring it")
organizer.inClick = false
world:RunFor(30)
H.check(not ns.Events.Get(key).x and #CalendarEvents() == 1 and ns.Events.Get(key).ci == CalendarEvents()[1].id,
    "creates it again in the same click, linked")
calendarID = ns.Events.Get(key).ci
Errors("cancelling")

H.section("Calendar: restoring keeps everyone's states")
local mineBefore = ns.Events.Mine(ns.Events.Get(key))
H.check(ns.Events.SetStatus(key, organizer.guid, ns.Events.STANDBY), "the organizer on standby")
H.check(member.ns.Events.Answer(key, member.ns.Events.SIGNED, member.ns.Events.TANK), "a member signed up")
world:RunFor(30)
-- From tentative to signed up, the game hides the event from the member
-- for a while (world:ShowHidden() brings it back).
world:ShowHidden()
world:RunFor(320)
H.eq(InCalendar().invites[organizer.guid].status, 5, "the organizer on standby in the calendar")
H.check(InCalendar().invites[member.guid] ~= nil and InCalendar().invites[member.guid].status ~= 8, "the member signed up there")
organizer.inClick = true
ns.Calendar.Cancel(key)
organizer.inClick = false
world:RunFor(10)
organizer.inClick = true
ns.Calendar.Restore(key)
organizer.inClick = false
world:RunFor(60)
calendarID = ns.Events.Get(key).ci
H.eq(InCalendar().invites[organizer.guid].status, 5, "made again, the calendar takes the organizer's standby from the addon")
H.eq(ns.Events.Mine(ns.Events.Get(key)).status, ns.Events.STANDBY, "and the addon keeps it")
H.check(InCalendar().invites[member.guid] ~= nil and member.ns.Events.Mine(member.ns.Events.Get(key)).st == 1,
    "the member's sign-up goes to it again, and stays in the addon")
ns.Events.SetStatus(key, organizer.guid, mineBefore.status)
world:RunFor(30)
Errors("restoring")

H.section("Calendar: deleted in the game's calendar window")
-- Missing for a moment (the calendar's data incomplete), then back.
world.calendar.events[calendarID].deleted = true
world:RunFor(12)
world.calendar.events[calendarID].deleted = nil
world:RunFor(30)
H.check(not ns.Events.Get(key).x and not InCalendar().deleted, "missing for a moment: restored when back, never deleted")
local OpenCalendar = organizer.env.C_Calendar.OpenCalendar
organizer.env.C_Calendar.OpenCalendar = function() end
world:WindowDelete(calendarID)
world:RunFor(1)
organizer.env.C_Calendar.OpenCalendar = OpenCalendar
H.check(ns.Events.Get(key).x, "deleted there: cancelled in the addon at once")
creates = Count(organizer.calendarCalls, "AddEvent")
for _ = 1, 3 do
    ClickSomewhere(organizer)
    world:RunFor(20)
end
H.eq(Count(organizer.calendarCalls, "AddEvent"), creates, "clicks never create it again")
H.eq(#CalendarEvents(), 0, "no copies")
Errors("deleted in the calendar window")

H.section("Calendar: copies of an event are deleted")
local restored = ns.Events.Get(key)
organizer.inClick = true
ns.Calendar.Restore(key)
organizer.inClick = false
world:RunFor(30)
local original = ns.Events.Get(key).ci
local copyAt = restored.tm
world:WindowCreate(organizer, { title = restored.ti, at = copyAt, type = 0 })
world:WindowCreate(organizer, { title = restored.ti, at = copyAt, type = 0 })
world:RunFor(60)
H.check(#CalendarEvents() == 1 and CalendarEvents()[1].id == original, "the copies go, the event stays")
H.eq(#ns.Events.List("upcoming"), 1, "and none comes into the addon")
Errors("copies")

H.section("Calendar: an event made in the game's calendar window")
local made = world:WindowCreate(organizer, { title = "Zul'Gurub", at = ns.Events.Now() + 3 * 86400 - (ns.Events.Now() % 60),
    type = 0 })
world:RunFor(20)
local adopted
for _, one in ipairs(ns.Events.List("upcoming")) do
    if one.ci == made then
        adopted = one
    end
end
H.check(adopted ~= nil and adopted.ti == "Zul'Gurub" and adopted.ty == 0 and adopted.owner == organizer.guid,
    "its creator's client brings it into the addon")
world:RunFor(30)
H.check(member.ns.Events.Get(adopted.key) ~= nil, "for everyone")
H.eq(#CalendarEvents(), 2, "and makes no copy")
local adoptedID = adopted.ci
H.check(ns.Calendar.Cancel(adopted.key) == false, "an event not open cannot go inside the click")
world:RunFor(5)
H.check(world.calendar.events[adoptedID].deleted, "it is opened, then deleted a moment later")
Errors("made in the calendar window")

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
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(Count(organizer.calendarCalls, "AddEvent"), addsBefore, "a click elsewhere creates nothing (the game refuses so many so fast)")
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
ClickSomewhere(organizer)
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

H.section("Calendar: clearing one's cancelled event deletes it")
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
H.check(ns.Events.Cancel(clearKey), "cancelled")
ns.UI.Clear({ ns.Events.Get(clearKey) })
H.eq(ns.Events.Get(clearKey), nil, "cleared from their list before the calendar deleted it: gone from the addon")
world:RunFor(30)
H.check(world.calendar.events[clearID].deleted, "and deleted from the calendar too")
H.eq(member.ns.Events.Get(clearKey), nil, "for everyone")
local takenBack = false
for _, one in ipairs(ns.Events.List("upcoming")) do
    takenBack = takenBack or one.ci == clearID or one.ti == "To clear"
end
H.check(not takenBack, "and never taken back into the addon")
Errors("clearing one's own")

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
local cancelledOwn = ns.Events.Get(adopted.key)
H.check(cancelledOwn ~= nil and cancelledOwn.x, "a cancelled event of the organizer's")
organizer.inClick = true
H.check(ns.Calendar.Restore(adopted.key), "restoring it sends it to the calendar first")
organizer.inClick = false
H.check(ns.Events.Get(adopted.key).x and ns.Calendar.Restoring(adopted.key), "still cancelled while the calendar answers")
world:RunFor(5)
H.check(ns.Events.Get(adopted.key).x and not ns.Calendar.Restoring(adopted.key), "refused by the game: it stays cancelled")
organizer.eventLimit = nil
world.calendar.events[lockID].deleted = true
world:RunFor(20)
H.check(not ns.Calendar.AtLimit(), "one of theirs gone from the calendar: no longer at the limit")
H.check(ns.Calendar.CreatedCount() > 0, "and /gevents status counts the events the player created in the calendar")
ns.EventForm.Open(nil)
H.check(form.Save:IsEnabled(), "Create is on again")
form.TitleBox:SetText("Under the limit")
H.Click(form.Save)
world:RunFor(5)
local under = Titled("Under the limit")
H.check(under ~= nil and under.ci ~= 0 and world.calendar.events[under.ci].title == "Under the limit" and not form:IsShown(),
    "a new event comes into the addon once the calendar has it, linked, and the form closes")
organizer.inClick = true
H.check(ns.Calendar.Restore(adopted.key), "restoring under the limit")
organizer.inClick = false
world:RunFor(5)
local restoredNow = ns.Events.Get(adopted.key)
H.check(not restoredNow.x and restoredNow.ci ~= 0 and not world.calendar.events[restoredNow.ci].deleted,
    "restored in the addon once the calendar has it again, linked")
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

H.section("Calendar: a change the game takes back is not lost")
ns.EventForm.Frame():Hide()
local kept = ns.Events.Get(adopted.key)
local keptID = kept.ci
H.check(ns.Events.Change(kept.key, { ty = kept.ty, ti = "Zul'Gurub (late)", tm = kept.tm, ml = 0 }),
    "a change with no click")
world:RunFor(20)
local updateEvent = organizer.env.C_Calendar.UpdateEvent
organizer.env.C_Calendar.UpdateEvent = function()
    error("the game refused it")
end
ClickSomewhere(organizer)
organizer.env.C_Calendar.UpdateEvent = updateEvent
H.eq(world.calendar.events[keptID].title, "Zul'Gurub", "the click's call fails: the calendar keeps its title")
world:RunFor(30)
H.eq(ns.Events.Get(kept.key).ti, "Zul'Gurub (late)", "the addon keeps the change, not the calendar's old title")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(world.calendar.events[keptID].title, "Zul'Gurub (late)", "the next click puts it in")
world.errors = {}

H.section("Calendar: deletions the game takes only in a click")
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
kept = ns.Events.Get(adopted.key)
world.restrictRemove = true
world:WindowCreate(organizer, { title = kept.ti, at = kept.tm, type = kept.ty })
world:RunFor(30)
H.eq(CopiesOf(kept), 1, "a copy the game does not let go with no click stays")
ClickSomewhere(organizer)
world:RunFor(10)
H.eq(CopiesOf(kept), 0, "the next click deletes it")
world.restrictRemove = nil
world:WindowCreate(organizer, { title = kept.ti, at = kept.tm, type = kept.ty })
world:RunFor(30)
H.eq(CopiesOf(kept), 0, "and with the game letting it, the next copy goes with no click again")
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
ns.Events.Change(kept.key, { ty = kept.ty, ti = "Zul'Gurub (later)", tm = kept.tm, ml = 0 })
world:RunFor(15)
H.check(told >= 1 and ns.Calendar.Pending()[1] ~= nil, "a change waiting for a click is told")
ClickSomewhere(organizer)
world:RunFor(10)
Errors("the window told")

H.section("Calendar: the game refusing another call leaves a new or restored event alone")
kept = ns.Events.Get(adopted.key)
ns.EventForm.Open(kept.key)
world:RunFor(5)
ns.EventForm.Frame():Hide()
ns.Calendar.Cancel(kept.key)
world:RunFor(30)
H.check(ns.Events.Get(kept.key).x and world.calendar.events[kept.ci].deleted, "cancelled, its calendar event deleted")
organizer.inClick = true
H.check(ns.Calendar.Restore(kept.key), "restoring it")
organizer.inClick = false
world:FireEvent(organizer, "ADDON_ACTION_BLOCKED", "GuildRaidsEvents", "EventSetInviteStatus()")
world:RunFor(60)
local back = ns.Events.Get(kept.key)
H.check(not back.x and back.ci ~= 0 and not world.calendar.events[back.ci].deleted,
    "another call refused meanwhile: it is restored all the same, linked, and its calendar event stays")
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

H.section("Calendar: a deletion that wanted a click, gone some other way")
kept = ns.Events.Get(adopted.key)
world.restrictRemove = true
local copyID = world:WindowCreate(organizer, { title = kept.ti, at = kept.tm, type = kept.ty })
world:RunFor(30)
H.check(ns.CalendarOrganizer.needsClick and CopiesOf(kept) == 1, "the game refuses deleting a copy with no click")
world:WindowDelete(copyID)
world.restrictRemove = nil
world:RunFor(20)
H.check(not ns.CalendarOrganizer.needsClick, "deleted in the game's window: nothing waits for a click any more")
world:WindowCreate(organizer, { title = kept.ti, at = kept.tm, type = kept.ty })
world:RunFor(30)
H.eq(CopiesOf(kept), 0, "the next copy goes with no click")
world.errors = {}
