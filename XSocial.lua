-- XSocial.lua
-- Core addon logic: data model, events, dynamic channel resolution, zero-storm sync, targeted inquire
-- Strictly Lua 5.0, Vanilla WoW 1.12 API only

local XSocial = XSocial or {}
local L = XSocial.L

-- ============================================================
-- SavedVariables (Account-wide, declared in .toc)
-- ============================================================
XSocialConfig = XSocialConfig or {}
XSocialDB = XSocialDB or {}

-- ============================================================
-- Default configuration
-- ============================================================
local default_config = {
    nickname     = "",
    notes        = {},
    channel      = "xsocial",
    pollInterval = 300,
    locked       = true,
    buttonPos    = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    debug        = false,
    windowWidth   = 620,
    windowHeight  = 360,
    compactWidth  = 378,
    compactHeight = 360,
    isCompact     = false,
}

-- ============================================================
-- Internal state (runtime only, not persisted)
-- ============================================================
local state = {
    roster             = {},
    roster_count       = 0,
    last_poll          = 0,
    last_announce_time = 0,
    last_who_time      = 0,
    pending_who_target = nil,
    channel_joined     = false,
    poll_timer         = 0,
    initialized        = false,
}

-- ============================================================
-- Event frame for event dispatch
-- ============================================================
local event_frame = CreateFrame("Frame", "XSocialEventFrame", UIParent)
event_frame:RegisterEvent("PLAYER_LOGIN")
event_frame:RegisterEvent("CHAT_MSG_CHANNEL")
event_frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
event_frame:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
event_frame:RegisterEvent("WHO_LIST_UPDATE")
event_frame:RegisterEvent("CHAT_MSG_SYSTEM")

-- ============================================================
-- Forward declarations
-- ============================================================
local init_config = nil
local is_channel_match = nil
local get_channel_index = nil
local join_channel = nil
local leave_channel = nil
local on_channel_joined = nil
local on_channel_left = nil
local send_announcement = nil
local inquire_toon = nil
local handle_channel_msg = nil
local handle_channel_notice = nil
local handle_channel_list = nil
local handle_system_msg = nil
local validate_nickname = nil
local validate_note = nil
local validate_channel = nil
local poll_via_api = nil
local poll_via_chatlist = nil
local update_roster_db = nil
local get_known_count = nil
local get_total_count = nil
local setup_hooks = nil

-- Export declarations on XSocial namespace (nil first per project conventions)
XSocial.init = nil
XSocial.join_channel = nil
XSocial.leave_channel = nil
XSocial.set_channel = nil
XSocial.get_channel = nil
XSocial.set_nickname = nil
XSocial.get_nickname = nil
XSocial.get_my_note = nil
XSocial.set_my_note = nil
XSocial.get_player = nil
XSocial.get_or_create_player = nil
XSocial.get_players = nil
XSocial.validate_nickname = nil
XSocial.validate_note = nil
XSocial.validate_channel = nil
XSocial.open_channel_chat = nil
XSocial.inquire_toon = nil
XSocial.send_announcement = nil
XSocial.do_poll = nil
XSocial.request_refresh = nil
XSocial.get_known_count = nil
XSocial.get_total_count = nil
XSocial.get_online_count = nil
XSocial.get_roster = nil
XSocial.get_nickname_map = nil
XSocial.save_config = nil
XSocial.get_config = nil
XSocial.format_time = nil
XSocial.print_msg = nil
XSocial.refresh_ui = nil

-- ============================================================
-- Local helper implementations
-- ============================================================

init_config = function()
    local config_key, config_val
    for config_key, config_val in pairs(default_config) do
        if XSocialConfig[config_key] == nil then
            if type(config_val) == "table" then
                XSocialConfig[config_key] = {}
                local sub_k, sub_v
                for sub_k, sub_v in pairs(config_val) do
                    XSocialConfig[config_key][sub_k] = sub_v
                end
            else
                XSocialConfig[config_key] = config_val
            end
        end
    end

    if not XSocialDB.version then XSocialDB.version = 1 end
    if not XSocialDB.players then XSocialDB.players = {} end
    if not XSocialDB.roster then XSocialDB.roster = {} end
    if not XSocialDB.lastPoll then XSocialDB.lastPoll = 0 end
    if not XSocialConfig.notes then XSocialConfig.notes = {} end
    if type(XSocialConfig.buttonPos) ~= "table" or not XSocialConfig.buttonPos.point then
        XSocialConfig.buttonPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    end
