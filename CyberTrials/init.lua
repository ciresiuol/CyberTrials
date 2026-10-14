local Cron = require("modules/external/Cron")
local user = require("modules/UserSettings/config/user")
local world = require("modules/external/world")
local raceLogic = require("modules/utils/raceLogic")
local hubs = require("modules/utils/interactionHubs")
local interactionUI = require("modules/external/interactionUI")

local messages = require("modules/utils/messages")
local trackEditor = require("modules/editor/trackEditor")
local editorWindow = require("modules/ui/editorWindow")
local nativeTabBar = require("modules/ui/nativeTabBar")

local nativeSettings = nil
local requiredModules = {}

local windowSettings = {
    Current = { mywindowhidden = false },
    Default = { mywindowhidden = false },
}

local timeTrials = {
    runtimeData = {
        inGame = false,
        inMenu = false,
        inEditor = false,
    },
    raceActive = false,
    activeRaceName = 'None',
    availableRaces = {},
    trackData = {
        name = '',
        description = 'Gotta go fast! Race through the checkpoint and to the finish line.',
        checkpoints = {},
        checkpointEnts = {},
        totalCheckpoints = 0,
        hubPosition = {},
        startPosition = {},
        props = {},
        propEnts = {},
        totalProps = 0,
        numberOfLaps = 1,
        creator = 'CyberTrials Editor',
    },
}

local cetopen = false
local currentMappin = nil
local raceNames = {}
local vehicleNames = {}
local selectedTrackName = nil
local selectedVehicleName = nil
local hasPopulatedVehNames = false
local hasPopulatedNames = false
local noVehicleEndRaceDelay = nil
local hasAppliedTD = false
local removeTD = nil
local resetIni = nil
local addedNativeSettings = false
local trackFiles = {}
local newscript = ''
local mappinID = nil
local mappinPos = {}
local selectedMappin = nil

local speedbreakerVehicleState = nil

local nativeCpSounds = {
    [1] = "sq024_race_start_fireworks",
    [2] = "ui_hacking_qh_hover",
    [3] = "dev_pocket_radio_on",
    [4] = "dev_pocket_radio_off",
}
local selectedCpSound = nativeCpSounds[user.settings.cpSoundFx] or nativeCpSounds[1]

local function restoreSpeedbreakerVehicleState()
    if speedbreakerVehicleState then
        GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningMultiplier', speedbreakerVehicleState.latTireThinMult)
        GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength', speedbreakerVehicleState.latTireThinLength)
        GameOptions.SetBool('Vehicle', 'EnableLowVelStoppingResistance', speedbreakerVehicleState.lowVelStopResist)
        GameOptions.SetBool('Vehicle', 'DisableCollisionDamage', speedbreakerVehicleState.disableDamage)
        GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed', speedbreakerVehicleState.maxAngSpd)
        GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed', speedbreakerVehicleState.maxLinSpd)
        GameOptions.SetFloat('Vehicle', 'VelocitySmoothingTime', speedbreakerVehicleState.velSmoothTime)
        speedbreakerVehicleState = nil
    end
end

local function cleanupSpeedbreaker()
    if resetIni then
        Cron.Halt(resetIni)
        resetIni = nil
    end
    if removeTD then
        Cron.Halt(removeTD)
        removeTD = nil
    end
    restoreSpeedbreakerVehicleState()
    if Game.GetPlayer() then
        StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorPlayerBuffLegendaryPlusPlus'), -1)
        StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorCooldown'), -1)
        StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.DetectorRushPlayerBuffUncommonPlus'), -1)
    end
    hasAppliedTD = false
end

local function ShowWarningMessage(message, duration)
    messages.ShowWarningMessage(message, duration)
end

local function ShowNotificationMessage(message, duration)
    messages.ShowNotificationMessage(message, duration)
end

function resetEverything()
    -- Failsafe full cleanup before any new race / session change / CET reload
    if raceLogic then
        if raceLogic.raceInProgress then
            pcall(function() raceLogic.endActiveRace(true) end)
        end
        if raceLogic.resetAllState then
            pcall(function() raceLogic.resetAllState() end)
        elseif raceLogic.fullSessionCleanup then
            pcall(function() raceLogic.fullSessionCleanup() end)
        else
            pcall(function() raceLogic.despawnAllCheckpoints() end)
            pcall(function() raceLogic.endActiveRace(true) end)
        end
    end
    pcall(function() trackEditor.deleteEverything(trackEditor, timeTrials.trackData) end)
    timeTrials.trackData = {
        name = '',
        description = '',
        numberOfLaps = 1,
        checkpoints = {},
        checkpointEnts = {},
        totalCheckpoints = 0,
        hubPosition = {},
        startPosition = {},
        props = {},
        propEnts = {},
        totalProps = 0,
        creator = 'CyberTrials Editor',
    }
    if currentMappin then
        pcall(function() Game.GetMappinSystem():UnregisterMappin(currentMappin) end)
        currentMappin = nil
    end
    -- Fully remove all interaction hubs for every race
    if hubs and hubs.shutdown then
        pcall(function() hubs.shutdown() end)
    end
    world.interactions = {}
    pcall(function() interactionUI.clearCallbacks() end)
    interactionUI.baseControler = nil
    interactionUI.hub = nil
    timeTrials.availableRaces = {}
    timeTrials.runtimeData.inGame = false
    timeTrials.runtimeData.inMenu = false
    timeTrials.runtimeData.inEditor = false
    timeTrials.raceActive = false
    timeTrials.activeRaceName = 'None'
    cetopen = false
    hasPopulatedNames = false
    hasPopulatedVehNames = false
    noVehicleEndRaceDelay = nil
    hasAppliedTD = false
    selectedTrackName = nil
    selectedVehicleName = nil
    mappinID = nil
    mappinPos = {}
    selectedMappin = nil
    speedbreakerVehicleState = nil
end

function calculateDistance(vec1, vec2)
    local dx = vec1.x - vec2.x
    local dy = vec1.y - vec2.y
    local dz = vec1.z - vec2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function removeSpaces(name)
    return name:gsub("%s+", "")
end

function getDisplayName(path)
    return trackEditor.getDisplayName(path)
end

