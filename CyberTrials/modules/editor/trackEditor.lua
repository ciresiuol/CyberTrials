--[[
    CyberTrials Track Editor module
    Handles placement, preview entities, deletion, import/export helpers, and item editing.
]]

local messages = require("modules/utils/messages")

local trackEditor = {
    -- Mode / placement state
    readyToPlace = false,
    placingStartLine = false,
    placingCheckpoint = false,
    placingInteraction = false,
    placingProp = false,

    -- Key press state
    keyPressed = false,
    centerKeyPressed = false,
    leftKeyPressed = false,
    rightKeyPressed = false,
    isPlacingKey1 = false,
    isPlacingKey2 = false,
    isPlacingKey3 = false,
    isPlacingKey4 = false,

    -- Entity tracking
    ObjectEntIDs = {},
    propEntIDs = {},
    hubEntityID = nil,
    startEntityID = nil,

    -- Paths
    availablePaths = {
        'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent',
        'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent',
        'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent',
    },
    selectedPath = 'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent',
    availablePropPaths = {
        'base\\gameplay\\devices\\traffic\\road_blockade\\road_barrier_poor_small.ent',
        'base\\gameplay\\devices\\lighting\\street\\street_lamps\\street_lamp_f.ent',
        'base\\environment\\decoration\\public_utility\\roadblock\\blockade\\destruction\\blockade_a_dst.ent',
        'base\\gameplay\\devices\\doors\\gates\\fence_barred_large.ent',
        'base\\environment\\decoration\\containers\\barrel\\drum\\barrel_drum_a_trash_a_phx.ent',
        'ep1\\environment\\decoration\\construction\\power_generator\\construction_lamp.ent',
    },
    selectedPropPath = 'base\\gameplay\\devices\\traffic\\road_blockade\\road_barrier_poor_small.ent',
    interactionPath = 'base\\environment\\ld_kit\\marker_pink_small.ent',
    startLinePath = 'base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent',

    -- Preview / flash
    flashInterval = 0.25,
    flashTimer = 0,
    flashEntityID = nil,
    lastPreviewPos = nil,

    -- Edit mode
    editingItem = false,
    editType = nil,      -- "checkpoint" | "prop" | "start" | "interaction"
    editIndex = nil,     -- 1-based for lists
    selectedCpIndex = 1,
    selectedPropIndex = 1,

    -- Cached look-at position used on release
    position = nil,
}

local function destroyEntity(entityID)
    if not entityID then return end
    local obj = Game.FindEntityByID(entityID)
    if obj and obj:GetEntity() then
        obj:GetEntity():Destroy()
    end
end

local function clearFlashEntity(self)
    destroyEntity(self.flashEntityID)
    self.flashEntityID = nil
    self.flashTimer = 0
    self.lastPreviewPos = nil
end

function trackEditor.getDisplayName(path)
    return path:match("([^\\]+)%.ent$") or path
end

function trackEditor.hasInteractionPoint(trackData)
    return trackData and trackData.hubPosition and trackData.hubPosition.position ~= nil
end

function trackEditor.canPlaceOtherItems(trackData)
    return trackEditor.hasInteractionPoint(trackData)
end

local function makePosRot(mappinpos)
    local pos = { x = mappinpos.x, y = mappinpos.y, w = 1.0, z = mappinpos.z }
    local rot = { roll = 0.0, pitch = 0.0, yaw = Game.GetPlayer():GetWorldYaw() }
    return pos, rot
end

local function spawnAt(path, pos, rot)
    local trans = Game.GetPlayer():GetWorldTransform()
    trans:SetOrientation(ToEulerAngles(rot):ToQuat())
    trans:SetPosition(ToVector4(pos))
    return exEntitySpawner.Spawn(path, trans, "")
end

