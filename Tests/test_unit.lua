-- Records (Pack.lua, Data.lua), times, how events and sign-ups are worked
-- out (Events.lua), the texts in every language and the release files.
local H = ...

local world = H.NewWorld({ seed = 1 })
local solo = world:NewClient("Solo Name", { rank = "Guild Master", rankIndex = 0 })
world:Login(solo)
world:RunFor(30)
local ns = solo.ns
local Pack, Data, Events = ns.Pack, ns.Data, ns.Events
local now = ns.Now()

H.section("Loading")
H.eq(#world.errors, 0, "no errors while loading and starting")
for _, err in ipairs(world.errors) do
    print("   " .. err)
end
H.check(type(GuildRaidsEvents) == "nil" and type(solo.env.GuildRaidsEvents) == "table", "the public API is a global of the game")

H.section("Times of the game's calendar")
H.eq(Events.Naive(1970, 1, 1, 0, 0), 0, "the start of 1970 is 0")
H.eq(Events.Naive(2000, 1, 1, 0, 0), 946684800, "a date as seconds, as if UTC (the Unix time of 2000-01-01 UTC)")
H.eq(Events.Naive(2026, 11, 24, 21, 30), 1795555800, "and with hours and minutes")
local date = Events.DateOf(Events.Naive(2024, 2, 29, 23, 45))
H.check(date.year == 2024 and date.month == 2 and date.day == 29 and date.hour == 23 and date.minute == 45,
    "and back, a leap day too")
H.eq(Events.DateOf(Events.Naive(2026, 11, 22, 12, 0)).weekday, 1, "22 November 2026 is a Sunday (1, as the game counts)")
H.eq(Events.DateOf(Events.Naive(2026, 11, 28, 12, 0)).weekday, 7, "and the 28th a Saturday")
for _, case in ipairs({ { 1999, 12, 31 }, { 2000, 3, 1 }, { 2100, 2, 28 }, { 2025, 1, 1 } }) do
    local back = Events.DateOf(Events.Naive(case[1], case[2], case[3], 0, 0))
    H.check(back.year == case[1] and back.month == case[2] and back.day == case[3],
        ("%04d-%02d-%02d survives the round trip"):format(case[1], case[2], case[3]))
end
H.eq(Events.Offset(), 0, "the calendar's clock and the server's agree here (both UTC)")
H.eq(Events.ToBase36(0), "0", "base 36: zero")
H.eq(Events.ToBase36(36 * 36 + 35), "10z", "base 36: digits and letters")

H.section("Pack: records")
local GUID = "Player-1-0000000A"
local start = Events.Naive(2026, 12, 1, 21, 0)
local record = {
    n = "Solo Name", rl = "TestRealm", t = now, av = 100,
    ev = {
        { id = "t2abc", ty = 0, ti = "Molten Core", tm = start, de = "Bring fire resistance.\nBe on time.",
          sl = { t = 2, h = 4, d = 14 }, ml = 60, ii = 839, wk = true, ac = true, lk = true, ci = 2773004, at = now },
        { id = "t2abd", ty = 4, ti = "Fishing contest", tm = start + 86400, ml = 0, ci = 0, at = now - 10, x = true },
    },
    pe = { ["Player-1-0000000B/zz"] = { ty = 1, ti = "Scholomance", tm = start, ml = 0, at = now } },
    su = { ["Player-1-0000000B/zz"] = { st = 1, ro = 2, no = "late 10 min", at = now },
        ["Player-1-0000000A/t2abc"] = { st = 3, at = now } },
    ms = { ["Player-1-0000000A/t2abc"] = { ["Player-1-0000000C"] = { st = 2, at = now }, ["Player-1-0000000D"] = { st = 0, at = now } } },
    xs = { ["Player-1-0000000A/t2abc"] = { ["Player-1-0000000E"] = { st = 2, ro = 1, no = "from Discord", at = now } } },
    cf = { t = now, br = { "Player-1-0000000F" } },
}
local key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, record)))
H.eq(key, GUID, "record key (the GUID)")
H.check(ns.Same(back, record), "record round trip, every field")
local bare = { n = "Solo Name", t = now, av = 100 }
_, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, bare)))
H.check(back.ev == nil and back.su == nil and back.ms == nil and back.xs == nil and back.cf == nil and back.pe == nil,
    "a record with nothing reads with nothing")