end

is_channel_match = function(chan_str, target_name)
    if not target_name or target_name == "" then return false end
    if not chan_str or chan_str == "" then return false end

    local clean_target = target_name
    local _, _, target_stripped = string.find(clean_target, "^%d+%.%s*(.+)")
    if target_stripped then clean_target = target_stripped end
    local _, _, target_trimmed = string.find(clean_target, "^%s*(.-)%s*$")
    if target_trimmed then clean_target = target_trimmed end

    local clean_chan = chan_str
    local _, _, chan_stripped = string.find(clean_chan, "^%d+%.%s*(.+)")
    if chan_stripped then clean_chan = chan_stripped end
    local _, _, chan_trimmed = string.find(clean_chan, "^%s*(.-)%s*$")
    if chan_trimmed then clean_chan = chan_trimmed end

    if clean_chan == clean_target then
        return true
    end

    return false
end

get_channel_index = function(channel_name)
    if not channel_name or channel_name == "" then return nil end

    -- Primary: Check GetChannelList() which in 1.12 returns id1, name1, id2, name2, ...
    if GetChannelList then
        local chan_list = { GetChannelList() }
        local total_n = table.getn(chan_list)
        local i
        for i = 1, total_n, 2 do
            local id = chan_list[i]
            local name = chan_list[i + 1]
            if id and name and is_channel_match(name, channel_name) then
                return id
            end
        end
    end

    -- Secondary: Scan channel slots 1 to 10 using GetChannelName(slot)
    if GetChannelName then
        local slot
        for slot = 1, 10 do
            local name_found = GetChannelName(slot)
            if name_found and is_channel_match(name_found, channel_name) then
                return slot
            end
        end
    end

    return nil
end

join_channel = function(channel_name)
    if not channel_name or channel_name == "" then return end
    state.channel_joined = false
    JoinChannelByName(channel_name)
end

leave_channel = function(channel_name)
    if not channel_name or channel_name == "" then return end
    LeaveChannelByName(channel_name)
    state.channel_joined = false
end

on_channel_joined = function(channel_name)
    state.channel_joined = true
    local my_name = UnitName("player")
    if my_name and my_name ~= "" then
        state.roster[my_name] = true
        state.roster_count = 1
        local p = XSocial.get_or_create_player(my_name)
        if XSocialConfig.nickname and XSocialConfig.nickname ~= "" then
            p.nick = XSocialConfig.nickname
        end
        local my_note = XSocial.get_my_note()
        if my_note and my_note ~= "" then
            p.note = my_note
        end
        local my_zone = GetZoneText()
        if my_zone and my_zone ~= "" then
            p.zone = my_zone
        end
    end
    XSocial.print_msg(string.format(L["Joined channel '%s'."], channel_name))
    send_announcement(false)
    XSocial.do_poll()
end

on_channel_left = function(channel_name)
    state.channel_joined = false
    state.roster = {}
    state.roster_count = 0
    XSocial.print_msg(string.format(L["Left channel '%s'."], channel_name))
    XSocial.refresh_ui()
end

send_announcement = function(force)
    local nick_text = XSocialConfig.nickname
    if not nick_text or nick_text == "" then return false end

    local current_time = time()
    if not force and (current_time - state.last_announce_time < 30) then
        return false
    end

    local target_channel = XSocialConfig.channel or "xsocial"
    local chan_idx = get_channel_index(target_channel)
    if chan_idx and chan_idx > 0 then
        state.last_announce_time = current_time
        local my_zone = GetZoneText() or ""
        my_zone = string.gsub(my_zone, "[#|]", "")
        local my_note = XSocial.get_my_note() or ""
        my_note = string.gsub(my_note, "[#|]", "")
        local out_msg = string.format("#%s# %s #%s#", nick_text, my_zone, my_note)
        SendChatMessage(out_msg, "CHANNEL", nil, chan_idx)
        return true
    end
    return false
end

inquire_toon = function(target_toon)
    if not target_toon or target_toon == "" then return false end
    local target_channel = XSocialConfig.channel or "xsocial"
    local chan_idx = get_channel_index(target_channel)
    if chan_idx and chan_idx > 0 then
        local out_msg = string.format("#whois# %s", target_toon)
        SendChatMessage(out_msg, "CHANNEL", nil, chan_idx)
    end

    -- Dual-track: trigger SendWho if 5-sec cooldown elapsed
    local current_time = time()
    if not state.last_who_time or (current_time - state.last_who_time >= 5) then
        state.last_who_time = current_time
        state.pending_who_target = target_toon
        state.who_timeout = current_time + 6
        state.friends_was_open = (FriendsFrame and FriendsFrame:IsVisible())
        if SetWhoToUI then
            SetWhoToUI(1)
        elseif SetWhoToUi then
            SetWhoToUi(1)
        end
        if SendWho then
            SendWho(target_toon)
        end
    end

    return true
