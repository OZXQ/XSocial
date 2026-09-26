-- HUDButton.lua
-- Floating rectangular HUD status button for XSocial
-- Displays: <ChannelName> | <TotalCount>
-- Left-Click: Toggle Main Window
-- Right-Click and Drag: Move HUD button
-- Flashing alert: Flashes red on new incoming channel chat messages
-- Strictly Lua 5.0, Vanilla WoW 1.12 API only

local XSocial = XSocial or {}
local L = XSocial.L

-- ============================================================
-- Module state
-- ============================================================
local hud_frame = nil
local hud_text = nil
local is_flashing = false
local flash_timer = 0
local flash_state = false

-- ============================================================
-- Forward declarations
-- ============================================================
local create_hud_button = nil
local update_hud_display = nil
local save_hud_position = nil
local restore_hud_position = nil
local update_lock_visuals = nil

-- Public namespace declarations
local HUDButton = {}
HUDButton.create = nil
HUDButton.update = nil
HUDButton.show = nil
HUDButton.hide = nil
HUDButton.is_visible = nil
HUDButton.set_locked = nil
HUDButton.start_flash = nil
HUDButton.stop_flash = nil
HUDButton.is_flashing = nil

-- ============================================================
-- Helper: Localized UI Font (adapts to zhCN / client font)
-- ============================================================
local function get_ui_font(size)
    if XSocial and XSocial.get_ui_font then
        return XSocial.get_ui_font(size)
    end
    if GameFontNormal and GameFontNormal.GetFont then
        return GameFontNormal:GetFont(), (size or 11)
    end
    return "Fonts\\FRIZQT__.TTF", (size or 11)
end

-- ============================================================
-- Local helper implementations
-- ============================================================

restore_hud_position = function()
    if not hud_frame then return end
    local config_data = XSocial.get_config() or {}
    local saved_pos = config_data.buttonPos

    hud_frame:ClearAllPoints()
    if type(saved_pos) == "table" and saved_pos.point then
        hud_frame:SetPoint(
            saved_pos.point,
            UIParent,
            saved_pos.relPoint or saved_pos.point,
            tonumber(saved_pos.x) or 0,
            tonumber(saved_pos.y) or 0
        )
    else
        hud_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

save_hud_position = function()
    if not hud_frame then return end
    local point_val, rel_to, rel_point_val, x_val, y_val = hud_frame:GetPoint(1)
    if not point_val then
        point_val, rel_to, rel_point_val, x_val, y_val = hud_frame:GetPoint()
    end
    local config_data = XSocial.get_config()
    if config_data then
        config_data.buttonPos = {
            point    = point_val or "CENTER",
            relPoint = rel_point_val or point_val or "CENTER",
            x        = math.floor((x_val or 0) + 0.5),
            y        = math.floor((y_val or 0) + 0.5),
        }
    end
end

update_lock_visuals = function()
    if not hud_frame or is_flashing then return end
    hud_frame:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
    hud_frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
end

update_hud_display = function()
    if not hud_frame or not hud_text then return end

    local channel_name = XSocial.get_channel() or "xsocial"
    local total_count = XSocial.get_total_count() or 0

    local display_str = string.format("%s | %d", tostring(channel_name), tonumber(total_count) or 0)
    hud_text:SetText(display_str)

    -- Dynamically adjust width to fit text comfortably with padding (handles CJK byte length safely)
    local text_width = hud_text:GetStringWidth() or 60
    local approx_len_width = string.len(display_str) * 8
    if approx_len_width > text_width then
        text_width = approx_len_width
    end
    hud_frame:SetWidth(math.max(85, math.floor(text_width + 18)))

    update_lock_visuals()
end

