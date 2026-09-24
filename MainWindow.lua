-- MainWindow.lua
-- Dual-Pane Main Window for XSocial
-- Merged Top Bar: Channel [⚙], Nickname [⚙], Note [⚙], Close [X]
-- Left Pane (~240px): Scrollable roster with click-to-whisper, compact [?] inquire, hover tooltips, and bottom search/online count
-- Right Pane (~370px): Dedicated channel chat with full color/link support for items, quests, spells, and player whisper links
-- Strictly Lua 5.0, Vanilla WoW 1.12 API only

local XSocial = XSocial or {}
local L = XSocial.L

-- ============================================================
-- Module state
-- ============================================================
local main_window = nil
local channel_label = nil
local nick_label = nil
local note_label = nil
local online_label = nil
local filter_edit = nil
local filter_text = ""
local prompt_dialog = nil

-- Top bar & Pane references for Compact Mode toggling
local top_bar_frame = nil
local roster_pane_frame = nil
local chat_pane_frame = nil
local row2_left_frame = nil
local compact_btn = nil
local is_compact = false
local LEFT_PANEL_WIDTH = 242

-- Roster scroll & frame recycling pool
local roster_scroll = nil
local roster_child = nil
local row_pool = {}

-- Right-pane chat frame & input
local chat_msg_frame = nil
local chat_edit_box = nil
local chat_edit_box_focused = false

-- ============================================================
-- Forward declarations
-- ============================================================
local create_main_window = nil
local create_top_bar = nil
local create_roster_pane = nil
local create_chat_pane = nil
local create_prompt_dialog = nil
local show_prompt_dialog = nil
local refresh_top_bar = nil
local refresh_roster = nil
local get_or_create_row = nil
local send_chat_input = nil
local toggle_compact_mode = nil
local apply_compact_layout = nil
local is_xsocial_editbox_target = nil
local hook_chat_frame_editbox = nil
local hook_shift_click_insert = nil

-- Public namespace declarations
local MainWindow = {}
MainWindow.create = nil
MainWindow.show = nil
MainWindow.hide = nil
MainWindow.toggle = nil
MainWindow.is_visible = nil
MainWindow.refresh = nil
MainWindow.refresh_roster = nil
MainWindow.refresh_tooltip = nil
MainWindow.append_chat_message = nil

-- ============================================================
-- Helper: Localized UI Font (adapts to zhCN / client font)
-- ============================================================
local function get_ui_font(size)
    if XSocial and XSocial.get_ui_font then
        return XSocial.get_ui_font(size)
    end
    return "Fonts\\FRIZQT__.TTF", (size or 11)
end

-- ============================================================
-- Helper: Header FontString
-- ============================================================
local function create_header_text(parent_frame, text_str, font_size)
    local font_string = parent_frame:CreateFontString(nil, "OVERLAY")
    font_string:SetFont(get_ui_font(font_size or 12))
    font_string:SetTextColor(1, 0.82, 0)
    font_string:SetText(text_str or "")
    return font_string
end

-- ============================================================
-- Prompt Dialog for Channel / Nickname / Note editing
-- ============================================================
create_prompt_dialog = function(parent_frame)
    if prompt_dialog then return prompt_dialog end

    local dialog_frame = CreateFrame("Frame", "XSocialPromptDialog", parent_frame)
    dialog_frame:SetWidth(300)
    dialog_frame:SetHeight(130)
    dialog_frame:SetPoint("CENTER", parent_frame, "CENTER", 0, 20)
    dialog_frame:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog_frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 16,
        insets   = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    dialog_frame:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    dialog_frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    dialog_frame:EnableMouse(true)
    dialog_frame:Hide()

    local title_label = dialog_frame:CreateFontString(nil, "OVERLAY")
    title_label:SetFont(get_ui_font(11))
    title_label:SetTextColor(1, 0.82, 0)
    title_label:SetPoint("TOP", dialog_frame, "TOP", 0, -14)
    dialog_frame._title = title_label

    local input_box = CreateFrame("EditBox", nil, dialog_frame)
    input_box:SetWidth(220)
    input_box:SetHeight(22)
    input_box:SetPoint("TOP", title_label, "BOTTOM", 0, -10)
    input_box:SetAutoFocus(false)
    input_box:SetFontObject(GameFontNormal)
    input_box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    input_box:SetBackdropColor(0.02, 0.02, 0.02, 0.9)
    input_box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dialog_frame._input = input_box

    local ok_button = CreateFrame("Button", nil, dialog_frame, "UIPanelButtonTemplate")
    ok_button:SetWidth(70)
    ok_button:SetHeight(20)
    ok_button:SetPoint("BOTTOMLEFT", dialog_frame, "BOTTOMLEFT", 50, 14)
    ok_button:SetText(L["OK"])

    local cancel_button = CreateFrame("Button", nil, dialog_frame, "UIPanelButtonTemplate")
    cancel_button:SetWidth(70)
    cancel_button:SetHeight(20)
    cancel_button:SetPoint("BOTTOMRIGHT", dialog_frame, "BOTTOMRIGHT", -50, 14)
    cancel_button:SetText(L["Cancel"])

    local function do_submit()
        local input_text = input_box:GetText()
        if dialog_frame._on_submit then
            local submit_func = dialog_frame._on_submit
            submit_func(input_text)
        end
        dialog_frame:Hide()
    end

    input_box:SetScript("OnEnterPressed", function()
        do_submit()
    end)
    input_box:SetScript("OnEscapePressed", function()
        dialog_frame:Hide()
    end)

    ok_button:SetScript("OnClick", function()
        do_submit()
    end)
    cancel_button:SetScript("OnClick", function()
        dialog_frame:Hide()
    end)

    prompt_dialog = dialog_frame
    return prompt_dialog
