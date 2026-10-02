# XSocial — Cross-Guild Channel Communication Addon PRD

Version: 0.6.0  |  Platform: Turtle WoW / Vanilla (Interface 11200)  |  Status: Draft Specification

---

## 1. Overview
XSocial is a lightweight Turtle WoW / Vanilla 1.12 addon designed for cross-guild friend circles, alts, and multi-account players communicating via a shared custom chat channel.

Vanilla WoW 1.12 provides no built-in channel join/leave notifications, and standard `SendAddonMessage` does not support custom chat channels (`"CHANNEL"` distribution was only introduced in later expansions). XSocial addresses these platform constraints with a **Decoupled Dual-Channel Architecture & Zero-Storm Base64 Protocol**:
- **Pure Human Chat Channel (`XSocialConfig.channel`, e.g. `xsocial`)**: Exclusively reserved for human conversation. Zero protocol messages are ever sent to this channel, completely eliminating chat pollution and the need for chat suppression hooks.
- **Dedicated Addon Message Channel (`TWB`)**: All presence announcements and inquiries are transmitted over the existing, clean addon channel `TWB`.
- **Eye-Unreadable Base64 Obfuscation (`XS1:<base64>`)**: All protocol packets on `TWB` are encoded with standard Base64 and namespaced with an `XS1:` prefix. Casual readers on the channel see only non-human-readable ASCII strings, and other addons ignore XSocial packets.
- **Targeted Discovery Protocol**: Announcements are broadcasted upon login, channel switch, or info updates (`ANN\t<NICK>\t<ZONE>\t<NOTE>`). Targeted inquiries (`INQ\t<Toon>`) are answered strictly by the queried player.
- **Best-Effort `/who` Fallback**: For players without XSocial, an optional fallback discovers their level, class, and zone.
- **Dedicated Chat Window**: Centralized inside XSocial's dedicated Chat Window on the right panel, featuring full hyperlink interactivity (items, quests, spells, and player whisper links).
- **Unified Data Model**: Nicknames are account-wide, while player notes are stored per-toon. All metadata is persisted in `SavedVariables` under `XSocialDB.version = 1`.

The user interface features:
1. A **minimalist floating HUD status button** displaying `<ChannelName> | <TotalCount>` (e.g. `maidou | 20`). Strictly shows total channel online count.
2. A **dual-pane Main Window (~500px wide × 360px high, min size 350x300)**:
   - **Merged Top Bar**: Channel `[⚙]`, Nickname `[⚙]`, Note `[⚙]`, HUD `[Lock]`, `[C]` Compact toggle, and `[X]`.
   - **Left Pane (Roster & Search, ~116px)**:
     - Compact scrollable roster with merged `TOONNAME<NICKNAME>` (gold nickname, click to whisper `/w <Toon> `) and compact `[?]` inquire button.
     - Rich hover tooltip showing Toon, Nickname, Level & Class, Location, and Note.
     - Top sub-bar: Compact online count badge `[count]` with tooltip, auto-fitting Search/Filter box, and `[R]` refresh button.
   - **Right Pane (Dedicated Channel Chat, dynamically expanded)**:
     - `ScrollingMessageFrame` showing pure channel conversation with full item/quest/spell/player hyperlink and color support.
     - 100% human chat: No protocol messages or filter tags ever enter this channel.
     - Real chat replaces Toon names with Nicknames as clickable player links (`|Hplayer:Toon|h[Nick]|h`) to allow easy whispering.
     - Bottom chat input box (and Enter key) to talk directly into the channel.

---

## 2. Background & Architecture Decisions

