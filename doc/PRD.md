# XSocial — Cross-Guild Channel Communication Addon PRD

Version: 0.5.0  |  Platform: Turtle WoW / Vanilla (Interface 11200)  |  Status: Approved Specification

---

## 1. Overview
XSocial is a lightweight Turtle WoW / Vanilla 1.12 addon designed for cross-guild friend circles, alts, and multi-account players communicating via a shared custom chat channel.

Vanilla WoW 1.12 provides no built-in channel join/leave notifications, and standard `SendAddonMessage` does not support custom chat channels (`"CHANNEL"` distribution was only introduced in later expansions). XSocial addresses these platform constraints with a **Targeted, Zero-Storm Protocol & Dedicated Social Hub**:
- Players announce their presence with their nickname, location, and a personal toon-specific note (`#NICK#ZONE#NOTE#`) upon logging in, switching channels, or updating information.
- A targeted inquiry protocol (`#whois# <Toon>`) lets players discover unknown members on demand, answered strictly by the queried player.
- For players without XSocial, an optional best-effort `/who` fallback discovers their level, class, and zone.
- All channel conversation is centralized inside XSocial's dedicated Chat Window on the right panel, featuring full hyperlink interactivity (items, quests, spells, and player whisper links).
- Nicknames are account-wide, while player notes are stored per-toon. All metadata is persisted in `SavedVariables` under a unified data model (`XSocialDB.version = 1`).

The user interface features:
1. A **minimalist floating HUD status button** displaying `<ChannelName> | <TotalCount>` (e.g. `maidou | 20`). Strictly shows total channel online count.
2. A **dual-pane Main Window (~620px wide × 360px high)**:
   - **Merged Top Bar**: Channel `[⚙]`, Nickname `[⚙]`, Note `[⚙]`, HUD `[Lock]`, and `[X]` (no redundant labels).
   - **Left Pane (Roster & Search, ~240px)**:
     - Scrollable member roster with Toon name (click to whisper `/w <Toon> `), Nickname (gold), and compact `[?]` inquire button.
     - Rich hover tooltip showing Toon, Nickname, Level & Class, Location, and Note.
     - Bottom bar: Total online count (`Online: %d`) and Search/Filter box.
   - **Right Pane (Dedicated Channel Chat, ~380px)**:
     - `ScrollingMessageFrame` showing channel conversation with full item/quest/spell/player hyperlink and color support.
     - Protocol messages (`#whois#`, `#NICK#ZONE#NOTE#`) are silently consumed for sync and never shown.
     - Real chat replaces Toon names with Nicknames as clickable player links (`|Hplayer:Toon|h[Nick]|h`) to allow easy whispering.
     - Bottom chat input box + `[Send]` button (and Enter key) to talk directly into the channel.

---

## 2. Background & Architecture Decisions

### 2.1 WoW 1.12 Platform Constraints
- **Custom Channel Limitations**: Custom channels do not emit presence events; roster discovery relies on `/chatlist` / `GetChannelRosterInfo`.
- **Addon Messaging Scope**: In WoW 1.12, `SendAddonMessage` is restricted to `"PARTY"`, `"RAID"`, `"GUILD"`, and `"BATTLEGROUND"`. Cross-guild channels **must** communicate over the custom channel itself.
- **Account-Wide Storage Boundary & Per-Toon Notes**:
  - `SavedVariables` in 1.12 are scoped per WoW login account (`WTF\Account\<ACCOUNT>\SavedVariables`).
  - **Account-wide Nickname**: The player has one nickname representing the human player behind the account (`XSocialConfig.nickname`).
  - **Per-Toon Notes**: Each character on the account can have a different spec/role (e.g. Priest is "Holy Healer", Warrior is "Prot Tank"). Notes are stored per toon in `XSocialConfig.notes = { [toonName] = note }`.

### 2.2 Chat Visibility & Dedicated Chat Window
- XSocial provides a dedicated chat window inside its Main Window to host the channel conversation with rich formatting (nicknames, clickable item links, etc.).
- **User-Managed ChatFrame Subscriptions**: XSocial does NOT forcibly alter or remove channels from the user's default `ChatFrame1`. Users who wish to keep their main chat box clean can manage their own ChatFrame channel subscriptions via standard game settings.

