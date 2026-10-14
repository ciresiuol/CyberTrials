--[[
    CyberTrials - Overlay Window (sidebar tab layout)
    ---------------------------------------------------------------------------
    Resolution-aware ImGui overlay with a resizable left tab bar.
    Tab bar can shrink to icon-only or expand to show icon + name.
    No custom window themes – uses default CET/ImGui styling.
]]

local messages   = require("modules/utils/messages")
local trackEditor = require("modules/editor/trackEditor")
local uiHelpers  = require("modules/ui/uiHelpers")

local editorWindow = {}

-- ---------------------------------------------------------------------------
-- Persistent UI state (survives between frames)
-- ---------------------------------------------------------------------------
local selectedTab        = 1
local tabBarWidth        = 160
local tabBarWidthPercent = 0.12
local draggingSplitter   = false
local isHoveringSplitter = false
local nameBuffer         = ""
local nameErrorMessage   = ""

local TABS = {
    { id = "race",    name = "Race Settings", icon = "FlagCheckered" },
    { id = "times",   name = "Best Times",    icon = "Trophy" },
    { id = "teleport",name = "Teleport",      icon = "MapMarkerPath" },
    { id = "editor",  name = "Track Editor",  icon = "Pencil" },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function FilterInput(input)
    local filtered = ""
    local invalidCharFound = false
    for i = 1, #input do
        local char = input:sub(i, i)
        if char:match("[a-zA-Z ]") then
            filtered = filtered .. char
        else
            invalidCharFound = true
        end
    end
    return filtered, invalidCharFound
end

local function endActiveRace(ctx)
    if not ctx.raceLogic or not ctx.raceLogic.raceInProgress then return end
    ctx.raceLogic.despawnAllCheckpoints()
    if Game.GetJournalManager() and not Game.GetJournalManager():GetTrackedEntry()
       and ctx.raceLogic.trackedJournalEntry then
        Game.GetJournalManager():TrackEntry(ctx.raceLogic.trackedJournalEntry)
        ctx.raceLogic.trackedJournalEntry = nil
    end
    if ctx.currentMappin then
        Game.GetMappinSystem():UnregisterMappin(ctx.currentMappin)
        ctx.currentMappin = nil
    end
    ctx.raceLogic.endActiveRaceQuick()
end

local function fmtTime(entry)
    if not entry then return "--:--.---" end
    local m = entry.min or 0
    local s = entry.sec or 0
    local ms = entry.milliSecs or 0
    return string.format("%02d:%02d.%03d", m, s, ms)
end

-- Collect run entries from either the new {runs=...} structure or a legacy array
local function getRunsForTrack(recentTimes, trackName)
    local entry = recentTimes and recentTimes[trackName]
    if type(entry) ~= "table" then return {} end
    if entry.runs then return entry.runs end
    if entry[1] then return entry end
    return {}
end

-- ---------------------------------------------------------------------------
-- Tab content drawers
-- ---------------------------------------------------------------------------

local function drawRaceSettings(ctx)
    uiHelpers.sectionHeader(uiHelpers.icon("Cog") .. "  Race Options")

    if ImGui.Button(uiHelpers.icon("FlagOff") .. "  End Active Race") then
        endActiveRace(ctx)
    end
    ImGui.Spacing()

    local changed
    ctx.user.settings.cashReward, changed = ImGui.Checkbox("Reward Eddies for finishing races", ctx.user.settings.cashReward)
    if changed then ctx.SaveSettings() end

    ctx.user.settings.checkpointAudio, changed = ImGui.Checkbox("Checkpoint sound effects", ctx.user.settings.checkpointAudio)
    if changed then ctx.SaveSettings() end

    if ctx.user.settings.checkpointAudio then
        ImGui.SetNextItemWidth(uiHelpers.scale(220))
        if ImGui.BeginCombo("Checkpoint Sound", ctx.selectedCpSound) then
            for i, sound in ipairs(ctx.nativeCpSounds) do
                if ImGui.Selectable(sound, sound == ctx.selectedCpSound) then
                    ctx.setSelectedCpSound(sound, i)
                end
            end
            ImGui.EndCombo()
        end
    end

    ctx.user.settings.disableTraffic, changed = ImGui.Checkbox("Stop traffic spawns during races", ctx.user.settings.disableTraffic)
    if changed then ctx.SaveSettings() end

    do
        local trafficStopped = false
        pcall(function() trafficStopped = GameOptions.GetBool("Traffic", "StopSpawn") end)
        local newVal, tChanged = ImGui.Checkbox("Traffic stopped (live)", trafficStopped)
        if tChanged then
            GameOptions.SetBool("Traffic", "StopSpawn", newVal)
        end
    end

    ctx.user.settings.backToStartOnFinish, changed = ImGui.Checkbox("Return to start line on finish", ctx.user.settings.backToStartOnFinish)
    if changed then ctx.SaveSettings() end

    ctx.user.settings.useSpeedbreaker, changed = ImGui.Checkbox("Speedbreaker (time dilation) in races", ctx.user.settings.useSpeedbreaker)
    if changed then ctx.SaveSettings() end

    ImGui.SetNextItemWidth(uiHelpers.scale(200))
    ctx.user.settings.lapCountMult, changed = ImGui.SliderFloat("Laps multiplier", ctx.user.settings.lapCountMult, 0.1, 10.0, "%.1f")
    if changed then ctx.SaveSettings() end

    ctx.user.settings.trackLeadMapPin, changed = ImGui.Checkbox("Track-lead marker for checkpoints", ctx.user.settings.trackLeadMapPin)
    if changed then ctx.SaveSettings() end

    if ctx.user.settings.trackLeadMapPin then
        ImGui.SetNextItemWidth(uiHelpers.scale(180))
        ctx.user.settings.leadMarkerCP, changed = ImGui.SliderInt("Marker target CP", ctx.user.settings.leadMarkerCP, 1, 3)
        if changed then ctx.SaveSettings() end
        ImGui.SetNextItemWidth(uiHelpers.scale(180))
        ctx.user.settings.leadMarkerDistance, changed = ImGui.SliderInt("Marker distance (m)", ctx.user.settings.leadMarkerDistance, 20, 50)
        if changed then ctx.SaveSettings() end
    end
end

local function drawBestTimes(ctx)
    uiHelpers.sectionHeader(uiHelpers.icon("Trophy") .. "  Best Race Times")

    ImGui.SetNextItemWidth(uiHelpers.scale(240))
    if ImGui.BeginCombo("##SelectVehicle", ctx.selectedVehicleName or "Select vehicle") then
        for _, vehicleName in ipairs(ctx.vehicleNames or {}) do
            if ImGui.Selectable(vehicleName, vehicleName == ctx.selectedVehicleName) then
                ctx.setSelectedVehicleName(vehicleName)
            end
        end
        ImGui.EndCombo()
    end

    ImGui.SetNextItemWidth(uiHelpers.scale(240))
    if ImGui.BeginCombo("##SelectTrack", ctx.selectedTrackName or "Select track") then
        for _, trackName in ipairs(ctx.raceNames or {}) do
            if ImGui.Selectable(trackName, trackName == ctx.selectedTrackName) then
                ctx.setSelectedTrackName(trackName)
            end
        end
        ImGui.EndCombo()
    end

    ImGui.Spacing()

    local recent = ctx.user.recentTimes or {}
    local rows = {}

    if ctx.selectedTrackName and ctx.selectedTrackName ~= "" then
        local runs = getRunsForTrack(recent, ctx.selectedTrackName)
        if #runs > 0 then
            for i, r in ipairs(runs) do
                rows[#rows + 1] = {
                    rank = i,
                    time = fmtTime(r),
                    vehicle = tostring(r.currentVehicle or r.vehicle or "Unknown"):gsub("Vehicle%.", ""),
                }
            end
        else
            local i = 0
            for _, race in pairs(recent) do
                if type(race) == "table" and (race.trackName == ctx.selectedTrackName) then
                    i = i + 1
                    rows[#rows + 1] = {
                        rank = i,
                        time = fmtTime(race),
                        vehicle = tostring(race.currentVehicle or "Unknown"):gsub("Vehicle%.", ""),
                    }
                end
            end
        end
    elseif ctx.selectedVehicleName and ctx.selectedVehicleName ~= "" then
        for _, race in pairs(recent) do
            if type(race) == "table" then
                local vname = tostring(race.currentVehicle or ""):gsub("Vehicle%.", "")
                if vname == ctx.selectedVehicleName then
                    rows[#rows + 1] = {
                        rank = #rows + 1,
                        time = fmtTime(race),
                        vehicle = race.trackName or "?",
                    }
                end
            end
        end
    end

    if #rows == 0 then
        ImGui.TextDisabled("No times to display. Finish a race first.")
        return
    end

    if ImGui.BeginTable("BestTimesTable", 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
        ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, uiHelpers.scale(40))
        ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Vehicle / Track", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableHeadersRow()
        for _, row in ipairs(rows) do
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            ImGui.Text(tostring(row.rank))
            ImGui.TableSetColumnIndex(1)
            ImGui.Text(row.time)
            ImGui.TableSetColumnIndex(2)
            ImGui.Text(row.vehicle)
        end
        ImGui.EndTable()
    end
end

local function drawTeleport(ctx)
    uiHelpers.sectionHeader(uiHelpers.icon("MapMarkerPath") .. "  Teleport to Races")

    ImGui.TextWrapped(
        "Exit your vehicle first. Teleports you to the race hub and places your last vehicle on the start line. "
        .. "Resets any previous race progress. Traffic is stopped if that setting is enabled."
    )
    ImGui.Spacing()

    local races = ctx.timeTrials.availableRaces or {}
    if #races == 0 then
        ImGui.TextDisabled("No races available.")
        return
    end

    for index, race in ipairs(races) do
        local label = string.format("%d.  %s", index, tostring(race.name or "Unnamed"))
        if ImGui.Button(label) then
            local inVehicle = Game.GetPlayer() and Game.GetPlayer().mountedVehicle ~= nil
            if inVehicle then
                messages.ShowWarningMessage("Please exit your vehicle before teleporting to races.", 3.0)
            elseif ctx.TeleportToRace then
                ctx.TeleportToRace(race)
            else
                messages.ShowWarningMessage("Teleport helper unavailable.", 3.0)
            end
        end
    end
end

local function drawTrackEditor(ctx)
    local td = ctx.timeTrials.trackData
    local windowWidth = ImGui.GetContentRegionAvail()

    uiHelpers.sectionHeader(uiHelpers.icon("Import") .. "  Import / Export")

    ImGui.SetNextItemWidth(math.min(windowWidth * 0.7, uiHelpers.scale(280)))
    if ImGui.BeginCombo("##SelectTrackImport", "Select saved track to import") then
        ctx.listTrackFiles()
        local currentItem = td.name
        for _, file in ipairs(ctx.trackFiles or {}) do
            if file and ImGui.Selectable(file, file == currentItem) then
                td.name = file
            end
        end
        ImGui.EndCombo()
    end

    nameBuffer = td.name or ""
    ImGui.SetNextItemWidth(math.min(windowWidth * 0.7, uiHelpers.scale(280)))
    local newName, nameChanged = ImGui.InputText("Track name for export", nameBuffer, 50)
    if nameChanged then
        local filtered, invalid = FilterInput(newName)
        td.name = filtered
        nameErrorMessage = invalid and "Special characters removed from track name." or ""
    end
    if nameErrorMessage ~= "" then
        ImGui.TextColored(1, 0.4, 0.3, 1, nameErrorMessage)
    end

    if ImGui.Button(uiHelpers.icon("Download") .. "  Import Track") then
        ctx.importTrackData()
    end
    ImGui.SameLine()
    if ImGui.Button(uiHelpers.icon("Pencil") .. "  Start Editing") then
        ctx.timeTrials.runtimeData.inEditor = true
        trackEditor.readyToPlace = true
    end

    if ImGui.Button(uiHelpers.icon("Upload") .. "  Export Track") then
        ctx.exportTrackData()
        ctx.listTrackFiles()
    end
    ImGui.SameLine()
    if ImGui.Button(uiHelpers.icon("Stop") .. "  Stop Editing") then
        trackEditor.deleteEverything(trackEditor, td)
        ctx.timeTrials.trackData = {
            name = "",
            description = "",
            numberOfLaps = 1,
            checkpoints = {},
            checkpointEnts = {},
            totalCheckpoints = 0,
            hubPosition = {},
            startPosition = {},
            props = {},
            propEnts = {},
            totalProps = 0,
            creator = "CyberTrials Editor",
        }
        ctx.timeTrials.runtimeData.inEditor = false
        trackEditor.readyToPlace = false
        trackEditor.resetPlacementFlags(trackEditor)
    end

    if not trackEditor.readyToPlace then
        ImGui.Spacing()
        ImGui.TextDisabled("Import a track (or create a new one) and press Start Editing.")
        return
    end

    -- ---- Active editor controls ----
    ImGui.Spacing()
    uiHelpers.sectionHeader(uiHelpers.icon("Information") .. "  Track Info")

    local descBuffer = tostring(td.description or "")
    td.description = ImGui.InputTextMultiline("##Description", descBuffer, 150, uiHelpers.scale(260), uiHelpers.scale(60))
    ImGui.TextDisabled(string.format("%d / 150 characters", #tostring(td.description or "")))

    local creatorBuffer = tostring(td.creator or "")
    td.creator = ImGui.InputText("Creator name", creatorBuffer, 40)

    ImGui.SetNextItemWidth(uiHelpers.scale(180))
    local lapsChanged
    td.numberOfLaps, lapsChanged = ImGui.SliderInt("Number of laps", td.numberOfLaps or 1, 1, 20)

    ImGui.TextWrapped(
        "Single-lap: start at the start line, finish at the last checkpoint.\n"
        .. "Multi-lap: each lap starts and ends at the start line; the final lap finishes on the last checkpoint arch."
    )

    ImGui.Spacing()
    uiHelpers.sectionHeader(uiHelpers.icon("MapMarker") .. "  Placement Tools")

    if ImGui.Button("Place Interaction Point") then
        trackEditor.setPlaceMode(trackEditor, "interaction", td)
    end
    ImGui.SameLine()
    if ImGui.Button("Place Start Line") then
        trackEditor.setPlaceMode(trackEditor, "start", td)
    end
    if ImGui.Button("Place Checkpoint") then
        trackEditor.setPlaceMode(trackEditor, "checkpoint", td)
    end
    ImGui.SameLine()
    if ImGui.Button("Place Prop") then
        trackEditor.setPlaceMode(trackEditor, "prop", td)
    end

    ImGui.Spacing()
    uiHelpers.sectionHeader(uiHelpers.icon("Delete") .. "  Remove / Edit")

    if #td.checkpoints > 0 then
        ImGui.SetNextItemWidth(uiHelpers.scale(200))
        local cpLabel = "Checkpoint #" .. tostring(trackEditor.selectedCpIndex or 1)
        if ImGui.BeginCombo("##EditCP", cpLabel) then
            for i = 1, #td.checkpoints do
                if ImGui.Selectable("Checkpoint #" .. tostring(i), i == (trackEditor.selectedCpIndex or 1)) then
                    trackEditor.selectedCpIndex = i
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        if ImGui.Button("Edit CP") then
            trackEditor.beginEdit(trackEditor, td, "checkpoint", trackEditor.selectedCpIndex or 1)
        end
        ImGui.SameLine()
        if ImGui.Button("Delete CP") then
            trackEditor.DeleteLastObject(trackEditor, td)
        end
    else
        ImGui.TextDisabled("No checkpoints placed")
    end

    if #td.props > 0 then
        ImGui.SetNextItemWidth(uiHelpers.scale(200))
        local propLabel = "Prop #" .. tostring(trackEditor.selectedPropIndex or 1)
        if ImGui.BeginCombo("##EditProp", propLabel) then
            for i = 1, #td.props do
                if ImGui.Selectable("Prop #" .. tostring(i), i == (trackEditor.selectedPropIndex or 1)) then
                    trackEditor.selectedPropIndex = i
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        if ImGui.Button("Edit Prop") then
            trackEditor.beginEdit(trackEditor, td, "prop", trackEditor.selectedPropIndex or 1)
        end
    else
        ImGui.TextDisabled("No props placed")
    end

    if td.startPosition and td.startPosition.position then
        if ImGui.Button("Edit Start Line") then
            trackEditor.beginEdit(trackEditor, td, "start", 1)
        end
    end
    if td.hubPosition and td.hubPosition.position then
        ImGui.SameLine()
        if ImGui.Button("Edit Interaction Point") then
            trackEditor.beginEdit(trackEditor, td, "interaction", 1)
        end
    end

    if trackEditor.editingItem then
        ImGui.Separator()
        ImGui.TextColored(1, 0.8, 0.2, 1, "EDITING: " .. tostring(trackEditor.editType)
            .. (trackEditor.editIndex and (" #" .. tostring(trackEditor.editIndex)) or ""))
        ImGui.Text("Hold placement key to preview, release to confirm")
        if ImGui.Button("Cancel Edit") then
            trackEditor.cancelEdit(trackEditor)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Main draw entry
-- ---------------------------------------------------------------------------

function editorWindow.Draw(ctx)
    if not ctx.cetopen or not Game.GetSystemRequestsHandler() then return end
    if Game.GetSystemRequestsHandler():IsPreGame() or Game.GetSystemRequestsHandler():IsGamePaused() then return end

    uiHelpers.updateResolution()
    local res = uiHelpers.res

    local minW = res.x * 0.28
    local minH = res.y * 0.32
    local maxW = res.x * 0.85
    local maxH = res.y * 0.85

    ImGui.SetNextWindowSizeConstraints(minW, minH, maxW, maxH)
    ImGui.SetNextWindowSize(res.x * 0.38, res.y * 0.48, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowPos(res.x * 0.04, res.y * 0.08, ImGuiCond.FirstUseEver)

    local winFlags = nil
    if isHoveringSplitter or draggingSplitter then
        winFlags = ImGuiWindowFlags.NoMove
    end

    local open = true
    if winFlags then
        open = ImGui.Begin("CyberTrials", true, winFlags)
    else
        open = ImGui.Begin("CyberTrials", true)
    end

    if not open then
        ImGui.End()
        return
    end

    local winW, winH = ImGui.GetWindowSize()
    local minBar = uiHelpers.scale(48)
    local maxBar = math.max(minBar + 20, winW * 0.45)

    tabBarWidth = math.max(minBar, math.min(maxBar, tabBarWidth))

    -- ---- Left tab bar ----
    ImGui.BeginChild("TabBar", tabBarWidth, -1, true)
    for i, tab in ipairs(TABS) do
        local label = uiHelpers.tabLabel(tab.icon, tab.name, tabBarWidth)
        if ImGui.Selectable(label, selectedTab == i) then
            selectedTab = i
        end
        if ImGui.IsItemHovered() and tabBarWidth < uiHelpers.scale(90) then
            ImGui.SetTooltip(tab.name)
        end
    end
    ImGui.EndChild()

    -- ---- Splitter ----
    ImGui.SameLine()
    local mouseX, mouseY = ImGui.GetMousePos()
    local windowX, windowY = ImGui.GetWindowPos()
    local relMouseX = mouseX - windowX
    local splitterX = tabBarWidth + 4
    local hoverThreshold = 6

    isHoveringSplitter = math.abs(relMouseX - splitterX) < hoverThreshold
        and mouseY > windowY + uiHelpers.scale(30)
        and mouseY < windowY + winH

    if isHoveringSplitter or draggingSplitter then
        ImGui.SetMouseCursor(ImGuiMouseCursor.ResizeEW)
        local drawList = ImGui.GetWindowDrawList()
        local glyph = uiHelpers.icon("ArrowSplitVertical")
        if relMouseX <= minBar + 10 then
            glyph = uiHelpers.icon("ArrowExpandRight")
        elseif relMouseX >= maxBar - 10 then
            glyph = uiHelpers.icon("ArrowExpandLeft")
        end
        ImGui.ImDrawListAddText(drawList, mouseX + 6, mouseY - 10, 0xFFFFFFFF, glyph)
    end

    if ImGui.IsMouseClicked(ImGuiMouseButton.Left) and isHoveringSplitter then
        draggingSplitter = true
    end
    if draggingSplitter and ImGui.IsMouseDown(ImGuiMouseButton.Left) then
        tabBarWidth = math.max(minBar, math.min(maxBar, relMouseX))
        tabBarWidthPercent = tabBarWidth / res.x
    end
    if draggingSplitter and ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
        draggingSplitter = false
    end

    -- ---- Content region ----
    ImGui.SameLine()
    ImGui.BeginChild("ContentRegion", 0, -1, true)

    local tab = TABS[selectedTab]
    if tab then
        if tab.id == "race" then
            drawRaceSettings(ctx)
        elseif tab.id == "times" then
            drawBestTimes(ctx)
        elseif tab.id == "teleport" then
            drawTeleport(ctx)
        elseif tab.id == "editor" then
            drawTrackEditor(ctx)
        end
    end

    ImGui.EndChild()
    ImGui.End()
end

return editorWindow
