# XSocial

**A private social & chat hub for friends and alts across guilds in Vanilla WoW 1.12.1 / Turtle WoW**  
**魔兽世界 1.12.1 / 乌龟服 跨公会私密好友圈与频道聊天插件**

---

[English](#english) | [中文说明](#chinese)

---

<a name="english"></a>
## English

### What is XSocial?
**XSocial** turns any custom in-game chat channel (e.g. `/join xsocial` or a private channel with your friends) into a full-featured social hub. 

If you play with friends across different guilds, have multiple alts, or want a clean private chat room, XSocial lets you easily chat, track who is online, see everyone's real nickname and notes, and invite party members with a single click.

---

### Key Features

#### 💬 Dedicated Private Chat Window
- **Clean Chat**: Chat with your channel friends in a dedicated side-by-side window without cluttering your main game chat.
- **Friendly Nicknames**: Chat messages display your friends' real account nicknames instead of unfamiliar alt character names.
- **Interactive Links**: Full support for clickable items, quests, spells, and player whisper links (with hover tooltips and dressing room previews).

#### ⚡ 1-Click Group Invite
- When someone sends messages like **`1`**, **`111`**, **`inv`**, **`invite`**, or **`求组`**, XSocial turns the message into a clickable link.
- Simply click their message to invite them to your party immediately.

#### 🔗 Send Item & Quest Links (Shift + Click)
- When typing in the XSocial chat box, **Shift + Click** anything in the game to insert its link directly into your message:
  - Items in your bags, bank, merchant, or loot window
  - Equipped weapons and armor from your character sheet
  - Quests from your quest log
  - Player names or items from other chat messages

#### 👥 Online Member Roster & Rich Info
- **Who's Online**: See everyone currently active in your channel at a glance.
- **Quick Search**: Filter the roster instantly by typing in the search box.
- **Hover Tooltips**: Hover over any player to see:
  - Account Nickname
  - Level and Class
  - Current Zone
  - Personal Note (e.g., "Holy Priest / Alchemist")
- **1-Click Whisper**: Click any character name to start whispering them.
- **`[?]` Button**: Query and refresh information for players you haven't met yet.

#### 🖥️ Floating Status Pill (HUD Button)
- A compact on-screen button showing your current channel and online count (e.g. `xsocial | 12`).
- **Left-Click**: Open or close the XSocial window.
- **Right-Click & Drag**: Move the button anywhere on your screen.
- **Unread Alert**: Gently flashes red when a new message arrives while your window is closed.

#### 🗜️ Compact Chat Mode
- Click the **`[C]`** button at the top right to hide the roster and collapse XSocial into a sleek, compact chat window.

---

### How to Use

| Action | What it does |
|---|---|
| `/xsocial` | Open / close the XSocial window |
| **Click HUD Button** | Open / close the XSocial window |
| **Right-Click & Drag HUD Button** | Move the HUD button |
| **Top Bar `[⚙]` Buttons** | Change your channel name, account nickname, or toon note |
| **`[C]` Button** | Switch between full window and compact chat-only mode |
| **`[X]` Button** | Close the window |
| **Type & Press Enter** | Send a message to your channel |

---

### Installation

1. Download or clone this folder.
2. Make sure the folder is named **`XSocial`**.
3. Place it into your game's addon folder:
   ```
   World of Warcraft\Interface\AddOns\XSocial\
   ```
4. Start the game or type `/reload` in chat.

---

<a name="chinese"></a>
## 中文说明

### 什么是 XSocial？
**XSocial** 能将游戏内任意自定义频道（例如与亲友加入的 `/join 频道名`）打造成一个功能完善的专属私密社交中心。

无论你是与分散在不同公会的朋友一同游戏、拥有众多小号，还是想拥有一个清爽私密的专属聊天室，XSocial 都能让你轻松畅聊、随时查看在线好友、显示每个人真实的账号昵称与角色备注，并支持一键点击组队。

---

### 核心功能

#### 💬 独立专属聊天窗口
- **清爽不刷屏**：拥有独立的聊天面板，频道亲友聊天不再与游戏原生主聊天框（交易、综合、拾取）挤在一起。
- **显示真实昵称**：自动将各种小号角色名显示为好友真正的统一昵称，再也不用猜“这是谁的小号”。
- **完整超链接交互**：完美支持物品、任务、法术超链接的鼠标悬浮提示与试衣间（Ctrl+点击）预览。

#### ⚡ 一键点击组队邀请 (Click-to-Invite)
- 当频道中有朋友发送 **`1`**、**`111`**、**`123`**、**`inv`**、**`求组`**、**`组我`** 等常用组队暗号时，消息会自动变为可点击链接。
- 直接鼠标轻点消息，即可瞬间向对方发起组队邀请。

#### 🔗 快捷发送链接 (Shift + 左键点击)
- 在 XSocial 聊天输入框输入时，按住 **Shift + 左键点击** 游戏内任意目标，即可将超链接自动填入输入框：
  - 背包、银行、商人售卖、拾取窗口中的物品
  - 角色装备面板上已穿戴的装备
  - 任务日志里的任务标题
  - 聊天框里的物品或玩家名字

#### 👥 实时在线成员列表与详细名片
- **成员一目了然**：左侧面板实时显示当前频道中所有在线的成员。
- **快速筛选**：在底部搜索框输入文字，即时过滤出想找的成员。
- **鼠标悬浮名片**：悬浮在成员身上即可查看详细信息：
  - 统一账号昵称
  - 等级与职业
  - 当前所在地图区域
  - 角色专属个性备注（如：“神牧 / 炼金制皮”）
- **点击私聊**：单击角色名字即可立刻打开私聊窗口（`/w 角色名 `）。
- **`[?]` 询问按钮**：点击即可主动更新未知成员的昵称与资料。

#### 🖥️ 极简桌面悬浮状态条 (HUD)
- 屏幕上小巧美观的胶囊型状态条，实时显示 `频道名称 | 在线人数`（例如 `xsocial | 12`）。
- **左键单击**：一键打开或关闭 XSocial 主界面。
- **右键拖拽**：随心所欲将状态条摆放在屏幕任何位置（跨角色永久保存）。
- **新消息闪烁提醒**：当主窗口处于关闭状态且有新聊天到达时，状态条边缘会自动红光闪烁提醒。

#### 🗜️ 极简纯聊天模式
- 点击窗口右上角的 **`[C]`** 按钮，一键收起左侧成员名册，窗口立刻缩进为简洁的纯聊天窗口，不遮挡游戏视野。

---

### 操作指南

| 操作 | 功能说明 |
|---|---|
| `/xsocial` | 打开或关闭主界面 |
| **单击 HUD 悬浮条** | 打开或关闭主界面 |
| **右键拖动 HUD 悬浮条** | 调整悬浮条在屏幕上的摆放位置 |
| **顶部栏齿轮 `[⚙]`** | 修改当前频道、账号昵称、当前角色备注 |
| **`[C]` 极简按钮** | 在完整双面板模式与极简纯聊天模式之间切换 |
| **`[X]` 关闭按钮** | 关闭主界面 |
| **输入框打字并回车** | 快速向频道发送消息 |

---

### 安装方法

1. 下载或解压本插件文件夹。
2. 确保文件夹名称为 **`XSocial`**（不要带 `-main` 或版本号后缀）。
3. 放入魔兽世界的插件目录：
   ```
   World of Warcraft\Interface\AddOns\XSocial\
   ```
4. 进入游戏，或在游戏聊天框输入 `/reload` 重载界面即可使用。