end

show_prompt_dialog = function(prompt_title, default_val, submit_callback)
    if not prompt_dialog then
        create_prompt_dialog(main_window)
    end
    prompt_dialog._title:SetText(prompt_title or "")
    prompt_dialog._input:SetText(default_val or "")
    prompt_dialog._on_submit = submit_callback
    prompt_dialog:Show()
    prompt_dialog._input:SetFocus()
end

-- ============================================================
-- Merged Top Bar: Channel [⚙], Nick [⚙], Note [⚙], Close [X]
-- ============================================================
create_top_bar = function(parent_frame)
    local bar_frame = CreateFrame("Frame", nil, parent_frame)
    bar_frame:SetPoint("TOPLEFT", parent_frame, "TOPLEFT", 12, -8)
    bar_frame:SetPoint("TOPRIGHT", parent_frame, "TOPRIGHT", -55, -8)
    bar_frame:SetHeight(22)
    top_bar_frame = bar_frame

    -- Item 1: Channel Name + Gear
    local chan_text = bar_frame:CreateFontString(nil, "OVERLAY")
    chan_text:SetFont(get_ui_font(11))
    chan_text:SetTextColor(0.4, 0.8, 1) -- light blue
    chan_text:SetPoint("LEFT", bar_frame, "LEFT", 4, 0)
    chan_text:SetText(XSocial.get_channel())
    channel_label = chan_text

    local chan_gear = CreateFrame("Button", nil, bar_frame)
    chan_gear:SetWidth(14)
    chan_gear:SetHeight(14)
    chan_gear:SetPoint("LEFT", chan_text, "RIGHT", 3, 0)
    chan_gear:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    local cg_nt = chan_gear:GetNormalTexture()
    if cg_nt then cg_nt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    chan_gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    chan_gear:SetScript("OnClick", function()
        show_prompt_dialog(
            L["Enter new channel name:"],
            XSocial.get_channel(),
            function(new_val)
                local ok, err = XSocial.set_channel(new_val)
                if not ok and err then
                    XSocial.print_msg(err)
                end
                refresh_top_bar()
            end
        )
    end)

    -- Item 2: Nickname + Gear
    local nick_text = bar_frame:CreateFontString(nil, "OVERLAY")
    nick_text:SetFont(get_ui_font(11))
    nick_text:SetTextColor(1, 0.82, 0) -- gold
    nick_text:SetPoint("LEFT", chan_gear, "RIGHT", 14, 0)
    local cur_nick = XSocial.get_nickname()
    if cur_nick == "" then cur_nick = "-" end
    nick_text:SetText(cur_nick)
    nick_label = nick_text

    local nick_gear = CreateFrame("Button", nil, bar_frame)
    nick_gear:SetWidth(14)
    nick_gear:SetHeight(14)
    nick_gear:SetPoint("LEFT", nick_text, "RIGHT", 3, 0)
    nick_gear:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    local ng_nt = nick_gear:GetNormalTexture()
    if ng_nt then ng_nt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    nick_gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    nick_gear:SetScript("OnClick", function()
        show_prompt_dialog(
            L["Enter new nickname:"],
            XSocial.get_nickname(),
            function(new_val)
                local ok, err = XSocial.set_nickname(new_val)
                if not ok and err then
                    XSocial.print_msg(err)
                end
                refresh_top_bar()
            end
        )
    end)

    -- Item 3: Note + Gear (Per-toon personal note)
    local note_text = bar_frame:CreateFontString(nil, "OVERLAY")
    note_text:SetFont(get_ui_font(11))
    note_text:SetTextColor(0.8, 0.8, 0.8) -- grey-white
    note_text:SetPoint("LEFT", nick_gear, "RIGHT", 14, 0)
    local cur_note = XSocial.get_my_note()
    if cur_note == "" then cur_note = "-" end
    note_text:SetText(cur_note)
    note_label = note_text

    local note_gear = CreateFrame("Button", nil, bar_frame)
    note_gear:SetWidth(14)
    note_gear:SetHeight(14)
    note_gear:SetPoint("LEFT", note_text, "RIGHT", 3, 0)
    note_gear:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    local ntg_nt = note_gear:GetNormalTexture()
    if ntg_nt then ntg_nt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    note_gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    note_gear:SetScript("OnClick", function()
        show_prompt_dialog(
            L["Enter new note:"],
            XSocial.get_my_note(),
            function(new_val)
                local ok, err = XSocial.set_my_note(new_val)
                if not ok and err then
                    XSocial.print_msg(err)
                end
                refresh_top_bar()
            end
        )
    end)

    return bar_frame
end

refresh_top_bar = function()
    if channel_label then
        channel_label:SetText(XSocial.get_channel())
    end
    if nick_label then
        local cur_nick = XSocial.get_nickname()
        if cur_nick == "" then cur_nick = "-" end
        nick_label:SetText(cur_nick)
    end
    if note_label then
        local cur_note = XSocial.get_my_note()
        if cur_note == "" then cur_note = "-" end
        note_label:SetText(cur_note)
    end
end

