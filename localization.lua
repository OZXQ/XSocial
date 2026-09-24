-- localization.lua
-- All UI strings for XSocial addon
-- English text is the key; metatable auto-fills missing keys with the key itself
-- Only non-English locales need explicit overrides

XSocial = XSocial or {}

local LOCALE = GetLocale()

local L = setmetatable({}, {
    __index = function(t, k)
        local v = tostring(k)
        rawset(t, k, v)
        return v
    end
})
XSocial.L = L

if LOCALE == "zhCN" then
    L["XSocial"] = "XSocial"

    L["Members"] = "成员"
    L["Config"] = "配置"
    L["Nickname"] = "昵称"
    L["Character"] = "角色"
    L["Filter:"] = "筛选:"
    L["No online members"] = "无在线成员"
    L["Unknown"] = "未知"
    L["Inquire"] = "询问"

    L["Channel Name"] = "频道名称"
    L["Poll Interval (sec)"] = "轮询间隔 (秒)"
    L["Refresh Now"] = "立即刷新"
    L["Save"] = "保存"

    L["Channel: %s"] = "频道: %s"
    L["Nick: %s"] = "昵称: %s"
    L["Lock"] = "锁定"
    L["Unlock"] = "解锁"
    L["Locked"] = "已锁定"
    L["Unlocked"] = "已解锁"
    L["Click toon to whisper | [Inquire] to discover"] = "点击角色名私聊 | 点击[询问]获取昵称"
    L["Left-click: Chat  |  Right-click: Config"] = "左键: 频道聊天  |  右键: 打开界面"
    L["Change Channel"] = "修改频道"
    L["Change Nickname"] = "修改昵称"
    L["Set Channel"] = "设置频道"
    L["Set Nickname"] = "设置昵称"
    L["Enter new channel name:"] = "输入新频道名称:"
    L["Enter new nickname:"] = "输入新昵称:"
    L["OK"] = "确定"
    L["Cancel"] = "取消"

    L["Online: %d/%d"] = "在线: %d/%d"
    L["Online: %d"] = "在线: %d"
    L["Last poll: %s"] = "上次轮询: %s"
    L["Next poll: %d sec"] = "下次轮询: %d 秒"
    L["Refreshing..."] = "刷新中..."
    L["Total: "] = "总计: "

    L["Joined channel '%s'."] = "已加入频道 '%s'。"
    L["Left channel '%s'."] = "已离开频道 '%s'。"
    L["Failed to join channel '%s'."] = "加入频道 '%s' 失败。"
    L["Channel not joined."] = "未加入频道。"
    L["Updating roster..."] = "正在更新在线名单..."
    L["Roster updated: %d members online."] = "在线名单已更新: %d 人在线。"
    L["Nickname saved as '%s'."] = "昵称已保存为 '%s'。"
    L["Configuration saved."] = "配置已保存。"

    L["Nickname cannot be empty."] = "昵称不能为空。"
    L["Nickname must be 1-24 bytes."] = "昵称长度须为 1-24 个字节。"
    L["Nickname cannot contain '#' or '|'."] = "昵称不能包含 '#' 或 '|'。"
    L["Channel name cannot be empty."] = "频道名称不能为空。"
    L["Channel name contains invalid characters."] = "频道名称包含无效字符。"
    L["Poll interval must be at least 60 seconds."] = "轮询间隔至少需要 60 秒。"

    L["Channel is full."] = "频道已满。"
    L["You are banned from the channel."] = "你已被该频道封禁。"
    L["Channel throttled, please wait."] = "频道消息被限制，请稍候。"

    L["Note"] = "备注"
    L["Note: %s"] = "备注: %s"
    L["Change Note"] = "修改备注"
    L["Set Note"] = "设置备注"
    L["Enter new note:"] = "输入新备注:"
    L["Note saved."] = "备注已保存。"
    L["Note cannot contain '#' or '|'."] = "备注不能包含 '#' 或 '|'。"
    L["Note must be 0-128 bytes."] = "备注长度不能超过 128 个字节。"

    L["Level / Class"] = "等级 / 职业"
    L["Level / Class: %s"] = "等级 / 职业: %s"
    L["Location"] = "位置"
    L["Location: %s"] = "位置: %s"
    L["Refresh"] = "刷新"
    L["Send"] = "发送"
    L["Type message in #%s..."] = "在 #%s 中发送消息..."
    L["Left-click: Toggle Window  |  Right-click: Drag"] = "左键: 打开/关闭界面  |  右键: 拖动"
    L["Toggle Compact Mode"] = "切换极简模式"
    L["Click to invite"] = "点击邀请"
end