### 2.3 Eliminating Network & Message Storms
- **The "Who is Asked is Who Replies" Rule**: 
  - Login broadcast is limited to a single announcement.
  - Inquiries are directed individually (`#whois# <Toon>`).
  - **Only the queried player (`UnitName("player") == Toon`) responds.** All other clients remain silent.
  - Exactly 1 query produces at most 1 reply. Total traffic is 100% predictable and immune to storms.

### 2.4 Best-Effort `/who` Fallback Architecture
When querying a character that may not have XSocial installed, clicking `[?]` triggers a `/who` query with safety guards:
- **Server Rate Limiting**: Throttled to at most **one `/who` request every 5 seconds**.
- **Full Roster Scan**: Listens for `WHO_LIST_UPDATE` and loops `for i = 1, GetNumWhoResults() do` to find an exact case-insensitive match on the queried toon name.
- **Origin Guard**: Tracks `state.pending_who_target`. Ignores `WHO_LIST_UPDATE` events not initiated by XSocial.
- **Timeout & Failure State**: If no matching result arrives within 5 seconds, marks the query as complete and re-enables the `[?]` button.

---

## 3. Goals & Non-Goals

### Goals
- **G1. Unified Player Data Model**: Store character records in `XSocialDB.players[toonName]` under schema version 1.
- **G2. Zero-Storm Targeted Synchronization**:
  - Broadcast `#NICK#ZONE#NOTE#` upon channel join, nickname change, or note change.
  - Targeted `#whois# <Toon>` inquiries answered exclusively by `<Toon>`.
  - Protocol traffic is silently consumed and never displayed in the chat window.
- **G3. Streamlined HUD Button**:
  - Displays `<ChannelName> | <TotalCount>` (e.g. `maidou | 20`). Strictly shows total channel online count.
  - Left-Click: Toggles Main Window.
  - Right-Click: Toggles Main Window.
  - Repositioning via Config Lock/Unlock toggle.
- **G4. Dual-Pane Main Window (~620px × 360px)**:
  - Merged Top Bar: Channel `[⚙]`, Nickname `[⚙]`, Note `[⚙]`, HUD `[Lock]`, `[X]`.
  - Left Pane (Roster): Scrollable member list with Toon name (whisper link), Nickname, and `[?]` button.
  - Row Hover Tooltips: Toon name, Nickname, Level & Class, Location, Note.
  - Bottom Bar (Left): Total online count (`Online: %d`) and Search/Filter box.
  - Right Pane (Dedicated Chat): `ScrollingMessageFrame` replacing Toon names with clickable Nickname links (`|Hplayer:Toon|h[Nick]|h`), clickable item/quest/spell links, bottom channel chat input box and `[Send]` button.
- **G5. Diagnostics & Debug Mode**:
  - Slash command `/xsocial debug` to inspect protocol packets and channel state in real time.

### Non-Goals
- No forced removal of channels from `ChatFrame1` (user manages their own chat channels).
- No "known/total" ratio on the HUD button (strictly total online count).
- No circular Minimap button.
- No external binary dependencies or non-standard Lua.

---

## 4. User Scenarios

1. **First-Time Setup & Note Definition**:
   - Player opens Main Window, clicks `[⚙]` next to Nickname to enter `"杰斯"`.
   - Clicks `[⚙]` next to Note to enter `"MC Healer / Main"`. (Saved specifically for this toon in `XSocialConfig.notes`).
   - Clicks `[⚙]` next to Channel to enter `"maidou"`.
   - Addon joins `maidou` and announces `#杰斯# Ironforge #MC Healer / Main#`.
2. **Channel Presence & Passive Discovery**:
   - Player logs in; addon announces `#NICK#ZONE#NOTE#`.
   - Other XSocial clients capture sender's nickname, location, and note into `XSocialDB.players[sender]`.
   - The message is consumed silently by the addon and does not display as chat text.
3. **Dedicated In-Addon Chat & Hyperlinks**:
   - Player opens Main Window. Right pane displays messages from `#maidou`.
   - Sender appears as their Nickname: `|cffffd100[杰斯]|r: Anyone for Stratholme?`
   - Someone links an item: `|cffa335ee|Hitem:19019:0:0:0|h[Thunderfury]|h|r`. It displays in purple.
   - Player clicks `[Thunderfury]`; item tooltip opens immediately. Ctrl-click previews dressing room.
   - Player clicks `[杰斯]`; chat box opens `/w Jeyth `.
   - Player types in the bottom input box and hits Enter; message is sent straight to the channel and appears in the right pane.