-- ============================================================
-- Left Pane: Member Roster & Search (~235px wide)
-- ============================================================
get_or_create_row = function(index_num, parent_child, row_width, row_height)
    if row_pool[index_num] then
        return row_pool[index_num]
    end

    local row_frame = CreateFrame("Button", nil, parent_child)
    row_frame:SetWidth(row_width)
    row_frame:SetHeight(row_height)
    row_frame:SetPoint("TOPLEFT", parent_child, "TOPLEFT", 0, -((index_num - 1) * row_height))

    -- Alternating background
    local row_bg = row_frame:CreateTexture(nil, "BACKGROUND")
    row_bg:SetAllPoints(row_frame)
    if math.mod(index_num, 2) == 0 then
        row_bg:SetTexture(0.1, 0.1, 0.1, 0.3)
    else
        row_bg:SetTexture(0.05, 0.05, 0.05, 0.15)
    end
    row_frame._bg = row_bg

    -- Column 1: Toon Name (Clickable to whisper)
    local toon_btn = CreateFrame("Button", nil, row_frame)
    toon_btn:SetWidth(105)
    toon_btn:SetHeight(row_height)
    toon_btn:SetPoint("LEFT", row_frame, "LEFT", 4, 0)

    local toon_text = toon_btn:CreateFontString(nil, "OVERLAY")
    toon_text:SetFont(get_ui_font(11))
    toon_text:SetTextColor(0.9, 0.9, 0.9)
    toon_text:SetPoint("LEFT", toon_btn, "LEFT", 0, 0)
    row_frame._toon_text = toon_text
    row_frame._toon_btn = toon_btn

    -- Hover Tooltip helpers for entire row (Toon, Nick, Level/Class, Zone, Note)
    local function show_row_tooltip()
        row_frame._bg:SetTexture(0.2, 0.2, 0.2, 0.45)
        local member_name = row_frame._char_name
        if member_name and member_name ~= "" and GameTooltip then
            GameTooltip:SetOwner(row_frame, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(member_name, 1, 1, 1)

            local p = XSocial.get_player(member_name)
            if p and p.nick and p.nick ~= "" then
                GameTooltip:AddDoubleLine(L["Nickname"], p.nick, 0.7, 0.7, 0.7, 1, 0.82, 0)
            end
            if p and (p.level or p.class) then
                local lvl_str = tostring(p.level or "")
                local cls_str = p.class or ""
                GameTooltip:AddDoubleLine(L["Level / Class"], lvl_str .. " " .. cls_str, 0.7, 0.7, 0.7, 1, 1, 1)
            end
            local zone_text = (p and p.zone and p.zone ~= "") and p.zone or L["Unknown"]
            GameTooltip:AddDoubleLine(L["Location"], zone_text, 0.7, 0.7, 0.7, 0.4, 0.8, 1)
            if p and p.note and p.note ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Note"] .. ": " .. p.note, 1, 0.82, 0.4, true)
            end
            GameTooltip:Show()
        end
    end

    local function hide_row_tooltip()
        if math.mod(index_num, 2) == 0 then
            row_frame._bg:SetTexture(0.1, 0.1, 0.1, 0.3)
        else
            row_frame._bg:SetTexture(0.05, 0.05, 0.05, 0.15)
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end

    row_frame:SetScript("OnEnter", show_row_tooltip)
    row_frame:SetScript("OnLeave", hide_row_tooltip)

    toon_btn:SetScript("OnClick", function()
        local target_name = row_frame._char_name
        if target_name and target_name ~= "" then
            ChatFrame_OpenChat("/w " .. target_name .. " ")
        end
    end)
    toon_btn:SetScript("OnEnter", function()
        toon_text:SetTextColor(1, 0.82, 0)
        show_row_tooltip()
    end)
    toon_btn:SetScript("OnLeave", function()
        toon_text:SetTextColor(0.9, 0.9, 0.9)
        hide_row_tooltip()
    end)

    -- Column 2: Nickname
    local nick_text = row_frame:CreateFontString(nil, "OVERLAY")
    nick_text:SetFont(get_ui_font(11))
    nick_text:SetPoint("LEFT", toon_btn, "RIGHT", 4, 0)
    row_frame._nick_text = nick_text

    -- Column 3: Compact [?] Inquire Button (Always visible)
    local inquire_btn = CreateFrame("Button", nil, row_frame, "UIPanelButtonTemplate")
    inquire_btn:SetWidth(18)
    inquire_btn:SetHeight(18)
    inquire_btn:SetPoint("RIGHT", row_frame, "RIGHT", -4, 0)
    inquire_btn:SetText("?")
    row_frame._inquire_btn = inquire_btn

    inquire_btn:SetScript("OnClick", function()
        local target_name = row_frame._char_name
        if target_name and target_name ~= "" then
            local send_ok = XSocial.inquire_toon(target_name)
            if send_ok then
                inquire_btn:SetText("...")
                inquire_btn:Disable()
            end
        end
    end)
    inquire_btn:SetScript("OnEnter", show_row_tooltip)
    inquire_btn:SetScript("OnLeave", hide_row_tooltip)

    row_pool[index_num] = row_frame
    return row_frame
end

create_roster_pane = function(parent_frame)
    -- Row 2 Left Sub-bar: Online count, Search EditBox, Refresh button
    local row2_left = CreateFrame("Frame", nil, parent_frame)
    row2_left:SetPoint("TOPLEFT", parent_frame, "TOPLEFT", 10, -32)
    row2_left:SetWidth(235)
    row2_left:SetHeight(22)
    row2_left_frame = row2_left

    local count_str = row2_left:CreateFontString(nil, "OVERLAY")
    count_str:SetFont(get_ui_font(10))
    count_str:SetTextColor(0.7, 0.7, 0.7)
    count_str:SetPoint("LEFT", row2_left, "LEFT", 2, 0)
    count_str:SetText(string.format(L["Online: %d"], 0))
    online_label = count_str

    local filter_box = CreateFrame("EditBox", nil, row2_left)
    filter_box:SetWidth(95)
    filter_box:SetHeight(18)
    filter_box:SetPoint("LEFT", count_str, "RIGHT", 6, 0)
    filter_box:SetAutoFocus(false)
    filter_box:SetFontObject(GameFontNormalSmall)
    filter_box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    filter_box:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
    filter_box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    filter_box:SetScript("OnTextChanged", function()
        filter_text = filter_box:GetText() or ""
        refresh_roster()
    end)
    filter_edit = filter_box

    local ref_btn = CreateFrame("Button", nil, row2_left, "UIPanelButtonTemplate")
    ref_btn:SetWidth(48)
    ref_btn:SetHeight(18)
    ref_btn:SetPoint("RIGHT", row2_left, "RIGHT", -2, 0)
    ref_btn:SetText(L["Refresh"])
    ref_btn:SetScript("OnClick", function()
        XSocial.do_poll()
    end)

    -- Row 3 Left Pane: Member Roster Panel
    local pane_frame = CreateFrame("Frame", nil, parent_frame)
    pane_frame:SetPoint("TOPLEFT", parent_frame, "TOPLEFT", 10, -58)
    pane_frame:SetPoint("BOTTOMLEFT", parent_frame, "BOTTOMLEFT", 10, 10)
    pane_frame:SetWidth(235)
    roster_pane_frame = pane_frame

    -- ScrollFrame container
    local scroll_frame = CreateFrame("ScrollFrame", "XSocialRosterScroll", pane_frame)
    scroll_frame:SetPoint("TOPLEFT", pane_frame, "TOPLEFT", 0, 0)
    scroll_frame:SetPoint("BOTTOMRIGHT", pane_frame, "BOTTOMRIGHT", 0, 0)
    scroll_frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    scroll_frame:SetBackdropColor(0.03, 0.03, 0.03, 0.6)
    scroll_frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
    scroll_frame:EnableMouseWheel(true)

    local scroll_child = CreateFrame("Frame", nil, scroll_frame)
    scroll_child:SetWidth(231)
    scroll_child:SetHeight(220)
    scroll_frame:SetScrollChild(scroll_child)

    scroll_frame:SetScript("OnMouseWheel", function()
        local current_scroll = this:GetVerticalScroll()
        local new_scroll = current_scroll - arg1 * 22
        if new_scroll < 0 then new_scroll = 0 end
        local max_scroll = scroll_child:GetHeight() - scroll_frame:GetHeight()
        if max_scroll < 0 then max_scroll = 0 end
        if new_scroll > max_scroll then new_scroll = max_scroll end
        this:SetVerticalScroll(new_scroll)
    end)

    roster_scroll = scroll_frame
    roster_child = scroll_child

    return pane_frame
end

refresh_roster = function()
    if not roster_child or not roster_scroll then return end

    local current_roster = XSocial.get_roster() or {}
    local total_count = XSocial.get_total_count() or 0

    if online_label then
        online_label:SetText(string.format(L["Online: %d"], total_count))
    end

    -- Filter and sort members
    local items = {}
    local char_name
    for char_name in pairs(current_roster) do
        local p = XSocial.get_player(char_name)
        local mapped_nick = (p and p.nick) or ""
        if filter_text == ""
           or string.find(char_name, filter_text, 1, true)
           or string.find(mapped_nick, filter_text, 1, true) then
            table.insert(items, char_name)
        end
    end
    table.sort(items)

    local item_count = table.getn(items)
    local row_height = 22
    local row_width = 231
    local total_height = math.max(item_count * row_height + 4, roster_scroll:GetHeight() or 220)
    roster_child:SetHeight(total_height)

    -- Populate reused rows from row_pool
    local idx
    for idx = 1, item_count do
        local member_name = items[idx]
        local row_widget = get_or_create_row(idx, roster_child, row_width, row_height)
        row_widget._char_name = member_name

        -- Column 1: Character Name
        row_widget._toon_text:SetText(member_name)

        -- Column 2: Nickname
        local p = XSocial.get_player(member_name)
        local known_nick = p and p.nick
        if known_nick and known_nick ~= "" then
            row_widget._nick_text:SetText(known_nick)
            row_widget._nick_text:SetTextColor(1, 0.82, 0) -- gold
        else
            row_widget._nick_text:SetText("-")
            row_widget._nick_text:SetTextColor(0.55, 0.55, 0.55) -- grey
        end

        -- Column 3: Inquire Button reset
        row_widget._inquire_btn:SetText("?")
        row_widget._inquire_btn:Enable()
        row_widget._inquire_btn:Show()

        row_widget:Show()
    end

    -- Hide remaining unused rows in row_pool to prevent ghost entries
    local pool_count = table.getn(row_pool)
    for idx = item_count + 1, pool_count do
        if row_pool[idx] then
            row_pool[idx]:Hide()
        end
    end
end

-- ============================================================
-- Universal EditBox Hyperlink & Shift-Click Proxy
-- Routes shift-clicked items, quests, spells, and players into XSocial's editbox
-- when XSocial chat input is open/focused, without breaking Blizzard chat.
-- ============================================================
local orig_cf_insert     = nil

local function insert_to_xsocial(text_or_link)
    if not text_or_link or not chat_edit_box then return false end
    chat_edit_box:Insert(text_or_link)
    chat_edit_box:SetFocus()
    return true
end

is_xsocial_editbox_target = function()
    if not chat_edit_box or not chat_edit_box:IsVisible() then
        return false
    end
    if ChatFrameEditBox and ChatFrameEditBox:IsVisible() and not chat_edit_box_focused then
        return false
    end
    return true
end

hook_chat_frame_editbox = function()
    if not ChatFrameEditBox or orig_cf_insert then return end

    orig_cf_insert = ChatFrameEditBox.Insert

    ChatFrameEditBox.Insert = function(self, text)
        if is_xsocial_editbox_target() and insert_to_xsocial(text) then
            return
        end
        if orig_cf_insert then
            return orig_cf_insert(self, text)
        end
    end
end

local shift_click_hooked = false

hook_shift_click_insert = function()
    if shift_click_hooked then return end
    if not OzHook or not OzHook.hook then return end
    shift_click_hooked = true

    -- 1. Hook ContainerFrameItemButton_OnClick (Bags)
    OzHook:hook("ContainerFrameItemButton_OnClick", function(button, ignoreShift)
        if button == "LeftButton" and IsShiftKeyDown() and not ignoreShift and is_xsocial_editbox_target() then
            local parent = this and this:GetParent()
            local bag = parent and parent:GetID()
            local slot = this and this:GetID()
            if bag and slot and insert_to_xsocial(GetContainerItemLink(bag, slot)) then
                return false
            end
        end
    end)

    -- 2. Hook PaperDollItemSlotButton_OnClick (Equipped Gear)
    OzHook:hook("PaperDollItemSlotButton_OnClick", function(button, ignoreShift)
        if button == "LeftButton" and IsShiftKeyDown() and not ignoreShift and is_xsocial_editbox_target() then
            local slot = this and this:GetID()
            if slot and insert_to_xsocial(GetInventoryItemLink("player", slot)) then
                return false
            end
        end
    end)

    -- 3. Hook SetItemRef (Chat Hyperlinks)
    OzHook:hook("SetItemRef", function(link, text, button)
        if IsShiftKeyDown() and is_xsocial_editbox_target() then
            if link and string.sub(link, 1, 6) == "player" then
                local name = string.sub(link, 8)
                local _, _, clean = string.find(name, "([^:]+)")
                name = string.gsub(clean or name, "^%s*(.-)%s*$", "%1")
                if insert_to_xsocial("|cffffffff|Hplayer:" .. name .. "|h[" .. name .. "]|h|r") then
                    return false
                end
            elseif link and string.sub(link, 1, 5) == "item:" then
                local _, item_link = GetItemInfo(link)
                if insert_to_xsocial(item_link or text or link) then
                    return false
                end
            else
                if insert_to_xsocial(text or link) then
                    return false
                end
            end
        end
    end)

    -- 4. Hook QuestLogTitleButton_OnClick (Quest Log)
    if QuestLogTitleButton_OnClick then
        OzHook:hook("QuestLogTitleButton_OnClick", function(button)
            if IsShiftKeyDown() and is_xsocial_editbox_target() then
                local offset = (FauxScrollFrame_GetOffset and QuestLogListScrollFrame) and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
                local btn = this or button
                local btn_id = (btn and btn.GetID) and btn:GetID() or 0
                local questIndex = btn_id + offset
                if btn and not btn.isHeader then
                    local questLink = (GetQuestLinkForLogIndex and GetQuestLinkForLogIndex(questIndex))
                        or (GetQuestLink and GetQuestLink(questIndex))
                    if not questLink and GetQuestLogTitle then
                        local title, level = GetQuestLogTitle(questIndex)
                        if title then
                            questLink = "|cffffff00|Hquest:0:" .. (level or 1) .. "|h[" .. title .. "]|h|r"
                        end
                    end
                    if insert_to_xsocial(questLink) then
                        return false
                    end
                end
            end
        end)
    end

    -- 5. Hook BankFrameItemButtonGeneric_OnClick (Bank)
    if BankFrameItemButtonGeneric_OnClick then
        OzHook:hook("BankFrameItemButtonGeneric_OnClick", function(button)
            if button == "LeftButton" and IsShiftKeyDown() and is_xsocial_editbox_target() then
                local slot = this and this:GetID()
                if slot and insert_to_xsocial(GetContainerItemLink(BANK_CONTAINER or -1, slot)) then
                    return false
                end
            end
        end)
    end

    -- 6. Hook MerchantItemButton_OnClick (Merchants)
    if MerchantItemButton_OnClick then
        OzHook:hook("MerchantItemButton_OnClick", function(button, ignoreShift)
            if button == "LeftButton" and IsShiftKeyDown() and not ignoreShift and is_xsocial_editbox_target() then
                local slot = this and this:GetID()
                if slot and GetMerchantItemLink and insert_to_xsocial(GetMerchantItemLink(slot)) then
                    return false
                end
            end
        end)
    end

    -- 7. Hook LootButton_OnClick (Loot Window)
    if LootButton_OnClick then
        OzHook:hook("LootButton_OnClick", function(button)
            if IsShiftKeyDown() and is_xsocial_editbox_target() then
                local slot = this and this:GetSlot()
                if slot and GetLootSlotLink and insert_to_xsocial(GetLootSlotLink(slot)) then
                    return false
                end
            end
        end)
    end
end

-- ============================================================
-- Right Pane: Dedicated Chat Window (~365px wide)
-- ============================================================
create_chat_pane = function(parent_frame)
    -- Row 2 Right Sub-bar: Chat Input EditBox (Full width, Enter sends message)
    local input_box = CreateFrame("EditBox", "XSocialChatEditBox", parent_frame)
    input_box:SetPoint("TOPLEFT", parent_frame, "TOPLEFT", 252, -32)
    input_box:SetPoint("TOPRIGHT", parent_frame, "TOPRIGHT", -10, -32)
    input_box:SetHeight(22)
    input_box:SetAutoFocus(false)
    input_box:EnableMouse(true)
    input_box:SetFontObject(GameFontNormal)
    input_box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    input_box:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
    input_box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    input_box:SetScript("OnEditFocusGained", function()
        chat_edit_box_focused = true
    end)
    input_box:SetScript("OnEditFocusLost", function()
        chat_edit_box_focused = false
    end)

    send_chat_input = function()
        local text = input_box:GetText()
        if text and text ~= "" then
            local target_chan = XSocial.get_channel()
            local chan_idx = GetChannelName(target_chan)
            if not chan_idx or chan_idx < 1 then
                if XSocial.get_channel_index then
                    chan_idx = XSocial.get_channel_index(target_chan)
                end
            end
            if chan_idx and chan_idx > 0 then
                SendChatMessage(text, "CHANNEL", nil, chan_idx)
                input_box:SetText("")
            else
                XSocial.print_msg(L["Channel not joined."])
            end
        end
    end

    input_box:SetScript("OnEnterPressed", function()
        send_chat_input()
    end)
    input_box:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)

    chat_edit_box = input_box
    XSocial.chat_edit_box = input_box
    XSocialChatEditBox = input_box

    -- Row 3 Right Pane: Dedicated Chat Window (~365px wide)
    local pane_frame = CreateFrame("Frame", "XSOCIAL_CHAT_WINDOW", parent_frame)
    pane_frame:SetPoint("TOPLEFT", parent_frame, "TOPLEFT", 252, -58)
    pane_frame:SetPoint("BOTTOMRIGHT", parent_frame, "BOTTOMRIGHT", -10, 10)
    chat_pane_frame = pane_frame
    XSOCIAL_CHAT_WINDOW = pane_frame

    -- Backdrop for chat box
    pane_frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    pane_frame:SetBackdropColor(0.02, 0.02, 0.02, 0.75)
    pane_frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

    -- ScrollingMessageFrame for channel chat
    local msg_frame = CreateFrame("ScrollingMessageFrame", "XSocialChatMsgFrame", pane_frame)
    msg_frame:SetPoint("TOPLEFT", pane_frame, "TOPLEFT", 6, -6)
    msg_frame:SetPoint("BOTTOMRIGHT", pane_frame, "BOTTOMRIGHT", -6, 6)
    msg_frame:SetMaxLines(128)
    msg_frame:SetFont(get_ui_font(11))
    msg_frame:SetJustifyH("LEFT")
    msg_frame:EnableMouse(true)
    msg_frame:EnableMouseWheel(true)

    if msg_frame.SetFading then
        msg_frame:SetFading(false)
    end

    if msg_frame.SetHyperlinksEnabled then
        msg_frame:SetHyperlinksEnabled(true)
    end

    msg_frame:SetScript("OnMouseWheel", function()
        if arg1 > 0 then
            this:ScrollUp()
        else
            this:ScrollDown()
        end
    end)

    -- Hyperlink click handling (Items, Quests, Spells, Click-to-Invite, and Player whisper links)
    msg_frame:SetScript("OnHyperlinkClick", function()
        -- 1. Click-to-Invite: |Hinvite:Sender|h
        if arg1 and string.sub(arg1, 1, 7) == "invite:" then
            local sender = string.sub(arg1, 8)
            if sender and string.len(sender) > 0 then
                local _, _, clean = string.find(sender, "([^:]+)")
                sender = clean or sender
                sender = string.gsub(sender, "^%s*(.-)%s*$", "%1")
                if string.len(sender) > 0 then
                    InviteByName(sender)
                    return
                end
            end
        end

        -- 2. Shift-Click Player link: |Hplayer:Sender|h -> insert player link into editbox
        if IsShiftKeyDown() and arg1 and string.sub(arg1, 1, 6) == "player" then
            local name = string.sub(arg1, 8)
            if name and string.len(name) > 0 then
                local _, _, clean = string.find(name, "([^:]+)")
                name = clean or name
                name = string.gsub(name, "^%s*(.-)%s*$", "%1")
                if is_xsocial_editbox_target() and chat_edit_box then
                    chat_edit_box:Insert("|cffffffff|Hplayer:" .. name .. "|h[" .. name .. "]|h|r")
                    chat_edit_box:SetFocus()
                    return
                end
            end
        end

        -- 3. Shift-Click Item / Quest / Spell in chat: insert formatted link into editbox
        if IsShiftKeyDown() and is_xsocial_editbox_target() and chat_edit_box then
            local insert_text = nil
            if arg2 and string.find(arg2, "%[.-%]") then
                insert_text = arg2
            elseif arg1 and string.sub(arg1, 1, 5) == "item:" then
                local _, item_link = GetItemInfo(arg1)
                insert_text = item_link
            elseif arg1 and string.sub(arg1, 1, 6) == "quest:" then
                insert_text = arg2 or ("|cffffff00|H" .. arg1 .. "|h[Quest]|h|r")
            end

            if insert_text then
                chat_edit_box:Insert(insert_text)
                chat_edit_box:SetFocus()
                return
            end
        end

        -- 4. Default Blizzard / Addon SetItemRef handling
        -- (Handles item preview tooltip, DressUp dressing room Ctrl-click, player whisper, etc.)
        if SetItemRef then
            SetItemRef(arg1, arg2, arg3)
        elseif ChatFrame_OnHyperlinkShow then
            ChatFrame_OnHyperlinkShow(arg1, arg2, arg3)
        end
    end)

    -- Hover item tooltip
    msg_frame:SetScript("OnHyperlinkEnter", function()
        if not arg1 then return end
        if string.sub(arg1, 1, 7) == "invite:" then
            local sender = string.sub(arg1, 8)
            if sender and string.len(sender) > 0 then
                local _, _, clean = string.find(sender, "([^:]+)")
                sender = clean or sender
                sender = string.gsub(sender, "^%s*(.-)%s*$", "%1")
                if GameTooltip and string.len(sender) > 0 then
                    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine((L["Click to invite"] or "Click to invite") .. ": " .. sender, 0, 1, 1)
                    GameTooltip:Show()
                end
            end
            return
        end
        if string.sub(arg1, 1, 6) ~= "player" and GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(arg1)
            GameTooltip:Show()
        end
    end)
    msg_frame:SetScript("OnHyperlinkLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    chat_msg_frame = msg_frame
    return pane_frame
end

-- ============================================================
-- Compact Mode Layout Management
-- ============================================================
apply_compact_layout = function(compact)
    is_compact = compact
    if not main_window then return end

    if is_compact then
        if top_bar_frame then top_bar_frame:Hide() end
        if row2_left_frame then row2_left_frame:Hide() end
        if roster_pane_frame then roster_pane_frame:Hide() end

        if chat_edit_box then
            chat_edit_box:ClearAllPoints()
            chat_edit_box:SetPoint("TOPLEFT", main_window, "TOPLEFT", 10, -32)
            chat_edit_box:SetPoint("TOPRIGHT", main_window, "TOPRIGHT", -10, -32)
        end
        if chat_pane_frame then
            chat_pane_frame:ClearAllPoints()
            chat_pane_frame:SetPoint("TOPLEFT", main_window, "TOPLEFT", 10, -58)
            chat_pane_frame:SetPoint("BOTTOMRIGHT", main_window, "BOTTOMRIGHT", -10, 10)
        end
        main_window:SetMinResize(200, 200)
    else
        if top_bar_frame then top_bar_frame:Show() end
        if row2_left_frame then row2_left_frame:Show() end
        if roster_pane_frame then roster_pane_frame:Show() end

        if chat_edit_box then
            chat_edit_box:ClearAllPoints()
            chat_edit_box:SetPoint("TOPLEFT", main_window, "TOPLEFT", 252, -32)
            chat_edit_box:SetPoint("TOPRIGHT", main_window, "TOPRIGHT", -10, -32)
        end
        if chat_pane_frame then
            chat_pane_frame:ClearAllPoints()
            chat_pane_frame:SetPoint("TOPLEFT", main_window, "TOPLEFT", 252, -58)
            chat_pane_frame:SetPoint("BOTTOMRIGHT", main_window, "BOTTOMRIGHT", -10, 10)
        end
        main_window:SetMinResize(450, 300)
        refresh_top_bar()
        refresh_roster()
    end
end

toggle_compact_mode = function()
    if not main_window then return end

    if not is_compact then
        -- Entering compact mode: remember current full mode dimensions
        if XSocialConfig then
            XSocialConfig.windowWidth = main_window:GetWidth()
            XSocialConfig.windowHeight = main_window:GetHeight()
        end

        local compact_w = (XSocialConfig and XSocialConfig.compactWidth) or (main_window:GetWidth() - LEFT_PANEL_WIDTH)
        local compact_h = (XSocialConfig and XSocialConfig.compactHeight) or main_window:GetHeight()
        if compact_w < 200 then compact_w = 200 end
        if compact_h < 200 then compact_h = 200 end

        apply_compact_layout(true)
        main_window:SetWidth(compact_w)
        main_window:SetHeight(compact_h)
    else
        -- Exiting compact mode: remember current compact mode dimensions
        if XSocialConfig then
            XSocialConfig.compactWidth = main_window:GetWidth()
            XSocialConfig.compactHeight = main_window:GetHeight()
        end

        local full_w = (XSocialConfig and XSocialConfig.windowWidth) or (main_window:GetWidth() + LEFT_PANEL_WIDTH)
        local full_h = (XSocialConfig and XSocialConfig.windowHeight) or main_window:GetHeight()
        if full_w < 450 then full_w = 450 end
        if full_h < 300 then full_h = 300 end

        apply_compact_layout(false)
        main_window:SetWidth(full_w)
        main_window:SetHeight(full_h)
    end

    if XSocialConfig then
        XSocialConfig.isCompact = is_compact
    end
end

-- ============================================================
-- Main Window Factory
-- ============================================================
create_main_window = function()
    if main_window then return main_window end

    local is_start_compact = (XSocialConfig and XSocialConfig.isCompact) and true or false

    local full_w = (XSocialConfig and XSocialConfig.windowWidth) or 620
    local full_h = (XSocialConfig and XSocialConfig.windowHeight) or 360
    if full_w < 450 then full_w = 450 end
    if full_h < 300 then full_h = 300 end

    local compact_w = (XSocialConfig and XSocialConfig.compactWidth) or (full_w - LEFT_PANEL_WIDTH)
    local compact_h = (XSocialConfig and XSocialConfig.compactHeight) or full_h
    if compact_w < 200 then compact_w = 200 end
    if compact_h < 200 then compact_h = 200 end

    local init_w = is_start_compact and compact_w or full_w
    local init_h = is_start_compact and compact_h or full_h

    local window_frame = CreateFrame("Frame", "XSocialMainWindow", UIParent)
    main_window = window_frame

    window_frame:SetWidth(init_w)
    window_frame:SetHeight(init_h)
    window_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window_frame:SetFrameStrata("DIALOG")

    -- Classic DialogBox backdrop
    window_frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 16,
        insets   = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    window_frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    window_frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    window_frame:SetMovable(true)
    window_frame:EnableMouse(true)
    window_frame:RegisterForDrag("LeftButton")
    window_frame:SetScript("OnDragStart", function() this:StartMoving() end)
    window_frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    window_frame:SetResizable(true)
    if is_start_compact then
        window_frame:SetMinResize(200, 200)
    else
        window_frame:SetMinResize(450, 300)
    end
    window_frame:SetMaxResize(1200, 900)

    -- Top-right close button [X]
    local close_btn = CreateFrame("Button", nil, window_frame, "UIPanelCloseButton")
    close_btn:SetPoint("TOPRIGHT", window_frame, "TOPRIGHT", -4, -4)
    close_btn:SetScript("OnClick", function()
        window_frame:Hide()
    end)

    -- Top-right Compact Mode toggle button [C]
    compact_btn = CreateFrame("Button", nil, window_frame, "UIPanelButtonTemplate")
    compact_btn:SetWidth(18)
    compact_btn:SetHeight(18)
    compact_btn:SetPoint("RIGHT", close_btn, "LEFT", 2, 0)
    compact_btn:SetText("C")
    compact_btn:SetScript("OnClick", function()
        toggle_compact_mode()
    end)
    compact_btn:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(L["Toggle Compact Mode"])
            GameTooltip:Show()
        end
    end)
    compact_btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Bottom-right resize grabber
    local resize_grip = CreateFrame("Button", nil, window_frame)
    resize_grip:SetWidth(16)
    resize_grip:SetHeight(16)
    resize_grip:SetPoint("BOTTOMRIGHT", window_frame, "BOTTOMRIGHT", -4, 4)
    resize_grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize_grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize_grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize_grip:SetScript("OnMouseDown", function()
        window_frame:StartSizing("BOTTOMRIGHT")
    end)
    resize_grip:SetScript("OnMouseUp", function()
        window_frame:StopMovingOrSizing()
        local cur_w = window_frame:GetWidth()
        local cur_h = window_frame:GetHeight()
        if XSocialConfig then
            if is_compact then
                XSocialConfig.compactWidth = cur_w
                XSocialConfig.compactHeight = cur_h
            else
                XSocialConfig.windowWidth = cur_w
                XSocialConfig.windowHeight = cur_h
            end
        end
    end)

    -- Build components
    create_top_bar(window_frame)
    create_roster_pane(window_frame)
    create_chat_pane(window_frame)

    -- If previously saved in compact mode, apply compact layout
    if is_start_compact then
        apply_compact_layout(true)
    end

    -- OnShow: Debounced roster request and stop HUD alert flashing
    window_frame:SetScript("OnShow", function()
        if XSocial.HUDButton and XSocial.HUDButton.stop_flash then
            XSocial.HUDButton.stop_flash()
        end
        XSocial.request_refresh()
        if not is_compact then
            refresh_top_bar()
            refresh_roster()
        end
    end)

    return main_window
