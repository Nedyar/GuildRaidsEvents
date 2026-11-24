-- Several members online: an event, its answers and statuses reach
-- everyone; the guild master chooses a bridge character, whose client
-- brings in a sign-up made outside the game through the public API.
local H = ...

local world = H.NewWorld({ seed = 7, senderFormat = "short", strictWhispers = true })
world.officerRanks = { [1] = true }
local master = world:NewClient("Master Name", { rank = "Guild Master", rankIndex = 0 })
local organizer = world:NewClient("Organizer Name", { rank = "Raider", rankIndex = 2 })
local member = world:NewClient("Member Name", { rank = "Member", rankIndex = 3, level = 58 })
local bridge = world:NewClient("Bridge Name", { rank = "Member", rankIndex = 3 })
local officer = world:NewClient("Officer Name", { rank = "Officer", rankIndex = 1 })
for _, client in ipairs({ master, organizer, member, bridge, officer }) do
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

H.section("Sync: an event reaches everyone")
local Events = organizer.ns.Events
local start = Events.Now() + 2 * 86400 + 25
local key = Events.Create({ ty = 0, ti = "Molten Core", tm = start, de = "Fire resistance.", ml = 55,
    sl = { t = 1, h = 1, d = 2 }, ac = true })
H.check(key ~= nil, "the organizer creates an event")
start = start - start % 60
H.eq(Events.Get(key).tm, start, "starting on a whole minute, as the calendar keeps it")
world:RunFor(30)
for _, client in ipairs({ master, member, bridge, officer }) do
    local event = client.ns.Events.Get(key)
    H.check(event ~= nil and event.ti == "Molten Core" and event.ml == 55 and event.ac, client.name .. " has it")
end

H.section("Sync: answers and statuses")
H.check(member.ns.Events.Answer(key, member.ns.Events.SIGNED, member.ns.Events.TANK, "first time here"), "a member signs up")
H.check(officer.ns.Events.Answer(key, 1, 1), "an officer signs up as tank too")
world:RunFor(30)
local function SignUpOf(client, guid)
    for _, signUp in ipairs(client.ns.Events.SignUps(client.ns.Events.Get(key))) do
        if signUp.guid == guid then
            return signUp
        end
    end
end
local seen = SignUpOf(organizer, member.guid)
H.check(seen ~= nil and seen.ro == 1 and seen.no == "first time here", "the organizer sees the sign-up, its role and note")
H.eq(seen.status, 1, "first tank in an event that confirms by itself: confirmed")
local own = SignUpOf(member, organizer.guid)
H.check(own and own.st == 1 and own.status == 1 and not own.auto, "the organizer is signed up and confirmed, as the calendar does")
H.eq(SignUpOf(master, officer.guid).status, 2, "the second, past the one place, on standby, for everyone")
H.check(organizer.ns.Events.SetStatus(key, officer.guid, 1), "the organizer confirms the officer")
world:RunFor(30)
H.eq(SignUpOf(member, officer.guid).status, 1, "the member sees the officer confirmed")
H.eq(SignUpOf(member, member.guid).status, 2, "and themselves on standby now")
H.check(not member.ns.Events.SetStatus(key, member.guid, 1), "a member may not give statuses")

H.section("Sync: an officer changes the event")
local event = officer.ns.Events.Get(key)
H.check(officer.ns.Events.Change(key, { ty = 0, ti = "Molten Core (moved)", tm = event.tm + 3600, de = event.de, ml = 55,
    sl = event.sl, ac = true }), "an officer changes it")
world:RunFor(30)
H.eq(organizer.ns.Events.Get(key).ti, "Molten Core (moved)", "the organizer sees the change")
H.eq(member.ns.Events.Get(key).tm, start + 3600, "and so does everyone")
H.check(not member.ns.Events.Change(key, { ty = 0, ti = "Mine now", tm = start, ml = 0 }), "a member may not change it")

