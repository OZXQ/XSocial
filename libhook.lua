-- OzHook: lightweight hook library for WoW 1.12
--
-- One API for global functions, methods, and frame scripts.
-- Everything goes through: wrapper → pre → original → post.
-- Auto-detects scripts (obj has GetScript, name starts with "On", no table method).
--
-- API:
--   OzHook:hook(target, preFn [, postFn])
--     preFn  — runs before original. return false to cancel. nil to skip.
--     postFn — runs after original. nil to skip.
--   OzHook:unhook(target, fn)  — remove fn from pre or post list. restores original if empty.

local MAJOR = "OzHook-1.0"
local MINOR = 1

if OzHook and OzHook.version and OzHook.version >= MINOR then
    return
end

OzHook = OzHook or {}
OzHook.version = MINOR
OzHook._registry = OzHook._registry or {}

local _G = getfenv(0)

local function isScriptTarget(obj, name)
    return type(obj) == "table"
        and type(obj.GetScript) == "function"
        and type(name) == "string"
        and string.sub(name, 1, 2) == "On"
        and obj[name] == nil
end

local function getOrig(obj, name)
    if obj == nil then return _G[name] end
    if type(obj) == "string" then return _G[obj] end
    if isScriptTarget(obj, name) then return obj:GetScript(name) end
    return obj[name]
end

local function installHook(obj, name, fn)
    if obj == nil then
        _G[name] = fn
    elseif type(obj) == "string" then
        _G[obj] = fn
    elseif isScriptTarget(obj, name) then
        obj:SetScript(name, fn)
    else
        obj[name] = fn
    end
end

local function regKey(obj, name)
    if obj == nil then
        return "_G:" .. name
    end
    if type(obj) == "string" then
        return "_G:" .. obj
    end
    return obj
end

local function createWrapper(entry)
    local orig = entry.orig

    return function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                    a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
        -- Prevent recursive hook execution
        if entry.running then
            return orig(
                a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                a11, a12, a13, a14, a15, a16, a17, a18, a19, a20
            )
        end

        entry.running = true

        -- Current argument list (may be replaced by pre-hooks)
        local args = {
            a1, a2, a3, a4, a5,
            a6, a7, a8, a9, a10,
            a11, a12, a13, a14, a15,
            a16, a17, a18, a19, a20
        }

        ----------------------------------------------------------------
        -- Pre hooks
        -- return false      -> cancel original call
        -- return nil        -> leave arguments unchanged
        -- return (...)      -> replace arguments
        ----------------------------------------------------------------
        for _, fn in ipairs(entry.pre) do
            local ret = { fn(unpack(args)) }

            if ret[1] == false then
                entry.running = nil
                return
            end

            if ret[1] ~= nil then
                args = ret
            end
        end

        ----------------------------------------------------------------
        -- Original function
        ----------------------------------------------------------------
        local results = {
            orig(unpack(args))
        }

        ----------------------------------------------------------------
        -- Post hooks
        -- Receive the final arguments (same API as before)
        ----------------------------------------------------------------
        for _, fn in ipairs(entry.post) do
            fn(unpack(args))
        end

        entry.running = nil

        return unpack(results)
    end
end

local function ensureHooked(obj, name)
    local k = regKey(obj, name)
    if not OzHook._registry[k] then OzHook._registry[k] = {} end
    local entry = OzHook._registry[k][name]
    if entry then return entry end

    local orig = getOrig(obj, name)
    local isScript = isScriptTarget(obj, name)

    if not isScript and orig == nil then
        error("[OzHook] " .. tostring(name) .. " is not a function (got nil)", 2)
    end

    entry = {
        owner = obj,
        name  = name,
        orig  = orig or function() end,
        pre   = {},
        post  = {},
    }
    entry.wrapper = createWrapper(entry)
    installHook(obj, name, entry.wrapper)
    OzHook._registry[k][name] = entry
    return entry
end

local function hasFn(list, fn)
    for _, f in ipairs(list) do
        if f == fn then return true end
    end
    return false
end

-- OzHook:hook("ChatFrame_OnEvent", preFn)
-- OzHook:hook("ChatFrame_OnEvent", preFn, postFn)
-- OzHook:hook("ChatFrame_OnEvent", nil, postFn)
-- OzHook:hook(GameTooltip, "AddMessage", preFn)
-- OzHook:hook(frame, "OnShow", preFn, postFn)
function OzHook:hook(obj, name, preFn, postFn)
    if type(obj) == "string" then
        obj, name, preFn, postFn = nil, obj, name, preFn
    end
    local entry = ensureHooked(obj, name)
    if preFn and not hasFn(entry.pre, preFn) then
        table.insert(entry.pre, preFn)
    end
    if postFn and not hasFn(entry.post, postFn) then
        table.insert(entry.post, postFn)
    end
end

-- Remove fn from pre or post list. Restores original and cleans up registry when empty.
-- OzHook:unhook("ChatFrame_OnEvent", fn)
-- OzHook:unhook(GameTooltip, "AddMessage", fn)
function OzHook:unhook(obj, name, fn)
    if type(obj) == "string" then
        fn = name
        name = obj
        obj = nil
    end
    local k = regKey(obj, name)
    local entry = OzHook._registry[k] and OzHook._registry[k][name]
    if not entry then return end

    for i, f in ipairs(entry.pre) do
        if f == fn then
            table.remove(entry.pre, i); break
        end
    end
    for i, f in ipairs(entry.post) do
        if f == fn then
            table.remove(entry.post, i); break
        end
    end

    if not next(entry.pre) and not next(entry.post) then
        installHook(obj, name, entry.orig)
        OzHook._registry[k][name] = nil
        if not next(OzHook._registry[k]) then
            OzHook._registry[k] = nil
        end
    end
end

-- Restore all originals and clear the registry.
function OzHook:unhookAll()
    for _, methods in pairs(OzHook._registry) do
        for _, entry in pairs(methods) do
            installHook(entry.owner, entry.name, entry.orig)
        end
    end
    OzHook._registry = {}
end

-- Check if a target is hooked, or if a specific fn is registered.
-- OzHook:isHooked("ChatFrame_OnEvent")           — true if any hook exists
-- OzHook:isHooked("ChatFrame_OnEvent", fn)       — true if fn is in pre or post list
-- OzHook:isHooked(GameTooltip, "AddMessage")
-- OzHook:isHooked(frame, "OnShow")
function OzHook:isHooked(obj, name, fn)
    if type(obj) == "string" then
        fn = name
        name = obj
        obj = nil
    end
    local k = regKey(obj, name)
    local entry = OzHook._registry[k] and OzHook._registry[k][name]
    if not entry then return false end
    if not fn then return true end
    return hasFn(entry.pre, fn) or hasFn(entry.post, fn)
end
