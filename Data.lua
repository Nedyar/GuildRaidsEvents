-- Data.lua: what Guild Raids & Events adds to LibGuildSync's database
-- (Store.lua): checking its records (see Pack.lua for their fields). Plain
-- Lua with no game API but the library's checks.
local _, ns = ...

local Lib = LibGuildSync
local Data = ns.Data
local LIMITS = ns.Pack.LIMITS

local FUTURE_SLACK = 300  -- how far a time may run ahead of ours
local MIN_START = 1e9     -- an event's start (Events.Naive), in 2001 or later
local MAX_START = 4e9

-- Copies of the same time: the one with more in it is kept.
Data.STATS = 1

function Data.Stats(record)
    local count = #(record.ev or {})
    for _ in pairs(record.su or {}) do
        count = count + 1
    end
    return count
end

local function IsTime(value, now)
    return Lib.IsTime(value) and not (now and value > now + FUTURE_SLACK)
end

-- A text as the game lets players type it: no escape sequences, links or
-- control characters (but new lines in a description).
local function CleanText(text, max, lines)
    if type(text) ~= "string" or #text > max then
        return nil
    end
    local pattern = lines and "[|%z\1-\9\11-\31]" or "[|%c]"
    if text:find(pattern) then
        return nil
    end
    return text
end
Data.CleanText = CleanText

-- A text cut to its first letters (UTF-8 characters, not bytes).
function Data.CutLetters(text, letters)
    local count, cut = 0, #text
    for start in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > letters then
            cut = start - 1
            break
        end
    end
    return text:sub(1, cut)
end

-- A sign-up's note as the record keeps it: trimmed, at most
-- LIMITS.noteLetters letters (a longer one is cut); nil when empty or
-- holding what the game does not let players type.
function Data.CleanNote(note)
    note = type(note) == "string" and note:match("^%s*(.-)%s*$") or ""
    if note == "" then
        return nil
    end
    return CleanText(Data.CutLetters(note, LIMITS.noteLetters), LIMITS.note)
end

function Data.IsID(id)
    return type(id) == "string" and #id >= 1 and #id <= LIMITS.id and id:find("^[%w]+$") ~= nil
end

-- An event's key: its organizer's GUID, "/", its ID.
function Data.IsKey(key)
    if type(key) ~= "string" or #key > LIMITS.key then
        return false
    end
    local guid, id = key:match("^(.+)/(.+)$")
    return guid ~= nil and Lib.IsGUID(guid) and Data.IsID(id)
end

