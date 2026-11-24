-- Guild Raids & Events: organizes the guild's raids, dungeons and other
-- events from a tab on the guild window (GuildTab.lua), linked to the
-- game's calendar (Calendar.lua). Members sign up with a role and a note,
-- the organizer and the officers confirm them or leave them on standby, and
-- each member is reminded before the events they go to (Reminders.lua).
-- Other addons read the events and add sign-ups made outside the game
-- through the public API (API.lua).
--
-- The addon messages, the guild roster, the saved database and the sync
-- are LibGuildSync's (a separate addon this one depends on), attached
-- below. Core.lua holds the startup and the slash commands.
local ADDON_NAME, ns = ...
local L = ns.L
local Lib = LibGuildSync

ns.ADDON_NAME = ADDON_NAME

Lib.Attach(ns, {
    title = "Guild Raids & Events",
    tag = "GRE",
    prefix = "GuildRaidsEvents",
    protocol = "1",
    savedVariable = "GuildRaidsEventsDB",
})

-- While a version that keeps the protocol is tried in game before its
-- release, it tells the guild it runs the last release (ANNOUNCE_AS): it
-- keeps sharing with the members on it, who are not told to update to a
-- version they cannot get yet. Set it to nil for the release.
local ANNOUNCE_AS = nil
if ANNOUNCE_AS then
    ns.VERSION_NUM = Lib.VersionNumber(ANNOUNCE_AS)
end

-- Nothing of ours needs reading before it is announced.
function ns.Sync.OwnReady()
    return true
end

-- Changes the members wait for (a sign-up, a confirmation) go out within
-- seconds.
for _, kind in ipairs({ "events", "signUps", "statuses", "external", "options" }) do
    ns.Sync.QUICK_KINDS[kind] = true
end

-- Startup ------------------------------------------------------------------

local events = CreateFrame("Frame")
ns.RegisterEvents(events, "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        ns.Data.PackForSave(ns.db)
    elseif event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        ns.Data.Load()
        if ns.db.settings.locale then
            ns.SetLocale(ns.db.settings.locale)
        end
    elseif event == "PLAYER_LOGIN" then
        -- The library first: our name, the roster, the messages and the sync.
        Lib.Start(ns)
        -- Each part starts on its own, so a failure in one (reported as a
        -- normal Lua error) does not stop the others.
        local parts = {
            ns.Events.Init, ns.Calendar.Init, ns.Reminders.Init, ns.GuildTab.Init, ns.Options.Init,
        }
        for _, init in ipairs(parts) do
            xpcall(init, geterrorhandler())
        end
    end
end)

-- Slash commands -------------------------------------------------------------

local function PrintHelp()
    ns.Print(L["/gevents status - what the addon knows and is doing"])
    ns.Print(L["/gevents sync - ask the guild for missing data now"])
    ns.Print(L["/gevents options - open the addon's options"])
    ns.Print(L["/gevents language [code|auto] - language of the addon's texts"])
    ns.Print(L["/gevents debug - show the sync log in the chat"])
    ns.Print(L["/gevents reset - forget the data of your current guild"])
end

local function PrintStatus()
    ns.Print(L["version %s. Saved data loaded by the client: %s."], ns.VERSION, ns.loadInfo.native and YES or NO)
    local guildKey = ns.Roster.guildKey
    if not guildKey then
        ns.Print(L["you are not in a guild (or the guild has not loaded yet)."])
    else
        local upcoming = #ns.Events.List("upcoming")
        ns.Print(L["guild %s: %d upcoming |4event:events;, %d |4member:members; in the roster."], guildKey, upcoming,
            ns.Roster.total)
    end
    -- What any click sends (an event to create waits for its own button).
    local pending = 0
    for _, item in ipairs(ns.Calendar.Pending()) do
        if item.kind ~= "create" then
            pending = pending + 1
        end
    end
    if pending > 0 then
        ns.Print(L["%d |4change waits:changes wait; for your click to reach the game's calendar."], pending)
    end
    -- The calendar's own state, as the author reads it (not translated).
    local last = ns.Calendar.lastSent
    ns.Print("calendar: data read %s; last change: %s", ns.Calendar.Scanned() and YES or NO,
        last and ("%s, %s ago: %s"):format(last.what, ns.Ago(last.at), last.result) or "none")
    ns.Print("calendar: %d guild events created by you in the months read", ns.Calendar.CreatedCount())
    if ns.Calendar.lastError then
        ns.Print("calendar: %s", ns.Calendar.lastError)
    end
    -- The default role, and the talent tree it comes from (Roles.lua).
    local tree, treeName = ns.Roles.ActiveTree()
    ns.Print("role: tree %s (%s), from the specialization %s, default %s", tostring(tree), tostring(treeName),
        ns.UI.RoleName(ns.Roles.OfSpec()), ns.UI.RoleName(ns.Roles.Default()))
    ns.Print(L["sync: %s"], ns.Sync.Describe())
end

SLASH_GUILDRAIDSEVENTS1 = "/gevents"
SLASH_GUILDRAIDSEVENTS2 = "/guildevents"
SlashCmdList.GUILDRAIDSEVENTS = function(message)
    message = strtrim(message or "")
    local command, rest = message:match("^(%S*)%s*(.-)$")
    local lower = command:lower()
    if lower == "" or lower == "status" then
        PrintStatus()
    elseif lower == "sync" then
        ns.Sync.SendHello(true)
    elseif lower == "options" then
        ns.Options.Open()
    elseif lower == "probe" and ns.Probe then
        -- The author's in-game test, left out of the released files.
        ns.Probe.Command(rest)
    elseif lower == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        ns.Print(ns.debugEnabled and L["sync log on."] or L["sync log off."])
    elseif lower == "language" or lower == "lang" then
        -- A language code in any case ("dede" is deDE), or auto.
        local code
        for _, known in ipairs(ns.LOCALES) do
            if known:lower() == rest:lower() then
                code = known
            end
        end
        if not code and rest:lower() ~= "auto" then
            ns.Print(L["languages: %s, or auto for the client's."], table.concat(ns.LOCALES, ", "))
            return
        end
        ns.db.settings.locale = code
        ns.SetLocale(code)
        ns.Print(L["language set to %s."], ns.LOCALE)
    elseif lower == "reset" then
        if rest:lower() ~= "confirm" then
            ns.Print(L["this forgets what you know about your current guild. Type /gevents reset confirm to do it."])
        else
            ns.Data.ResetGuild(ns.Roster.guildKey)
            ns.Print(L["data of your current guild forgotten."])
        end
    else
        PrintHelp()
    end
end
