# Guild Raids & Events

An addon for WoW Forever (the `_forever_` client, 1.60.x) to organize your
guild's raids, dungeons and other events from a tab on the guild window,
linked to the game's calendar.

- **A Raids & Events tab** on the guild window, under Blizzard's own tabs
  (Chat, Roster, Guild Info...). It lists the guild's upcoming events, the
  soonest first, and those of the last week. Each row shows when the event
  is, its type and organizer, how many go in each role (signed up or
  confirmed: not those tentative, on standby or out), and your answer.
- **An event's view**: click a row. Its sign-ups show in three columns, tanks,
  healers and damage, each name in its class colour, with its state
  (in the game calendar's colours: signed up and confirmed in green, standby
  and tentative in orange): confirmed
  first, then signed up, tentative and on standby; each column's count, as
  the rows', counts those signed up or confirmed; a column scrolls when they
  are more than it shows. Point at a name for its
  note. Those left out are listed under the columns.
  Under the columns, only signing up: not signed up, choose your role (at
  first the one your class and specialization stand for, the talent tree
  with the most points of your active spec group, a Feral druid tanking;
  then the one you chose last with that specialization) and write a short
  note if you like, on the left, and answer **Signed up** or **Tentative**,
  on the right; signed up in any way (a moderator too), only **Remove
  sign-up**, in the middle, as the game's calendar lets you: the event then
  leaves your calendar for about an hour (or until you log in again), and
  you sign up again once it is back (a moderator taken out is one no
  more). The organizer, whom the game keeps in their event, has nothing
  there. The buttons say so when they are off.
  Once signed up, a right-click on your own name gives its menu: your
  role, your note (**Edit note**) and, for the organizer and the
  moderators, your status (**Confirmed**, **Standby**, **Tentative** or
  **Out**; out, you stay in the event's list, as in the game). Your role
  you also change by dragging your name to another column.
- **Creating an event**: **New event**, under the list, for those whose
  guild rank may add guild events to the game's calendar. Give it a title,
  a type (raid, dungeon, PvP, meeting, other) and, for a raid or a dungeon,
  its instance, for PvP world PvP or a battleground (typed to search the
  game's Group Finder list, or picked from it); a day, picked in a
  month's calendar up to the last day the game's calendar takes, and a
  time; a description, places per role (or no limit), a minimum level,
  whether it repeats every week, whether it confirms sign-ups automatically,
  and whether it is locked. **Create** puts it in the game's calendar first,
  and the event comes into the addon once the calendar has it. The calendar
  has its own limit of events created; the addon has none: if the calendar
  refuses one, nothing comes into the addon, and Create and New event stay
  off, with the game's message, until one of your events leaves the
  calendar.
- **Confirmations**: the event's organizer and its moderators right-click a
  name for its menu: one of the game's statuses (confirmed, standby, out or
  tentative), the organizer's too, as in the game's calendar, and its role;
  or they drag the name to another column to change its role. Other members
  cannot change their own status, as in the game. They also change the
  event (**Edit**) or delete it (**Delete event**), as far as the game's
  calendar lets them. An event that confirms sign-ups
  automatically confirms those who sign up in each role while it has
  places, in the order they signed up, and leaves the rest on standby.
- **Deleting an event**, as in the game's calendar: **Delete event**, once
  you confirm it, deletes it from the calendar first, then from the addon,
  for everyone. Its organizer and its moderators may, and so may the guild
  master and those whose rank has the game's officer privileges (on any
  event, as the game's calendar lets them; their rank gives them nothing
  else). There is no getting a deleted event back, and no list of them.
- **Moderators**, as in the game's calendar: the organizer names them from
  a name's menu (**Set moderator**), among those in the event's list, and a
  moderator may name or take back others too, never the organizer. One who
  takes their sign-up back leaves the event's list and is a moderator no
  more, and signing up again does not make them one
  again. They are marked as the game's calendar marks them, and kept in
  step with it both ways. A moderator's client keeps the event in step with
  the calendar as its organizer's does (the organizer's own status too),
  also while the organizer is away.
- **Locked events**: the game's **Lock event**, in the form. Members then
  cannot sign up, answer tentative or remove their sign-up, in the addon as
  in the game's calendar; the organizer still changes their own state and
  gives statuses. A locked event shows "(Locked)" after its title. Next
  week's event of a weekly one takes answers again.
- **The game's calendar, both ways**: each event is also a guild sign-up
  event in the calendar, and the two stay in step wherever a change is
  made, also with the calendar's window open. **Create**, **Save** and
  **Delete event** change the calendar with the same click, the calendar
  first: the addon takes the change only once the calendar has taken it,
  and when the game refuses it, nothing changes and the addon says why
  (**Save** stays off, saying why, while the game would not take it). What
  you change in the calendar's window (title, time, type, description,
  whether it is locked, the statuses of the sign-ups) comes into the addon;
  an event deleted there is deleted from the addon, for everyone, once the
  calendar's data comes again without it; a guild event you create
  there comes into the addon as yours; a sign-up made there counts as made
  in the addon. Your own answer, and the confirmations of the events you
  organize, reach the calendar by themselves. When both sides changed the
  same thing, the calendar's wins.