-- The fields of an event (or of an officer's change of one), checked: a new
-- table, or nil.
local function CleanFields(event, now)
    if type(event) ~= "table" or not Lib.IsCount(event.ty, 4) or not IsTime(event.at, now)
        or not Lib.IsCount(event.tm, MAX_START) or event.tm < MIN_START then
        return nil
    end
    local title = CleanText(event.ti, LIMITS.title)
    if not title or title == "" then
        return nil
    end
    local clean = { ty = event.ty, ti = title, tm = math.floor(event.tm), at = event.at, ml = 0 }
    if event.de ~= nil then
        clean.de = CleanText(event.de, LIMITS.description, true)
        if not clean.de then
            return nil
        end
    end
    if event.sl ~= nil then
        local slots = event.sl
        if type(slots) ~= "table" or not Lib.IsCount(slots.t, LIMITS.slots) or not Lib.IsCount(slots.h, LIMITS.slots)
            or not Lib.IsCount(slots.d, LIMITS.slots) then
            return nil
        end
        clean.sl = { t = slots.t, h = slots.h, d = slots.d }
    end
    if event.ml ~= nil then
        if not Lib.IsCount(event.ml, LIMITS.level) then
            return nil
        end
        clean.ml = event.ml
    end
    if event.ii ~= nil then
        if not Lib.IsCount(event.ii, 1000000) or event.ii == 0 then
            return nil
        end
        clean.ii = event.ii
    end
    clean.wk = event.wk == true or nil
    clean.nx = event.nx == true or nil
    clean.ac = event.ac == true or nil
    clean.lk = event.lk == true or nil
    clean.x = event.x == true or nil
    return clean
end
Data.CleanFields = CleanFields

local function CleanAnswer(answer, now)
    if type(answer) ~= "table" or not Lib.IsCount(answer.st, 3) or answer.st < 1 or not IsTime(answer.at, now) then
        return nil
    end
    local clean = { st = answer.st, at = answer.at }
    if answer.ro ~= nil then
        if not Lib.IsCount(answer.ro, 3) or answer.ro < 1 then
            return nil
        end
        clean.ro = answer.ro
    end
    if answer.no ~= nil then
        clean.no = CleanText(answer.no, LIMITS.note)
        if not clean.no then
            return nil
        end
        if clean.no == "" then
            clean.no = nil
        end
    end
    return clean
end

local function CleanStatus(status, now)
    if type(status) ~= "table" or not Lib.IsCount(status.st, 4) or not IsTime(status.at, now) then
        return nil
    end
    return { st = status.st, at = status.at }
end

-- The string keys of a table, sorted: what goes over a limit is the same
-- on every client.
local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

-- { [key] = { [GUID] = item } }, each item checked by clean; at most
-- LIMITS.statusEvents events and LIMITS.perEvent items in one.
local function CleanNested(map, clean, now)
    if type(map) ~= "table" then
        return nil
    end
    local result, events = {}, 0
    for _, key in ipairs(SortedKeys(map)) do
        local inner = map[key]
        if Data.IsKey(key) and type(inner) == "table" then
            local items, count = {}, 0
            for _, guid in ipairs(SortedKeys(inner)) do
                local item = inner[guid]
                local checked = Lib.IsGUID(guid) and clean(item, now)
                if checked and count < LIMITS.perEvent then
                    items[guid] = checked
                    count = count + 1
                end
            end
            if count > 0 and events < LIMITS.statusEvents then
                result[key] = items
                events = events + 1
            end
        end
    end
    return next(result) and result or nil
end

local function CleanOptions(options, now)
    if type(options) ~= "table" or not IsTime(options.t, now) or type(options.br) ~= "table" then
        return nil
    end
    local clean, seen = { t = options.t, br = {} }, {}
    for _, guid in ipairs(options.br) do
        if Lib.IsGUID(guid) and not seen[guid] and #clean.br < LIMITS.bridges then
            seen[guid] = true
            clean.br[#clean.br + 1] = guid
        end
    end
    return clean
end

-- A checked copy of a record, or nil when it cannot be trusted. What does
-- not pass its checks inside it is left out, the rest kept: every client
-- leaves out the same.
function Data.CleanRecord(record, now)
    local clean = Data.CleanBase(record, now)
    if not clean then
        return nil
    end
    if type(record.ev) == "table" then
        local events, ids = {}, {}
        for _, event in ipairs(record.ev) do
            local fields = Data.IsID(type(event) == "table" and event.id) and CleanFields(event, now)
            if fields and not ids[event.id] and #events < LIMITS.events then
                ids[event.id] = true
                fields.id = event.id
                fields.ci = Lib.IsCount(event.ci, 4294967295) and event.ci or 0
                events[#events + 1] = fields
            end
        end
        clean.ev = #events > 0 and events or nil
    end
    if type(record.pe) == "table" then
        local patches, count = {}, 0
        for _, key in ipairs(SortedKeys(record.pe)) do
            local fields = Data.IsKey(key) and CleanFields(record.pe[key], now)
            if fields and count < LIMITS.patches then
                patches[key] = fields
                count = count + 1
            end
        end
        clean.pe = count > 0 and patches or nil
    end
    if type(record.su) == "table" then
        local answers, count = {}, 0
        for _, key in ipairs(SortedKeys(record.su)) do
            local checked = Data.IsKey(key) and CleanAnswer(record.su[key], now)
            if checked and count < LIMITS.signUps then
                answers[key] = checked
                count = count + 1
            end
        end
        clean.su = count > 0 and answers or nil
    end
    clean.ms = CleanNested(record.ms, CleanStatus, now)
    clean.xs = CleanNested(record.xs, CleanAnswer, now)
    if record.cf ~= nil then
        clean.cf = CleanOptions(record.cf, now)
    end
    return clean
end