4. **Inquiring Unknown Members via Dual-Track**:
   - Player clicks `[?]` next to `Alex`.
   - Addon sends `#whois# Alex` and queues `SendWho('n-"Alex"')`.
   - If Alex has XSocial: Alex's client replies with `#老王# Stormwind #Warrior Tank#`. Roster updates immediately.
   - If Alex lacks XSocial: `WHO_LIST_UPDATE` returns `Level 60 Warrior, Stormwind`. Alex's row updates with location and level, while nickname remains `-`.
5. **HUD Button Glance**:
   - HUD button displays `maidou | 20` (showing 20 members online in the channel).
   - Click toggles the Main Window.

---

## 5. Functional Requirements

### F1. Account-Wide Data Model & Schema

- **F1.1 Clean Schema (Version 1)**:
  ```lua
  XSocialConfig = {
      nickname     = "杰斯",                                    -- Account-wide nickname
      notes        = { ["Jeyth"] = "MC Healer / Main" },         -- Per-toon notes table
      channel      = "maidou",
      channelPwd   = "",
      pollInterval = 300,
      locked       = true,
      buttonPos    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 200, y = -100 },
      debug        = false,
  }

  XSocialDB = {
      version = 1,
      players = {
          ["Jeyth"] = {
              nick  = "杰斯",
              note  = "MC Healer / Main",
              zone  = "Ironforge",
              level = 60,
              class = "Priest",
          },
      },
  }
  ```

- **F1.2 Per-Toon Note Accessor**:
  - `XSocial.get_my_note()`: returns `XSocialConfig.notes[UnitName("player")] or ""`
  - `XSocial.set_my_note(val)`: sets `XSocialConfig.notes[UnitName("player")] = val`

- **F1.3 Input Validation & Sanitization**:
  - **Nickname**: 1 to 24 bytes. Reject `#` and `|`.
  - **Note**: 0 to 128 bytes (~42 Chinese characters). Reject `#` and `|`.
  - **Zone**: Sanitized from `GetZoneText()`, stripping any `#` or `|`.

---

### F2. Protocol Reference & Communication

#### Protocol Specification:

| Message Type | Format | Trigger | Response | Receiver Action |
| :--- | :--- | :--- | :--- | :--- |
| **Announcement** | `#<NICK># <ZONE> #<NOTE>#` | Channel join, Nick change, Note change | None | Updates `nick`, `zone`, `note` in `players[sender]`. Silently consumed. |
| **Inquiry** | `#whois# <Toon>` | Player clicks `[?]` | Target replies with Announcement if `UnitName("player") == Toon` | Silently consumed. |
| **Normal Chat** | Any regular text | Player types in chat input box | None | Formats sender with Nickname link and displays in right pane. |

- **F2.1 Outbound SendChatMessage**:
  ```lua
  local chan_idx = get_channel_index(target_channel)
  if chan_idx and chan_idx > 0 then
      SendChatMessage(payload, "CHANNEL", nil, chan_idx)
  end
  ```

- **F2.2 Inbound Message Handler**:
  - Triggered on `CHAT_MSG_CHANNEL` for `XSocialConfig.channel`:
    - **Announcement Pattern**: `string.find(msg, "^#([^#]+)#%s*([^#]*)%s*#([^#]*)#")`
      - Updates `XSocialDB.players[sender] = { nick = nick, zone = zone, note = note }`.
      - Does NOT print to chat window.
    - **Inquiry Pattern**: `string.find(msg, "^#whois#%s+([^%s]+)")`
      - If queried target is player, replies with own announcement immediately.
      - Does NOT print to chat window.
    - **Normal Chat**:
      - Replaces sender toon name with mapped Nickname.
      - Constructs clickable link: `|Hplayer:sender|h|cffffd100[display_nick]|r|h: message`.
      - Appends to right-pane `ScrollingMessageFrame`.

---

### F3. Targeted Inquire & `/who` Fallback Engine