end

-- ============================================================
-- Public MainWindow API
-- ============================================================

function MainWindow.create()
    return create_main_window()
end

function MainWindow.show()
    if not main_window then
        create_main_window()
    end
    main_window:Show()
end

function MainWindow.hide()
    if main_window then
        main_window:Hide()
    end
end

function MainWindow.toggle()
    if not main_window or not main_window:IsVisible() then
        MainWindow.show()
    else
        MainWindow.hide()
    end
end

function MainWindow.is_visible()
    if main_window then
        return main_window:IsVisible()
    end
    return false
end

function MainWindow.refresh()
    if not main_window or not main_window:IsVisible() then return end
    if not is_compact then
        refresh_top_bar()
        refresh_roster()
    end
end

function MainWindow.refresh_roster()
    if not is_compact then
        refresh_roster()
    end
end

function MainWindow.is_compact()
    return is_compact
end

function MainWindow.toggle_compact()
    toggle_compact_mode()
end

function MainWindow.refresh_tooltip()
    if is_compact then return end
    if GameTooltip and GameTooltip:IsVisible() then
        local i
        local count = table.getn(row_pool)
        for i = 1, count do
            local rf = row_pool[i]
            if rf and rf:IsVisible() then
                local is_hover = false
                if MouseIsOver then
                    is_hover = MouseIsOver(rf)
                elseif rf.IsMouseOver then
                    is_hover = rf:IsMouseOver()
                end
                if is_hover then
                    local on_enter = rf:GetScript("OnEnter")
                    if on_enter then
                        on_enter()
                    end
                    break
                end
            end
        end
    end
end

function MainWindow.append_chat_message(sender_name, msg_text)
    if not chat_msg_frame then
        create_main_window()
    end
    if not chat_msg_frame then return end

    local display_name = sender_name
    local p = XSocial.get_player(sender_name)
    if p and p.nick and p.nick ~= "" then
        display_name = p.nick
    end

    local timestamp = date("%H:%M")
    local formatted_line = string.format(
        "|cff888888[%s]|r |Hplayer:%s|h|cffffd100[%s]|h|r: %s",
        timestamp,
        sender_name or "",
        display_name or "",
        msg_text or ""
    )
    chat_msg_frame:AddMessage(formatted_line, 1, 1, 1)
end

-- ============================================================
-- Namespace exports & Wiring
-- ============================================================
XSocial.MainWindow = MainWindow
XSocial.open_main_window = MainWindow.show
XSocial.close_main_window = MainWindow.hide
XSocial.toggle_main_window = MainWindow.toggle
XSocial.toggle_compact_mode = MainWindow.toggle_compact
MainWindow.hook_chat_frame_editbox = hook_chat_frame_editbox
MainWindow.hook_shift_click_insert = hook_shift_click_insert

hook_shift_click_insert()
hook_chat_frame_editbox()