H.section("Sync: sign-ups from outside the game")
local api = bridge.env.GuildRaidsEvents
local ok, why = api.SetExternalSignUp(key, "Master Name", "signedUp", "healer", "via Discord")
H.check(not ok and why == "notBridge", "before the guild master chooses it, a character brings in nothing")
H.check(api.RegisterBridge("Some Bridge"), "an addon registers as a bridge")
H.check(master.ns.Rights.AddBridge("bridge name"), "the guild master chooses the bridge character, by name in any case")
local added, reason = organizer.ns.Rights.AddBridge("Member Name")
H.check(not added and reason == "notMaster", "nobody else can")
world:RunFor(30)
H.check(api.IsBridgeCharacter(), "the bridge character knows it is one")
ok = api.SetExternalSignUp(key, "Master Name", "signedUp", "healer", "via Discord")
H.check(ok, "it brings in a sign-up for a member")
ok, why = api.SetExternalSignUp(key, "Nobody Here", "signedUp", "healer")
H.check(not ok and why == "notMember", "not for someone outside the guild")
ok, why = api.SetExternalSignUp(key, "Member Name", "maybe")
H.check(not ok and why == "badStatus", "not with an unknown answer")
ok, why = api.SetExternalSignUp("Player-1-00000001/none", "Member Name", "signedUp")
H.check(not ok and why == "noEvent", "not to an unknown event")
local function Lock(locked)
    local e = organizer.ns.Events.Get(key)
    return organizer.ns.Events.Change(key, { ty = e.ty, ti = e.ti, tm = e.tm, de = e.de, sl = e.sl, ml = e.ml, ii = e.ii,
        wk = e.wk, ac = e.ac, lk = locked or nil })
end
H.check(Lock(true), "the organizer locks the event")
world:RunFor(30)
ok, why = api.SetExternalSignUp(key, "Member Name", "signedUp", "damage")
H.check(not ok and why == "locked", "a locked event takes no sign-ups from outside the game either")
H.check(api.GetEvent(key).locked, "the API says it is locked")
H.check(Lock(false), "and unlocks it")
world:RunFor(30)
local external = SignUpOf(organizer, master.guid)
H.check(external ~= nil and external.external and external.ro == 2 and external.no == "via Discord",
    "everyone sees it, marked as from outside the game")
local events = master.env.GuildRaidsEvents.GetEvents()
H.eq(#events, 1, "the API lists the upcoming event")
local listed = events[1]
H.check(listed.key == key and listed.title == "Molten Core (moved)" and listed.type == "raid" and listed.organizer == "Organizer Name"
    and listed.slots.tank == 1 and listed.minLevel == 55 and listed.autoConfirm and listed.locked == false and listed.startUnix == listed.start,
    "with its fields as the API describes them")
local healer
for _, signUp in ipairs(listed.signUps) do
    if signUp.name == "Master Name" then
        healer = signUp
    end
end
H.check(healer and healer.status == "signedUp" and healer.role == "healer" and healer.external and healer.manage == "confirmed"
    and healer.auto, "and its sign-ups, the brought-in one confirmed by itself")
H.check(api.SetExternalSignUp(key, "Master Name", nil), "taking it back")
world:RunFor(30)
H.eq(SignUpOf(organizer, master.guid), nil, "it is gone for everyone")
local changed = 0
master.env.GuildRaidsEvents.OnChange(function()
    changed = changed + 1
end)
member.ns.Events.Answer(key, 2, 3)
world:RunFor(30)
H.check(changed > 0, "OnChange tells another addon the events changed")
Errors("the sync")

H.section("Sync: reminders")
member.ns.Reminders.SetMinutes(15)
local soon = organizer.ns.Events.Create({ ty = 3, ti = "Guild meeting", tm = organizer.ns.Events.Now() + 20 * 60 + 30, ml = 0 })
world:RunFor(20)
member.ns.Events.Answer(soon, 1, 3)
world:RunFor(60)
H.eq(member.raidWarnings, nil, "no reminder 20 minutes before")
world:RunFor(6 * 60)
H.check(member.raidWarnings and #member.raidWarnings == 1 and member.raidWarnings[1]:find("Guild meeting", 1, true),
    "a raid warning 15 minutes before, for those who go")
world:RunFor(120)
H.eq(#member.raidWarnings, 1, "only once")
H.eq(bridge.raidWarnings, nil, "none for those who do not go")
Errors("the reminders")
