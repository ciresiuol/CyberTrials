--[[
    CyberTrials - Native Settings Menu Pages Module
    ---------------------------------------------------------------------------
    Controls which group of options ("page") is visible inside the CyberTrials
    Native Settings tab by using a single string-list selector.

    References:
      - Native Settings README:
          https://github.com/justarandomguyintheinternet/CP77_nativeSettings
      - addSelectorString / removeSubcategory / refresh API (same README)
      - SettingsMainGameController:
          https://nativedb.red4ext.com/SettingsMainGameController

    Design:
      1. A "Navigation" subcategory holds one addSelectorString widget whose
         elements are the page names (Race, Audio, Traffic, …).
      2. Changing the selector clears content subcategories and rebuilds only
         the options that belong to the newly selected page.
      3. Host code registers each page via a build() callback that adds its
         own subcategories/options and calls trackContentPath() for cleanup.
]]

local nativeTabBar = {}

--- @class PageDef
--- @field id string           Unique page id (used as subcategory path suffix)
--- @field label string        Display name in the selector list
--- @field build fun()         Host callback that adds this page's options

local state = {
    nativeSettings = nil,   -- GetMod("nativeSettings")
    tabPath = nil,          -- e.g. "/CyberTrials"
    navSubcat = nil,        -- e.g. "/CyberTrials/Nav"
    contentPrefix = nil,    -- e.g. "/CyberTrials/Tab_"
    pages = {},             -- array of PageDef
    pageNames = {},         -- string list for addSelectorString
    activeIndex = 1,
    contentPaths = {},      -- subcategories currently owned by the active page
    selectorOption = nil,   -- table returned by addSelectorString
    ready = false,
}

-- ---------------------------------------------------------------------------
-- Content lifecycle
-- ---------------------------------------------------------------------------

local function clearContent()
    if not state.nativeSettings then return end
    for _, path in ipairs(state.contentPaths) do
        pcall(function() state.nativeSettings.removeSubcategory(path) end)
    end
    state.contentPaths = {}
end

--- Register a content subcategory path so it can be torn down on page switch.
function nativeTabBar.trackContentPath(path)
    if type(path) == "string" and path ~= "" then
        table.insert(state.contentPaths, path)
    end
end

--- Convenience: build a unique content subcategory path for the active page.
function nativeTabBar.contentPath(suffix)
    local page = state.pages[state.activeIndex]
    local id = (page and page.id) or "content"
    return (state.contentPrefix or "/CyberTrials/Tab_") .. id .. "_" .. tostring(suffix or "main")
end

local function rebuildContent()
    clearContent()
    local page = state.pages[state.activeIndex]
    if page and type(page.build) == "function" then
        page.build()
    end
    if state.nativeSettings and state.nativeSettings.refresh then
        state.nativeSettings.refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Navigation (selector string)
-- ---------------------------------------------------------------------------

local function rebuildNav()
    if not state.nativeSettings or not state.navSubcat then return end

    -- Drop previous selector if we are rebuilding
    if state.selectorOption then
        pcall(function() state.nativeSettings.removeOption(state.selectorOption) end)
        state.selectorOption = nil
    end

    -- Ensure navigation subcategory exists
    pcall(function()
        state.nativeSettings.addSubcategory(state.navSubcat, "Menu Page")
    end)

    -- Build the display name list for the selector
    state.pageNames = {}
    for _, page in ipairs(state.pages) do
        table.insert(state.pageNames, page.label or page.id or "Page")
    end
    if #state.pageNames == 0 then
        state.pageNames = { "None" }
    end

    if state.activeIndex < 1 or state.activeIndex > #state.pageNames then
        state.activeIndex = 1
    end

    -- Single selector string cycles between menu pages
    -- API: addSelectorString(path, label, desc, elements, currentValue, defaultValue, callback)
    state.selectorOption = state.nativeSettings.addSelectorString(
        state.navSubcat,
        "Page",
        "Choose which settings page to view.",
        state.pageNames,
        state.activeIndex,
        1,
        function(value)
            local idx = tonumber(value) or 1
            if idx < 1 then idx = 1 end
            if idx > #state.pages then idx = #state.pages end
            if state.activeIndex == idx then return end
            state.activeIndex = idx
            rebuildContent()
        end
    )
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Initialize the page selector host.
--- @param nativeSettings table  GetMod("nativeSettings")
--- @param tabPath string        Root tab path, e.g. "/CyberTrials"
--- @param pages PageDef[]       Ordered list of page definitions
--- @param startIndex number|nil Optional initial page (default 1)
function nativeTabBar.setup(nativeSettings, tabPath, pages, startIndex)
    state.nativeSettings = nativeSettings
    state.tabPath = tabPath
    state.navSubcat = tabPath .. "/Nav"
    state.contentPrefix = tabPath .. "/Tab_"
    state.pages = pages or {}
    state.activeIndex = startIndex or 1
    if state.activeIndex < 1 or state.activeIndex > #state.pages then
        state.activeIndex = 1
    end
    state.contentPaths = {}
    state.selectorOption = nil
    state.ready = nativeSettings ~= nil and type(pages) == "table" and #pages > 0

    if not state.ready then
        print("CyberTrials nativeTabBar: setup skipped (missing nativeSettings or pages)")
        return false
    end

    rebuildNav()
    rebuildContent()
    return true
end

--- Force a full rebuild of the active page content (e.g. after data changes).
--- Does not recreate the page selector itself.
function nativeTabBar.refresh()
    if not state.ready then return end
    rebuildContent()
end

--- Switch to a page by id or 1-based index.
function nativeTabBar.select(idOrIndex)
    if not state.ready then return end
    local idx = nil
    if type(idOrIndex) == "number" then
        idx = idOrIndex
    elseif type(idOrIndex) == "string" then
        for i, page in ipairs(state.pages) do
            if page.id == idOrIndex then
                idx = i
                break
            end
        end
    end
    if not idx or idx < 1 or idx > #state.pages then return end
    if state.activeIndex == idx then return end
    state.activeIndex = idx

    -- Keep the selector widget in sync when changed programmatically
    if state.selectorOption and state.nativeSettings.setOption then
        pcall(function()
            state.nativeSettings.setOption(state.selectorOption, state.activeIndex)
        end)
    end

    rebuildContent()
end

function nativeTabBar.getActiveId()
    local page = state.pages[state.activeIndex]
    return page and page.id or nil
end

function nativeTabBar.isReady()
    return state.ready
end

return nativeTabBar
