-- Pack.lua: the packed form of Guild Raids & Events's records (LibGuildSync's
-- Pack.lua has the numbers, texts, Base64 and hashing they are made of).
-- Plain Lua with no game API, so it can be tested outside the game.
local _, ns = ...

local Pack = ns.Pack

-- The most a record may hold. Anything bigger is refused when read, so the
-- addon never writes more (Events.lua checks each list before adding to
-- it): a record over one of these could not be read again, by the guild
-- or by its own character at the next login.
local EVENTS = 1000  -- a guard against broken data, never reached: creating has no limit of the
                     -- addon's (the game's calendar has its own), and each list below names events
Pack.LIMITS = {
    text = 64,       -- names
    title = 128,     -- an event's title: 31 letters in the game's calendar, up to 4 bytes each
    id = 16,         -- an event's own ID
    key = 96,        -- an event's key: the organizer's GUID, "/", its ID
    description = 1024,  -- 255 letters in the game's calendar
    noteLetters = 60,  -- a sign-up's note, in letters (the box in an event's view)
    note = 240,      -- and in bytes: up to 4 each
    events = EVENTS,       -- events a record holds
    patches = EVENTS,      -- events one moderator changed
    signUps = EVENTS,      -- events one member answered (an organizer answers each of theirs)
    statusEvents = EVENTS, -- events one member gave statuses in (an organizer, each of theirs),
                           -- brought outside sign-ups to, or named moderators in
    perEvent = 1000, -- statuses, outside sign-ups or moderators in one event: a guild's members at most
    slots = 40,      -- places of one role
    level = 255,
    bridges = 20,    -- characters the guild master lets add outside sign-ups
}

-- Records --------------------------------------------------------------------