- **F3.1 Dual Trigger**: Clicking `[?]` on `TargetToon`:
  1. Sends `#whois# <TargetToon>` to channel.
  2. If `/who` cooldown elapsed (>= 5 sec since last `/who`):
     - Sets `state.pending_who_target = TargetToon`.
     - Sets `state.last_who_time = time()`.
     - Sets `state.who_timeout = time() + 6` (watchdog timer in `OnUpdate` to reset `SetWhoToUI(0)` if server drops query).
     - Records `state.friends_was_open = (FriendsFrame and FriendsFrame:IsVisible())` to preserve player's manual UI state.
     - Calls `SetWhoToUI(1)` to route results to `WHO_LIST_UPDATE` instead of chat frame.
     - Calls `SendWho(TargetToon)`.
- **F3.2 Silent `/who` Suppression**:
  - `ShowUIPanel` is hooked: blocks `ShowUIPanel(FriendsFrame)` if `state.pending_who_target` is active and `state.friends_was_open` is false.
  - `FriendsFrame_OnEvent` and `WhoFrame_OnEvent` are hooked: cancels handling `WHO_LIST_UPDATE` when `state.pending_who_target` is active so Blizzard's UI does not trigger popup or list refresh.
  - Fail-safe cleanup in `WHO_LIST_UPDATE`, `CHAT_MSG_SYSTEM`, and watchdog timer hides `FriendsFrame` if it became visible and was not previously open.
- **F3.3 WHO_LIST_UPDATE Handler**:
  ```lua
  local num_results = GetNumWhoResults() or 0
  local updated = false
  for i = 1, num_results do
      local name, guild, level, race, class, zone = GetWhoInfo(i)
      if name and name ~= "" then
          if (state.pending_who_target and name == state.pending_who_target) or (state.roster and state.roster[name]) then
              local p = XSocial.get_or_create_player(name)
              if level and level > 0 then p.level = level end
              if class and class ~= "" then p.class = class end
              if zone and zone ~= "" then p.zone = zone end
              updated = true
          end
      end
  end
  if SetWhoToUI then SetWhoToUI(0) end
  if state.pending_who_target and FriendsFrame and not state.friends_was_open and FriendsFrame:IsVisible() then
      if HideUIPanel then HideUIPanel(FriendsFrame) else FriendsFrame:Hide() end
  end
  state.pending_who_target = nil
  state.who_timeout = nil
  state.friends_was_open = nil
  if updated then XSocial.refresh_ui() end
  ```
- **F3.4 CHAT_MSG_SYSTEM Fallback**:
  - Catches `/who` results if printed to chat (e.g. manual `/who` in chat or fallback).
  - Matches `|Hplayer:([^|]+)|h.-%s+%-%s+(.-)%s*$` to extract `who_name` and `who_zone` (and level if present).
  - Updates `p.zone` and triggers UI refresh.
- **F3.5 Live Tooltip Refresh**:
  - Hovering on `toon_btn`, `inquire_btn`, or `row_frame` shows the tooltip.
  - Location displays `p.zone` or `Unknown` (`未知`).
  - When `/who` succeeds, `XSocial.MainWindow.refresh_tooltip()` re-triggers `OnEnter` immediately if the mouse is hovering over that row.

---

### F4. Main Window (Dual-Pane Layout)