end

validate_nickname = function(nick)
    if not nick or nick == "" then
        return false, L["Nickname cannot be empty."]
    end
    local byte_len = string.len(nick)
    if byte_len < 1 or byte_len > 24 then
        return false, L["Nickname must be 1-24 bytes."]
    end
    if string.find(nick, "#") or string.find(nick, "|") then
        return false, L["Nickname cannot contain '#' or '|'."]
    end
    return true
end

validate_note = function(note_val)
    if not note_val or note_val == "" then
        return true
    end
    local byte_len = string.len(note_val)
    if byte_len > 128 then
        return false, L["Note must be 0-128 bytes."]
    end
    if string.find(note_val, "#") or string.find(note_val, "|") then
        return false, L["Note cannot contain '#' or '|'."]
    end
    return true
end

validate_channel = function(chan)
    if not chan or chan == "" then
        return false, L["Channel name cannot be empty."]
    end
    if string.find(chan, "%s") or string.find(chan, "#") or string.find(chan, "|") then
        return false, L["Channel name contains invalid characters."]
    end
    return true
end

update_roster_db = function()
    XSocialDB.roster = {}
    local char_name
    for char_name in pairs(state.roster) do
        table.insert(XSocialDB.roster, char_name)
    end
    XSocialDB.lastPoll = state.last_poll
end

poll_via_api = function()
    local target_channel = XSocialConfig.channel or "xsocial"
    local chan_idx = get_channel_index(target_channel)
    if not chan_idx or chan_idx < 1 then return false end
    if not GetChannelRosterInfo then return false end

    local member_idx = 1
    local call_ok, member_info, char_name
    local new_roster = {}
    local member_count = 0

    while true do
        call_ok, member_info = pcall(GetChannelRosterInfo, chan_idx, member_idx)
        if not call_ok or not member_info then break end
        char_name = nil
        if type(member_info) == "string" then
            char_name = member_info
        elseif type(member_info) == "table" then
            char_name = member_info.name or member_info[1]
        end
        if char_name and char_name ~= "" then
            new_roster[char_name] = true
            member_count = member_count + 1
        end
        member_idx = member_idx + 1
    end

    if member_count > 0 then
        state.roster = new_roster
        state.roster_count = member_count
        update_roster_db()
        return true
    end
    return false
end

poll_via_chatlist = function()
    local target_channel = XSocialConfig.channel or "xsocial"
    local chan_idx = get_channel_index(target_channel)
    if not chan_idx or chan_idx < 1 then return false end

    if ListChannelByName then
        ListChannelByName(target_channel)
    end
    return true
end

get_known_count = function()
    local count = 0
    local char_name
    for char_name in pairs(state.roster) do
        local p = XSocialDB.players and XSocialDB.players[char_name]
        if p and p.nick and p.nick ~= "" then
            count = count + 1
        end
    end
    return count
end

get_total_count = function()
    return state.roster_count
end

-- ============================================================
-- Click-to-Invite Keyword Link Converter (Lightweight O(1) matching)
-- Fast-paths: skips messages > 12 bytes; checks exact triggers via lookup table
-- ============================================================
local INVITE_KEYWORDS = {
    ["1"] = true,
    ["111"] = true,
    ["123"] = true,
    ["inv"] = true,
    ["invite"] = true,
    ["求组"] = true,
    ["组我"] = true,
    ["组"] = true,
}

local function convert_keywords_to_links(msg, sender)
    if not msg or not sender or sender == "" then return msg end

    -- Fast-path: skip messages longer than 12 bytes or containing hyperlinks
    if string.len(msg) > 12 or string.find(msg, "|H") then
        return msg
    end

    -- Trim leading and trailing whitespace
    local _, _, clean = string.find(msg, "^%s*(.-)%s*$")
    if clean and clean ~= "" then
        local keyword = string.lower(clean)
        if keyword and INVITE_KEYWORDS[keyword] then
            return "|cff00ffff|Hinvite:" .. sender .. "|h[" .. clean .. "]|h|r"
        end
    end

    return msg