-- Preview entity that follows look-at while key is held
function trackEditor.updatePreview(self, dt, trackData)
    if not self.keyPressed and not self.centerKeyPressed and not self.leftKeyPressed and not self.rightKeyPressed then
        return
    end
    if not self.readyToPlace then return end

    local player = Game.GetPlayer()
    if not player then return end
    local tgtSys = Game.GetTargetingSystem()
    local lookPos = tgtSys:GetLookAtPosition(player, true, true)
    self.position = lookPos

    local path = nil
    if self.editingItem then
        if self.editType == "checkpoint" then
            path = trackData.checkpointEnts[self.editIndex] or self.selectedPath
        elseif self.editType == "prop" then
            path = trackData.propEnts[self.editIndex] or self.selectedPropPath
        elseif self.editType == "start" then
            path = self.startLinePath
        elseif self.editType == "interaction" then
            path = self.interactionPath
        end
    elseif self.placingProp then
        path = self.selectedPropPath
    elseif self.placingCheckpoint or self.centerKeyPressed or self.leftKeyPressed or self.rightKeyPressed then
        if self.centerKeyPressed then
            path = self.availablePaths[1]
        elseif self.leftKeyPressed then
            path = self.availablePaths[3]
        elseif self.rightKeyPressed then
            path = self.availablePaths[2]
        else
            path = self.selectedPath
        end
    elseif self.placingStartLine then
        path = self.startLinePath
    elseif self.placingInteraction then
        path = self.interactionPath
    end

    if not path then return end

    self.flashTimer = self.flashTimer + dt
    local needRespawn = false
    if not self.flashEntityID then
        needRespawn = true
    elseif self.flashTimer >= self.flashInterval then
        needRespawn = true
        self.flashTimer = 0
    end

    if needRespawn then
        clearFlashEntity(self)
        local pos, rot = makePosRot(lookPos)
        self.flashEntityID = spawnAt(path, pos, rot)
        self.lastPreviewPos = lookPos
    end
end

function trackEditor.clearPreview(self)
    clearFlashEntity(self)
end

-- Called when placement key is released
function trackEditor.onPlaceRelease(self, trackData)
    clearFlashEntity(self)
    if not self.readyToPlace or not self.position then return end

    if self.editingItem then
        trackEditor.finishEdit(self, trackData)
        return
    end

    if self.placingProp then
        trackEditor.NewProp(self, trackData, self.position, true)
    elseif self.placingCheckpoint then
        trackEditor.NewCheckpoint(self, trackData, self.position)
    elseif self.placingInteraction then
        trackEditor.NewInteractionHub(self, trackData, self.position)
    elseif self.placingStartLine then
        trackEditor.NewStartLine(self, trackData, self.position)
    end
end

function trackEditor.onSpecificCpRelease(self, trackData, dir)
    clearFlashEntity(self)
    if not self.readyToPlace or not self.position then return end
    if self.editingItem then return end
    trackEditor.NewSpecificCheckpoint(self, trackData, self.position, dir)
end

-- ===== Placement guards =====
local function requireInteraction(self, trackData)
    if trackEditor.canPlaceOtherItems(trackData) then
        return true
    end
    messages.ShowWarningMessage('Place an Interaction Point first before placing anything else.', 4.0)
    return false
end

-- ===== Permanent placement =====
function trackEditor.SpawnProp(self, trackData, mappinpos, isPermanent)
    local pos, rot = makePosRot(mappinpos)
    local entityID = spawnAt(self.selectedPropPath, pos, rot)
    if isPermanent then
        table.insert(self.propEntIDs, entityID)
        table.insert(trackData.props, { position = pos, rotation = rot })
        table.insert(trackData.propEnts, self.selectedPropPath)
        trackData.totalProps = #trackData.props
        messages.ShowWarningMessage('Placed Prop Number ' .. tostring(trackData.totalProps), 3.0)
    end
    return entityID
end

function trackEditor.NewProp(self, trackData, mappinpos, isPermanent)
    if not requireInteraction(self, trackData) then return end
    if trackData.totalProps >= 150 then
        messages.ShowWarningMessage('You have reached the maximum of 150 props', 4.0)
        return
    end
    trackEditor.SpawnProp(self, trackData, mappinpos, isPermanent)
