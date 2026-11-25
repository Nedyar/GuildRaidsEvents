-- What the game gives Guild Raids & Events that LibGuildSync's shared
-- harness does not simulate: the game's calendar above all (world.calendar,
-- shared by every client, as the server keeps it), the calendar's clock,
-- context menus, and clicks of the player (hardware events).
--
-- The calendar behaves as WoW Forever's did in the probe (build 71037):
-- AddEvent and UpdateEvent only inside a click (H.Click), else
-- ADDON_ACTION_BLOCKED; everything else at any time. A sign-up goes from
-- not signed up to signed up or tentative only; taking it back
-- (RemoveEvent) hides the event from that player's calendar until
-- world:ShowHidden() (the game shows it again about an hour later).
--
-- What a player does in the game's calendar window: world:WindowEdit(id,
-- fields), world:WindowDelete(id), world:WindowCreate(client, fields),
-- world:WindowAnswer(client, id, status), world:WindowStatus(id, guid,
-- status) and world:WindowModerator(id, guid, on). A member without the
-- addon (world:AddMember) stands as client { guid = their GUID }.
return function(H)
    H.NoOpMethods.SetMaxLines = true
    H.NoOpMethods.SetJustifyV = true
    H.NoOpMethods.SetSize = true
    H.NoOpMethods.SetNormalTexture = true
    H.NoOpMethods.SetPushedTexture = true
    H.NoOpMethods.SetDisabledTexture = true
    H.NoOpMethods.SetHyperlinksEnabled = true

    -- WoW Forever's Group Finder activities, as C_LFGList gives them: a few
    -- dungeons (category 2), raids (114) and battlegrounds (118), and a
    -- quest (116), which is no place.
    H.ACTIVITIES = {
        [796] = { "Wailing Caverns", "", 2, 15 }, [797] = { "Scholomance", "", 2, 55 },
        [798] = { "Sima Ígnea", "", 2, 13 }, [805] = { "Scarlet Monastery - Graveyard", "Scarlet Graveyard", 2, 26 },
        [813] = { "Dire Maul (East)", "", 2, 55 },
        [836] = { "Zul'Gurub", "", 114, 56 }, [838] = { "Onyxia's Lair", "", 114, 60 }, [839] = { "Molten Core", "", 114, 60 },
        [919] = { "Warsong Gulch", "", 118, 10 }, [920] = { "Warsong Gulch", "", 118, 20 }, [932] = { "Alterac Valley", "", 118, 51 },
        [1992] = { "Islas Lanza Negra", "", 118, 60 }, [1000] = { "Questing", "", 116, 1 },
    }
    H.FrameMethods.SetTitle = function(self, title)
        self._title = title
    end
    H.FrameMethods.SetTexture = function(self, texture)
        self._texture = texture
    end
    H.FrameMethods.Enable = function(self)
        self:SetEnabled(true)
    end
    H.FrameMethods.Disable = function(self)
        self:SetEnabled(false)
    end

    -- Menus also have titles.
    local NewMenuDescription = H.NewMenuDescription
    function H.NewMenuDescription()
        local description = NewMenuDescription()
        function description:CreateTitle(text)
            self.entries[#self.entries + 1] = { kind = "title", text = text }
        end
        function description:CreateDivider()
            self.entries[#self.entries + 1] = { kind = "divider" }
        end
        return description
    end

    -- A click of the player on a button: its OnClick, inside a hardware
    -- event.
    function H.Click(button, mouse)
        if (button.IsEnabled and not button:IsEnabled()) or (button.IsShown and not button:IsShown()) then
            return
        end
        local client = button._client
        client.inClick = true
        local ok, err = pcall(button._scripts.OnClick, button, mouse or "LeftButton", false)
        client.inClick = false
        if not ok then
            error(err, 2)
        end
    end

    -- The first entry of a menu whose text is text.
    function H.MenuEntry(entries, text)
        for _, entry in ipairs(entries or {}) do
            if entry.text == text then
                return entry
            end
        end
    end

    local STATUS = { Invited = 0, Available = 1, Declined = 2, Confirmed = 3, Out = 4, Standby = 5, Signedup = 6,
        NotSignedup = 7, Tentative = 8 }

    local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local function DaysIn(month, year)
        if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
            return 29
        end
        return DAYS_IN_MONTH[month]
    end

    -- The calendar's clock: the server's time read as UTC.
    local function CalendarTime(world)
        local t = os.date("!*t", world:ServerTime())
        return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min, weekday = t.wday }
    end
    H.CalendarTime = CalendarTime

    local function Calendar(world)
        world.calendar = world.calendar or { events = {}, nextID = 2773000, hidden = {} }
        return world.calendar
    end

    -- Every hidden event shows again in the calendars of those who took
    -- their sign-up back.
    local function ShowHidden(world)
        Calendar(world).hidden = {}
    end

    -- The events of a day in a client's calendar, in order.
    local function DayEvents(client, year, month, day)
        local calendar = Calendar(client.world)
        local hidden = calendar.hidden[client.guid] or {}
        local list = {}
        for _, event in pairs(calendar.events) do
            local s = event.start
            if not event.deleted and not hidden[event.id] and s.year == year and s.month == month and s.day == day then
                list[#list + 1] = event
            end
        end
        table.sort(list, function(a, b)
            local ta, tb = a.start.hour * 60 + a.start.minute, b.start.hour * 60 + b.start.minute
            if ta ~= tb then
                return ta < tb
            end
            return a.id < b.id
        end)
        return list
    end

    local function Broadcast(world, ...)
        local args = { ... }
        world:Schedule(0.2, function()
            for _, other in ipairs(world.clients) do
                if other.loggedIn then
                    for _, event in ipairs(args) do
                        world:FireEvent(other, event)
                    end
                end
            end
        end)
    end

    -- The game's calendar window, used by a player.
    local function WindowEdit(world, id, fields)
        local event = Calendar(world).events[id]
        for field, value in pairs(fields) do
            if field == "hour" or field == "minute" or field == "day" then
                event.start[field] = value
            else
                event[field] = value
            end
        end
        Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST")
    end
    local function WindowDelete(world, id)
        Calendar(world).events[id].deleted = true
        Broadcast(world, "CALENDAR_UPDATE_GUILD_EVENTS", "CALENDAR_UPDATE_EVENT_LIST")
    end
    local function WindowCreate(world, client, fields)
        local calendar = Calendar(world)
        calendar.nextID = calendar.nextID + 1
        local t = os.date("!*t", fields.at)
        calendar.events[calendar.nextID] = {
            id = calendar.nextID, title = fields.title, type = fields.type or 4, description = fields.description or "",
            start = { year = t.year, month = t.month, day = t.day, hour = t.hour, minute = t.min },
            creator = client.guid,
            invites = { [client.guid] = { status = 3, modStatus = "CREATOR", at = world:ServerTime() } },
        }
        Broadcast(world, "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_GUILD_EVENTS", "CALENDAR_UPDATE_EVENT_LIST")
        return calendar.nextID
    end
    -- status nil: the sign-up taken back (the event then leaves that
    -- player's calendar, as with RemoveEvent).
    local function WindowAnswer(world, client, id, status)
        local calendar = Calendar(world)
        local event = calendar.events[id]
        if status then
            event.invites[client.guid] = { status = status, modStatus = "", at = world:ServerTime() }
        else
            event.invites[client.guid] = nil
            calendar.hidden[client.guid] = calendar.hidden[client.guid] or {}
            calendar.hidden[client.guid][id] = true
        end
        Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_INVITE_LIST")
    end
    local function WindowStatus(world, id, guid, status)
        Calendar(world).events[id].invites[guid].status = status
        Broadcast(world, "CALENDAR_UPDATE_INVITE_LIST")
    end
    -- The creator (or a moderator) names a moderator in the window, or
    -- takes it back.
    local function WindowModerator(world, id, guid, on)
        Calendar(world).events[id].invites[guid].modStatus = on and "MODERATOR" or ""
        Broadcast(world, "CALENDAR_UPDATE_INVITE_LIST")
    end

    local function NameOf(world, guid)
        for _, member in ipairs(world.roster) do
            if member.guid == guid then
                return member.short
            end
        end
        return "?"
    end

    local function CalendarAPI(client, env)
        local world = client.world
        local calendar = Calendar(world)
        client.calendarCalls = {}
        client.month = nil
        local open      -- { draft = true, fields } or { id, fields }
        local selected  -- the event a context menu acts on
        local function Log(name)
            client.calendarCalls[#client.calendarCalls + 1] = name
        end
        local function Restricted(name)
            Log(name)
            if not client.inClick then
                world:FireEvent(client, "ADDON_ACTION_BLOCKED", "GuildRaidsEvents", name .. "()")
                return false
            end
            return true
        end
        local function Month(offset)
            local now = CalendarTime(world)
            local base = client.month or { month = now.month, year = now.year }
            local index = base.year * 12 + base.month - 1 + offset
            return index % 12 + 1, math.floor(index / 12)
        end
        local function EventAt(offset, day, index)
            local month, year = Month(offset)
            return DayEvents(client, year, month, day)[index]
        end
        -- Its creator, one of its moderators, or the guild master or an
        -- officer (seen in game).
        local function MayRemove(event)
            local mine = event.invites[client.guid]
            if event.creator == client.guid or mine ~= nil and mine.modStatus == "MODERATOR" then
                return true
            end
            for _, member in ipairs(world.roster) do
                if member.guid == client.guid then
                    return member.rankIndex == 0 or (world.officerRanks or {})[member.rankIndex] == true
                end
            end
            return false
        end
        local function MyStatus(event)
            local invite = event.invites[client.guid]
            return invite and invite.status or STATUS.NotSignedup
        end
        local function StartTime(s)
            return { year = s.year, month = s.month, monthDay = s.day, hour = s.hour, minute = s.minute }
        end
        local function Invites(event)
            local list = {}
            for guid, invite in pairs(event.invites) do
                list[#list + 1] = { guid = guid, name = NameOf(world, guid), invite = invite }
            end
            table.sort(list, function(a, b)
                return a.name < b.name
            end)
            return list
        end
        local function Fields()
            open.fields = open.fields or {}
            return open.fields
        end
        local function Refused(event)
            if event and event.locked and event.creator ~= client.guid then
                Log("refused: locked")
                return true
            end
            return false
        end
        -- The game's clock setting: 24 hours, unless a test sets
        -- client.twelveHour.
        env.GetCVarBool = function(name)
            if name == "timeMgrUseMilitaryTime" then
                return not client.twelveHour
            end
            return false
        end
        env.C_DateAndTime = {
            GetCurrentCalendarTime = function()
                return CalendarTime(world)
            end,
        }
        env.Enum = env.Enum or {}
        env.Enum.CalendarStatus = STATUS
        env.Enum.CalendarEventType = { Raid = 0, Dungeon = 1, PvP = 2, Meeting = 3, Other = 4 }
        env.C_Calendar = {
            OpenCalendar = function()
                Log("OpenCalendar")
                world:Schedule(0.3, function()
                    world:FireEvent(client, "CALENDAR_UPDATE_EVENT_LIST")
                end, client)
            end,
            SetAbsMonth = function(month, year)
                client.month = { month = month, year = year }
            end,
            GetMonthInfo = function(offset)
                local month, year = Month(offset)
                return { month = month, year = year, numDays = DaysIn(month, year), firstWeekday = 1 }
            end,
            GetNumDayEvents = function(offset, day)
                local month, year = Month(offset)
                return #DayEvents(client, year, month, day)
            end,
            GetDayEvent = function(offset, day, index)
                local event = EventAt(offset, day, index)
                if not event then
                    return nil
                end
                return {
                    eventID = event.id, title = event.title, calendarType = "GUILD_EVENT", eventType = event.type,
                    inviteStatus = MyStatus(event),
                    modStatus = event.creator == client.guid and "CREATOR"
                        or event.invites[client.guid] and event.invites[client.guid].modStatus or "",
                    invitedBy = NameOf(world, event.creator), startTime = StartTime(event.start), inviteType = 1,
                    isLocked = event.locked == true,
                }
            end,
            GetNumGuildEvents = function()
                local count = 0
                for _, event in pairs(calendar.events) do
                    if not event.deleted then
                        count = count + 1
                    end
                end
                return count
            end,
            GetGuildEventInfo = function(index)
                local list = {}
                for _, event in pairs(calendar.events) do
                    if not event.deleted then
                        list[#list + 1] = event
                    end
                end
                table.sort(list, function(a, b)
                    return a.id < b.id
                end)
                local event = list[index]
                return event and {
                    eventID = event.id, title = event.title, year = event.start.year, month = event.start.month,
                    monthDay = event.start.day, hour = event.start.hour, minute = event.start.minute, eventType = event.type,
                    calendarType = "GUILD_EVENT", inviteStatus = MyStatus(event),
                } or nil
            end,
            CanAddEvent = function()
                return client.canAddEvent ~= false
            end,
            -- New events up to a year ahead.
            GetMaxCreateDate = function()
                local t = os.date("!*t", world:ServerTime() + 365 * 86400)
                return { year = t.year, month = t.month, monthDay = t.day, hour = 0, minute = 0 }
            end,
            IsActionPending = function()
                return false
            end,
            CreateGuildSignUpEvent = function()
                Log("CreateGuildSignUpEvent")
                open = { draft = true, fields = {} }
            end,
            EventSetTitle = function(title)
                Fields().title = title
            end,
            EventSetType = function(eventType)
                Fields().type = eventType
            end,
            EventSetDate = function(month, day, year)
                Fields().date = { month = month, day = day, year = year }
            end,
            EventSetTime = function(hour, minute)
                Fields().time = { hour = hour, minute = minute }
            end,
            EventSetDescription = function(description)
                Fields().description = description
            end,
            EventSetLocked = function()
                Fields().locked = true
            end,
            EventClearLocked = function()
                Fields().locked = false
            end,
            AddEvent = function()
                if not Restricted("AddEvent") or not open or not open.draft then
                    return
                end
                -- The game's limit of events created (client.eventLimit), as
                -- the server refuses one more.
                local made = 0
                for _, one in pairs(calendar.events) do
                    if not one.deleted and one.creator == client.guid then
                        made = made + 1
                    end
                end
                if client.eventLimit and made >= client.eventLimit then
                    open = nil
                    world:Schedule(0.2, function()
                        world:FireEvent(client, "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_ERROR_EVENTS_EXCEEDED",
                            client.eventLimit)
                    end, client)
                    return
                end
                local f = open.fields
                calendar.nextID = calendar.nextID + 1
                local event = {
                    id = calendar.nextID, title = f.title, type = f.type, description = f.description or "",
                    locked = f.locked == true,
                    start = { year = f.date.year, month = f.date.month, day = f.date.day, hour = f.time.hour,
                        minute = f.time.minute },
                    creator = client.guid,
                    invites = { [client.guid] = { status = STATUS.Confirmed, modStatus = "CREATOR", at = world:ServerTime() } },
                }
                calendar.events[event.id] = event
                open = nil
                Broadcast(world, "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_GUILD_EVENTS", "CALENDAR_UPDATE_EVENT_LIST")
            end,
            -- Which events a client opened: client.opened[event ID] = times.
            OpenEvent = function(offset, day, index)
                Log("OpenEvent")
                local event = EventAt(offset, day, index)
                if not event then
                    return false
                end
                client.opened = client.opened or {}
                client.opened[event.id] = (client.opened[event.id] or 0) + 1
                open = { id = event.id }
                world:Schedule(0.2, function()
                    world:FireEvent(client, "CALENDAR_OPEN_EVENT", "GUILD_EVENT")
                end, client)
                return true
            end,
            IsEventOpen = function()
                return open ~= nil
            end,
            -- Its creator and its moderators.
            EventCanEdit = function()
                local event = open and open.id and calendar.events[open.id]
                local mine = event and event.invites[client.guid]
                return event ~= nil and (event.creator == client.guid or mine ~= nil and mine.modStatus == "MODERATOR")
            end,
            GetEventInfo = function()
                local event = open and open.id and calendar.events[open.id]
                if open and open.draft then
                    return { title = open.fields.title or "", calendarType = "GUILD_EVENT", isLocked = open.fields.locked == true }
                end
                if not event then
                    return nil
                end
                return {
                    title = event.title, description = event.description, eventType = event.type,
                    time = StartTime(event.start), creator = NameOf(world, event.creator), inviteStatus = MyStatus(event),
                    calendarType = "GUILD_EVENT", inviteType = 1, isLocked = event.locked == true,
                }
            end,
            CloseEvent = function()
                Log("CloseEvent")
                open = nil
                world:FireEvent(client, "CALENDAR_CLOSE_EVENT")
            end,
            UpdateEvent = function()
                if not Restricted("UpdateEvent") or not open or not open.id then
                    return
                end
                local event = calendar.events[open.id]
                local f = open.fields or {}
                event.title = f.title or event.title
                event.type = f.type or event.type
                event.description = f.description or event.description
                if f.locked ~= nil then
                    event.locked = f.locked
                end
                if f.date then
                    event.start.year, event.start.month, event.start.day = f.date.year, f.date.month, f.date.day
                end
                if f.time then
                    event.start.hour, event.start.minute = f.time.hour, f.time.minute
                end
                Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST")
            end,
            EventSignUp = function()
                Log("EventSignUp")
                local event = open and open.id and calendar.events[open.id]
                if not Refused(event) and event and MyStatus(event) == STATUS.NotSignedup then
                    event.invites[client.guid] = { status = STATUS.Signedup, modStatus = "", at = world:ServerTime() }
                    Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            EventTentative = function()
                Log("EventTentative")
                local event = open and open.id and calendar.events[open.id]
                if not Refused(event) and event and MyStatus(event) == STATUS.NotSignedup then
                    event.invites[client.guid] = { status = STATUS.Tentative, modStatus = "", at = world:ServerTime() }
                    Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            RemoveEvent = function()
                Log("RemoveEvent")
                local event = open and open.id and calendar.events[open.id]
                if not Refused(event) and event then
                    event.invites[client.guid] = nil
                    calendar.hidden[client.guid] = calendar.hidden[client.guid] or {}
                    calendar.hidden[client.guid][event.id] = true
                    open = nil
                    world:FireEvent(client, "CALENDAR_CLOSE_EVENT")
                    Broadcast(world, "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            -- world.invitesLoading: an event's list not there yet, as it
            -- may come a moment after the event opens.
            GetNumInvites = function()
                local event = open and open.id and calendar.events[open.id]
                return event and not world.invitesLoading and #Invites(event) or 0
            end,
            EventGetInvite = function(index)
                local event = open and open.id and calendar.events[open.id]
                local entry = event and Invites(event)[index]
                if not entry then
                    return nil
                end
                return {
                    name = entry.name, guid = entry.guid, inviteStatus = entry.invite.status,
                    modStatus = entry.invite.modStatus, inviteIsMine = entry.guid == client.guid,
                }
            end,
            -- When a line answered (weekday 0: not known).
            EventGetInviteResponseTime = function(index)
                local event = open and open.id and calendar.events[open.id]
                local entry = event and Invites(event)[index]
                if not entry or not entry.invite.at then
                    return { year = 0, month = 0, monthDay = 0, hour = 0, minute = 0, weekday = 0 }
                end
                local t = os.date("!*t", entry.invite.at)
                return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min, weekday = t.wday }
            end,
            -- By its creator or a moderator, on anyone in the list but its
            -- creator; no click needed.
            EventSetModerator = function(index)
                Log("EventSetModerator")
                local event = open and open.id and calendar.events[open.id]
                local entry = event and Invites(event)[index]
                local mine = event and event.invites[client.guid]
                if entry and entry.invite.modStatus ~= "CREATOR"
                        and (event.creator == client.guid or mine and mine.modStatus == "MODERATOR") then
                    entry.invite.modStatus = "MODERATOR"
                    Broadcast(world, "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            EventClearModerator = function(index)
                Log("EventClearModerator")
                local event = open and open.id and calendar.events[open.id]
                local entry = event and Invites(event)[index]
                local mine = event and event.invites[client.guid]
                if entry and entry.invite.modStatus == "MODERATOR"
                        and (event.creator == client.guid or mine and mine.modStatus == "MODERATOR") then
                    entry.invite.modStatus = ""
                    Broadcast(world, "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            -- By its creator or a moderator (a moderator's, untested in the
            -- game: as its window offers it in edit mode).
            EventSetInviteStatus = function(index, status)
                Log("EventSetInviteStatus")
                local event = open and open.id and calendar.events[open.id]
                local entry = event and Invites(event)[index]
                local mine = event and event.invites[client.guid]
                if entry and (event.creator == client.guid or mine and mine.modStatus == "MODERATOR") then
                    entry.invite.status = status
                    Broadcast(world, "CALENDAR_UPDATE_INVITE_LIST")
                end
            end,
            ContextMenuSelectEvent = function(offset, day, index)
                local event = EventAt(offset, day, index)
                selected = event and event.id
            end,
            -- Only the open event (WoW Forever said false for one not
            -- open; its window offers Delete on the event selected), by
            -- those MayRemove says. world.refuseRemove:
            -- the game says no all the same.
            ContextMenuEventCanRemove = function(offset, day, index)
                local event = EventAt(offset, day, index)
                return event ~= nil and MayRemove(event) and open ~= nil and open.id == event.id
                    and not world.refuseRemove
            end,
            -- world.restrictRemove: refused outside a click, as the game
            -- did once (the addon then waits for a click to delete).
            ContextMenuEventRemove = function()
                if world.restrictRemove then
                    if not Restricted("ContextMenuEventRemove") then
                        return
                    end
                else
                    Log("ContextMenuEventRemove")
                end
                local event = selected and calendar.events[selected]
                if not open or open.id ~= selected then
                    world:Schedule(0.2, function()
                        world:FireEvent(client, "CALENDAR_UPDATE_ERROR", "CALENDAR_ERROR_PERMISSIONS")
                    end, client)
                elseif event and MayRemove(event) then
                    event.deleted = true
                    Broadcast(world, "CALENDAR_UPDATE_GUILD_EVENTS", "CALENDAR_UPDATE_EVENT_LIST")
                end
            end,
        }
        -- The cursor, for dragging (the tests say which frame it is over
        -- with IsMouseOver), and the screen's scale.
        env.GetCursorPosition = function()
            return 0, 0
        end
        env.UIParent.GetEffectiveScale = function()
            return 1
        end
        -- Guild ranks with "Has officer privileges": client.world.officerRanks
        -- = { [rank index] = true }.
        env.C_GuildInfo.GuildControlGetRankFlags = function(rankOrder)
            local flags = {}
            for i = 1, 24 do
                flags[i] = false
            end
            flags[22] = (world.officerRanks or {})[rankOrder - 1] == true
            return flags
        end
        -- Context menus: the last one is client.contextMenu (its entries).
        env.MenuUtil = {
            CreateContextMenu = function(owner, generator)
                local root = H.NewMenuDescription()
                generator(owner, root)
                client.contextMenu = root.entries
            end,
        }
        env.RaidNotice_AddMessage = function(_, text)
            client.raidWarnings = client.raidWarnings or {}
            client.raidWarnings[#client.raidWarnings + 1] = text
        end
        env.RaidWarningFrame = {}
        env.ChatTypeInfo = { RAID_WARNING = {} }
        env.SOUNDKIT.RAID_WARNING = 8959
        env.UISpecialFrames = {}
        env.CALENDAR_TYPE_RAID, env.CALENDAR_TYPE_DUNGEON = "Raid", "Dungeon"
        env.TANK, env.HEALER, env.DAMAGER = "Tank", "Healer", "Damage"
        env.YES, env.NO = "Yes", "No"
        env.C_LFGList = {
            GetActivityInfoTable = function(id)
                local activity = H.ACTIVITIES[id]
                if not activity then
                    return nil
                end
                return { fullName = activity[1], shortName = activity[2], categoryID = activity[3],
                    minLevelSuggestion = activity[4], minLevel = activity[4], isPvpActivity = activity[3] == 118 }
            end,
        }
    end

    -- Every world made by the tests gets it.
    local NewWorld = H.NewWorld
    function H.NewWorld(options)
        local world = NewWorld(options)
        local MakeEnv = world.MakeEnv
        world.MakeEnv = function(self, client)
            local env = MakeEnv(self, client)
            CalendarAPI(client, env)
            return env
        end
        world.ShowHidden = ShowHidden
        world.WindowEdit, world.WindowDelete, world.WindowCreate = WindowEdit, WindowDelete, WindowCreate
        world.WindowAnswer, world.WindowStatus, world.WindowModerator = WindowAnswer, WindowStatus, WindowModerator
        return world
    end
end