-- A record is what one character shares, under its GUID:
--   n = name, rl = realm, t = time of its last change, av = addon version,
--   ev = the events it organizes: { id = its own ID (the event's key is
--       the organizer's GUID, "/", id), ty = type (0 raid, 1 dungeon,
--       2 PvP, 3 meeting, 4 other, as the game's calendar numbers them),
--       ti = title, tm = when it starts, in the server's calendar time
--       (seconds, as if that time were UTC: Events.Naive), de =
--       description, sl = places per role { t = tanks, h = healers,
--       d = damage }, or nil for no limit, ml = minimum level (0: none),
--       ii = where: the Group Finder activity of its raid, dungeon or
--       battleground (UI.PlacesFor), UI.WORLD_PVP for world PvP, 0 for none,
--       wk = repeats weekly (nx = its next week's was made), ac = confirms by itself (the first to sign up
--       in each role, the rest on standby), lk = locked (members cannot
--       answer it, as the game's calendar has it), x = deleted, ci = its event
--       ID in the game's calendar, 0 until it is there, at = time of its
--       last change },
--   pe = the guild's events a moderator changed, the event's whole fields as
--       they left it (x: they deleted it): { [key] = { at, ty, ti, tm, de, sl, ml, ii, wk, nx, ac, lk, x } },
--   su = its sign-ups: { [key] = { st = 1 signed up, 2 tentative, 3 not
--       coming, ro = role (1 tank, 2 healer, 3 damage), no = note, at =
--       time of the answer } },
--   ms = the statuses it gave, as organizer or moderator: { [key] = { [GUID]
--       = { st = 0 none, 1 confirmed, 2 standby, 3 out, 4 tentative, at = time } } },
--   mo = the moderators it named or took back, as organizer or moderator:
--       { [key] = { [GUID] = { on = true or false, at = time } } } (packed
--       last, after cf: a record of an older version has none),
--   xs = sign-ups made outside the game (by another addon, through the
--       API) that it brought in: { [key] = { [GUID] = { st, ro, no, at } } },
--   cf = the guild's options, from its guild master only: { t = time,
--       br = the GUIDs of the characters that may bring in outside sign-ups }.
-- A packed record is prefixed by its length, so fields added later are
-- skipped by older readers.
local LIMITS = Pack.LIMITS
local ABSENT, PRESENT = 0, 1
-- An event's flags, added up.
local WEEKLY, AUTO, DELETED, SLOTS, LOCKED, NEXT = 1, 2, 4, 8, 16, 32

local function Has(flags, flag)
    return math.floor(flags / flag) % 2 == 1
end

-- The fields every event and moderator's change has.
local function WriteFields(writer, event)
    writer:Byte(event.ty)
    writer:Str(event.ti)
    writer:UInt(event.tm)
    writer:Str(event.de or "")
    local flags = (event.wk and WEEKLY or 0) + (event.ac and AUTO or 0) + (event.x and DELETED or 0)
        + (event.sl and SLOTS or 0) + (event.lk and LOCKED or 0) + (event.nx and NEXT or 0)
    writer:Byte(flags)
    if event.sl then
        writer:Byte(event.sl.t)
        writer:Byte(event.sl.h)
        writer:Byte(event.sl.d)
    end
    writer:Byte(event.ml or 0)
    writer:UInt(event.ii or 0)
    writer:UInt(event.at)
end

local function ReadFields(reader, event)
    event.ty = reader:Byte()
    event.ti = reader:Str(LIMITS.title)
    event.tm = reader:UInt()
    event.de = reader:Str(LIMITS.description)
    if event.de == "" then
        event.de = nil
    end
    local flags = reader:Byte()
    event.wk = Has(flags, WEEKLY) or nil
    event.ac = Has(flags, AUTO) or nil
    event.x = Has(flags, DELETED) or nil
    event.lk = Has(flags, LOCKED) or nil
    event.nx = Has(flags, NEXT) or nil
    if Has(flags, SLOTS) then
        event.sl = { t = reader:Byte(), h = reader:Byte(), d = reader:Byte() }
    end
    event.ml = reader:Byte()
    event.ii = reader:UInt()
    if event.ii == 0 then
        event.ii = nil
    end
    event.at = reader:UInt()
    return event
end

-- The keys of a table, sorted, so the same record always packs the same.
local function SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function Count(reader, max, what)
    local count = reader:UInt()
    if count > max then
        error("too many " .. what, 0)
    end
    return count
end

local function WriteEvents(writer, record)
    local list = record.ev or {}
    writer:UInt(#list)
    for _, event in ipairs(list) do
        writer:Str(event.id)
        writer:UInt(event.ci or 0)
        WriteFields(writer, event)
    end
    local keys = SortedKeys(record.pe)
    writer:UInt(#keys)
    for _, key in ipairs(keys) do
        writer:Str(key)
        WriteFields(writer, record.pe[key])
    end
end

local function ReadEvents(reader, record)
    local count = Count(reader, LIMITS.events, "events")
    if count > 0 then
        record.ev = {}
        for i = 1, count do
            local event = { id = reader:Str(LIMITS.id), ci = reader:UInt() }
            record.ev[i] = ReadFields(reader, event)
        end
    end
    count = Count(reader, LIMITS.patches, "changed events")
    if count > 0 then
        record.pe = {}
        for _ = 1, count do
            local key = reader:Str(LIMITS.key)
            record.pe[key] = ReadFields(reader, {})
        end
    end
end

local function WriteAnswer(writer, answer)
    writer:Byte(answer.st)
    writer:Byte(answer.ro or 0)
    writer:Str(answer.no or "")
    writer:UInt(answer.at)
end

local function ReadAnswer(reader)
    local answer = { st = reader:Byte(), ro = reader:Byte(), no = reader:Str(LIMITS.note), at = reader:UInt() }
    if answer.ro == 0 then
        answer.ro = nil
    end
    if answer.no == "" then
        answer.no = nil
    end
    return answer
end

-- { [key] = { [GUID] = item } }, with write(writer, item) and read(reader).
local function WriteNested(writer, map, write)
    local keys = SortedKeys(map)
    writer:UInt(#keys)
    for _, key in ipairs(keys) do
        writer:Str(key)
        local guids = SortedKeys(map[key])
        writer:UInt(#guids)
        for _, guid in ipairs(guids) do
            writer:Str(guid)
            write(writer, map[key][guid])
        end
    end
end

local function ReadNested(reader, max, what, read)
    local count = Count(reader, max, what)
    if count == 0 then
        return nil
    end
    local map = {}
    for _ = 1, count do
        local key = reader:Str(LIMITS.key)
        local inner = {}
        for _ = 1, Count(reader, LIMITS.perEvent, what) do
            local guid = reader:Str(LIMITS.text)
            inner[guid] = read(reader)
        end
        map[key] = inner
    end
    return map
end

local function WriteStatus(writer, status)
    writer:Byte(status.st)
    writer:UInt(status.at)
end

local function ReadStatus(reader)
    return { st = reader:Byte(), at = reader:UInt() }
end

local function WriteAnswers(writer, record)
    local keys = SortedKeys(record.su)
    writer:UInt(#keys)
    for _, key in ipairs(keys) do
        writer:Str(key)
        WriteAnswer(writer, record.su[key])
    end
    WriteNested(writer, record.ms, WriteStatus)
    WriteNested(writer, record.xs, WriteAnswer)
end

local function ReadAnswers(reader, record)
    local count = Count(reader, LIMITS.signUps, "sign-ups")
    if count > 0 then
        record.su = {}
        for _ = 1, count do
            local key = reader:Str(LIMITS.key)
            record.su[key] = ReadAnswer(reader)
        end
    end
    record.ms = ReadNested(reader, LIMITS.statusEvents, "statuses", ReadStatus)
    record.xs = ReadNested(reader, LIMITS.statusEvents, "outside sign-ups", ReadAnswer)
end

local function WriteOptions(writer, record)
    local options = record.cf
    if not options then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(options.t)
    local bridges = options.br or {}
    writer:UInt(#bridges)
    for _, guid in ipairs(bridges) do
        writer:Str(guid)
    end
end

local function ReadOptions(reader, record)
    if reader:Byte() ~= PRESENT then
        return
    end
    local options = { t = reader:UInt(), br = {} }
    for i = 1, Count(reader, LIMITS.bridges, "bridge characters") do
        options.br[i] = reader:Str(LIMITS.text)
    end
    record.cf = options
end

local function WriteModerator(writer, moderator)
    writer:Byte(moderator.on and PRESENT or ABSENT)
    writer:UInt(moderator.at)
end

local function ReadModerator(reader)
    return { on = reader:Byte() == PRESENT, at = reader:UInt() }
end

function Pack.WriteRecord(writer, guid, record)
    local body = Pack.Writer()
    body:Str(guid)
    body:Str(record.n or "")
    body:UInt(record.t)
    body:UInt(record.av or 0)
    body:Str(record.rl or "")
    WriteEvents(body, record)
    WriteAnswers(body, record)
    WriteOptions(body, record)
    WriteNested(body, record.mo, WriteModerator)
    writer:Str(body:Result())
end

function Pack.ReadRecord(reader)
    reader = reader:Sub(reader:UInt())
    local guid = reader:Str()
    local record = { n = reader:Str(), t = reader:UInt(), av = reader:UInt(), rl = reader:Str() }
    if record.n == "" then
        record.n = nil
    end
    if record.rl == "" then
        record.rl = nil
    end
    ReadEvents(reader, record)
    ReadAnswers(reader, record)
    ReadOptions(reader, record)
    -- Packed by an older version, the record ends here.
    if not reader:AtEnd() then
        record.mo = ReadNested(reader, LIMITS.statusEvents, "moderators", ReadModerator)
    end
    -- Anything after this was added by a later version.
    return guid, record
end