end

function trackEditor.NewCheckpoint(self, trackData, mappinpos)
    if not requireInteraction(self, trackData) then return end
    if trackData.totalCheckpoints >= 250 then
        messages.ShowWarningMessage('You have reached the maximum of 250 checkpoints', 4.0)
        return
    end
    local pos, rot = makePosRot(mappinpos)
    local entityID = spawnAt(self.selectedPath, pos, rot)
    table.insert(self.ObjectEntIDs, entityID)
    table.insert(trackData.checkpoints, { position = pos, rotation = rot })
    table.insert(trackData.checkpointEnts, self.selectedPath)
    trackData.totalCheckpoints = #trackData.checkpoints
    messages.ShowWarningMessage('Placed Checkpoint Number ' .. tostring(trackData.totalCheckpoints), 3.0)
end

function trackEditor.NewSpecificCheckpoint(self, trackData, mappinpos, cpDir)
    if not requireInteraction(self, trackData) then return end
    if trackData.totalCheckpoints >= 250 then
        messages.ShowWarningMessage('You have reached the maximum of 250 checkpoints', 4.0)
        return
    end
    local path = self.availablePaths[1]
    if cpDir == 'right' then
        path = self.availablePaths[2]
    elseif cpDir == 'left' then
        path = self.availablePaths[3]
    end
    local pos, rot = makePosRot(mappinpos)
    local entityID = spawnAt(path, pos, rot)
    table.insert(self.ObjectEntIDs, entityID)
    table.insert(trackData.checkpoints, { position = pos, rotation = rot })
    table.insert(trackData.checkpointEnts, path)
    trackData.totalCheckpoints = #trackData.checkpoints
    messages.ShowWarningMessage('Placed Checkpoint Number ' .. tostring(trackData.totalCheckpoints), 3.0)
end

function trackEditor.NewStartLine(self, trackData, mappinpos)
    if not requireInteraction(self, trackData) then return end
    if trackData.startPosition and trackData.startPosition.position then
        messages.ShowWarningMessage('You have reached the maximum of 1 starting line', 4.0)
        return
    end
    local pos, rot = makePosRot(mappinpos)
    self.startEntityID = spawnAt(self.startLinePath, pos, rot)
    trackData.startPosition = { position = pos, rotation = rot }
    messages.ShowWarningMessage('Placed Start Line', 3.0)
end

function trackEditor.NewInteractionHub(self, trackData, mappinpos)
    if trackData.hubPosition and trackData.hubPosition.position then
        messages.ShowWarningMessage('You have reached the maximum of 1 interaction hub', 4.0)
        return
    end
    local pos, rot = makePosRot(mappinpos)
    self.hubEntityID = spawnAt(self.interactionPath, pos, rot)
    trackData.hubPosition = { position = pos, rotation = rot }
    messages.ShowWarningMessage('Placed Interaction Point', 3.0)
end

-- ===== Deletion =====
function trackEditor.deleteAllProps(self, trackData)
    for _, entityID in ipairs(self.propEntIDs) do
        destroyEntity(entityID)
    end
    self.propEntIDs = {}
    trackData.props = {}
    trackData.propEnts = {}
    trackData.totalProps = 0
end

function trackEditor.deleteAllCheckpoints(self, trackData)
    for _, entityID in ipairs(self.ObjectEntIDs) do
        destroyEntity(entityID)
    end
    self.ObjectEntIDs = {}
    trackData.checkpoints = {}
    trackData.checkpointEnts = {}
    trackData.totalCheckpoints = 0
end

function trackEditor.deleteStartLine(self, trackData)
    destroyEntity(self.startEntityID)
    self.startEntityID = nil
    trackData.startPosition = {}
end

function trackEditor.deleteInteractionHub(self, trackData)
    destroyEntity(self.hubEntityID)
    self.hubEntityID = nil
    trackData.hubPosition = {}