### 2.1 WoW 1.12 Platform Constraints & Dual-Channel Model
- **Custom Channel Limitations**: Custom channels do not emit presence events; roster discovery relies on `/chatlist` / `GetChannelRosterInfo`.
- **Addon Messaging Scope**: In WoW 1.12, `SendAddonMessage` is restricted to `"PARTY"`, `"RAID"`, `"GUILD"`, and `"BATTLEGROUND"`. It cannot broadcast across arbitrary channels or guilds.
- **Decoupled Dual-Channel Model**:
  - Previous designs mixed protocol messages (`#whois#`, `#NICK#ZONE#NOTE#`) directly into the user's chat channel (`xsocial`), requiring invasive hooks to hide protocol spam from the player's Blizzard chat frames.
  - Architecture v0.6.0 separates user chat from addon metadata:
    - **User Chat Channel (`XSocialConfig.channel`)**: 100% human chat.
    - **Addon Message Channel (`TWB`)**: Dedicated background channel for addon metadata synchronization.
- **Account-Wide Storage Boundary & Per-Toon Notes**:
  - `SavedVariables` in 1.12 are scoped per WoW login account (`WTF\Account\<ACCOUNT>\SavedVariables`).
  - **Account-wide Nickname**: The player has one nickname representing the human player behind the account (`XSocialConfig.nickname`).
  - **Per-Toon Notes**: Each character on the account can have a different spec/role (e.g. Priest is "Holy Healer", Warrior is "Prot Tank"). Notes are stored per toon in `XSocialConfig.notes = { [toonName] = note }`.

### 2.2 Eye-Unreadable Base64 Obfuscation on `TWB`
- `TWB` is an established, active channel for addon messaging in the community (much cleaner and quieter than `LFT`).
- To prevent raw text pollution and ensure messages are completely unreadable to the human eye on `TWB`, all XSocial packets are encoded in standard Base64:
  - Envelope: `XS1:<base64-string>` (e.g. `XS1:QU5OCeaWsOaJiAlJcm9uZm9yZ2UJTUMgSGVhbGVy`).
  - The `XS1:` prefix acts as an unambiguous namespace identifier:
    - Other addons and casual players on `TWB` ignore XSocial packets.
    - XSocial immediately drops any message on `TWB` that does not start with `XS1:`.
  - Base64 is lightweight and requires zero cryptographic key exchange, providing seamless out-of-the-box plug-and-play operation.

### 2.3 Elimination of Chat Suppression Hooks
- Because protocol messages are strictly sent to `TWB`, the user's `xsocial` channel never contains protocol noise.
- **Hook Removal**: The `ChatFrame_OnEvent` hook previously required to suppress `#whois#` and protocol lines from Blizzard's default chat frames is completely deleted.
- Non-addon players chatting in `xsocial` see pure conversation without protocol leaks.

### 2.4 Eliminating Network & Message Storms
- **The "Who is Asked is Who Replies" Rule**: 
  - Login broadcast is limited to a single announcement.
  - Inquiries are directed individually (`INQ\t<Toon>`).
  - **Only the queried player (`UnitName("player") == Toon`) responds.** All other clients remain silent.
  - Exactly 1 query produces at most 1 reply. Total traffic is 100% predictable and immune to storms.

### 2.5 Best-Effort `/who` Fallback Architecture
When querying a character that may not have XSocial installed, clicking `[?]` triggers a `/who` query with safety guards:
- **Server Rate Limiting**: Throttled to at most **one `/who` request every 5 seconds**.
- **Full Roster Scan**: Listens for `WHO_LIST_UPDATE` and loops `for i = 1, GetNumWhoResults() do` to find an exact case-insensitive match on the queried toon name.
- **Origin Guard**: Tracks `state.pending_who_target`. Ignores `WHO_LIST_UPDATE` events not initiated by XSocial.
- **Timeout & Failure State**: If no matching result arrives within 5 seconds, marks the query as complete and re-enables the `[?]` button.

---

## 3. Goals & Non-Goals

### Goals
- **G1. Unified Player Data Model**: Store character records in `XSocialDB.players[toonName]` under schema version 1.
- **G2. Zero-Storm Targeted Synchronization via `TWB`**:
  - Broadcast Base64-obfuscated announcements (`XS1:<base64>`) over dedicated addon channel `TWB` upon channel join, nickname change, or note change.
  - Targeted inquiries (`INQ\t<Toon>`) answered exclusively by `<Toon>` over `TWB`.
  - Protocol traffic is completely decoupled from the user's chat channel (`xsocial`), keeping user chat 100% pure.