function UpdateLeadMappin()
    if not raceLogic.raceInProgress or not raceLogic.positions then return end
    if user.settings.trackLeadMapPin then
        if currentMappin then
            local playerPos = GetPlayer():GetWorldPosition()
            local nextCheckpointPos = raceLogic.getAheadPosition(user.settings.leadMarkerCP) or raceLogic.positions[#raceLogic.positions]
            if nextCheckpointPos then
                local direction = Vector4.new(nextCheckpointPos.x - playerPos.x, nextCheckpointPos.y - playerPos.y, nextCheckpointPos.z - playerPos.z, 0)
                local length = math.sqrt(direction.x^2 + direction.y^2 + direction.z^2)
                if length <= 0.001 then return end
                direction.x = direction.x / length
                direction.y = direction.y / length
                direction.z = direction.z / length
                direction.x = direction.x * user.settings.leadMarkerDistance
                direction.y = direction.y * user.settings.leadMarkerDistance
                direction.z = direction.z * user.settings.leadMarkerDistance
                local newMappinPos = Vector4.new(playerPos.x + direction.x, playerPos.y + direction.y, playerPos.z + direction.z, 1)
                Game.GetMappinSystem():SetMappinPosition(currentMappin, newMappinPos)
            end
        else
            local mappinData = MappinData.new()
            mappinData.mappinType = 'Mappins.QuestDynamicMappinDefinition'
            mappinData.variant = gamedataMappinVariant.Zzz13_DogtownGateVariant
            mappinData.visibleThroughWalls = true
            mappinData.active = true
            local playerPos = GetPlayer():GetWorldPosition()
            if playerPos and #raceLogic.positions > 0 then
                local nextCheckpointPos = raceLogic.getAheadPosition(user.settings.leadMarkerCP) or raceLogic.positions[#raceLogic.positions]
                if not nextCheckpointPos then return end
                local direction = Vector4.new(nextCheckpointPos.x - playerPos.x, nextCheckpointPos.y - playerPos.y, nextCheckpointPos.z - playerPos.z, 0)
                local length = math.sqrt(direction.x^2 + direction.y^2 + direction.z^2)
                if length <= 0.001 then return end
                direction.x = direction.x / length
                direction.y = direction.y / length
                direction.z = direction.z / length
                direction.x = direction.x * user.settings.leadMarkerDistance
                direction.y = direction.y * user.settings.leadMarkerDistance
                direction.z = direction.z * user.settings.leadMarkerDistance
                local baseMappinPos = Vector4.new(playerPos.x + direction.x, playerPos.y + direction.y, playerPos.z + direction.z, 1)
                currentMappin = Game.GetMappinSystem():RegisterMappin(mappinData, baseMappinPos)
            end
        end
    else
        if currentMappin then
            Game.GetMappinSystem():UnregisterMappin(currentMappin)
        end
        currentMappin = nil
    end
end

function getAvailableRaces()
    local files = dir('modules/tracks')
    if type(files) ~= 'table' then return end

    for _, file in ipairs(files) do
        local extension = file.name:match("^.+(%..+)$")
        if extension == ".lua" then
            local filename = tostring(file.name:gsub("%.lua$", ""))
            if not requiredModules[filename] then
                local modulePath = 'modules/tracks/' .. filename
                local ok, track = pcall(require, modulePath)
                if ok and type(track) == 'table' and track.name and type(track.checkpoints) == 'table' and #track.checkpoints >= 3 then
                    requiredModules[filename] = true

                    local startInteraction = track.hubPosition
                    if not (startInteraction and startInteraction.position) then
                        startInteraction = {
                            position = track.checkpoints[1].position,
                            rotation = track.checkpoints[1].rotation
                        }
                    end

                    local startLine = nil
                    if track.startPosition and track.startPosition.position then
                        startLine = track.startPosition
                    elseif track.checkpoints and track.checkpoints[1] then
                        startLine = {
                            position = track.checkpoints[1].position,
                            rotation = track.checkpoints[1].rotation
                        }
                    end

                    local dat = {
                        startInteraction = startInteraction,
                        startPosition = startLine,
                        name = track.name,
                        description = track.description or '',
                        checkpoints = track.checkpoints,
                        laps = track.numberOfLaps or 1
                    }

                    local trackExists = false
                    for _, existingTrack in ipairs(timeTrials.availableRaces) do
                        if existingTrack.name == dat.name then
                            trackExists = true
                            break
                        end
                    end
                    if not trackExists then
                        table.insert(timeTrials.availableRaces, dat)
                    end
                elseif not ok then
                    print('CyberTrials: unable to load track module ' .. tostring(modulePath) .. ': ' .. tostring(track))
                end
            end
        end
    end
end

function SaveWindowSettings()
    local file = io.open('modules/UserSettings/windowsettings.json', 'w')
    if file then
        file:write(json.encode(windowSettings.Current))
        file:close()
    end
end

function LoadWindowSettings()
    local file = io.open('modules/UserSettings/windowsettings.json', 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == 'table' then
            windowSettings.Current = decoded
            if windowSettings.Current.mywindowhidden == nil then
                windowSettings.Current.mywindowhidden = windowSettings.Default.mywindowhidden
            end
            return
        end
    end
    windowSettings.Current = {
        mywindowhidden = windowSettings.Default.mywindowhidden
    }
    SaveWindowSettings()
end

function SaveSettings()
    local settingsFile = io.open('modules/UserSettings/UserSettings.json', 'w')
    if settingsFile then
        settingsFile:write(json.encode(user.settings))
        settingsFile:close()
    end
end

function LoadSettings()
    local defaults = user.defaultSettings or {}
    local loaded = nil
    local settingsFile = io.open('modules/UserSettings/UserSettings.json', 'r')

    if settingsFile then
        local settingsContent = settingsFile:read('*all')
        settingsFile:close()
        if settingsContent and #settingsContent > 0 then
            local ok, decoded = pcall(json.decode, settingsContent)
            if ok and type(decoded) == 'table' then
                loaded = decoded
            end
        end
    end

    if not loaded then
        loaded = {}
    end

    for key, defaultValue in pairs(defaults) do
        if loaded[key] == nil then
            loaded[key] = defaultValue
        end
    end

    user.settings = loaded
    if not nativeCpSounds[user.settings.cpSoundFx] then
        user.settings.cpSoundFx = user.defaultSettings.cpSoundFx or 1
    end
    -- Apply persisted live traffic spawn toggle
    if user.settings.trafficSpawnsStoppedLive ~= nil then
        pcall(function()
            GameOptions.SetBool("Traffic", "StopSpawn", user.settings.trafficSpawnsStoppedLive == true)
        end)
    end
    SaveSettings()
end

function LoadRecentTimes()
    local timesFile = io.open('modules/UserSettings/RecentTimes.json', 'r')
    if not timesFile then
        user.recentTimes = user.recentTimes or {}
        return
    end

    local timesContent = timesFile:read('*all')
    timesFile:close()

    if timesContent and #timesContent > 0 then
        local ok, decoded = pcall(json.decode, timesContent)
        if ok and type(decoded) == 'table' then
            user.recentTimes = decoded
            return
        end
    end

    user.recentTimes = {}
end

function PopulateRaceNames()
    LoadRecentTimes()
    if hasPopulatedNames == false then
        raceNames = {}
        if type(user.recentTimes) == 'table' then
            for trackName, _ in pairs(user.recentTimes) do
                if type(trackName) == 'string' and trackName ~= "NoData" then
                    local alreadyExists = false
                    for _, name in ipairs(raceNames) do
                        if name == trackName then
                            alreadyExists = true
                            break
                        end
                    end
                    if not alreadyExists then
                        table.insert(raceNames, trackName)
                    end
                end
            end
        end
    end
    hasPopulatedNames = true
end

function PopulateVehicleNames()
    if hasPopulatedVehNames == false then
        vehicleNames = {}
        local vehicleSet = {}
        if user.recentTimes then
            for _, races in pairs(user.recentTimes) do
                if type(races) == 'table' then
                    for _, race in ipairs(races) do
                        if race.currentVehicle and not vehicleSet[race.currentVehicle] then
                            table.insert(vehicleNames, tostring(race.currentVehicle):gsub("Vehicle%.", ""))
                            vehicleSet[race.currentVehicle] = true
                        end
                    end
                end
            end
        end
    end
    hasPopulatedVehNames = true
end

local function escapeLuaString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', [[\"]])
    value = value:gsub("\r", "\\r")
    value = value:gsub("\n", "\\n")
    return value
end

function listTrackFiles()
    trackFiles = {}
    local folder = 'modules/tracks'
    local files = dir(folder)
    if type(files) ~= 'table' then return trackFiles end
    for _, file in ipairs(files) do
        local extension = file.name:match("^.+(%..+)$")
        if extension == ".lua" then
            local filename = tostring(file.name:gsub("%.lua$", ""))
            local exists = false
            for _, existingFile in ipairs(trackFiles) do
                if tostring(existingFile) == tostring(filename) or tostring(timeTrials.trackData.name) == tostring(filename) then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(trackFiles, filename)
            end
        end
    end
    return trackFiles
end

function exportTrackData()
    local formattedName = removeSpaces(timeTrials.trackData.name)
    if formattedName == '' then
        ShowWarningMessage('Please enter a valid track name containing at least one letter.', 4.0)
        return
    elseif #timeTrials.trackData.checkpoints < 3 then
        ShowWarningMessage('Please place at least 3 checkpoints before exporting a track.', 4.0)
        return
    elseif not timeTrials.trackData.hubPosition.position then
        ShowWarningMessage('Please place an interaction point before exporting a track.', 4.0)
        return
    end

    newscript = ''
    newscript = newscript .. formattedName .. ' = {\n'
    newscript = newscript .. '    name = "' .. escapeLuaString(timeTrials.trackData.name) .. '",\n'
    if timeTrials.trackData.description ~= '' and timeTrials.trackData.creator ~= '' then
        if not string.find(timeTrials.trackData.description, ' - - - Created') then
            newscript = newscript .. '    description = "' .. escapeLuaString(timeTrials.trackData.description) .. ' - - - Created By: ' .. escapeLuaString(timeTrials.trackData.creator) .. '",\n'
        else
            newscript = newscript .. '    description = "' .. escapeLuaString(timeTrials.trackData.description) .. '",\n'
        end
        newscript = newscript .. '    creator = "' .. escapeLuaString(timeTrials.trackData.creator) .. '",\n'
    elseif timeTrials.trackData.description ~= '' and timeTrials.trackData.creator == '' then
        newscript = newscript .. '    description = "' .. escapeLuaString(timeTrials.trackData.description) .. '",\n'
    elseif timeTrials.trackData.description == '' and timeTrials.trackData.creator ~= '' then
        newscript = newscript .. '    creator = "' .. escapeLuaString(timeTrials.trackData.creator) .. '",\n'
    end
    newscript = newscript .. '    numberOfLaps = ' .. tostring(timeTrials.trackData.numberOfLaps) .. ',\n'

    newscript = newscript .. '    hubPosition = {\n'
    if timeTrials.trackData.hubPosition.position and timeTrials.trackData.hubPosition.rotation then
        newscript = newscript .. '        position = { x = ' .. timeTrials.trackData.hubPosition.position.x .. ', y = ' .. timeTrials.trackData.hubPosition.position.y .. ', z = ' .. timeTrials.trackData.hubPosition.position.z .. ' },\n'
        newscript = newscript .. '        rotation = { roll = ' .. timeTrials.trackData.hubPosition.rotation.roll .. ', pitch = ' .. timeTrials.trackData.hubPosition.rotation.pitch .. ', yaw = ' .. timeTrials.trackData.hubPosition.rotation.yaw .. ' }\n'
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    startPosition = {\n'
    if timeTrials.trackData.startPosition.position and timeTrials.trackData.startPosition.rotation then
        newscript = newscript .. '        position = { x = ' .. timeTrials.trackData.startPosition.position.x .. ', y = ' .. timeTrials.trackData.startPosition.position.y .. ', z = ' .. timeTrials.trackData.startPosition.position.z .. ' },\n'
        newscript = newscript .. '        rotation = { roll = ' .. timeTrials.trackData.startPosition.rotation.roll .. ', pitch = ' .. timeTrials.trackData.startPosition.rotation.pitch .. ', yaw = ' .. timeTrials.trackData.startPosition.rotation.yaw .. ' }\n'
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    checkpoints = {\n'
    for _, checkpoint in ipairs(timeTrials.trackData.checkpoints) do
        newscript = newscript .. '        {position = { x = ' .. checkpoint.position.x .. ', y = ' .. checkpoint.position.y .. ', z = ' .. checkpoint.position.z .. ' }, rotation = { roll = ' .. checkpoint.rotation.roll .. ', pitch = ' .. checkpoint.rotation.pitch .. ', yaw = ' .. checkpoint.rotation.yaw .. ' }},\n'
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    checkpointEnts = {\n'
    for index, path in ipairs(timeTrials.trackData.checkpointEnts) do
        if index ~= timeTrials.trackData.totalCheckpoints then
            local formattedPath = path:gsub("\\", "\\\\")
            newscript = newscript .. '        "' .. formattedPath .. '",\n'
        else
            local finishLinePath = "base\\\\gameplay\\\\devices\\\\street_signs\\\\race_checkpoint\\\\race_checkpoint_finish.ent"
            newscript = newscript .. '        "' .. finishLinePath .. '",\n'
        end
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    totalCheckpoints = ' .. tonumber(timeTrials.trackData.totalCheckpoints) .. ',\n'

    newscript = newscript .. '    props = {\n'
    for _, prop in ipairs(timeTrials.trackData.props) do
        newscript = newscript .. '        {position = { x = ' .. prop.position.x .. ', y = ' .. prop.position.y .. ', z = ' .. prop.position.z .. ' }, rotation = { roll = ' .. prop.rotation.roll .. ', pitch = ' .. prop.rotation.pitch .. ', yaw = ' .. prop.rotation.yaw .. ' }},\n'
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    propEnts = {\n'
    for _, path in ipairs(timeTrials.trackData.propEnts) do
        local formattedPath = path:gsub("\\", "\\\\")
        newscript = newscript .. '        "' .. formattedPath .. '",\n'
    end
    newscript = newscript .. '    },\n'

    newscript = newscript .. '    totalProps = ' .. tonumber(timeTrials.trackData.totalProps) .. ',\n'
    newscript = newscript .. '}\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.init()\n'
    newscript = newscript .. '    local val = {}\n'
    newscript = newscript .. '    local trans = WorldTransform.new()\n'
    newscript = newscript .. '    local checkId = nil\n'
    newscript = newscript .. '    for _, point in ipairs(' .. formattedName .. '.checkpoints) do\n'
    newscript = newscript .. '        trans:SetPosition(ToVector4(point.position))\n'
    newscript = newscript .. '        trans:SetOrientation(ToEulerAngles(point.rotation):ToQuat())\n'
    newscript = newscript .. '        checkId = exEntitySpawner.Spawn(' .. formattedName .. '.checkpointEnts[_], trans)\n'
    newscript = newscript .. '        table.insert(val, _, checkId)\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return val\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.spawnProps()\n'
    newscript = newscript .. '    local val = {}\n'
    newscript = newscript .. '    local trans = WorldTransform.new()\n'
    newscript = newscript .. '    local checkId = nil\n'
    newscript = newscript .. '    for _, prop in ipairs(' .. formattedName .. '.props) do\n'
    newscript = newscript .. '        trans:SetPosition(ToVector4(prop.position))\n'
    newscript = newscript .. '        trans:SetOrientation(ToEulerAngles(prop.rotation):ToQuat())\n'
    newscript = newscript .. '        checkId = exEntitySpawner.Spawn(' .. formattedName .. '.propEnts[_], trans)\n'
    newscript = newscript .. '        table.insert(val, _, checkId)\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return val\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetCheckpointPositions()\n'
    newscript = newscript .. '    local val = {}\n'
    newscript = newscript .. '    for _, point in ipairs(' .. formattedName .. '.checkpoints) do\n'
    newscript = newscript .. '        table.insert(val, ToVector4(point.position))\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return val\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetPropPositions()\n'
    newscript = newscript .. '    local propVal = {}\n'
    newscript = newscript .. '    for _, prop in ipairs(' .. formattedName .. '.props) do\n'
    newscript = newscript .. '        table.insert(propVal, ToVector4(prop.position))\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return propVal\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetCheckpointRotations()\n'
    newscript = newscript .. '    local rotVal = {}\n'
    newscript = newscript .. '    for _, point in ipairs(' .. formattedName .. '.checkpoints) do\n'
    newscript = newscript .. '        table.insert(rotVal, ToEulerAngles(point.rotation))\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return rotVal\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetPropRotations()\n'
    newscript = newscript .. '    local propRotVal = {}\n'
    newscript = newscript .. '    for _, prop in ipairs(' .. formattedName .. '.props) do\n'
    newscript = newscript .. '        table.insert(propRotVal, ToEulerAngles(prop.rotation))\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return propRotVal\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetCheckpointEntities()\n'
    newscript = newscript .. '    local entVal = {}\n'
    newscript = newscript .. '    for _, path in ipairs(' .. formattedName .. '.checkpointEnts) do\n'
    newscript = newscript .. '        table.insert(entVal, path)\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return entVal\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'function ' .. formattedName .. '.GetPropEntities()\n'
    newscript = newscript .. '    local propEntVal = {}\n'
    newscript = newscript .. '    for _, path in ipairs(' .. formattedName .. '.propEnts) do\n'
    newscript = newscript .. '        table.insert(propEntVal, path)\n'
    newscript = newscript .. '    end\n'
    newscript = newscript .. '    return propEntVal\n'
    newscript = newscript .. 'end\n\n'

    newscript = newscript .. 'return ' .. formattedName .. '\n'

    local path = "modules/tracks/" .. formattedName .. ".lua"
    local file = io.open(path, "w")
    if not file then
        ShowWarningMessage('Unable to write the track file. Check the mod folder permissions.', 5.0)
        return
    end
    file:write(newscript)
    file:close()

    requiredModules[formattedName] = nil
    if package and package.loaded then
        package.loaded["modules/tracks/" .. formattedName] = nil
    end
    getAvailableRaces()
    ShowWarningMessage('Track exported successfully: ' .. formattedName, 3.0)
end

function importTrackData()
    local formattedFilename = removeSpaces(timeTrials.trackData.name)
    if formattedFilename == '' then
        ShowWarningMessage('Please select a saved track to import.', 4.0)
        return
    end
    local modulePath = 'modules/tracks/' .. formattedFilename
    local ok, loadedTrack = pcall(require, modulePath)
    local track = ok and loadedTrack or nil
    if not track then
        local messageText = 'Unable to find saved track with filename: ' .. formattedFilename
        ShowWarningMessage(messageText, 4.0)
        print(messageText)
        return
    end
    if not track.name or not track.checkpoints or not track.checkpointEnts or not track.totalCheckpoints then
        local messageText = 'Unable to import track due to missing required elements.'
        ShowWarningMessage(messageText, 4.0)
        print(messageText)
        return
    end

    print("Importing saved track with name: " .. tostring(formattedFilename))
    trackEditor.deleteEverything(trackEditor, timeTrials.trackData)
    timeTrials.trackData.name = tostring(track.name)
    timeTrials.trackData.description = track.description or ''
    timeTrials.trackData.creator = track.creator or ''
    timeTrials.trackData.numberOfLaps = (track.numberOfLaps and track.numberOfLaps ~= 1) and track.numberOfLaps or 1
    timeTrials.trackData.checkpoints = {}
    timeTrials.trackData.checkpointEnts = {}
    timeTrials.trackData.props = {}
    timeTrials.trackData.propEnts = {}
    timeTrials.trackData.hubPosition = {}
    timeTrials.trackData.startPosition = {}

    if track.hubPosition and track.hubPosition.position then
        timeTrials.trackData.hubPosition.position = track.hubPosition.position
        timeTrials.trackData.hubPosition.rotation = track.hubPosition.rotation
    end

    if track.startPosition and track.startPosition.position then
        timeTrials.trackData.startPosition.position = track.startPosition.position
        timeTrials.trackData.startPosition.rotation = track.startPosition.rotation
    end

    for _, checkpoint in ipairs(track.checkpoints) do
        table.insert(timeTrials.trackData.checkpoints, {
            position = checkpoint.position,
            rotation = checkpoint.rotation,
        })
    end

    if track.checkpointEnts then
        for _, path in ipairs(track.checkpointEnts) do
            if tostring(path) ~= 'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_finish.ent' then
                table.insert(timeTrials.trackData.checkpointEnts, path)
            else
                table.insert(timeTrials.trackData.checkpointEnts, 'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent')
            end
        end
    else
        for i = 1, #timeTrials.trackData.checkpoints do
            table.insert(timeTrials.trackData.checkpointEnts, 'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent')
        end
    end
    timeTrials.trackData.totalCheckpoints = track.totalCheckpoints

    if track.props then
        for _, prop in ipairs(track.props) do
            table.insert(timeTrials.trackData.props, {
                position = prop.position,
                rotation = prop.rotation,
            })
        end
    end

    if track.propEnts then
        for _, path in ipairs(track.propEnts) do
            table.insert(timeTrials.trackData.propEnts, path)
        end
    end

    if track.totalProps then
        timeTrials.trackData.totalProps = track.totalProps
    end

    trackEditor.spawnFromData(trackEditor, timeTrials.trackData)
    ShowWarningMessage('Track imported: ' .. tostring(track.name), 3.0)
end

local function fmtMs(ms)
    if not ms then return "--:--.---" end
    local m = math.floor(ms / 60000)
    local s = math.floor((ms % 60000) / 1000)
    local mi = ms % 1000
    return string.format("%d:%02d.%03d", m, s, mi)
end

-- Collect run entries from either the new {runs=...} structure or a legacy array
local function getRunsForTrack(trackName)
    local entry = user.recentTimes and user.recentTimes[trackName]
    if type(entry) ~= "table" then return {}, entry end
    if entry.runs then return entry.runs, entry end
    if entry[1] then return entry, entry end
    return {}, entry
end

function DrawWindowHider()
    if not cetopen then return end
    if ImGui.Begin("Window Hider Tool") then
        if ImGui.BeginMenu("Manually Enhanced Collabs") then
            if ImGui.Button("Toggle CyberTrials Mod") then
                if windowSettings.Current.mywindowhidden == true then
                    windowSettings.Current.mywindowhidden = false
                    SaveWindowSettings()
                elseif windowSettings.Current.mywindowhidden == false then
                    windowSettings.Current.mywindowhidden = true
                    SaveWindowSettings()
                end
            end
            ImGui.EndMenu()
        end
        ImGui.End()
    end
end

-- ---------------------------------------------------------------------------
-- Native Settings (tabbed via modules/ui/nativeTabBar.lua)
-- ---------------------------------------------------------------------------
local nsTrackNames = { "None" }
local nsVehicleNames = { "All Vehicles" }
local nsSelectedTrackIdx = 1
local nsSelectedVehicleIdx = 1
local nsResultLabels = { "No times to display" }
local nsResultSubcatPaths = {} -- pure-text result rows (Best Times tab)

-- Teleport player (and optionally their vehicle 20m underground) to a race hub.
-- Also resets any active race and applies the traffic-disable setting.
local function teleportRaceBodies(race, vehicle)
    local startPos, startRot
    if race.startPosition and race.startPosition.position then
        startPos = ToVector4(race.startPosition.position)
        startRot = ToEulerAngles(race.startPosition.rotation or { roll = 0, pitch = 0, yaw = 0 })
    else
        startPos = ToVector4(race.startInteraction.position)
        startRot = ToEulerAngles(race.startInteraction.rotation or { roll = 0, pitch = 0, yaw = 0 })
    end

    local hubPos = ToVector4(race.startInteraction.position)
    local hubRot = ToEulerAngles(race.startInteraction.rotation or { roll = 0, pitch = 0, yaw = 0 })
    local tele = Game.GetTeleportationFacility()
    if not tele then
        ShowWarningMessage("Teleportation is unavailable right now.", 3.0)
        return false
    end

    -- Place the vehicle on the start line, facing the correct way to begin the race
    if vehicle then
        tele:Teleport(vehicle, startPos, startRot)
        raceLogic.currVeh = vehicle
        if raceLogic.repairVehicle then
            raceLogic.repairVehicle(vehicle)
        end
        if raceLogic.holdVehiclePose then
            raceLogic.holdVehiclePose(vehicle, startPos, startRot, 1.0)
        end
    end

    -- Place the player at the interaction hub (ready to start)
    if Game.GetPlayer() then
        tele:Teleport(Game.GetPlayer(), hubPos, hubRot)
    end
    return true
end

function TeleportToRace(race)
    if not race or not race.startInteraction or not race.startInteraction.position then
        ShowWarningMessage("Invalid race location.", 3.0)
        return false
    end

    -- Do not teleport while the player is sitting in a vehicle
    if Game.GetPlayer() and Game.GetPlayer().mountedVehicle then
        ShowWarningMessage("Please exit your vehicle before teleporting to races.", 3.0)
        return false
    end

    -- Reset any previous race progress first
    if raceLogic and raceLogic.raceInProgress then
        raceLogic.endActiveRaceQuick()
    elseif raceLogic then
        raceLogic.resetRace()
    end

    -- Stop traffic on teleport when the race setting is enabled
    if raceLogic and raceLogic.stopTrafficForRace then
        raceLogic.stopTrafficForRace()
    elseif user.settings.disableTraffic then
        GameOptions.SetBool("Traffic", "StopSpawn", true)
    end

    -- Require a vehicle the player has already entered/exited. Never spawn from garage.
    local vehicle = raceLogic.ensurePlayerVehicle()
    if not vehicle then
        ShowWarningMessage("You need to enter/exit a vehicle of your choice before starting the event.", 4.0)
        return false
    end
    return teleportRaceBodies(race, vehicle)
end

local function nsRebuildTrackAndVehicleLists()
    nsTrackNames = {}
    local seenTracks = {}
    -- Prefer known race names, then anything stored in recentTimes
    if type(raceNames) == "table" then
        for _, name in ipairs(raceNames) do
            if name and not seenTracks[name] then
                table.insert(nsTrackNames, name)
                seenTracks[name] = true
            end
        end
    end
    if type(user.recentTimes) == "table" then
        for name, _ in pairs(user.recentTimes) do
            if type(name) == "string" and not seenTracks[name] then
                table.insert(nsTrackNames, name)
                seenTracks[name] = true
            end
        end
    end
    if #nsTrackNames == 0 then
        nsTrackNames = { "None" }
    end
    if nsSelectedTrackIdx > #nsTrackNames then
        nsSelectedTrackIdx = 1
    end

    nsVehicleNames = { "All Vehicles" }
    local seenVeh = {}
    local trackName = nsTrackNames[nsSelectedTrackIdx]
    local runs = getRunsForTrack(trackName)
    for _, race in ipairs(runs) do
        local v = tostring(race.currentVehicle or "Unknown"):gsub("Vehicle%.", "")
        if v ~= "" and not seenVeh[v] then
            table.insert(nsVehicleNames, v)
            seenVeh[v] = true
        end
    end
    if nsSelectedVehicleIdx > #nsVehicleNames then
        nsSelectedVehicleIdx = 1
    end
end

local function nsRebuildResultLabels()
    nsResultLabels = {}
    local trackName = nsTrackNames[nsSelectedTrackIdx]
    local runs, entry = getRunsForTrack(trackName)
    local vehicleFilter = nsVehicleNames[nsSelectedVehicleIdx]
    local filtered = {}
    for _, race in ipairs(runs) do
        local v = tostring(race.currentVehicle or "Unknown"):gsub("Vehicle%.", "")
        if vehicleFilter == "All Vehicles" or v == vehicleFilter then
            table.insert(filtered, race)
        end
    end
    table.sort(filtered, function(a, b)
        return (a.totalMillisecs or math.huge) < (b.totalMillisecs or math.huge)
    end)

    if entry and entry.bestFullMs then
        local lapsLabel = (entry.bestLaps and entry.bestLaps > 1) and string.format(" (%d laps)", entry.bestLaps) or ""
        table.insert(nsResultLabels, "BEST RACE: " .. fmtMs(entry.bestFullMs) .. lapsLabel)
        if entry.bestLapMs then
            table.insert(nsResultLabels, "BEST LAP:  " .. fmtMs(entry.bestLapMs))
        end
    end

    for i, race in ipairs(filtered) do
        if i > 10 then break end
        local laps = race.laps or 1
        local lapsStr = (laps > 1) and string.format(" [%dl]", laps) or ""
        local veh = tostring(race.currentVehicle or "?"):gsub("Vehicle%.", "")
        table.insert(nsResultLabels, string.format("%d. %02d:%02d.%03d%s - %s",
            i, race.min or 0, race.sec or 0, race.milliSecs or 0, lapsStr, veh))
    end

    if #nsResultLabels == 0 then
        nsResultLabels = { "No times recorded for this selection" }
    end
end

local function nsClearResultSubcats()
    for _, path in ipairs(nsResultSubcatPaths) do
        pcall(function() nativeSettings.removeSubcategory(path) end)
    end
    nsResultSubcatPaths = {}
end

-- ---- Per-tab content builders (called by nativeTabBar on selection) ----

local function nsBuildRaceTab()
    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Race")

    nativeSettings.addButton(path, "End Active Race", "Ends the current race event, if one is in progress.", "End Race", 40, function()
        if raceLogic and raceLogic.raceInProgress == true then
            if Game.GetJournalManager() and not Game.GetJournalManager():GetTrackedEntry() and raceLogic.trackedJournalEntry then
                Game.GetJournalManager():TrackEntry(raceLogic.trackedJournalEntry)
                raceLogic.trackedJournalEntry = nil
            end
            if currentMappin then
                Game.GetMappinSystem():UnregisterMappin(currentMappin)
                currentMappin = nil
            end
            raceLogic.endActiveRaceQuick()
        end
    end)
    nativeSettings.addSwitch(path, "Reward Eddies for Finishing Races", "Gives a reward of Eddies for completing race events.", user.settings.cashReward, user.defaultSettings.cashReward, function(state)
        user.settings.cashReward = state
        SaveSettings()
    end)
    nativeSettings.addSwitch(path, "Return To Start Line When Finishing", "Teleports you back to the start line after a race ends (skipped if already within 50m).", user.settings.backToStartOnFinish, user.defaultSettings.backToStartOnFinish, function(state)
        user.settings.backToStartOnFinish = state
        SaveSettings()
    end)
    nativeSettings.addSwitch(path, "Speedbreaker Ability", "Enables Speedbreaker during races. Activate by tapping Exit Vehicle (or a custom CET binding). ~5s duration, 20s cooldown.", user.settings.useSpeedbreaker, user.defaultSettings.useSpeedbreaker, function(state)
        user.settings.useSpeedbreaker = state
        SaveSettings()
    end)
    nativeSettings.addRangeFloat(path, "Laps Count Multiplier", "Multiplies laps for multi-lap races. Does not affect single-lap (sprint) races.", 0.1, 5, 0.1, "%.1f", user.settings.lapCountMult, user.defaultSettings.lapCountMult, function(state)
        user.settings.lapCountMult = state
        SaveSettings()
    end)
end

local function nsBuildAudioTab()
    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Audio")

    nativeSettings.addSwitch(path, "Checkpoint Reached Sound FX", "Plays a sound effect when a checkpoint is passed.", user.settings.checkpointAudio, user.defaultSettings.checkpointAudio, function(state)
        user.settings.checkpointAudio = state
        SaveSettings()
    end)
    nativeSettings.addSelectorString(path, "Checkpoint Audio Sound", "Sound effect used when reaching a checkpoint (if enabled above).", nativeCpSounds, user.settings.cpSoundFx, user.defaultSettings.cpSoundFx, function(value)
        user.settings.cpSoundFx = value
        SaveSettings()
    end)
end

local function nsBuildTrafficTab()
    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Traffic")

    nativeSettings.addSwitch(path, "Stop Traffic Spawns For Races", "When enabled, traffic is stopped when you teleport to a race and re-enabled when the race ends.", user.settings.disableTraffic, user.defaultSettings.disableTraffic, function(state)
        user.settings.disableTraffic = state
        SaveSettings()
    end)
    do
        local trafficStopped = user.settings.trafficSpawnsStoppedLive
        if trafficStopped == nil then
            trafficStopped = false
            pcall(function() trafficStopped = GameOptions.GetBool("Traffic", "StopSpawn") end)
        end
        -- Apply persisted live traffic state on menu build
        pcall(function() GameOptions.SetBool("Traffic", "StopSpawn", trafficStopped == true) end)
        nativeSettings.addSwitch(path, "Traffic Spawns Stopped (Live)", "Directly toggles the game's traffic spawn state. Persists with other mod settings.", trafficStopped == true, user.defaultSettings.trafficSpawnsStoppedLive or false, function(state)
            GameOptions.SetBool("Traffic", "StopSpawn", state)
            user.settings.trafficSpawnsStoppedLive = state
            SaveSettings()
        end)
    end
end

local function nsBuildMarkersTab()
    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Markers")

    nativeSettings.addSwitch(path, "Use Map Marker For Checkpoints", "Shows a map marker ahead of you pointing toward an upcoming checkpoint.", user.settings.trackLeadMapPin, user.defaultSettings.trackLeadMapPin, function(state)
        user.settings.trackLeadMapPin = state
        SaveSettings()
    end)
    nativeSettings.addRangeInt(path, "Track Lead Marker Target Checkpoint", "How many checkpoints ahead the track lead marker targets.", 1, 3, 1, user.settings.leadMarkerCP, user.defaultSettings.leadMarkerCP, function(state)
        user.settings.leadMarkerCP = state
        SaveSettings()
    end)
    nativeSettings.addRangeInt(path, "Track Lead Marker Distance", "How many meters ahead of the player the track lead marker appears.", 20, 50, 1, user.settings.leadMarkerDistance, user.defaultSettings.leadMarkerDistance, function(state)
        user.settings.leadMarkerDistance = state
        SaveSettings()
    end)
end

local function nsBuildInterfaceTab()
    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Interface")

    nativeSettings.addSwitch(path, "Show Tooltips", "Display helpful tooltips in the CyberTrials CET overlay windows.", user.settings.showTooltips ~= false, true, function(state)
        user.settings.showTooltips = state
        SaveSettings()
    end)
end

local function nsBuildBestTimesTab()
    nsClearResultSubcats()
    nsRebuildTrackAndVehicleLists()
    nsRebuildResultLabels()

    local path = nativeTabBar.contentPath("main")
    nativeTabBar.trackContentPath(path)
    nativeSettings.addSubcategory(path, "Best Times")

    nativeSettings.addSelectorString(path, "Track", "Select a track to view recorded times for.", nsTrackNames, nsSelectedTrackIdx, 1, function(value)
        nsSelectedTrackIdx = value
        nsSelectedVehicleIdx = 1
        -- Rebuild this tab in place via the tab bar
        if nativeTabBar and nativeTabBar.refresh then
            nativeTabBar.refresh()
        end
    end)

    nativeSettings.addSelectorString(path, "Vehicle", "Filter times by vehicle, or show all.", nsVehicleNames, nsSelectedVehicleIdx, 1, function(value)
        nsSelectedVehicleIdx = value
        if nativeTabBar and nativeTabBar.refresh then
            nativeTabBar.refresh()
        end
    end)

    -- Pure-text result rows (subcategory labels with no widgets)
    for i, label in ipairs(nsResultLabels) do
        local rpath = "/CyberTrials/BT_Result_" .. tostring(i)
        nativeSettings.addSubcategory(rpath, tostring(label))
        table.insert(nsResultSubcatPaths, rpath)
        nativeTabBar.trackContentPath(rpath)
    end
end

function NativeMenu()
    if not nativeSettings then return end

    -- Root tab for the mod (Native Settings path: /CyberTrials)
    nativeSettings.addTab("/CyberTrials", "CyberTrials")

    -- Page selector (string list) controls which option groups are visible.
    -- See modules/ui/nativeTabBar.lua for details.
    nativeTabBar.setup(nativeSettings, "/CyberTrials", {
        { id = "race",      label = "Race",       build = nsBuildRaceTab },
        { id = "audio",     label = "Audio",      build = nsBuildAudioTab },
        { id = "traffic",   label = "Traffic",    build = nsBuildTrafficTab },
        { id = "markers",   label = "Markers",    build = nsBuildMarkersTab },
        { id = "interface", label = "Interface",  build = nsBuildInterfaceTab },
        { id = "besttimes", label = "Best Times", build = nsBuildBestTimesTab },
    }, 1)
end

function timeTrials:new()
    registerForEvent('onInit', function()
        -- Failsafe cleanup in case CET mods were reloaded mid-race
        if raceLogic then
            if raceLogic.raceInProgress then
                pcall(function() raceLogic.endActiveRace(true) end)
            end
            if raceLogic.fullSessionCleanup then
                pcall(function() raceLogic.fullSessionCleanup() end)
            elseif raceLogic.resetRace then
                pcall(function() raceLogic.resetRace() end)
            end
        end
        cleanupSpeedbreaker()

        if raceLogic.setCleanupCallback then
            raceLogic.setCleanupCallback(cleanupSpeedbreaker)
        end
        LoadSettings()
        LoadWindowSettings()
        LoadRecentTimes()
        nativeSettings = GetMod("nativeSettings")
        getAvailableRaces()
        if nativeSettings then
            NativeMenu()
            addedNativeSettings = true
        end
        if currentMappin then
            Game.GetMappinSystem():UnregisterMappin(currentMappin)
            currentMappin = nil
        end

        world.init()
        interactionUI.init()

        Observe('PlayerPuppet', 'OnMakePlayerVisibleAfterSpawn', function(_, event)
            if raceLogic and raceLogic.currVeh then
                raceLogic.currVehEnt = nil
                raceLogic.currVeh = nil
            end
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
                raceLogic.endActiveRaceQuick()
            elseif raceLogic and raceLogic.raceInProgress and not noVehicleEndRaceDelay then
                raceLogic.endActiveRaceQuick()
            end
            if currentMappin then
                Game.GetMappinSystem():UnregisterMappin(currentMappin)
                currentMappin = nil
            end
            trackEditor.clearPreview(trackEditor)
            self.runtimeData.inGame = true
            LoadSettings()
            -- Populate tracks BEFORE wiring up interaction hubs
            getAvailableRaces()
            world.onSessionStart()
            hubs.onSessionStart(timeTrials.availableRaces)
            -- Force map mappins to rebuild on next UpdateRootState
            hubs.clearMappins()
            self.runtimeData.inGame = true
        end)

        Observe('DriveEvents', 'OnUpdate', function(_, event)
            if raceLogic and raceLogic.raceInProgress then
                raceLogic.update()
            end
        end)

        Observe('ExitingEvents', 'OnEnter', function(_, event)
            if Game.GetPlayer().mountedVehicle then
                if Game.GetPlayer().mountedVehicle:IsPlayerDriver() == true then
                    raceLogic.currVeh = Game.GetPlayer().mountedVehicle
                    raceLogic.currVehEnt = Game.GetPlayer().mountedVehicle:GetEntity()
                end
            end
            if raceLogic and raceLogic.raceInProgress then
                ShowWarningMessage('Warning: Race will end in 10 seconds if you do not return to your vehicle!!!', 5.0)
                noVehicleEndRaceDelay = Cron.After(10.0, function()
                    raceLogic.endActiveRaceQuick()
                    noVehicleEndRaceDelay = nil
                end)
            end
        end)

        Observe('EnteringEvents', 'OnEnter', function(_, event)
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
            end
            raceLogic.currVeh = nil
            raceLogic.currVehEnt = nil
            if Game.GetPlayer().mountedVehicle and Game.GetPlayer().mountedVehicle:IsPlayerDriver() == true then
                raceLogic.currVeh = Game.GetPlayer().mountedVehicle
                raceLogic.currVehEnt = Game.GetPlayer().mountedVehicle:GetEntity()
            end
        end)

        Observe('PlayerPuppet', 'OnDeath', function(_, event)
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
                raceLogic.endActiveRaceQuick()
            elseif raceLogic and raceLogic.raceInProgress and not noVehicleEndRaceDelay then
                raceLogic.endActiveRaceQuick()
            end
            if raceLogic and raceLogic.currVeh then
                raceLogic.currVehEnt = nil
                raceLogic.currVeh = nil
            end
            self.runtimeData.inGame = false
        end)

        Observe('MenuScenario_PreGameSubMenu', 'OnEnterScenario', function(_, event)
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
                raceLogic.endActiveRaceQuick()
            elseif raceLogic and raceLogic.raceInProgress and not noVehicleEndRaceDelay then
                raceLogic.endActiveRaceQuick()
            end
            if raceLogic and raceLogic.currVeh then
                raceLogic.currVehEnt = nil
                raceLogic.currVeh = nil
            end
            self.runtimeData.inGame = false
        end)

        Observe('MenuScenario_SingleplayerMenu', 'OnEnterScenario', function(_, event)
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
                raceLogic.endActiveRaceQuick()
            elseif raceLogic and raceLogic.raceInProgress and not noVehicleEndRaceDelay then
                raceLogic.endActiveRaceQuick()
            end
            if raceLogic and raceLogic.currVeh then
                raceLogic.currVehEnt = nil
                raceLogic.currVeh = nil
            end
            self.runtimeData.inGame = false
        end)

        Observe('LoadingScreenLogicController', 'OnInitialize', function(_, event)
            if raceLogic and raceLogic.raceInProgress and noVehicleEndRaceDelay then
                Cron.Halt(noVehicleEndRaceDelay)
                raceLogic.endActiveRaceQuick()
            elseif raceLogic and raceLogic.raceInProgress and not noVehicleEndRaceDelay then
                raceLogic.endActiveRaceQuick()
            end
        end)

        ObserveAfter("BaseMappinBaseController", "UpdateRootState", function(this)
            hubs.setupMappins(timeTrials.availableRaces)
        end)

        Observe('hudCarRaceController', 'OnInitialize', function(this)
            raceLogic.SetupHUDcontroller(this)
        end)

        Observe('hudCarRaceController', 'OnUninitialize', function(this)
            raceLogic.hudController = nil
        end)

        Observe('PlayerPuppet', 'OnAction', function(_, action)
            if timeTrials.runtimeData.inEditor then
                local actionName = Game.NameToString(action:GetName(action))
                local actionType = action:GetType(action).value
                if actionName == 'Reload' and actionType == "BUTTON_PRESSED" then
                    if trackEditor.readyToPlace == true then
                        trackEditor.keyPressed = true
                    end
                elseif actionName == 'Reload' and actionType == "BUTTON_RELEASED" then
                    trackEditor.keyPressed = false
                    if trackEditor.readyToPlace == true then
                        trackEditor.onPlaceRelease(trackEditor, timeTrials.trackData)
                    end
                end
            end
            if raceLogic and raceLogic.raceInProgress and user.settings.useSpeedbreaker then
                local actionName = Game.NameToString(action:GetName(action))
                local actionType = action:GetType(action).value
                if actionName == 'Exit' and actionType == "BUTTON_PRESSED" then
                    local latTireThinMult = GameOptions.GetFloat('Vehicle', 'LateralTireSkidThinningMultiplier')
                    local latTireThinLength = GameOptions.GetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength')
                    local lowVelStopResist = GameOptions.GetBool('Vehicle', 'EnableLowVelStoppingResistance')
                    local disableDamage = GameOptions.GetBool('Vehicle', 'DisableCollisionDamage')
                    local maxAngSpd = GameOptions.GetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed')
                    local maxLinSpd = GameOptions.GetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed')
                    local velSmoothTime = GameOptions.GetFloat('Vehicle', 'VelocitySmoothingTime')
                    if hasAppliedTD == false then
                        StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorPlayerBuffLegendaryPlusPlus'), 0)
                        StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.DetectorRushPlayerBuffUncommonPlus'), 0)
                        GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningMultiplier', 3.5)
                        GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength', 25.0)
                        GameOptions.SetBool('Vehicle', 'EnableLowVelStoppingResistance', false)
                        GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed', 75.0)
                        GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed', 40.0)
                        GameOptions.SetFloat('Vehicle', 'VelocitySmoothingTime', 0.05)
                        hasAppliedTD = true
                        resetIni = Cron.After(5.0, function()
                            GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningMultiplier', latTireThinMult)
                            GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength', latTireThinLength)
                            GameOptions.SetBool('Vehicle', 'EnableLowVelStoppingResistance', lowVelStopResist)
                            GameOptions.SetBool('Vehicle', 'DisableCollisionDamage', disableDamage)
                            GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed', maxAngSpd)
                            GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed', maxLinSpd)
                            GameOptions.SetFloat('Vehicle', 'VelocitySmoothingTime', velSmoothTime)
                            resetIni = nil
                            removeTD = Cron.After(15.0, function()
                                if Game.GetPlayer() then
                                    StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorPlayerBuffLegendaryPlusPlus'), -1)
                                    StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorCooldown'), -1)
                                    StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.DetectorRushPlayerBuffUncommonPlus'), -1)
                                end
                                hasAppliedTD = false
                                removeTD = nil
                            end)
                        end)
                    end
                end
            end
        end)

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu)
            timeTrials.runtimeData.inMenu = isInMenu
        end)

        Observe("WorldMapMenuGameController", "ShowMappinTooltip", function(this, controller)
            if not this or not world or #world.interactions == 0 or not this.selectedMappin then return end
            mappinID = nil
            selectedMappin = this.selectedMappin
            mappinID = selectedMappin.mappin
            mappinPos = ToVector4(mappinID:GetWorldPosition())
        end)

        Observe("WorldMapTooltipBaseController", "Show", function(this)
            if not world or #world.interactions == 0 then return end
            for _, track in ipairs(timeTrials.availableRaces) do
                local trackPos = Vector4.new(track.startInteraction.position.x, track.startInteraction.position.y, track.startInteraction.position.z)
                if calculateDistance(trackPos, mappinPos) < 10 then
                    if this and this.titleText and this.descText then
                        this.titleText:SetText(track.name)
                        if track.description and track.description ~= '' then
                            this.descText:SetText(track.description)
                        else
                            this.descText:SetText("Gotta go fast! Race through the checkpoint and to the finish line.")
                        end
                        local totalDistance = 0
                        if track.checkpoints and #track.checkpoints > 1 then
                            for i = 1, #track.checkpoints - 1 do
                                totalDistance = RoundFEx((totalDistance + calculateDistance(track.checkpoints[i].position, track.checkpoints[i + 1].position) * (track.laps or 1)))
                            end
                        end
                    end
                end
            end
        end)
    end)

    registerForEvent('onShutdown', function()
        -- End any in-progress race, remove all hubs, reset every variable
        if raceLogic and raceLogic.raceInProgress then
            pcall(function() raceLogic.endActiveRace(true) end)
        end
        cleanupSpeedbreaker()
        if hubs and hubs.shutdown then
            pcall(function() hubs.shutdown() end)
        end
        if currentMappin then
            pcall(function() Game.GetMappinSystem():UnregisterMappin(currentMappin) end)
            currentMappin = nil
        end
        pcall(resetEverything)
        pcall(function()
            if raceLogic and raceLogic.restoreTrafficAfterRace then
                raceLogic.restoreTrafficAfterRace()
            end
        end)
        -- Final variable wipe (covers anything resetEverything might miss)
        if raceLogic and raceLogic.resetAllState then
            pcall(function() raceLogic.resetAllState() end)
        end
        timeTrials.availableRaces = {}
        timeTrials.raceActive = false
        timeTrials.activeRaceName = 'None'
        world.interactions = {}
    end)
end

registerForEvent("onUpdate", function(dt)
    if Game.GetSystemRequestsHandler():IsPreGame() then
        if timeTrials.runtimeData.inGame == true then
            timeTrials.runtimeData.inGame = false
        end
        if nativeSettings and not addedNativeSettings then
            NativeMenu()
            addedNativeSettings = true
        end
    elseif Game.GetSystemRequestsHandler():IsGamePaused() then
        if nativeSettings and not addedNativeSettings then
            NativeMenu()
            addedNativeSettings = true
        end
    end

    -- Editor placement preview / release handling
    if trackEditor.readyToPlace then
        if trackEditor.keyPressed or trackEditor.centerKeyPressed or trackEditor.leftKeyPressed or trackEditor.rightKeyPressed then
            trackEditor.updatePreview(trackEditor, dt, timeTrials.trackData)
        end
    end

    if not timeTrials.runtimeData.inMenu and timeTrials.runtimeData.inGame then
        Cron.Update(dt)
        interactionUI.update()
        world.update()
        if raceLogic.raceInProgress == true then
            interactionUI.hub = nil
            UpdateLeadMappin()
            timeTrials.raceActive = true
            if timeTrials.track then
                timeTrials.activeRaceName = timeTrials.track.name
            else
                timeTrials.activeRaceName = 'None'
            end
        else
            timeTrials.raceActive = false
            timeTrials.activeRaceName = 'None'
            if currentMappin then
                Game.GetMappinSystem():UnregisterMappin(currentMappin)
                currentMappin = nil
            end
        end
    end
end)

registerInput('NewTrials_RaceBind1', 'Press to activate Speedbreaker ability during races (slows down time for a few seconds)', function(breakpress)
    if user.settings.useSpeedbreaker == false then return end
    if not breakpress or not raceLogic or not raceLogic.raceInProgress or hasAppliedTD then return end

    speedbreakerVehicleState = {
        latTireThinMult = GameOptions.GetFloat('Vehicle', 'LateralTireSkidThinningMultiplier'),
        latTireThinLength = GameOptions.GetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength'),
        lowVelStopResist = GameOptions.GetBool('Vehicle', 'EnableLowVelStoppingResistance'),
        disableDamage = GameOptions.GetBool('Vehicle', 'DisableCollisionDamage'),
        maxAngSpd = GameOptions.GetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed'),
        maxLinSpd = GameOptions.GetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed'),
        velSmoothTime = GameOptions.GetFloat('Vehicle', 'VelocitySmoothingTime')
    }

    StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorPlayerBuffLegendaryPlusPlus'), 0)
    StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.DetectorRushPlayerBuffUncommonPlus'), 0)
    GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningMultiplier', 3.5)
    GameOptions.SetFloat('Vehicle', 'LateralTireSkidThinningVectorMaxLength', 25.0)
    GameOptions.SetBool('Vehicle', 'EnableLowVelStoppingResistance', false)
    GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxAngularSpeed', 75.0)
    GameOptions.SetFloat('Vehicle', 'ForceMoveToMaxLinearSpeed', 40.0)
    GameOptions.SetFloat('Vehicle', 'VelocitySmoothingTime', 0.05)
    hasAppliedTD = true

    resetIni = Cron.After(5.0, function()
        restoreSpeedbreakerVehicleState()
        resetIni = nil
        removeTD = Cron.After(15.0, function()
            if Game.GetPlayer() then
                StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorPlayerBuffLegendaryPlusPlus'), -1)
                StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.SynapticAcceleratorCooldown'), -1)
                StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), TweakDBID.new('BaseStatusEffect.DetectorRushPlayerBuffUncommonPlus'), -1)
            end
            hasAppliedTD = false
            removeTD = nil
        end)
    end)
end)

registerInput('NewTrials_BuildBind1', 'Hold and release to place current item', function(keypress)
    if trackEditor.readyToPlace ~= true then return end
    if keypress then
        trackEditor.keyPressed = true
    else
        trackEditor.keyPressed = false
        trackEditor.onPlaceRelease(trackEditor, timeTrials.trackData)
    end
end)

registerInput('NewTrials_BuildBind2_CenterCP', 'Hold and release to place center-style checkpoint', function(keypress)
    if trackEditor.readyToPlace ~= true then return end
    if keypress then
        trackEditor.centerKeyPressed = true
    else
        trackEditor.centerKeyPressed = false
        trackEditor.onSpecificCpRelease(trackEditor, timeTrials.trackData, 'center')
    end
end)

registerInput('NewTrials_BuildBind3_LeftCP', 'Hold and release to place left-style checkpoint', function(keypress)
    if trackEditor.readyToPlace ~= true then return end
    if keypress then
        trackEditor.leftKeyPressed = true
    else
        trackEditor.leftKeyPressed = false
        trackEditor.onSpecificCpRelease(trackEditor, timeTrials.trackData, 'left')
    end
end)

registerInput('NewTrials_BuildBind4_RightCP', 'Hold and release to place right-style checkpoint', function(keypress)
    if trackEditor.readyToPlace ~= true then return end
    if keypress then
        trackEditor.rightKeyPressed = true
    else
        trackEditor.rightKeyPressed = false
        trackEditor.onSpecificCpRelease(trackEditor, timeTrials.trackData, 'right')
    end
end)

registerForEvent('onDraw', function()
    if windowSettings.Current.mywindowhidden ~= true then
        local ctx = {
            cetopen = cetopen,
            user = user,
            timeTrials = timeTrials,
            raceLogic = raceLogic,
            currentMappin = currentMappin,
            nativeCpSounds = nativeCpSounds,
            selectedCpSound = selectedCpSound,
            setSelectedCpSound = function(sound, i)
                selectedCpSound = sound
                user.settings.cpSoundFx = i
                SaveSettings()
            end,
            SaveSettings = SaveSettings,
            SaveWindowSettings = SaveWindowSettings,
            LoadRecentTimes = LoadRecentTimes,
            vehicleNames = vehicleNames,
            raceNames = raceNames,
            selectedVehicleName = selectedVehicleName,
            selectedTrackName = selectedTrackName,
            setSelectedVehicleName = function(n) selectedVehicleName = n end,
            setSelectedTrackName = function(n) selectedTrackName = n end,
            listTrackFiles = listTrackFiles,
            trackFiles = trackFiles,
            exportTrackData = exportTrackData,
            importTrackData = importTrackData,
            windowSettings = windowSettings,
            TeleportToRace = TeleportToRace,
        }
        editorWindow.Draw(ctx)
    end
    if raceLogic and raceLogic.track and raceLogic.raceInProgress and raceLogic.track.hasCustomWindow then
        raceLogic.track.DrawCustomWindow()
    end
    local WindowHiderTool = GetMod("WindowHiderTool")
    if WindowHiderTool and cetopen then
        DrawWindowHider()
    elseif not WindowHiderTool then
        windowSettings.Current.mywindowhidden = false
    end
end)

registerForEvent('onOverlayOpen', function()
    LoadSettings()
    LoadWindowSettings()
    LoadRecentTimes()
    hasPopulatedNames = false
    hasPopulatedVehNames = false
    PopulateRaceNames()
    PopulateVehicleNames()
    getAvailableRaces()
    selectedCpSound = nativeCpSounds[user.settings.cpSoundFx] or nativeCpSounds[1]
    cetopen = true
end)

registerForEvent('onOverlayClose', function()
    cetopen = false
end)

return timeTrials, timeTrials:new()