end
XSocial.convert_keywords_to_links = convert_keywords_to_links

handle_channel_msg = function(msg_text, sender_name, chan_arg4, chan_arg8, chan_arg9)
    if not msg_text then return end
    local target_channel = XSocialConfig.channel or "xsocial"

    local is_match = false
    if chan_arg9 and is_channel_match(chan_arg9, target_channel) then
        is_match = true
    elseif chan_arg4 and is_channel_match(chan_arg4, target_channel) then
        is_match = true
    end

    if not is_match then return end

    -- Anyone speaking in this channel is active in the roster
    if sender_name and sender_name ~= "" and not state.roster[sender_name] then
        state.roster[sender_name] = true
        local count = 0
        local k
        for k in pairs(state.roster) do count = count + 1 end
        state.roster_count = count
        update_roster_db()
        XSocial.refresh_ui()
    end

    -- Pattern 1: #NICK# <ZONE> #<NOTE># (announcement or answer to whois)
    local _, _, nick_cap, zone_cap, note_cap = string.find(msg_text, "^#([^#]+)#%s*([^#]*)%s*#([^#]*)#")
    if nick_cap and nick_cap ~= "" and sender_name and sender_name ~= "" then
        local p = XSocial.get_or_create_player(sender_name)
        p.nick = nick_cap
        local _, _, zone_trim = string.find(zone_cap or "", "^%s*(.-)%s*$")
        if zone_trim and zone_trim ~= "" then p.zone = zone_trim end
        local _, _, note_trim = string.find(note_cap or "", "^%s*(.-)%s*$")
        if note_trim and note_trim ~= "" then p.note = note_trim end
        XSocial.refresh_ui()
        return
    end

    -- Legacy Pattern: #NICKNAME# online
    local _, _, nick_captured = string.find(msg_text, "^#([^#]+)#%s*[Oo][Nn][Ll][Ii][Nn][Ee]")
    if nick_captured and nick_captured ~= "" and sender_name and sender_name ~= "" then
        local p = XSocial.get_or_create_player(sender_name)
        p.nick = nick_captured
        XSocial.refresh_ui()
        return
    end

    -- Pattern 2: #whois# <Toon> (targeted inquire)
    -- Rule: Who is asked is who replies
    local _, _, query_toon = string.find(msg_text, "^#whois#%s+([^%s]+)")
    if query_toon and sender_name then
        local player_name = UnitName("player")
        if player_name and query_toon == player_name then
            -- I am the queried toon! Reply with my own announcement
            if XSocialConfig.nickname and XSocialConfig.nickname ~= "" then
                send_announcement(true) -- bypass 30s throttle
            end
        end
        return
    end

    -- Pattern 3: Normal Chat message from player!
    local display_text = msg_text
    local my_name = UnitName("player")
    if sender_name and sender_name ~= my_name then
        display_text = convert_keywords_to_links(msg_text, sender_name)
    end

    if XSocial.MainWindow and XSocial.MainWindow.append_chat_message then
        XSocial.MainWindow.append_chat_message(sender_name, display_text)
    end
    if sender_name and sender_name ~= my_name then
        if XSocial.MainWindow and not XSocial.MainWindow.is_visible() then
            if XSocial.HUDButton and XSocial.HUDButton.start_flash then
                XSocial.HUDButton.start_flash()
            end
        end
    end
end

handle_channel_notice = function(notice_type, player_name, chan_arg4, chan_arg8, chan_arg9)
    local target_channel = XSocialConfig.channel or "xsocial"

    local is_match = false
    if chan_arg9 and is_channel_match(chan_arg9, target_channel) then
        is_match = true
    elseif chan_arg4 and is_channel_match(chan_arg4, target_channel) then
        is_match = true
    elseif chan_arg8 then
        local chan_name_from_id = GetChannelName(chan_arg8)
        if chan_name_from_id and is_channel_match(chan_name_from_id, target_channel) then
            is_match = true
        end
    end

    if not is_match then return end

    if notice_type == "YOU_JOINED" then
        on_channel_joined(target_channel)
    elseif notice_type == "YOU_LEFT" then
        on_channel_left(target_channel)
    elseif notice_type == "JOINED" and player_name and player_name ~= "" then
        state.roster[player_name] = true
        local count = 0
        local k
        for k in pairs(state.roster) do count = count + 1 end
        state.roster_count = count
        update_roster_db()
        XSocial.refresh_ui()
    elseif notice_type == "LEFT" and player_name and player_name ~= "" then
        state.roster[player_name] = nil
        local count = 0
        local k
        for k in pairs(state.roster) do count = count + 1 end
        state.roster_count = count
        update_roster_db()
        XSocial.refresh_ui()
    elseif notice_type == "CHANNEL_FULL" then
        XSocial.print_msg(L["Channel is full."])
    elseif notice_type == "BANNED" then
        XSocial.print_msg(L["You are banned from the channel."])
    elseif notice_type == "THROTTLED" then
        XSocial.print_msg(L["Channel throttled, please wait."])
    end