end

function trackEditor.DeleteLastProp(self, trackData)
    if #self.propEntIDs == 0 then
        messages.ShowWarningMessage('No props to delete', 3.0)
        return
    end
    local lastIndex = #self.propEntIDs
    destroyEntity(self.propEntIDs[lastIndex])
    table.remove(self.propEntIDs, lastIndex)
    table.remove(trackData.props, lastIndex)
    table.remove(trackData.propEnts, lastIndex)
    trackData.totalProps = #trackData.props
end

function trackEditor.DeleteLastObject(self, trackData)
    local lastIndex = #self.ObjectEntIDs
    if lastIndex == 0 then return end
    destroyEntity(self.ObjectEntIDs[lastIndex])
    table.remove(self.ObjectEntIDs, lastIndex)
    table.remove(trackData.checkpoints, lastIndex)
    table.remove(trackData.checkpointEnts, lastIndex)
    trackData.totalCheckpoints = #trackData.checkpoints
end

function trackEditor.deleteEverything(self, trackData)
    trackEditor.deleteStartLine(self, trackData)
    trackEditor.deleteAllCheckpoints(self, trackData)
    trackEditor.deleteInteractionHub(self, trackData)
    trackEditor.deleteAllProps(self, trackData)
    trackData.name = trackData.name or ''
    trackData.description = trackData.description or ''
    trackData.numberOfLaps = trackData.numberOfLaps or 1
    trackData.creator = trackData.creator or 'CyberTrials Editor'
    self.editingItem = false
    self.editType = nil
    self.editIndex = nil
    clearFlashEntity(self)
end

-- ===== Spawn from imported data =====
function trackEditor.spawnFromData(self, trackData)
    for i, checkpoint in ipairs(trackData.checkpoints) do
        local path = trackData.checkpointEnts[i] or self.availablePaths[1]
        local entityID = spawnAt(path, checkpoint.position, checkpoint.rotation)
        table.insert(self.ObjectEntIDs, entityID)
    end
    for i, prop in ipairs(trackData.props) do
        local path = trackData.propEnts[i] or self.availablePropPaths[1]
        local entityID = spawnAt(path, prop.position, prop.rotation)
        table.insert(self.propEntIDs, entityID)
    end
    if trackData.hubPosition and trackData.hubPosition.position then
        self.hubEntityID = spawnAt(self.interactionPath, trackData.hubPosition.position, trackData.hubPosition.rotation)
    end
    if trackData.startPosition and trackData.startPosition.position then
        self.startEntityID = spawnAt(self.startLinePath, trackData.startPosition.position, trackData.startPosition.rotation)
    end
end

-- ===== Edit mode =====
function trackEditor.beginEdit(self, trackData, editType, index)
    if not trackData then return end
    self.editingItem = true
    self.editType = editType
    self.editIndex = index
    self.placingStartLine = false
    self.placingCheckpoint = false
    self.placingInteraction = false
    self.placingProp = false

    local pos = nil
    if editType == "checkpoint" and trackData.checkpoints[index] then
        pos = trackData.checkpoints[index].position
    elseif editType == "prop" and trackData.props[index] then
        pos = trackData.props[index].position
    elseif editType == "start" and trackData.startPosition and trackData.startPosition.position then
        pos = trackData.startPosition.position
    elseif editType == "interaction" and trackData.hubPosition and trackData.hubPosition.position then
        pos = trackData.hubPosition.position
    end

    if pos then
        local player = Game.GetPlayer()
        if player then
            local tp = Game.GetTeleportationFacility()
            if tp then
                local yaw = player:GetWorldYaw()
                tp:Teleport(player, ToVector4({ x = pos.x, y = pos.y, z = pos.z + 1.0, w = 1.0 }), EulerAngles.new(0, 0, yaw))
            end
        end
        messages.ShowWarningMessage('Editing selected item. Hold placement key to relocate, release to confirm.', 5.0)
    else
        messages.ShowWarningMessage('Selected item has no position data.', 3.0)
        self.editingItem = false
        self.editType = nil
        self.editIndex = nil
    end