create_hud_button = function()
    if hud_frame then return hud_frame end

    -- Safe dimensions: Height 24, edgeSize 8 leaves positive center area (24 - 16 = 8)
    local frame_widget = CreateFrame("Frame", "XSocialHUDButton", UIParent)
    frame_widget:SetWidth(80)
    frame_widget:SetHeight(24)
    frame_widget:SetFrameStrata("MEDIUM")
    frame_widget:SetMovable(true)
    frame_widget:EnableMouse(true)
    frame_widget:RegisterForDrag("RightButton")

    -- Sleek semi-transparent dark backdrop
    frame_widget:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame_widget:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
    frame_widget:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Status label
    local label_text = frame_widget:CreateFontString(nil, "OVERLAY")
    label_text:SetFont(get_ui_font(11))
    label_text:SetTextColor(1, 1, 1, 0.95)
    label_text:SetPoint("CENTER", frame_widget, "CENTER", 0, 0)
    hud_text = label_text

    hud_frame = frame_widget
    restore_hud_position()

    -- Clamp to screen safely after valid coordinates are established
    if frame_widget.SetClampedToScreen then
        frame_widget:SetClampedToScreen(true)
    end

    -- MouseUp: Left-Click toggles Main Window
    frame_widget:SetScript("OnMouseUp", function()
        if frame_widget._is_dragging then
            frame_widget._is_dragging = nil
            return
        end
        if arg1 == "LeftButton" then
            if is_flashing then
                HUDButton.stop_flash()
            end
            if XSocial.toggle_main_window then
                XSocial.toggle_main_window()
            end
        end
    end)

    -- Right-Click and Drag to move
    frame_widget:SetScript("OnDragStart", function()
        frame_widget._is_dragging = true
        this:StartMoving()
    end)

    frame_widget:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        save_hud_position()
        frame_widget._is_dragging = nil
    end)

    -- Flashing animation handler
    frame_widget:SetScript("OnUpdate", function()
        if is_flashing then
            local dt = arg1 or 0.05
            flash_timer = flash_timer + dt
            if flash_timer >= 0.5 then
                flash_timer = 0
                flash_state = not flash_state
                if flash_state then
                    frame_widget:SetBackdropColor(0.8, 0.1, 0.1, 0.85)
                    frame_widget:SetBackdropBorderColor(1.0, 0.2, 0.2, 1.0)
                else
                    frame_widget:SetBackdropColor(0.05, 0.05, 0.05, 0.2)
                    frame_widget:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.2)
                end
            end
        end
    end)

    -- Hover tooltip
    frame_widget:SetScript("OnEnter", function()
        if not is_flashing then
            frame_widget:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        end
        if GameTooltip then
            GameTooltip:SetOwner(frame_widget, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:SetText(L["XSocial"])

            local chan_name = XSocial.get_channel() or "xsocial"
            local total_count = XSocial.get_total_count() or 0

            GameTooltip:AddLine(string.format(L["Channel: %s"], tostring(chan_name)), 1, 0.82, 0)
            GameTooltip:AddLine(string.format(L["Online: %d"], tonumber(total_count) or 0), 0.9, 0.9, 0.9)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Left-click: Toggle Window  |  Right-click: Drag"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)

    frame_widget:SetScript("OnLeave", function()
        if not is_flashing then
            frame_widget:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
            update_lock_visuals()
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    update_hud_display()
    frame_widget:Show()

    return frame_widget
end

-- ============================================================
-- Public HUDButton API
-- ============================================================

function HUDButton.create()
    return create_hud_button()
end

function HUDButton.update()
    update_hud_display()
end

function HUDButton.set_locked(is_locked)
    local config_data = XSocial.get_config()
    config_data.locked = is_locked
    update_lock_visuals()
end

function HUDButton.start_flash()
    is_flashing = true
    flash_timer = 0
    flash_state = false
end

function HUDButton.stop_flash()
    is_flashing = false
    flash_timer = 0
    flash_state = false
    if hud_frame then
        hud_frame:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
        hud_frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    end
end

function HUDButton.is_flashing()
    return is_flashing
end

function HUDButton.show()
    if hud_frame then
        hud_frame:Show()
    end
end

function HUDButton.hide()
    if hud_frame then
        hud_frame:Hide()
    end
end

function HUDButton.is_visible()
    if hud_frame then
        return hud_frame:IsVisible()
    end
    return false
end

-- ============================================================
-- Namespace exports
-- ============================================================
XSocial.HUDButton = HUDButton
XSocial._create_icon = HUDButton.create
XSocial._update_icon = HUDButton.update