- **G3. Hook-Free Clean Chat Experience**:
  - Eliminate all chat suppression hooks on `ChatFrame_OnEvent`.
  - Zero risk of protocol leakage to non-addon users or default Blizzard chat frames.
- **G4. Streamlined HUD Button**:
  - Displays `<ChannelName> | <TotalCount>` (e.g. `maidou | 20`). Strictly shows total channel online count.
  - Left-Click: Toggles Main Window.
  - Right-Click: Toggles Main Window.
  - Repositioning via Config Lock/Unlock toggle.
- **G5. Dual-Pane Main Window (~500px × 360px, min 350x300)**:
  - Merged Top Bar: Channel `[⚙]`, Nickname `[⚙]`, Note `[⚙]`, HUD `[Lock]`, `[C]`, `[X]`.
  - Left Pane (Roster, ~116px): Compact scrollable roster with merged `TOONNAME<NICKNAME>` (whisper link, gold nickname) and compact `[?]` button.
  - Left Sub-Bar: Compact online badge `[count]` with tooltip, auto-fitting Search/Filter box, and `[R]` refresh button.
  - Row Hover Tooltips: Toon name, Nickname, Level & Class, Location, Note.
  - Right Pane (Dedicated Chat): `ScrollingMessageFrame` replacing Toon names with clickable Nickname links (`|Hplayer:Toon|h[Nick]|h`), clickable item/quest/spell links, bottom channel chat input box (Enter key to send).
- **G6. Diagnostics & Debug Mode**:
  - Slash command `/xsocial debug` to inspect protocol packets and channel state in real time.

### Non-Goals
- No forced removal of channels from `ChatFrame1` (user manages their own chat channels).
- No cryptographic encryption keys (Base64 is strictly for eye-unreadable obfuscation without key exchange overhead).
- No "known/total" ratio on the HUD button (strictly total online count).
- No circular Minimap button.
- No external binary dependencies or non-standard Lua.

---

## 4. User Scenarios

1. **First-Time Setup & Note Definition**:
   - Player opens Main Window, clicks `[⚙]` next to Nickname to enter `"杰斯"`.
   - Clicks `[⚙]` next to Note to enter `"MC Healer / Main"`. (Saved specifically for this toon in `XSocialConfig.notes`).
   - Clicks `[⚙]` next to Channel to enter `"maidou"`.
   - Addon joins `maidou` for chat, joins `TWB` for addon sync, and broadcasts Base64 presence over `TWB`.
2. **Channel Presence & Passive Discovery**:
   - Player logs in; addon announces presence on `TWB` as `XS1:<base64(ANN\t杰斯\tIronforge\tMC Healer / Main)>`.
   - Other XSocial clients listening on `TWB` decode the packet and capture sender's nickname, location, and note into `XSocialDB.players[sender]`.
   - Zero traffic appears in the `maidou` chat channel.
3. **Dedicated In-Addon Chat & Hyperlinks**:
   - Player opens Main Window. Right pane displays messages from `#maidou`.
   - Sender appears as their Nickname: `|cffffd100[杰斯]|r: Anyone for Stratholme?`
   - Someone links an item: `|cffa335ee|Hitem:19019:0:0:0|h[Thunderfury]|h|r`. It displays in purple.
   - Player clicks `[Thunderfury]`; item tooltip opens immediately. Ctrl-click previews dressing room.
   - Player clicks `[杰斯]`; chat box opens `/w Jeyth `.
   - Player types in the bottom input box and hits Enter; message is sent straight to the `#maidou` channel and appears in the right pane.