- **F4.1 Window Geometry & Visual Layout**:
  - Dimensions: ~620px width × 360px height (Resizable, min size: 450x300 in full mode, 260x200 in compact mode).
  - **Full Mode Wireframe**:
    ```
    +-------------------------------------------------------------------------------------------------+
    | maidou [⚙]   杰斯 [⚙]   MC Healer [⚙]                                             [C]  [X]      |  <- Row 1 (Top Bar)
    +------------------------------------------------+------------------------------------------------+
    | Online: 20   [ Search...    ]        [Refresh] | [ Type message in #maidou...                 ] |  <- Row 2 (Controls & Input)
    +------------------------------------------------+------------------------------------------------+
    |  Toon Name       Nickname                  [?] | [14:05] |cffffd100[老王]|r: Anyone for Strath? |  <- Row 3 (Panels)
    | ---------------------------------------------- | [14:06] |cffffd100[杰斯]|r: I can heal!        |
    |  Jeyth           杰斯                      [?] | [14:08] |cffffd100[大队长]|r: Count me in as tank|
    |  Alex            老王                      [?] | [14:10] |cffff8000[Thunderfury]|r linked!      |
    |  MageGuy         -                         [?] |                                                |
    |  WarTank         大队长                    [?] |                                                |
    |  HunterBob       -                         [?] |                                                |
    |  Roguelike       夜行者                    [?] |                                                |
    |  DruidCat        -                         [?] |                                                |
    |  ShamanTotem     萨满老张                  [?] |                                                |
    |  Palaboy         圣光阿强                  [?] |                                                |
    |  WarlockPet      -                         [?] |                                             ///|
    +------------------------------------------------+------------------------------------------------+
    ```
  - **Compact Mode Wireframe (`[C]` toggled)**:
    ```
    +-------------------------------------------------------------+
    |                                                    [C]  [X] |  <- Row 1
    +-------------------------------------------------------------+
    | [ Type message in #maidou...                              ] |  <- Row 2 (Full-width Input)
    +-------------------------------------------------------------+
    | [14:05] |cffffd100[老王]|r: Anyone for Stratholme?          |  <- Row 3 (Full-width Chat History)
    | [14:06] |cffffd100[杰斯]|r: I can heal!                     |
    | [14:08] |cffffd100[大队长]|r: Count me in as tank.           |
    | [14:10] |cffff8000[Thunderfury]|r linked!                   |
    |                                                          ///|
    +-------------------------------------------------------------+
    ```