end

function trackEditor.finishEdit(self, trackData)
    if not self.editingItem or not self.position then
        self.editingItem = false
        self.editType = nil
        self.editIndex = nil
        return
    end

    local pos, rot = makePosRot(self.position)
    local path = nil

    if self.editType == "checkpoint" and self.editIndex and trackData.checkpoints[self.editIndex] then
        path = trackData.checkpointEnts[self.editIndex] or self.selectedPath
        destroyEntity(self.ObjectEntIDs[self.editIndex])
        local newId = spawnAt(path, pos, rot)
        self.ObjectEntIDs[self.editIndex] = newId
        trackData.checkpoints[self.editIndex] = { position = pos, rotation = rot }
        messages.ShowWarningMessage('Checkpoint #' .. tostring(self.editIndex) .. ' position updated.', 3.0)
    elseif self.editType == "prop" and self.editIndex and trackData.props[self.editIndex] then
        path = trackData.propEnts[self.editIndex] or self.selectedPropPath
        destroyEntity(self.propEntIDs[self.editIndex])
        local newId = spawnAt(path, pos, rot)
        self.propEntIDs[self.editIndex] = newId
        trackData.props[self.editIndex] = { position = pos, rotation = rot }
        messages.ShowWarningMessage('Prop #' .. tostring(self.editIndex) .. ' position updated.', 3.0)
    elseif self.editType == "start" then
        path = self.startLinePath
        destroyEntity(self.startEntityID)
        self.startEntityID = spawnAt(path, pos, rot)
        trackData.startPosition = { position = pos, rotation = rot }
        messages.ShowWarningMessage('Start Line position updated.', 3.0)
    elseif self.editType == "interaction" then
        path = self.interactionPath
        destroyEntity(self.hubEntityID)
        self.hubEntityID = spawnAt(path, pos, rot)
        trackData.hubPosition = { position = pos, rotation = rot }
        messages.ShowWarningMessage('Interaction Point position updated.', 3.0)
    end

    self.editingItem = false
    self.editType = nil
    self.editIndex = nil
    clearFlashEntity(self)
end

function trackEditor.cancelEdit(self)
    self.editingItem = false
    self.editType = nil
    self.editIndex = nil
    clearFlashEntity(self)
end

function trackEditor.resetPlacementFlags(self)
    self.placingStartLine = false
    self.placingCheckpoint = false
    self.placingInteraction = false
    self.placingProp = false
    self.keyPressed = false
    self.centerKeyPressed = false
    self.leftKeyPressed = false
    self.rightKeyPressed = false
    self.isPlacingKey1 = false
    self.isPlacingKey2 = false
    self.isPlacingKey3 = false
    self.isPlacingKey4 = false
    clearFlashEntity(self)
end

function trackEditor.setPlaceMode(self, mode, trackData)
    -- mode: "interaction" | "start" | "checkpoint" | "prop"
    trackEditor.resetPlacementFlags(self)
    trackEditor.cancelEdit(self)

    if mode == "interaction" then
        if self.hubEntityID then
            messages.ShowWarningMessage('Please delete the previously added interaction point before adding a new one.', 4.0)
            return
        end
        self.placingInteraction = true
        return
    end

    if not trackEditor.canPlaceOtherItems(trackData) then
        messages.ShowWarningMessage('Place an Interaction Point first before placing anything else.', 4.0)
        return
    end

    if mode == "start" then
        if self.startEntityID then
            messages.ShowWarningMessage('Please delete the previously added start line before adding a new one.', 4.0)
            return
        end
        self.placingStartLine = true
    elseif mode == "checkpoint" then
        self.placingCheckpoint = true
    elseif mode == "prop" then
        self.placingProp = true
    end
end

return trackEditor