end

handle_channel_list = function(list_str, chan_arg4, chan_arg8, chan_arg9)
    if not list_str or list_str == "" then return end
    local target_channel = XSocialConfig.channel or "xsocial"

    local is_match = false
    if chan_arg9 and is_channel_match(chan_arg9, target_channel) then
        is_match = true
    elseif chan_arg4 and is_channel_match(chan_arg4, target_channel) then
        is_match = true
    elseif chan_arg8 then
        local chan_name_from_id = GetChannelName(chan_arg8)
        if chan_name_from_id and is_channel_match(chan_name_from_id, target_channel) then
            is_match = true
        end
    else
        local active_id = get_channel_index(target_channel)
        if active_id and active_id > 0 then
            is_match = true
        end
    end

    if not is_match then return end

    local new_roster = {}
    local member_count = 0
    local name_match

    for name_match in string.gfind(list_str, "([^,%s@*]+)") do
        if name_match and name_match ~= "" then
            local clean_name = string.gsub(name_match, "[%[%]%:%(%)%.]", "")
            if clean_name ~= "" and not string.find(clean_name, "%d") then
                if not is_channel_match(clean_name, target_channel) and clean_name ~= "channel" and clean_name ~= "Channel" then
                    new_roster[clean_name] = true
                    member_count = member_count + 1
                end
            end
        end
    end

    local my_name = UnitName("player")
    if my_name and my_name ~= "" then
        if not new_roster[my_name] then
            new_roster[my_name] = true
            member_count = member_count + 1
        end
    end

    if member_count > 0 then
        state.roster = new_roster
        state.roster_count = member_count
        state.last_poll = time()
        update_roster_db()
        XSocial.refresh_ui()
    end
end

handle_system_msg = function(msg)
    if not msg or msg == "" then return end

    -- Pattern 1: Hyperlinked who result: |Hplayer:Name|h[Name]|h: Level 60 ... - Zone
    local _, _, who_name, who_zone = string.find(msg, "|Hplayer:([^|]+)|h.-%s+%-%s+(.-)%s*$")

    -- Pattern 2: Non-hyperlinked who result: Name: Level 60 ... - Zone
    if not who_name then
        local _, _, raw_name, raw_zone = string.find(msg, "^([%w\128-\255_]+)%s*:%s*.-%s+%-%s+(.-)%s*$")
        if raw_name and (state.pending_who_target == raw_name or (state.roster and state.roster[raw_name])) then
            who_name = raw_name
            who_zone = raw_zone
        end
    end

    if who_name and who_zone and who_zone ~= "" then
        local p = XSocial.get_or_create_player(who_name)
        p.zone = who_zone

        -- Extract level if present in system message
        local _, _, lvl = string.find(msg, "Level%s+(%d+)")
        if not lvl then
            _, _, lvl = string.find(msg, "(%d+)%s*级")
        end
        if lvl then
            p.level = tonumber(lvl)
        end

        if state.pending_who_target and FriendsFrame and not state.friends_was_open and FriendsFrame:IsVisible() then
            if HideUIPanel then HideUIPanel(FriendsFrame) else FriendsFrame:Hide() end
        end
        state.pending_who_target = nil
        state.who_timeout = nil
        state.friends_was_open = nil
        if SetWhoToUI then SetWhoToUI(0) elseif SetWhoToUi then SetWhoToUi(0) end
        XSocial.refresh_ui()
    end
end