-- A later version's extra fields are skipped, and the next record still reads.
local body = Pack.RecordString(GUID, record)
local reader = Pack.Reader(body)
local length = reader:UInt()
local longer = Pack.Writer()
longer:Str(body:sub(reader.pos, reader.pos + length - 1) .. "\1\2\3")
longer:Raw(Pack.RecordString("Player-1-0000000B", bare))
reader = Pack.Reader(longer:Result())
H.eq((Pack.ReadRecord(reader)), GUID, "a record with fields from a later version reads")
H.eq((Pack.ReadRecord(reader)), "Player-1-0000000B", "the record after it reads too")
local tooMany = H.DeepCopy(record)
for i = 3, Pack.LIMITS.events + 1 do
    tooMany.ev[i] = H.DeepCopy(record.ev[1])
    tooMany.ev[i].id = "x" .. i
end
H.check(not pcall(Pack.ReadRecord, Pack.Reader(Pack.RecordString(GUID, tooMany))), "too many events refused")
local longTitle = H.DeepCopy(record)
longTitle.ev[1].ti = ("x"):rep(Pack.LIMITS.title + 1)
H.check(not pcall(Pack.ReadRecord, Pack.Reader(Pack.RecordString(GUID, longTitle))), "an overlong title refused")

H.section("Data: checking records")
local clean = Data.CleanRecord(record, now)
H.check(clean ~= nil and ns.Same(clean.ev, record.ev) and ns.Same(clean.su, record.su) and ns.Same(clean.ms, record.ms)
    and ns.Same(clean.xs, record.xs) and ns.Same(clean.cf, record.cf) and ns.Same(clean.pe, record.pe),
    "a good record passes as it is")
local function Without(change)
    local copy = H.DeepCopy(record)
    change(copy)
    return Data.CleanRecord(copy, now)
