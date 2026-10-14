--[[
    CyberTrials - Shared UI Helpers
    ---------------------------------------------------------------------------
    Resolution-aware scaling, icon helpers, and common ImGui utilities.
    Used by the overlay window and any other UI modules.
]]

local uiHelpers = {}

-- Cached display resolution (updated each frame when needed)
uiHelpers.res = { x = 1920, y = 1080 }

--- Refresh the cached resolution from the game / ImGui IO.
function uiHelpers.updateResolution()
    local ok, w, h = pcall(function()
        local io = ImGui.GetIO()
        if io and io.DisplaySize then
            return io.DisplaySize.x, io.DisplaySize.y
        end
        return nil, nil
    end)
    if ok and w and h and w > 0 and h > 0 then
        uiHelpers.res.x = w
        uiHelpers.res.y = h
    end
end

--- Scale a value relative to a 1920x1080 reference design.
--- Prefer the smaller axis so UI stays usable on ultrawide / portrait.
function uiHelpers.scale(value)
    local sx = uiHelpers.res.x / 1920
    local sy = uiHelpers.res.y / 1080
    return value * math.min(sx, sy)
end

--- Scale only against horizontal resolution.
function uiHelpers.scaleX(value)
    return value * (uiHelpers.res.x / 1920)
end

--- Scale only against vertical resolution.
function uiHelpers.scaleY(value)
    return value * (uiHelpers.res.y / 1080)
end

--- Safe icon glyph lookup (CET provides IconGlyphs globally).
function uiHelpers.icon(name)
    if IconGlyphs and IconGlyphs[name] then
        return IconGlyphs[name]
    end
    return ""
end

--- Build a selectable label that shows icon only when the bar is narrow,
--- or icon + name when wide enough.
function uiHelpers.tabLabel(iconName, displayName, barWidth)
    local glyph = uiHelpers.icon(iconName)
    local minForText = uiHelpers.scale(90)
    if barWidth >= minForText and displayName and displayName ~= "" then
        return glyph .. "  " .. displayName
    end
    return glyph
end

--- Draw a horizontal separator with optional light spacing.
function uiHelpers.sectionHeader(text)
    ImGui.Spacing()
    ImGui.TextColored(0.85, 0.75, 0.35, 1.0, text)
    ImGui.Separator()
    ImGui.Spacing()
end

return uiHelpers