- **F4.2 Merged Top Bar (Row 1)**:
  - Height: 24px.
  - Controls:
    - Channel name pill + `[⚙]`.
    - Nickname pill + `[⚙]`.
    - Note pill + `[⚙]` (displays current character's note).
    - `[C]` Compact Mode toggle button (left of `[X]`).
    - Close `[X]` button.
    - No redundant text labels (`Channel:`, `Nick:`, `Note:`).
- **F4.3 Row 2 — Controls & Chat Input**:
  - Left sub-bar (235px):
    - `Online: %d` count string.
    - Search / Filter `EditBox` (real-time filtering by Toon or Nickname).
    - `[Refresh]` button (triggers `/chatlist`).
  - Right sub-bar:
    - Chat Input `EditBox` spanning full remaining width. Send button deleted (press Enter to send).
- **F4.4 Row 3 — Dual Panels (Roster & Chat)**:
  - **Left Pane — Member Roster (235px fixed width)**:
    - Scrollable frame with recycled row pool (22px row height, ~10 visible rows).
    - Anchors from `TOPLEFT, 10, -56` to `BOTTOMLEFT, 10, 10`.
    - Columns:
      - **Toon Name**: Left-aligned (width: 105px). Clicking opens `/w <Toon> `.
      - **Nickname**: Gold text (`#FFD100`, width: 100px). Shows `-` if unmapped.
      - **[?] Inquire Button**: Compact 18x18px button, always visible.
    - **Row Hover Tooltip (`ANCHOR_RIGHT`)**:
      ```
      +-----------------------------------------+
      | Jeyth                                   |
      | Nickname: 杰斯                          |
      | Level / Class: 60 Priest                |
      | Location: Ironforge                     |
      | Note: MC Healer / Main                  |
      +-----------------------------------------+
      ```
  - **Right Pane — Dedicated Chat Window (`XSOCIAL_CHAT_WINDOW`)**:
    - Global frame name: `XSOCIAL_CHAT_WINDOW` (exposed globally for third-party addon hooking).
    - Full mode: Anchors from `TOPLEFT, 252, -58` to `BOTTOMRIGHT, -10, 10`.
    - Compact mode: Anchors from `TOPLEFT, 10, -58` to `BOTTOMRIGHT, -10, 10`.
    - Resizing dynamically expands/contracts only this pane.
    - Bottom-right corner has resize grabber handle `///`.
- **F4.5 Right Pane Features & Hyperlinks**:
  - `ScrollingMessageFrame` with mousewheel scrolling, 128 max lines, and auto-fade disabled (`SetFading(false)` so messages remain permanently visible).
  - **Full Hyperlink & Color Support (Item / Quest / Spell / Player / Invite)**:
    - Calls `msg_frame:SetHyperlinksEnabled(true)` to enable mouse interaction on links.
    - **Click-to-Invite (click2inv)**: Ultra-lightweight `O(1)` keyword matcher: messages longer than 12 bytes or containing hyperlinks are immediately bypassed. Short messages are trimmed and checked against an `O(1)` trigger lookup table (`1`, `111`, `123`, `inv`, `invite`, `求组`, `组我`, `组`) without expensive `string.gsub` calls. Matched messages are wrapped into clickable cyan hyperlinks `|cff00ffff|Hinvite:Sender|h[...]|h|r`. Clicking invites the player immediately (`InviteByName`). Hovering displays tooltip `Click to invite: <Sender>`.
    - **Preserving In-Message Links & Colors**: Prefix line with `[HH:MM] |Hplayer:Toon|h|cffffd100[Nick]|h|r: ` while leaving message body untouched. All Blizzard color codes (`|c...`) and item/quest hyperlinks render in authentic rarity colors.
    - **`OnHyperlinkClick` Handler**:
      - **Invite Links (`invite:Sender`)**:
        - Left-Click sends group invite via `InviteByName(sender)`.
        - Handled natively in XSocial with fallback support even if external chat addons are uninstalled.
      - **Player Links (`player:Toon`)**:
        - Formatted as `|cffffffff|Hplayer:Toon|h[Nick]|h|r`.
        - **Left-Click**: Invokes `ChatFrame_SendTell(Toon)` to open a whisper `/w <Toon> `.
        - **Shift-Click**: Automatically formats the player name as `|cffffffff|Hplayer:Toon|h[Toon]|h|r` and inserts it directly into the active editbox (`chat_edit_box`), then sets keyboard focus so the user can keep typing.
      - **Item Links (`item:ID:...`)**:
        - Formatted with authentic rarity color codes (`|cffxxxxxx|Hitem:...|h[Name]|h|r`).
        - **Left-Click**: Toggles static `ItemRefTooltip` window displaying detailed equipment attributes, stats, flavor text, and enchant data.
        - **Ctrl-Click**: Opens the Blizzard Dressing Room model viewer (`DressUpItemLink`) to preview the item on the player's 3D character.
        - **Shift-Click**: Inserts the colored item hyperlink (resolved via `GetItemInfo` fallback if necessary) into `chat_edit_box`.
      - **Quest Links (`quest:ID:Level`)**:
        - Formatted as `|cffffff00|Hquest:ID:Level|h[QuestTitle]|h|r`.
        - **Left-Click**: Displays quest detail tooltip or toggles QuestLog entry.
        - **Shift-Click**: Inserts the formatted quest hyperlink into `chat_edit_box`.
      - **Spell Links (`spell:ID` / `enchant:ID`)**:
        - Left-Click displays spell tooltip; Shift-Click inserts spell hyperlink into `chat_edit_box`.
    - **`OnHyperlinkEnter` & `OnHyperlinkLeave`**:
      - Hovering over an item, quest, or spell link displays `GameTooltip:SetHyperlink(arg1)` anchored to the cursor (`ANCHOR_CURSOR`).
      - Hovering over an invite link displays a custom tooltip: `Click to invite: <Sender>` (`点击邀请: <玩家>`).
  - **Bottom Chat Input & Universal Shift-Click Link Support**:
    - `EditBox` (`XSocialChatEditBox`) + Enter key to send messages directly to the active channel.
    - **Universal Shift-Click Proxying (`ChatFrameEditBox`)**:
      - In Vanilla WoW 1.12, Blizzard hardcodes `if ChatFrameEditBox:IsVisible() then ChatFrameEditBox:Insert(...)` across 11 different UI frames.
      - `XSocial` installs a transparent, non-invasive proxy on `ChatFrameEditBox.IsVisible` and `ChatFrameEditBox.Insert`.
      - **Routing Logic (`is_xsocial_editbox_target`)**:
        - If Blizzard's `ChatFrameEditBox` is actively open and has keyboard focus, Blizzard chat takes precedence and receives all links.
        - If `chat_edit_box` has focus, or if `chat_edit_box` is visible and Shift is held while Blizzard's editbox is closed: all Shift-click actions across the entire game (Bags `ContainerFrame`, PaperDoll `PaperDollFrame`, Bank, Loot window, Merchant vendors, Trade window, Crafting/TradeSkills, QuestLog, SpellBook, and Chat hyperlinks) transparently insert into `chat_edit_box` and acquire focus.
        - When XSocial is closed, the proxy completely passes through to native Blizzard behavior with zero side effects.

---

### F5. HUD Status Button
- **Visual Wireframe**:
  ```
  +--------------------+
  |  maidou | 20       |
  +--------------------+
  ```
- **Display**: `<ChannelName> | <TotalCount>` (e.g. `maidou | 20`). Strictly shows total channel count.
- **Left-Click**: Toggles Main Window visibility.
- **Right-Click and Drag**: Move the button to any position on the screen (position persisted in `XSocialConfig.buttonPos`).
- **New Message Flashing Alert**:
  - When a new chat message from another player arrives on the channel while the Main Window is closed
    - The HUD button flashes between **red** (`0.8, 0.1, 0.1, 0.85`) and **transparent** (`0.05, 0.05, 0.05, 0.2`) at a 0.5-second interval.
  - When the player opens the Main Window (e.g. by clicking the HUD button or via `/xsocial`), flashing automatically stops and the button returns to its normal resting appearance.

---

## 6. Technical Specifications (WoW 1.12 & Lua 5.0)

### 6.1 Lua 5.0 Compliance
- Strict ban on Lua 5.1+ features: No `#table`, no `string.match`, no `string.gmatch`.
- Use `table.getn(t)`, `string.find()`, `string.gfind()`.
- Use recycled row pool (`row_pool = {}`) to avoid garbage collection spikes.

### 6.2 Slash Commands & Debugging
- `/xsocial` — Toggle Main Window.
- `/xsocial debug` — Toggle debug logging in chat.
- `/xsocial refresh` — Force channel poll.
- `/xsocial test` — Send self-inquire `#whois# <PlayerName>` for round-trip verification.

---

## 7. Configuration & Storage Reference

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `XSocialConfig.nickname` | string | `""` | User's account-wide nickname (1–24 bytes) |
| `XSocialConfig.notes` | table | `{}` | Per-toon notes table `[toonName] = note` (0–128 bytes each) |
| `XSocialConfig.channel` | string | `"xsocial"` | Target custom chat channel name |
| `XSocialConfig.channelPwd` | string | `""` | Optional channel password |
| `XSocialConfig.pollInterval` | number | `300` | Background roster refresh interval (sec) |
| `XSocialConfig.locked` | boolean | `true` | Lock HUD button position |
| `XSocialConfig.buttonPos` | table | `{...}` | Saved screen coordinates of HUD button |
| `XSocialConfig.debug` | boolean | `false` | Enable verbose protocol debug messages |
| `XSocialDB.version` | number | `1` | Database schema version |
| `XSocialDB.players` | table | `{}` | Unified character store `[toonName] = { nick, note, zone, level, class }` |

---

## 8. Milestones

- **M1: Data Model & Per-Toon Notes**
  - Implement `XSocialDB.version = 1` with `players` table.
  - Implement `XSocialConfig.notes[toonName]` storage and UI accessors.
  - Update `localization.lua` with all new strings (EN + zhCN).
  - Add `/xsocial debug` and `/xsocial test` commands.
- **M2: Protocol Engine & Dual-Track Inquire**
  - Outbound `#NICK#ZONE#NOTE#` broadcast and `#whois#` reply logic.
  - Inbound parsing into `players[sender]`.
  - Dual-track inquire with 5-second `/who` rate limiter and exact-match `WHO_LIST_UPDATE` scanner.
- **M3: Top Bar Merging & Roster Pane**
  - Merged Top Bar: Channel `[⚙]`, Nick `[⚙]`, Note `[⚙]` (current toon), Lock, Close.
  - Recycled row pool with clickable Toon name, Nickname, and compact `[?]` button.
  - Rich `GameTooltip` with Toon, Nick, Level/Class, Location, Note (no last seen).
  - Bottom Bar (Left): `Online: %d`, real-time Search box, and `[Refresh]`.
- **M4: Right-Pane Dedicated Chat Window**
  - `ScrollingMessageFrame` with mousewheel scrolling, clickable nickname player links, and full item/quest/spell hyperlink support.
  - Bottom chat input box + `[Send]` button.
  - HUD button display: strictly `<Channel> | <TotalCount>`.
  - Integration testing and polish.