end
H.eq(Data.CleanRecord(H.DeepCopy(record), now - 3600) and "kept" or "refused", "refused", "a record from the future refused")
H.eq(#Without(function(r) r.ev[1].ti = "Molten|cffff0000Core" end).ev, 1, "an event with an escape sequence left out")
H.eq(#Without(function(r) r.ev[1].ti = "" end).ev, 1, "an event without a title left out")
H.eq(#Without(function(r) r.ev[1].ty = 5 end).ev, 1, "an unknown type left out")
H.eq(#Without(function(r) r.ev[1].ii = 0.5 end).ev, 1, "a place that is no ID left out")
H.eq(#Without(function(r) r.ev[1].sl.t = Pack.LIMITS.slots + 1 end).ev, 1, "too many places left out")
H.eq(#Without(function(r) r.ev[1].tm = 12345 end).ev, 1, "an impossible start left out")
H.eq(#Without(function(r) r.ev[2].id = r.ev[1].id end).ev, 1, "two events with one ID: the second left out")
H.eq(#Without(function(r) r.ev[1].id = "bad id" end).ev, 1, "a bad ID left out")
H.check(Without(function(r) r.ev[1].de = "two\nlines" end).ev[1].de == "two\nlines", "new lines pass in a description")
H.eq(#Without(function(r) r.ev[1].de = "tab\there" end).ev, 1, "other control characters do not")
H.eq(Without(function(r) r.su["Player-1-0000000B/zz"].st = 4 end).su["Player-1-0000000B/zz"], nil, "an unknown answer left out")
H.eq(Without(function(r) r.su["Player-1-0000000B/zz"].ro = 4 end).su["Player-1-0000000B/zz"], nil, "an unknown role left out")
H.eq(Without(function(r) r.su["Player-1-0000000B/zz"].no = ("n"):rep(Pack.LIMITS.note + 1) end).su["Player-1-0000000B/zz"], nil,
    "an overlong note left out")
H.eq(Without(function(r) r.su["nokey"] = { st = 1, at = now } end).su["nokey"], nil, "an answer to a bad key left out")
H.eq(Without(function(r) r.ms["Player-1-0000000A/t2abc"]["Player-1-0000000C"].st = 9 end).ms["Player-1-0000000A/t2abc"]["Player-1-0000000C"],
    nil, "an unknown status left out")
H.eq(Without(function(r) r.su["Player-1-0000000B/zz"].at = now + 3600 end).su["Player-1-0000000B/zz"], nil,
    "an answer dated in the future left out")
H.eq(#Without(function(r) r.cf.br = { "Player-1-0000000F", "Player-1-0000000F", "nope" } end).cf.br, 1,
    "bridge characters: repeated and bad GUIDs left out")

H.section("Places")
local UI = ns.UI
local dungeons = UI.PlacesFor(1)
H.eq(#dungeons, 5, "the dungeons of the game's Group Finder")
H.check(dungeons[1].name == "Sima Ígnea" and dungeons[2].name == "Wailing Caverns" and dungeons[3].name == "Scarlet Graveyard",
    "the lowest level first, by the short name when there is one")
H.check(dungeons[4].name == "Dire Maul (East)" and dungeons[5].name == "Scholomance", "the same level by name")
local pvp = UI.PlacesFor(2)
H.check(#pvp == 4 and pvp[1].id == UI.WORLD_PVP and pvp[2].name == "Alterac Valley", "world PvP, then each battleground once")
H.eq(UI.PlaceName(805), "Scarlet Graveyard", "a place's name comes from the game")
H.eq(UI.PlaceName(UI.WORLD_PVP), "World PvP", "world PvP")
H.eq(UI.PlaceName(nil), nil, "no place, no name")
H.eq(#UI.PlacesFor(3) + #UI.PlacesFor(4), 0, "none for meetings and other events")
H.eq(UI.KindText({ ty = 0, ii = 839 }), "Raid: Molten Core", "an event's type with its place")
H.eq(UI.KindText({ ty = 4 }), "Other", "or alone")
H.eq(UI.FindPlaces(1, "IGNEA")[1].name, "Sima Ígnea", "searching ignores case and accents")
H.eq(#UI.FindPlaces(1, "  "), 5, "an empty search finds all")
H.eq(#UI.FindPlaces(1, "zzz"), 0, "and one that matches nothing, none")

H.section("Events: an event as its organizer or an officer left it")
-- A guild of four: the guild master (solo), an officer, a member and a
-- bridge character, whose records are set by hand.
local officerKey, officer = world:AddMember("Officer Name", nil, { rank = "Officer", rankIndex = 1 })
local _, member = world:AddMember("Member Name", nil, { rank = "Member", rankIndex = 3 })
local _, bridge = world:AddMember("Bridge Name", nil, { rank = "Member", rankIndex = 3 })
local _, other = world:AddMember("Other Name", nil, { rank = "Member", rankIndex = 3 })
world.officerRanks = { [1] = true }
world:RosterChanged()
world:RunFor(5)
ns.Rights.ForgetRanks()
local guild = Data.CurrentGuild(true)
local base = { id = "e1", ty = 0, ti = "Molten Core", tm = Events.Now() + 3 * 86400, ml = 0, ci = 0, at = now - 100,
    sl = { t = 1, h = 1, d = 2 } }
guild.members[member] = { t = now, av = 100, n = "Member Name", ev = { base } }
Events.Invalidate()
local eventKey = member .. "/e1"
H.check(Events.Get(eventKey) ~= nil and Events.Get(eventKey).owner == member, "a member's event is the guild's, under its key")
guild.members[other] = { t = now, av = 100, n = "Other Name", pe = { [eventKey] = { ty = 0, ti = "Hacked", tm = base.tm, ml = 0, at = now } } }
Events.Invalidate()
H.eq(Events.Get(eventKey).ti, "Molten Core", "a member who is no officer cannot change it")
guild.members[officer] = { t = now, av = 100, n = "Officer Name", pe = { [eventKey] = { ty = 0, ti = "Molten Core (moved)", tm = base.tm + 3600,
    ml = 0, at = now - 50, sl = { t = 1, h = 1, d = 2 } } } }
Events.Invalidate()
H.eq(Events.Get(eventKey).ti, "Molten Core (moved)", "an officer's newer change counts")
H.eq(Events.Get(eventKey).by, officer, "and says who made it")
base.at = now - 10
base.ti = "Molten Core (organizer)"
Events.Invalidate()
H.eq(Events.Get(eventKey).ti, "Molten Core (organizer)", "the organizer's newer change wins in turn")
world.officerRanks = {}
ns.Rights.ForgetRanks()
guild.members[officer].pe[eventKey].at = now
Events.Invalidate()
H.eq(Events.Get(eventKey).ti, "Molten Core (organizer)", "an officer no longer one no longer counts")
world.officerRanks = { [1] = true }
ns.Rights.ForgetRanks()
guild.members[officer].pe = nil

H.section("Events: sign-ups, statuses and confirming by itself")
local event
local function Refresh()
    Events.Invalidate()
    event = Events.Get(eventKey)
end
guild.members[solo.guid] = guild.members[solo.guid] or { t = now, av = 100 }
guild.members[solo.guid].su = { [eventKey] = { st = 1, ro = 1, at = now - 40 } }
guild.members[officer].su = { [eventKey] = { st = 1, ro = 1, no = "can heal too", at = now - 30 } }
guild.members[other].su = { [eventKey] = { st = 2, ro = 3, at = now - 20 } }
guild.members[member].su = { [eventKey] = { st = 1, ro = 3, at = now - 10 } }
Refresh()
local signUps = Events.SignUps(event)
H.eq(#signUps, 4, "four answers")
H.eq(signUps[1].guid, solo.guid, "in the order they came")
H.check(signUps[2].no == "can heal too" and signUps[2].name == "Officer Name", "with their note and name")
local counts, tentative = Events.Counts(signUps)
H.check(counts[1] == 2 and counts[2] == 0 and counts[3] == 2 and tentative == 1, "counted by role, the tentative too, who show there")
H.eq(signUps[1].status, Events.NONE, "no status while the event does not confirm by itself")
base.ac = true
Refresh()
signUps = Events.SignUps(event)
H.check(signUps[1].status == Events.CONFIRMED and signUps[1].auto, "confirming by itself: the first tank is confirmed")
H.eq(signUps[2].status, Events.STANDBY, "the second tank, past the one place, on standby")
H.eq(signUps[3].status, Events.NONE, "the tentative one gets no status")
H.eq(signUps[4].status, Events.CONFIRMED, "the damage dealer has a place")
guild.members[member].ms = { [eventKey] = { [officer] = { st = 1, at = now } } }
Refresh()
signUps = Events.SignUps(event)
H.check(signUps[2].status == Events.CONFIRMED and not signUps[2].auto, "the organizer confirms the second tank")
H.eq(signUps[1].status, Events.STANDBY, "who then takes the place first: the other goes on standby")
guild.members[other].ms = { [eventKey] = { [solo.guid] = { st = 1, at = now + 1 } } }
Refresh()
H.eq(Events.SignUps(event)[1].status, Events.STANDBY, "a member who may not manage it gives no status")
guild.members[solo.guid].ms = { [eventKey] = { [officer] = { st = 3, at = now + 2 } } }
Refresh()
signUps = Events.SignUps(event)
H.eq(signUps[2].status, Events.OUT, "the guild master's newer status wins")
H.eq(signUps[1].status, Events.CONFIRMED, "and the place goes back to the first tank")
H.eq(Events.Counts(signUps)[1], 1, "those out are not counted")

H.section("Events: sign-ups from outside the game")
guild.members[bridge] = { t = now, av = 100, n = "Bridge Name",
    xs = { [eventKey] = { [other] = { st = 1, ro = 2, no = "from Discord", at = now + 5 } } } }
Refresh()
local function Find(list, guid)
    for _, signUp in ipairs(list) do
        if signUp.guid == guid then
            return signUp
        end
    end
end
H.eq(Find(Events.SignUps(event), other).st, Events.TENTATIVE, "a character the guild master did not choose brings none in")
guild.members[solo.guid].cf = { t = now, br = { bridge } }
Refresh()
local brought = Find(Events.SignUps(event), other)
H.check(brought.st == Events.SIGNED and brought.ro == 2 and brought.external and brought.no == "from Discord",
    "a bridge character's newer sign-up counts, marked as from outside the game")
guild.members[other].su[eventKey] = { st = 3, at = now + 6 }
Refresh()
H.check(Find(Events.SignUps(event), other).st == Events.DECLINED and not Find(Events.SignUps(event), other).external,
    "the member's own newer answer wins in turn")
guild.members[officer].cf = { t = now + 10, br = {} }
Refresh()
H.check(ns.Rights.IsBridge(bridge), "the options of anyone but the guild master are left out")

H.section("Events: the player's own changes")
local created = Events.Create({ ty = 1, ti = "Scholomance", tm = Events.Now() + 86400, de = "", ml = 55, sl = { t = 1, h = 1, d = 3 } })
H.check(created ~= nil and Events.Get(created) ~= nil and Events.Get(created).owner == solo.guid, "creating an event")
H.check(Events.Get(created).de == nil and Events.Get(created).ci == 0, "with no description and not in the calendar yet")
H.check(Events.Change(created, { ty = 1, ti = "Scholomance!", tm = Events.Get(created).tm, ml = 55 }), "changing it")
H.check(Events.Get(created).ti == "Scholomance!" and Events.Get(created).sl == nil, "every field as the form left them")
H.check(Events.Cancel(created), "cancelling it")
H.check(Events.Get(created).x == true, "it is marked cancelled")
H.check(Events.Change(created, { ty = 1, ti = "Scholomance", tm = Events.Get(created).tm, ml = 55 }), "changing it again")
H.check(Events.Get(created).x == true, "keeps it cancelled")
H.check(Events.Cancel(created, false) and not Events.Get(created).x, "and it can be brought back")
H.check(Events.Change(eventKey, { ty = 0, ti = "Molten Core (by the master)", tm = event.tm, ml = 0 }), "the guild master changes a member's event")
H.check(guild.members[solo.guid].pe[eventKey] ~= nil and Events.Get(eventKey).ti == "Molten Core (by the master)",
    "in their own record")
H.check(Events.Answer(created, Events.TENTATIVE, Events.HEALER, "  maybe  "), "answering")
local mine = Events.Mine(Events.Get(created))
H.check(mine and mine.st == Events.TENTATIVE and mine.ro == Events.HEALER and mine.no == "maybe", "the answer, its note trimmed")
H.check(Events.Answer(created, nil) and Events.Mine(Events.Get(created)) == nil, "taking it back")
H.check(Events.SetStatus(created, member, Events.CONFIRMED), "giving a status in one's event")
H.check(not Events.Create({ ty = 9, ti = "Bad", tm = Events.Now() + 86400 }), "an event with bad fields is not created")
local beforeMany = #guild.members[solo.guid].ev
local allMade = true
for i = 1, 25 do
    allMade = allMade and Events.Create({ ty = 4, ti = "Event " .. i, tm = Events.Now() + 86400 + i, ml = 0 }) ~= nil
end
H.check(allMade and #guild.members[solo.guid].ev == beforeMany + 25, "no limit of the addon's own on creating events")
H.check(not Events.SetExternal(created, member, Events.SIGNED), "the guild master is no bridge character: nothing brought in")

H.section("Events: upkeep")
local record0 = guild.members[solo.guid]
record0.ev = {
    { id = "w1", ty = 0, ti = "Weekly raid", tm = Events.Now() - 4 * 3600, ml = 0, ci = 77, at = now - 1000, wk = true,
      lk = true },
    { id = "old", ty = 0, ti = "Old raid", tm = Events.Now() - 8 * 86400, ml = 0, ci = 0, at = now - 1000 },
}
record0.su = { ["Player-1-00000099/gone"] = { st = 1, at = now - 40 * 86400 }, ["Player-1-00000099/recent"] = { st = 1, at = now - 86400 } }
Events.Tidy()
local weekly = {}
for _, e in ipairs(record0.ev) do
    weekly[e.id] = e
end
H.eq(weekly.old, nil, "an event past a week is dropped")
H.check(weekly.w1 ~= nil and weekly.w1.wk and weekly.w1.nx, "a weekly event that started stays weekly, its next one made")
local nexts = {}
for id, e in pairs(weekly) do
    if id ~= "w1" then
        nexts[#nexts + 1] = e
    end
end
table.sort(nexts, function(a, b)
    return a.tm < b.tm
end)
local nextWeek = nexts[1]
H.check(#nexts == 2 and nextWeek.wk and nextWeek.tm == weekly.w1.tm + Events.WEEK and nextWeek.ci == 0
    and nexts[2].tm == nextWeek.tm + Events.WEEK, "next week's and the one after: always two to come, not in the calendar yet")
H.check(nextWeek ~= nil and not nextWeek.lk, "taking answers again, though last week's was locked")
H.eq(record0.su["Player-1-00000099/gone"], nil, "an answer to an event nobody knows of, a month old, is dropped")
H.check(record0.su["Player-1-00000099/recent"] ~= nil, "a recent one is kept")
local function Titled(title)
    local list = {}
    for _, e in ipairs(record0.ev) do
        if e.ti == title then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        return a.tm < b.tm
    end)
    return list
end
local raidKey = Events.Create({ ty = 0, ti = "Raid night", tm = Events.Now() + 3 * 86400, ml = 0, wk = true })
local raids = Titled("Raid night")
H.check(raidKey ~= nil and #raids == 2 and raids[2].tm == raids[1].tm + Events.WEEK and raids[1].wk and raids[2].wk,
    "a weekly event created: next week's appears at once, weekly too")
H.check(raids[2].ci == 0 and Events.Get(solo.guid .. "/" .. raids[2].id) ~= nil, "an event of its own, not in the calendar yet")
Events.Tidy()
H.eq(#Titled("Raid night"), 2, "and no more until this week's starts")
H.check(Events.Change(raidKey, { ty = 0, ti = "Raid night", tm = raids[1].tm, ml = 0, wk = true }), "changing it")
Events.Tidy()
H.check(#Titled("Raid night") == 2 and Events.Get(raidKey).wk, "makes no other, and it stays weekly")
local farKey = Events.Create({ ty = 0, ti = "Far raid", tm = Events.Now() + 20 * 86400, ml = 0 })
H.eq(#Titled("Far raid"), 1, "an event not weekly is alone")
H.check(Events.Change(farKey, { ty = 0, ti = "Far raid", tm = Events.Now() + 20 * 86400, ml = 0, wk = true })
    and #Titled("Far raid") == 2, "made weekly when changed: next week's at once")

H.section("Locales")
local function ReadKeys(paths)
    local keys = {}
    for _, file in ipairs(paths) do
        local handle = io.open(H.ADDON .. "/" .. file, "rb")
        local text = handle:read("*a")
        handle:close()
        for k in text:gmatch('L%["(.-)"%]') do
            keys[k] = true
        end
    end
    return keys
end
local codeFiles = {}
for _, file in ipairs(H.FILES) do
    if not file:find("^Locales/") then
        codeFiles[#codeFiles + 1] = file
    end
end
local codeKeys = ReadKeys(codeFiles)
H.check(next(codeKeys) ~= nil, "the code's texts are found")
local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%d%.]*[sdf]") do
        list[#list + 1] = spec
    end
    return table.concat(list, " ")
end
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local texts = {}
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile(H.ADDON .. "/Locales/" .. locale .. ".lua"))
    setfenv(chunk, env)
    chunk("GuildRaidsEvents", { RegisterLocale = function(_, fill) fill(texts) end })
    local missing, extra, badSpecs = {}, {}, {}
    for k in pairs(codeKeys) do
        if texts[k] == nil and locale ~= "esMX" then
            missing[#missing + 1] = k
        end
    end
    for k, v in pairs(texts) do
        if not codeKeys[k] then
            extra[#extra + 1] = k
        elseif Specifiers(k) ~= Specifiers(v) then
            badSpecs[#badSpecs + 1] = k
        end
    end
    H.check(#missing == 0, locale .. " has every text" .. (#missing > 0 and (": missing " .. #missing .. ", first: " .. missing[1]) or ""))
    H.check(#extra == 0, locale .. " has no unused text" .. (#extra > 0 and (": " .. table.concat(extra, " | ")) or ""))
    H.check(#badSpecs == 0, locale .. " keeps the format specifiers" .. (#badSpecs > 0 and (": " .. table.concat(badSpecs, " | ")) or ""))
end

H.section("Release files")
local function Read(path)
    local handle = io.open(H.ADDON .. "/" .. path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()
    return text
end
local toc = Read("GuildRaidsEvents.toc")
local changelog = Read("CHANGELOG.md")
local tocVersion = toc:match("## Version: ([%d%.]+)")
H.check(changelog ~= nil and changelog:match("## ([%d%.]+)") == tocVersion, "the TOC version is the changelog's newest")
local announced = Read("Core.lua"):match('\nlocal ANNOUNCE_AS = "([%d%.]+)"')
if announced then
    print(("  NOTE: Core.lua tells the guild this is %s: set ANNOUNCE_AS to nil before tagging a release"):format(announced))
end
H.check(toc:find("## Dependencies: LibGuildSync", 1, true) ~= nil, "LibGuildSync is a dependency")
H.check(toc:find("## SavedVariables: GuildRaidsEventsDB", 1, true) ~= nil, "the saved variable is declared")
local pkgmeta = Read(".pkgmeta")
H.check(pkgmeta ~= nil and pkgmeta:find("package%-as: GuildRaidsEvents") ~= nil, ".pkgmeta packages the folder as GuildRaidsEvents")
H.check(pkgmeta ~= nil and pkgmeta:find("\n    %- Tests\n") ~= nil, ".pkgmeta leaves the tests out of the package")
H.check(pkgmeta ~= nil and pkgmeta:find("required%-dependencies:\n    %- lib%-guild%-sync\n") ~= nil,
    ".pkgmeta makes LibGuildSync a required relation on CurseForge")
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    H.check(toc:find("## Notes-" .. locale .. ": ", 1, true) ~= nil, "the TOC has notes in " .. locale)
end
H.check(toc:find("## Dependencies:", 1, true) and not toc:lower():find("bottar"), "the TOC names no other guild addon")