- **Weekly events**: an event that repeats every week comes with next week's
  at once, and the one after is made each time one starts, so there are
  always two to come. Each goes to the calendar with its **Create in
  calendar** button, in its view and on its row (the game lets an addon
  create a calendar event only inside a click of the player); the button is
  off while the game takes no new event, as its own Create button, or after
  it reported its limit, and an event it refuses stays, waiting.
- **Reminders**: before the events you signed up to (or are tentative for),
  a raid warning on the screen, a line in the chat and a sound. Choose 5,
  15, 30 or 60 minutes before, or none, in Options > AddOns > Guild Raids &
  Events.
- **The notification mark**, as the game shows its own, on the tab and on the
  micro menu's guild button, while an upcoming event waits for your answer
  (until you see it in the list); in the list, on the rows of those new
  when you opened the tab, until you point at them, answer them or open it
  again.

Everything travels between the members who have the addon, by hidden
addon messages, while any of them is online: what you missed reaches you
when you log in.

One more thing the game's calendar does, and the addon with it: guild
events take sign-ups, not invitations, so sign-ups made outside the game
stay in the addon.

## Installing

With the CurseForge app, install Guild Raids & Events: the app also installs
**LibGuildSync**, the shared code of the guild addons. By hand, copy the
`GuildRaidsEvents` and `LibGuildSync` folders into
`World of Warcraft\_forever_\Interface\AddOns\`.

## Commands

| Command | What it does |
|---|---|
| `/gevents` or `/gevents status` | What the addon knows and is doing |
| `/gevents sync` | Ask the guild for missing data now |
| `/gevents options` | Open the addon's options |
| `/gevents language [code\|auto]` | Language of the addon's texts |
| `/gevents debug` | Show the sync log in the chat |
| `/gevents reset` | Forget the data of your current guild |

`/guildevents` works too.

## For addon authors

Other addons use the global table `GuildRaidsEvents` (API.lua). It names no
other addon: an addon that brings in sign-ups made outside the game (from a
website or a chat bot, say) registers as a "bridge", the guild master
chooses in the options which characters may bring them in, and those
characters' clients add them by the name of the guild member who signed up.

| Function | What it does |
|---|---|
| `GuildRaidsEvents.API_VERSION` | `1` |
| `GuildRaidsEvents.RegisterBridge(name)` | Registers a bridge addon: the options then show the page of bridge characters |
| `GuildRaidsEvents.IsBridgeCharacter()` | Whether the current character may bring sign-ups in |
| `GuildRaidsEvents.GetEvents(which)` | `"upcoming"` (the default), `"past"` or `"all"`: a list of events |
| `GuildRaidsEvents.GetEvent(key)` | One event, or nil |
| `GuildRaidsEvents.SetExternalSignUp(key, characterName, status, role, note)` | Brings in a sign-up: status `"signedUp"`, `"tentative"`, `"declined"`, or nil to take it back; role `"tank"`, `"healer"` or `"damage"`. Returns true, or false and why: `"notReady"`, `"notBridge"`, `"noEvent"`, `"locked"` (the event takes no answers), `"notMember"`, `"badStatus"`, `"badRole"`, `"full"` (this character holds as many as its record can) |
| `GuildRaidsEvents.OnChange(callback)` | Calls `callback()` whenever the events change |

An event is `{ key, title, type, start, startUnix, description, organizer,
organizerGUID, slots, minLevel, weekly, autoConfirm, locked, calendarID,
changed, signUps }`: `type` is `"raid"`, `"dungeon"`, `"pvp"`, `"meeting"`
or `"other"`; `start` is the game's calendar time (the server's) as seconds
as if it were UTC, and `startUnix` the same moment as a Unix time; `slots`
is `{ tank, healer, damage }`, or nil for no limit. A sign-up is `{ name,
guid, class, level, status, role, note, time, manage, auto, external }`:
`manage` is `"confirmed"`, `"standby"`, `"out"` or nil, `auto` says the
event set it automatically, and `external` that it was brought in from outside
the game. The newest answer of a member counts, whether made in the game or
brought in.

## Tests

The tests run outside the game with Lua 5.1, from the addon's folder, with
the `LibGuildSync` folder next to it (its test harness is shared):

```
lua5.1 Tests\run.lua . Tests
```

`Tests/game.lua` simulates the game's calendar as WoW Forever behaves
(build 71037): creating and changing only inside a click, and what a
player does in the calendar's own window (`world:WindowEdit` and the like).
`/gevents probe` is the in-game test that found out how it behaves: it
creates a test event, signs up to it with another character, gives statuses
and deletes it, and says what worked. `Probe.lua` stays in the repository
but not in the released files (`.pkgmeta` and `#@do-not-package@` in the
TOC).

## Releasing

CurseForge packages every tagged commit pushed here.

1. Raise `## Version` in `GuildRaidsEvents.toc` and add that version's entry
   at the top of `CHANGELOG.md`. The tests check that both match. If
   `ANNOUNCE_AS` is set in `Core.lua` (a version tried in game while telling
   the guild it is the last release), set it to nil. The tests print a note
   while it is on.
2. Commit, tag the commit `v<version>` and push the tag:
   `git push origin v<version>`. A tag containing `beta` or `alpha` makes a
   beta or alpha file instead of a release.
3. CurseForge builds the zip as `.pkgmeta` says: the `GuildRaidsEvents`
   folder without the tests and the probe, with `CHANGELOG.md` as the
   file's changelog.

## License

MIT. See [LICENSE](LICENSE).