4. **Inquiring Unknown Members via Dual-Track**:
   - Player clicks `[?]` next to `Alex` in the merged roster row `Alex<- >`.
   - Addon sends `XS1:<base64(INQ\tAlex)>` over `TWB` and queues `SendWho('n-"Alex"')`.
   - If Alex has XSocial: Alex's client replies over `TWB` with `XS1:<base64(ANN\t老王\tStormwind\tWarrior Tank)>`. Alex's row updates to `Alex<老王>` immediately.
   - If Alex lacks XSocial: `WHO_LIST_UPDATE` returns `Level 60 Warrior, Stormwind`. Alex's row tooltip updates with location and level, while nickname remains `-`.
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
      channel      = "maidou",                                   -- User chat channel
      addonChannel = "TWB",                                      -- Dedicated background addon channel
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
  - **Nickname**: 1 to 24 bytes. Reject `\t`, `|`, and control characters.
  - **Note**: 0 to 128 bytes (~42 Chinese characters). Reject `\t` and `|`.
  - **Zone**: Sanitized from `GetZoneText()`, stripping control characters.

---

### F2. Protocol Reference & Dual-Channel Communication

#### Protocol Specification:

| Message Type | Channel | Envelope Format | Raw Payload | Trigger | Response |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Announcement** | `TWB` | `XS1:<base64>` | `ANN\t<NICK>\t<ZONE>\t<NOTE>` | Login, Nick change, Note change, or reply to Inquire | None |
| **Inquiry** | `TWB` | `XS1:<base64>` | `INQ\t<Toon>` | Player clicks `[?]` | Target replies with Announcement if `UnitName("player") == Toon` |
| **User Chat** | `xsocial` | Plain text | Normal chat text | Player types in chat input box | None (appended to dedicated chat pane) |

- **F2.1 Base64 Obfuscation Engine**:
  - Encodes payloads into standard RFC 4648 Base64 characters (`A-Z, a-z, 0-9, +, /, =`).
  - Ensures packets are non-human-readable to casual observers on `TWB`.
  - Max raw payload length is ~150 bytes, expanding to ~200 bytes Base64 (well below WoW's 255-byte chat limit).

- **F2.2 Outbound Protocol Transport (`TWB`)**:
  - All protocol messages (`ANN`, `INQ`) are transmitted over the `TWB` channel index:
    ```lua
    local chan_idx = get_channel_index("TWB")
    if chan_idx and chan_idx > 0 then
        local packet = "XS1:" .. base64_encode(payload)
        SendChatMessage(packet, "CHANNEL", nil, chan_idx)
    end
    ```
  - User conversation is sent directly to `XSocialConfig.channel` without any envelope or encoding.

- **F2.3 Inbound Message Routing**:
  - **On `TWB` Channel**:
    - Ignores messages not starting with `^XS1:(.+)`.
    - Base64 decodes the payload string.
    - If payload starts with `ANN\t<nick>\t<zone>\t<note>`:
      - Updates `XSocialDB.players[sender] = { nick = nick, zone = zone, note = note }`.
      - Triggers UI refresh.
    - If payload starts with `INQ\t<toon>`:
      - If `UnitName("player") == toon`, immediately responds with own `ANN` announcement over `TWB`.
    - Never prints anything to any chat window.
  - **On User Chat Channel (`xsocial`)**:
    - 100% human chat.
    - Formats keywords (`1`, `inv`, `求组`) into clickable party invite links.
    - Formats sender as clickable Nickname link `|Hplayer:sender|h|cffffd100[display_nick]|r|h: message`.
    - Appends line to dedicated chat pane.
    - Triggers HUD button unread flashing if window is closed.

- **F2.4 Elimination of Chat Suppression Hooks**:
  - Because protocol packets are never sent to `xsocial`, `ChatFrame_OnEvent` suppression hooks for `#whois#` are completely removed.
  - Clean, zero-interference operation alongside Blizzard default chat frames.

---

### F3. Targeted Inquire & `/who` Fallback Engine

- **F3.1 Dual Trigger**: Clicking `[?]` on `TargetToon`:
  1. Sends `XS1:<base64(INQ\tTargetToon)>` over `TWB`.
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
    - Close `[X]` button (also closes on Escape key via `UISpecialFrames`).
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