setup_hooks = function()
    -- Hook ChatFrame_OnEvent to suppress protocol messages (#whois#) from chat display
    local function pre_chat_event()
        if event == "CHAT_MSG_CHANNEL" then
            local target_chan = XSocialConfig.channel or "xsocial"
            if (arg9 and is_channel_match(arg9, target_chan)) or (arg4 and is_channel_match(arg4, target_chan)) then
                local text = arg1 or ""
                if string.find(text, "^#whois#") then
                    return false -- suppress from player chat frame
                end
            end
        end
    end

    if OzHook and OzHook.hook then
        OzHook:hook("ChatFrame_OnEvent", pre_chat_event)

        if ShowUIPanel then
            OzHook:hook("ShowUIPanel", function(frame)
                if state.pending_who_target and frame == FriendsFrame and not state.friends_was_open then
                    return false
                end
            end)
        end

        if FriendsFrame_OnEvent then
            OzHook:hook("FriendsFrame_OnEvent", function()
                if event == "WHO_LIST_UPDATE" and state.pending_who_target then
                    return false
                end
            end)
        end

        if WhoFrame_OnEvent then
            OzHook:hook("WhoFrame_OnEvent", function()
                if event == "WHO_LIST_UPDATE" and state.pending_who_target then
                    return false
                end
            end)
        end
    else
        -- Fallback direct hooks if OzHook is not available
        if ChatFrame_OnEvent then
            local orig_ChatFrame_OnEvent = ChatFrame_OnEvent
            ChatFrame_OnEvent = function()
                if pre_chat_event() == false then return end
                return orig_ChatFrame_OnEvent()
            end
        end
        if ShowUIPanel then
            local orig_ShowUIPanel = ShowUIPanel
            ShowUIPanel = function(frame, force)
                if state.pending_who_target and frame == FriendsFrame and not state.friends_was_open then
                    return
                end
                return orig_ShowUIPanel(frame, force)
            end
        end
        if FriendsFrame_OnEvent then
            local orig_FriendsFrame_OnEvent = FriendsFrame_OnEvent
            FriendsFrame_OnEvent = function()
                if event == "WHO_LIST_UPDATE" and state.pending_who_target then
                    return
                end
                return orig_FriendsFrame_OnEvent()
            end
        end
        if WhoFrame_OnEvent then
            local orig_WhoFrame_OnEvent = WhoFrame_OnEvent
            WhoFrame_OnEvent = function()
                if event == "WHO_LIST_UPDATE" and state.pending_who_target then
                    return
                end
                return orig_WhoFrame_OnEvent()
            end
        end
    end
end

-- ============================================================
-- Public API implementation
-- ============================================================

function XSocial.init()
    if state.initialized then return end
    state.initialized = true

    init_config()
    setup_hooks()
    join_channel(XSocialConfig.channel or "xsocial")

    -- Start OnUpdate polling timer
    state.poll_timer = 0
    event_frame:SetScript("OnUpdate", function()
        state.poll_timer = state.poll_timer + arg1
        local interval = XSocialConfig.pollInterval or 300

        -- Watchdog for pending who query timeout (reset SetWhoToUI if server didn't respond)
        if state.who_timeout and time() > state.who_timeout then
            if state.pending_who_target and FriendsFrame and not state.friends_was_open and FriendsFrame:IsVisible() then
                if HideUIPanel then HideUIPanel(FriendsFrame) else FriendsFrame:Hide() end
            end
            state.who_timeout = nil
            state.pending_who_target = nil
            state.friends_was_open = nil
            if SetWhoToUI then SetWhoToUI(0) elseif SetWhoToUi then SetWhoToUi(0) end
        end

        if not state.channel_joined then
            if state.poll_timer >= 1 then
                state.poll_timer = 0
                local target_chan = XSocialConfig.channel or "xsocial"
                local idx = get_channel_index(target_chan)
                if idx and idx > 0 then
                    on_channel_joined(target_chan)
                end
            end
        elseif state.poll_timer >= interval then
            state.poll_timer = 0
            XSocial.do_poll()
        end
    end)

    if XSocial.HUDButton and XSocial.HUDButton.create then
        XSocial.HUDButton.create()
    elseif XSocial._create_icon then
        XSocial._create_icon()
    end

    SlashCmdList["XSOCIAL"] = function()
        if XSocial.toggle_main_window then
            XSocial.toggle_main_window()
        end
    end
    SLASH_XSOCIAL1 = "/xsocial"
end

function XSocial.join_channel(channel_name)
    join_channel(channel_name)
end

function XSocial.leave_channel(channel_name)
    leave_channel(channel_name)
end

function XSocial.set_channel(new_channel)
    local is_valid, err_msg = validate_channel(new_channel)
    if not is_valid then
        return false, err_msg
    end
    local old_channel = XSocialConfig.channel
    if old_channel and old_channel ~= new_channel then
        leave_channel(old_channel)
    end

    -- Clear state for previous channel
    state.roster = {}
    state.roster_count = 0
    state.channel_joined = false
    state.last_poll = 0
    state.poll_timer = 0
    update_roster_db()

    -- Save and join new channel
    XSocialConfig.channel = new_channel
    join_channel(new_channel)
    XSocial.refresh_ui()

    -- Immediate probe: if already joined, trigger on_channel_joined immediately
    local idx = get_channel_index(new_channel)
    if idx and idx > 0 then
        on_channel_joined(new_channel)
    end

    return true
end

function XSocial.get_channel()
    return XSocialConfig.channel or "xsocial"
end

function XSocial.set_nickname(nick)
    local is_valid, err_msg = validate_nickname(nick)
    if not is_valid then
        return false, err_msg
    end
    XSocialConfig.nickname = nick
    local player_name = UnitName("player")
    if player_name and player_name ~= "" then
        XSocial.get_or_create_player(player_name).nick = nick
    end
    XSocial.print_msg(string.format(L["Nickname saved as '%s'."], nick))
    send_announcement(true)
    XSocial.refresh_ui()
    return true
end

function XSocial.get_nickname()
    return XSocialConfig.nickname or ""
end

function XSocial.get_my_note()
    local my_name = UnitName("player")
    return (my_name and XSocialConfig.notes and XSocialConfig.notes[my_name]) or ""
end

function XSocial.set_my_note(val)
    local is_valid, err_msg = validate_note(val)
    if not is_valid then
        return false, err_msg
    end
    local my_name = UnitName("player")
    if not my_name or my_name == "" then
        return false, "Player not found."
    end
    local notes = XSocialConfig.notes or {}
    XSocialConfig.notes = notes
    notes[my_name] = val
    XSocial.get_or_create_player(my_name).note = val
    XSocial.print_msg(L["Note saved."])
    send_announcement(true)
    XSocial.refresh_ui()
    return true
end

function XSocial.get_or_create_player(toon_name)
    local players = XSocialDB.players
    if not players then
        players = {}
        XSocialDB.players = players
    end
    if not players[toon_name] then
        players[toon_name] = {}
    end
    return players[toon_name]
end

function XSocial.get_player(toon_name)
    return XSocialDB.players and XSocialDB.players[toon_name]
end

function XSocial.get_players()
    return XSocialDB.players or {}
end

function XSocial.get_channel_index(channel_name)
    return get_channel_index(channel_name)
end

function XSocial.get_ui_font(size)
    local font_file = nil
    if GameFontNormal and GameFontNormal.GetFont then
        font_file = GameFontNormal:GetFont()
    end
    if not font_file or font_file == "" then
        font_file = STANDARD_TEXT_FONT
    end
    if not font_file or font_file == "" then
        font_file = "Fonts\\FRIZQT__.TTF"
    end
    return font_file, (size or 11)
end

function XSocial.validate_nickname(nick)
    return validate_nickname(nick)
end

function XSocial.validate_note(note_val)
    return validate_note(note_val)
end

function XSocial.validate_channel(chan)
    return validate_channel(chan)
end

function XSocial.open_channel_chat()
    local target_chan = XSocialConfig.channel or "xsocial"
    local chan_idx = get_channel_index(target_chan)
    if chan_idx and chan_idx > 0 then
        ChatFrame_OpenChat("/" .. chan_idx .. " ")
    else
        XSocial.print_msg(L["Channel not joined."])
    end
end

function XSocial.inquire_toon(target_toon)
    return inquire_toon(target_toon)
end

function XSocial.send_announcement(force)
    return send_announcement(force)
end

function XSocial.do_poll()
    if not state.channel_joined then return end
    local api_success = poll_via_api()
    if not api_success then
        poll_via_chatlist()
    end
    state.last_poll = time()
    XSocial.refresh_ui()
end

function XSocial.request_refresh()
    local current_time = time()
    if (current_time - state.last_poll) < 30 then
        XSocial.refresh_ui()
        return false
    end
    XSocial.do_poll()
    return true
end

function XSocial.get_known_count()
    return get_known_count()
end

function XSocial.get_total_count()
    return get_total_count()
end

function XSocial.get_online_count()
    return get_total_count()
end

function XSocial.get_roster()
    return state.roster
end

function XSocial.get_nickname_map()
    local map = {}
    if XSocialDB.players then
        local name, p
        for name, p in pairs(XSocialDB.players) do
            if p.nick and p.nick ~= "" then
                map[name] = p.nick
            end
        end
    end
    return map
end

function XSocial.save_config(updates)
    if updates then
        local key, val
        for key, val in pairs(updates) do
            XSocialConfig[key] = val
        end
    end
    XSocial.print_msg(L["Configuration saved."])
    XSocial.refresh_ui()
end

function XSocial.get_config()
    return XSocialConfig
end

function XSocial.format_time(timestamp)
    if not timestamp or timestamp == 0 then return "-" end
    local diff = time() - timestamp
    if diff < 60 then
        return string.format("%ds ago", diff)
    elseif diff < 3600 then
        return string.format("%dm ago", math.floor(diff / 60))
    else
        return string.format("%dh ago", math.floor(diff / 3600))
    end
end

function XSocial.print_msg(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[XSocial]|r " .. tostring(msg))
    end
end

function XSocial.refresh_ui()
    if XSocial.HUDButton and XSocial.HUDButton.update then
        XSocial.HUDButton.update()
    end
    if XSocial.MainWindow and XSocial.MainWindow.refresh then
        XSocial.MainWindow.refresh()
    end
    if XSocial.MainWindow and XSocial.MainWindow.refresh_tooltip then
        XSocial.MainWindow.refresh_tooltip()
    end
    if XSocial._on_ui_refresh then
        XSocial._on_ui_refresh()
    end
end

-- ============================================================
-- Slash command registration
-- ============================================================
SLASH_XSOCIAL1 = "/xsocial"
SlashCmdList["XSOCIAL"] = function(msg)
    local cmd = msg or ""
    local _, _, stripped = string.find(cmd, "^%s*(.-)%s*$")
    if stripped then cmd = stripped end

    if cmd == "debug" then
        XSocialConfig.debug = not XSocialConfig.debug
        XSocial.print_msg("Debug mode: " .. (XSocialConfig.debug and "ON" or "OFF"))
    elseif cmd == "refresh" then
        XSocial.do_poll()
    elseif cmd == "test" then
        local my_name = UnitName("player")
        if my_name and my_name ~= "" then
            inquire_toon(my_name)
            XSocial.print_msg("Sent test inquiry for " .. my_name)
        end
    else
        if XSocial.toggle_main_window then
            XSocial.toggle_main_window()
        end
    end
end

-- ============================================================
-- Event handler
-- ============================================================
event_frame:SetScript("OnEvent", function()
    local current_event = event
    if current_event == "PLAYER_LOGIN" then
        XSocial.init()
    elseif current_event == "CHAT_MSG_CHANNEL_NOTICE" then
        handle_channel_notice(arg1, arg2, arg4, arg8, arg9)
    elseif current_event == "CHAT_MSG_CHANNEL" then
        handle_channel_msg(arg1, arg2, arg4, arg8, arg9)
    elseif current_event == "CHAT_MSG_CHANNEL_LIST" then
        handle_channel_list(arg1, arg4, arg8, arg9)
    elseif current_event == "WHO_LIST_UPDATE" then
        local num_results = GetNumWhoResults() or 0
        local i
        local updated = false
        for i = 1, num_results do
            local w_name, w_guild, w_level, w_race, w_class, w_zone = GetWhoInfo(i)
            if w_name and w_name ~= "" then
                if (state.pending_who_target and w_name == state.pending_who_target) or (state.roster and state.roster[w_name]) then
                    local p = XSocial.get_or_create_player(w_name)
                    if w_level and w_level > 0 then p.level = w_level end
                    if w_class and w_class ~= "" then p.class = w_class end
                    if w_zone and w_zone ~= "" then p.zone = w_zone end
                    updated = true
                end
            end
        end
        if SetWhoToUI then
            SetWhoToUI(0)
        elseif SetWhoToUi then
            SetWhoToUi(0)
        end
        if state.pending_who_target and FriendsFrame and not state.friends_was_open and FriendsFrame:IsVisible() then
            if HideUIPanel then HideUIPanel(FriendsFrame) else FriendsFrame:Hide() end
        end
        state.pending_who_target = nil
        state.who_timeout = nil
        state.friends_was_open = nil
        if updated then
            XSocial.refresh_ui()
        end
    elseif current_event == "CHAT_MSG_SYSTEM" then
        handle_system_msg(arg1)
    end
end)
