--[[
    CyberTrials - Race Logic Module (rewritten)

    Checkpoint model
    ----------------
    Start line : treated as virtual index 0. Spawned during pre-race/countdown,
                 destroyed the instant the race begins (when driving is enabled).
                 For multi-lap races the same start-line pose is also the lap-end
                 / finish gate after every full set of physical checkpoints.

    Single-lap : virtual 1 .. totalCPs
                 finish = last physical checkpoint (finish arch entity)
    Multi-lap  : each lap = physical CPs 1..totalCPs, then START LINE gate
                 finishVirtual = (totalCPs + 1) * numberOfLaps
                 start-line gate uses normal forward checkpoint entity

    Visibility
    ----------
    Only the next 2 virtual checkpoints exist in the world at once
    (1 if the next is the race finish). Crossed CPs are destroyed immediately.
    Entities are allowed time to stream in; we never thrash-respawn during that window.

    Active race vehicle
    -------------------
    currVeh is set ONLY when the player explicitly enters or exits a vehicle
    (via EnteringEvents / ExitingEvents in init.lua). No nearby-vehicle
    auto-discovery is used to define the active race vehicle.

    Session cleanup
    ---------------
    Any race end (finish or abort) destroys all CP/prop entities, clears every
    runtime field, restores traffic/UI/hubs, and marks the session so the next
    start waits briefly before spawning.
]]

local Cron = require("modules/external/Cron")
local user = require("modules/UserSettings/config/user")

local REGULAR_CP_PATH = "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent"
local FINISH_CP_PATH  = "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_finish.ent"

local SETTLE_SEC = 2.0  -- do not treat a missing entity as failed before this

local nativeCpSounds = {
    [1] = "sq024_race_start_fireworks",
    [2] = "ui_hacking_qh_hover",
    [3] = "dev_pocket_radio_on",
    [4] = "dev_pocket_radio_off",
}

local raceLogic = {
    raceInProgress   = false,
    track            = nil,
    numberOfLaps     = 1,
    currentLap       = 1,
    currentCP        = 0,
    totalCPs         = 0,
    finishVirtual    = 0,
    positions        = {},
    activeEnts       = {},   -- [virtualIndex] = entityId
    spawnAt          = {},   -- [virtualIndex] = os.clock when spawned
    activeProps      = {},
    hudController    = nil,
    playerMounted    = false,
    currVeh          = nil,
    trackedJournalEntry = nil,
    hitSound         = "",
    cleanupCallback  = nil,
    raceStartSimTime = nil,
    lapStartSimTime  = nil,
    bestLapMs        = nil,
    _trafficStoppedByMod = false,
    _sessionId       = 0,    -- increments on every start/end; cancels stale Crons
    _priorRace       = false,
    -- Every entity ID this module has ever spawned this game session.
    -- Save-reload clears the engine; we must clear these without a reload.
    _lifetimeIds     = {},
    _lastTrackSnap   = nil,  -- {checkpoints, startPosition} for proximity purge
    _startLineEntId  = nil,  -- pre-race / lap-gate start-line entity
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function showWarning(message, duration)
    local text = SimpleScreenMessage.new()
    text.duration = duration or 4.0
    text.message = message
    text.isInstant = true
    text.isShown = true
    local bb = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UI_Notifications)
    if bb then
        bb:SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(text), true)
    end
end

local function showNotification(message, duration)
    local text = SimpleScreenMessage.new()
    text.duration = duration or 4.0
    text.message = message
    text.isInstant = true
    text.isShown = true
    local bb = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UI_Notifications)
    if bb then
        bb:SetVariant(GetAllBlackboardDefs().UI_Notifications.OnscreenMessage, ToVariant(text), true)
    end
end

local function distance(a, b)
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function removeSpaces(name)
    return (name or ""):gsub("%s+", "")
end

function raceLogic.repairVehicle(vehicle)
    if not vehicle then return end
    pcall(function()
        local component = vehicle.vehicleComponent
        if not component and vehicle.GetVehicleComponent then
            component = vehicle:GetVehicleComponent()
        end
        if component and component.RepairVehicle then
            component:RepairVehicle()
        end
    end)
end

function raceLogic.stopTrafficForRace()
    if not user.settings.disableTraffic then return end
    GameOptions.SetBool("Traffic", "StopSpawn", true)
    raceLogic._trafficStoppedByMod = true
end

function raceLogic.restoreTrafficAfterRace()
    if raceLogic._trafficStoppedByMod then
        GameOptions.SetBool("Traffic", "StopSpawn", false)
        raceLogic._trafficStoppedByMod = false
    end
end

function raceLogic.SetupHUDcontroller(hudController)
    raceLogic.hudController = hudController
end

function raceLogic.setCleanupCallback(callback)
    raceLogic.cleanupCallback = callback
end

local function runCleanupCallback()
    if raceLogic.cleanupCallback then
        pcall(raceLogic.cleanupCallback)
    end
end

local function restoreInteractionHubs()
    local ok, hubs = pcall(require, "modules/utils/interactionHubs")
    if ok and hubs and hubs.restoreAfterRace then
        pcall(hubs.restoreAfterRace)
    end
end

-- ---------------------------------------------------------------------------
-- Virtual checkpoint addressing
-- ---------------------------------------------------------------------------

local function cpsPerLap()
    if raceLogic.numberOfLaps > 1 then
        return raceLogic.totalCPs + 1
    end
    return math.max(1, raceLogic.totalCPs)
end

local function toSlot(v)
    local cpl = cpsPerLap()
    if cpl <= 0 then return 1 end
    return ((v - 1) % cpl) + 1
end

local function isStartLineGate(v)
    return raceLogic.numberOfLaps > 1 and toSlot(v) > raceLogic.totalCPs
end

local function toPhysical(v)
    if isStartLineGate(v) then return nil end
    if raceLogic.totalCPs <= 0 then return 1 end
    if raceLogic.numberOfLaps > 1 then
        return toSlot(v)
    end
    return ((v - 1) % raceLogic.totalCPs) + 1
end

local function isRaceFinish(v)
    return raceLogic.finishVirtual > 0 and v >= raceLogic.finishVirtual
end

local function isLapEnd(v)
    if raceLogic.numberOfLaps > 1 then
        return isStartLineGate(v)
    end
    return raceLogic.totalCPs > 0 and (v % raceLogic.totalCPs) == 0
end

local function getStartLinePose()
    local t = raceLogic.track
    if t and t.startPosition and t.startPosition.position then
        return t.startPosition.position, t.startPosition.rotation or { roll = 0, pitch = 0, yaw = 0 }
    end
    if t and t.checkpoints and t.checkpoints[1] then
        return t.checkpoints[1].position, t.checkpoints[1].rotation or { roll = 0, pitch = 0, yaw = 0 }
    end
    return nil, nil
end

local function getCPPose(v)
    if isStartLineGate(v) then
        return getStartLinePose()
    end
    local p = toPhysical(v)
    local cp = raceLogic.track and raceLogic.track.checkpoints and p and raceLogic.track.checkpoints[p]
    if not cp then return nil, nil end
    return cp.position, cp.rotation
end

local function getCheckpointPath(v)
    -- Multi-lap start-line gate: always normal forward CP
    if isStartLineGate(v) then
        return REGULAR_CP_PATH
    end
    -- Absolute finish on a single-lap (or non-start-line) gate: finish arch
    if isRaceFinish(v) then
        return FINISH_CP_PATH
    end
    local p = toPhysical(v)
    local path = raceLogic.track and raceLogic.track.checkpointEnts and p and raceLogic.track.checkpointEnts[p]
    if not path or string.find(tostring(path), "race_checkpoint_finish", 1, true) then
        return REGULAR_CP_PATH
    end
    return path
end

-- ---------------------------------------------------------------------------
-- Entity destroy / spawn (simple, no thrash)
-- ---------------------------------------------------------------------------

local function destroyId(id)
    if not id then return end
    -- Always request despawn by ID first (works even if entity not resolved yet)
    pcall(function()
        local pss = Game.GetPreventionSpawnSystem()
        if pss and pss.RequestDespawn then
            pss:RequestDespawn(id)
        end
    end)
    local ent = nil
    pcall(function() ent = Game.FindEntityByID(id) end)
    if not ent then return end
    pcall(function() exEntitySpawner.Despawn(ent) end)
    pcall(function()
        if ent.Dispose then ent:Dispose() end
    end)
    pcall(function()
        if ent.GetEntity then
            local inner = ent:GetEntity()
            if inner and inner.Dispose then inner:Dispose() end
        end
    end)
    -- Last-resort: mark as destroyed via GameObject API if present
    pcall(function()
        if ent.Destroy then ent:Destroy() end
    end)
end

local function rememberId(id, pos)
    if not id then return end
    raceLogic._lifetimeIds = raceLogic._lifetimeIds or {}
    raceLogic._lifetimeIds[#raceLogic._lifetimeIds + 1] = id
    if pos then
        raceLogic._lifetimePos = raceLogic._lifetimePos or {}
        raceLogic._lifetimePos[#raceLogic._lifetimePos + 1] = {
            x = pos.x or pos.X, y = pos.y or pos.Y, z = pos.z or pos.Z, id = id
        }
    end
end

-- Immediate hard-destroy of every tracked entity (no deferred Crons that can race a new start)
local function destroyLifetimeIdsNow()
    local list = raceLogic._lifetimeIds or {}
    for _, id in ipairs(list) do
        destroyId(id)
    end
    raceLogic._lifetimeIds = {}
    raceLogic._lifetimePos = {}
end

-- Destroy every entity this mod has ever spawned, with a few deferred retries.
-- Uses a generation token so deferred work from an older cleanup never touches
-- entities belonging to a newer race.
local function destroyLifetimeIds()
    local list = {}
    for _, id in ipairs(raceLogic._lifetimeIds or {}) do
        list[#list + 1] = id
    end
    local gen = (raceLogic._cleanupGen or 0) + 1
    raceLogic._cleanupGen = gen
    raceLogic._lifetimeIds = {}
    raceLogic._lifetimePos = {}

    local function sweep()
        for _, id in ipairs(list) do destroyId(id) end
    end
    sweep()
    Cron.After(0.35, function()
        if raceLogic._cleanupGen ~= gen then return end
        sweep()
    end)
    Cron.After(1.0, function()
        if raceLogic._cleanupGen ~= gen then return end
        sweep()
    end)
    Cron.After(2.5, function()
        if raceLogic._cleanupGen ~= gen then return end
        sweep()
    end)
end

-- Dispose any non-player/vehicle entity within radius of known CP positions
-- without teleporting the player (uses player local spatial query only when near).
local function purgeNearPositions(positions, radius)
    if type(positions) ~= "table" or #positions == 0 then return end
    local player = Game.GetPlayer()
    if not player then return end
    radius = radius or 6.0
    local protect = raceLogic.currVeh or player.mountedVehicle

    local function isProtected(entity)
        if not entity then return true end
        if entity == player or entity == protect then return true end
        local ok = false
        pcall(function()
            if player.mountedVehicle and entity == player.mountedVehicle then ok = true end
            if entity.IsPlayer and entity:IsPlayer() then ok = true end
            if entity.IsVehicle and entity:IsVehicle() then ok = true end
        end)
        return ok
    end

    -- Only scan around the player (safe, no teleport). Caller should run this
    -- while the player is still near the relevant CPs, or after teleports.
    local ents = nil
    pcall(function()
        if player.GetEntitiesAroundObject then
            ents = player:GetEntitiesAroundObject(math.max(radius, 25.0))
        end
    end)
    if type(ents) ~= "table" then return end

    for _, entity in pairs(ents) do
        if entity and not isProtected(entity) then
            local epos = nil
            pcall(function() epos = entity:GetWorldPosition() end)
            if epos then
                for _, p in ipairs(positions) do
                    local dx = (epos.x or 0) - (p.x or 0)
                    local dy = (epos.y or 0) - (p.y or 0)
                    local dz = (epos.z or 0) - (p.z or 0)
                    if (dx*dx + dy*dy + dz*dz) <= (radius * radius) then
                        pcall(function()
                            if entity.Dispose then entity:Dispose() end
                            pcall(function() exEntitySpawner.Despawn(entity) end)
                        end)
                        break
                    end
                end
            end
        end
    end
end

-- Proximity purge: dispose non-player, non-vehicle entities near track CPs / start.
-- Catches invisible leftover race_checkpoint devices a save-reload would otherwise clear.
local function proximityPurgeTrack(track)
    if not track then return end
    local player = Game.GetPlayer()
    local tele = Game.GetTeleportationFacility()
    if not player or not tele then return end

    local positions = {}
    if type(track.checkpoints) == "table" then
        for _, cp in ipairs(track.checkpoints) do
            if cp and cp.position then
                positions[#positions + 1] = cp.position
            end
        end
    end
    if track.startPosition and track.startPosition.position then
        positions[#positions + 1] = track.startPosition.position
    end
    if track.hubPosition and track.hubPosition.position then
        positions[#positions + 1] = track.hubPosition.position
    end
    if #positions == 0 then return end

    local origPos, origOri
    pcall(function()
        origPos = player:GetWorldPosition()
        local t = player:GetWorldTransform()
        if t and t.Orientation then
            origOri = t:GetOrientation():ToEulerAngles()
        end
    end)
    origOri = origOri or EulerAngles.new(0, 0, 0)

    local protect = raceLogic.currVeh or player.mountedVehicle

    local function isProtected(entity)
        if not entity then return true end
        if entity == player or entity == protect then return true end
        local ok = false
        pcall(function()
            if player.mountedVehicle and entity == player.mountedVehicle then ok = true end
            if protect and entity == protect then ok = true end
            if entity.IsPlayer and entity:IsPlayer() then ok = true end
            if entity.IsVehicle and entity:IsVehicle() then ok = true end
            if entity.GetEntity then
                local inner = entity:GetEntity()
                if inner then
                    if inner.IsVehicle and inner:IsVehicle() then ok = true end
                    if inner.IsPlayer and inner:IsPlayer() then ok = true end
                end
            end
        end)
        return ok
    end

    for _, pos in ipairs(positions) do
        pcall(function()
            tele:Teleport(player, ToVector4(pos), EulerAngles.new(0, 0, 0))
        end)
        local ents = nil
        pcall(function()
            if player.GetEntitiesAroundObject then
                ents = player:GetEntitiesAroundObject(4.0)
            end
        end)
        if type(ents) == "table" then
            for _, entity in pairs(ents) do
                if entity and not isProtected(entity) then
                    pcall(function()
                        if entity.Dispose then
                            entity:Dispose()
                        elseif entity.GetEntity then
                            local inner = entity:GetEntity()
                            if inner and inner.Dispose then inner:Dispose() end
                        end
                        pcall(function() exEntitySpawner.Despawn(entity) end)
                    end)
                end
            end
        end
    end

    if origPos then
        pcall(function() tele:Teleport(player, origPos, origOri) end)
    end
end

-- ---------------------------------------------------------------------------
-- Checkpoint entities (rewritten)
--
-- activeEnts[virtualIndex] = entityId from exEntitySpawner.Spawn
-- Window = next 2 virtual indices, or 1 if the next is the race finish.
-- On cross: take the ID out of activeEnts first, then despawn via CET APIs.
-- Never clear activeEnts without destroying the tracked IDs first.
-- ---------------------------------------------------------------------------

local function despawnEntityById(id)
    if not id then return end
    -- CET primary path
    pcall(function()
        local ent = Game.FindEntityByID(id)
        if ent then
            exEntitySpawner.Despawn(ent)
        end
    end)
    pcall(function()
        local pss = Game.GetPreventionSpawnSystem()
        if pss and pss.RequestDespawn then
            pss:RequestDespawn(id)
        end
    end)
    pcall(function()
        local ent = Game.FindEntityByID(id)
        if ent and ent.Dispose then ent:Dispose() end
    end)
end

function raceLogic.despawnCheckpoint(virtualIndex)
    local id = raceLogic.activeEnts[virtualIndex]
    raceLogic.activeEnts[virtualIndex] = nil
    raceLogic.spawnAt[virtualIndex] = nil
    if not id then return end
    despawnEntityById(id)
    -- One short retry for late stream-in
    local sid = raceLogic._sessionId
    Cron.After(0.4, function()
        if sid ~= raceLogic._sessionId then return end
        despawnEntityById(id)
    end)
end

--- Pre-race start-line visual. Despawned as soon as the player is mounted.
local function spawnStartLineEntity()
    if raceLogic._startLineEntId then
        despawnEntityById(raceLogic._startLineEntId)
        raceLogic._startLineEntId = nil
    end
    local pos, rot = getStartLinePose()
    if not pos then return end
    local trans = WorldTransform.new()
    trans:SetPosition(ToVector4(pos))
    trans:SetOrientation(ToEulerAngles(rot or { roll = 0, pitch = 0, yaw = 0 }):ToQuat())
    local id = exEntitySpawner.Spawn(REGULAR_CP_PATH, trans)
    raceLogic._startLineEntId = id
    rememberId(id, pos)
end

local function despawnStartLineEntity()
    local id = raceLogic._startLineEntId
    raceLogic._startLineEntId = nil
    if not id then return end
    despawnEntityById(id)
    local sid = raceLogic._sessionId
    Cron.After(0.4, function()
        if sid ~= raceLogic._sessionId then return end
        despawnEntityById(id)
    end)
end

function raceLogic.despawnStartLine()
    despawnStartLineEntity()
end

function raceLogic.despawnAllCheckpoints()
    local ids = {}
    for v, id in pairs(raceLogic.activeEnts) do
        ids[#ids + 1] = id
        raceLogic.activeEnts[v] = nil
        raceLogic.spawnAt[v] = nil
    end
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    if raceLogic._startLineEntId then
        ids[#ids + 1] = raceLogic._startLineEntId
        raceLogic._startLineEntId = nil
    end
    for _, id in ipairs(ids) do
        despawnEntityById(id)
    end
    local sid = raceLogic._sessionId
    Cron.After(0.5, function()
        if sid ~= raceLogic._sessionId then return end
        for _, id in ipairs(ids) do despawnEntityById(id) end
    end)
end

function raceLogic.despawnProps()
    for i, propId in ipairs(raceLogic.activeProps) do
        despawnEntityById(propId)
        raceLogic.activeProps[i] = nil
    end
    raceLogic.activeProps = {}
end

--- Spawn a single virtual checkpoint if it is still needed and not already live.
local function spawnOne(v)
    if not raceLogic.track or raceLogic.finishVirtual <= 0 then return end
    if v < 1 or v > raceLogic.finishVirtual then return end
    if v <= raceLogic.currentCP then return end

    local existing = raceLogic.activeEnts[v]
    if existing then
        local live = false
        pcall(function()
            if Game.FindEntityByID(existing) then live = true end
        end)
        if live then return end
        -- Slot booked but entity gone: drop the dead ID and respawn
        raceLogic.activeEnts[v] = nil
        raceLogic.spawnAt[v] = nil
        despawnEntityById(existing)
    end

    local pos, rot = getCPPose(v)
    if not pos then return end

    local path = getCheckpointPath(v)
    local trans = WorldTransform.new()
    trans:SetPosition(ToVector4(pos))
    trans:SetOrientation(ToEulerAngles(rot or { roll = 0, pitch = 0, yaw = 0 }):ToQuat())
    local id = exEntitySpawner.Spawn(path, trans)
    if not id then return end
    raceLogic.activeEnts[v] = id
    raceLogic.spawnAt[v] = os.clock()
    rememberId(id, pos)
end

--- Next 2 virtual CPs, or only the next one when it is the finish.
local function desiredWindow()
    local want = {}
    local n = raceLogic.currentCP + 1
    if n < 1 or n > raceLogic.finishVirtual then return want end
    want[n] = true
    if n < raceLogic.finishVirtual then
        want[n + 1] = true
    end
    return want
end

--- Keep world entities exactly equal to the desired window.
function raceLogic.syncCheckpoints()
    if not raceLogic.track or raceLogic.finishVirtual <= 0 then return end
    if not raceLogic.raceInProgress then return end

    local want = desiredWindow()

    -- Despawn anything outside the window (tracked IDs only)
    local remove = {}
    for v, _ in pairs(raceLogic.activeEnts) do
        if not want[v] then
            remove[#remove + 1] = v
        end
    end
    for i = 1, #remove do
        raceLogic.despawnCheckpoint(remove[i])
    end

    -- Spawn missing window members
    for v, _ in pairs(want) do
        spawnOne(v)
    end
end

function raceLogic.spawnUpcomingCheckpoints(_force)
    raceLogic.syncCheckpoints()
end

function raceLogic.spawnCheckpoint(virtualIndex, _force)
    spawnOne(virtualIndex)
end

-- ---------------------------------------------------------------------------
-- Hold pose / vehicle helpers
-- ---------------------------------------------------------------------------

function raceLogic.holdVehiclePose(vehicle, position, orientation, duration)
    if not vehicle or not position or not orientation then return end
    if not Game.GetTeleportationFacility() then return end
    duration = duration or 1.0
    local interval = 0.05
    local steps = math.max(1, math.floor(duration / interval))
    local sid = raceLogic._sessionId

    local function step(i)
        if sid ~= raceLogic._sessionId and not raceLogic.raceInProgress then return end
        pcall(function()
            Game.GetTeleportationFacility():Teleport(vehicle, position, orientation)
        end)
        raceLogic.repairVehicle(vehicle)
        if i < steps then
            Cron.After(interval, function() step(i + 1) end)
        end
    end
    step(1)
end

--- Find a player-owned / summoned vehicle entity in the world near the player.
local function findNearbyPlayerVehicle(maxDist)
    maxDist = maxDist or 60.0
    local player = Game.GetPlayer()
    if not player then return nil end
    if player.mountedVehicle then
        return player.mountedVehicle
    end

    local ents = nil
    pcall(function()
        if player.GetEntitiesAroundObject then
            ents = player:GetEntitiesAroundObject(maxDist)
        end
    end)
    if type(ents) ~= "table" then return nil end

    local best, bestDist = nil, maxDist + 1
    local ppos = nil
    pcall(function() ppos = player:GetWorldPosition() end)

    for _, entity in pairs(ents) do
        if entity then
            local isVeh = false
            pcall(function()
                if entity.IsVehicle and entity:IsVehicle() then isVeh = true end
            end)
            if not isVeh then
                pcall(function()
                    if entity.GetEntity then
                        local inner = entity:GetEntity()
                        if inner and inner.IsVehicle and inner:IsVehicle() then
                            entity = inner
                            isVeh = true
                        end
                    end
                end)
            end
            if isVeh then
                -- Prefer vehicles the player can drive / that look like player vehicles
                local okCandidate = true
                pcall(function()
                    if entity.IsDestroyed and entity:IsDestroyed() then okCandidate = false end
                end)
                if okCandidate then
                    local d = maxDist
                    if ppos then
                        pcall(function()
                            local vp = entity:GetWorldPosition()
                            if vp then d = ppos:Distance(vp) end
                        end)
                    end
                    if d < bestDist then
                        best, bestDist = entity, d
                    end
                end
            end
        end
    end
    return best
end

--- Ensure the player has a usable race vehicle.
--- currVeh is defined ONLY by explicit enter/exit (init.lua observers).
--- Prefer currently mounted vehicle if it matches / updates currVeh; never
--- auto-discover an arbitrary nearby vehicle as the active race vehicle.
function raceLogic.ensurePlayerVehicle()
    local player = Game.GetPlayer()
    if player and player.mountedVehicle then
        -- Only accept the mounted vehicle if the player is the driver and we
        -- already have (or are establishing) an explicit race vehicle.
        local ok = false
        pcall(function()
            if player.mountedVehicle:IsPlayerDriver() then ok = true end
        end)
        if ok then
            raceLogic.currVeh = player.mountedVehicle
            return raceLogic.currVeh
        end
    end

    if raceLogic.currVeh then
        local stillValid = false
        pcall(function()
            if raceLogic.currVeh.GetEntityID and raceLogic.currVeh:GetEntityID() then
                stillValid = true
            end
        end)
        if stillValid then return raceLogic.currVeh end
        raceLogic.currVeh = nil
    end

    -- No explicit enter/exit vehicle — do NOT invent one from nearby entities.
    return nil
end

--- Force-mount the player into currVeh using every available API.
local function forceMountPlayer(vehicle)
    if not vehicle then return false end
    local player = Game.GetPlayer()
    if not player then return false end
    if player.mountedVehicle == vehicle then
        raceLogic.currVeh = vehicle
        raceLogic.playerMounted = true
        return true
    end

    local mounted = false
    local slot = "seat_front_left"

    -- Preferred: VehicleComponent.MountEntityToSlot
    pcall(function()
        local vc = vehicle.vehicleComponent
        if not vc and vehicle.GetVehicleComponent then
            vc = vehicle:GetVehicleComponent()
        end
        if vc and vc.MountEntityToSlot and vehicle.GetEntityID then
            vc:MountEntityToSlot(vehicle:GetEntityID(), player:GetEntityID(), slot)
            mounted = true
        end
    end)

    -- Fallback: MountingFacility
    if not mounted then
        pcall(function()
            local mf = Game.GetMountingFacility()
            if mf and mf.Mount then
                local mi = MountingInfo.new()
                mi.childId = player:GetEntityID()
                mi.parentId = vehicle:GetEntityID()
                mi.slotName = slot
                mf:Mount(mi)
                mounted = true
            end
        end)
    end

    if player.mountedVehicle then
        raceLogic.currVeh = player.mountedVehicle
        raceLogic.playerMounted = true
        return true
    end
    if mounted then
        raceLogic.currVeh = vehicle
        raceLogic.playerMounted = true
        return true
    end
    return false
end

--- No longer summons from garage. Uses only a vehicle the player already has
--- in the world (mounted or nearby). Callback receives that vehicle or nil.
function raceLogic.summonActiveGarageVehicleTo(position, orientation, onReady)
    local v = raceLogic.ensurePlayerVehicle()
    if not v then
        if onReady then onReady(nil) end
        return
    end
    raceLogic.currVeh = v
    if position and orientation and Game.GetTeleportationFacility() then
        pcall(function()
            Game.GetTeleportationFacility():Teleport(v, position, orientation)
        end)
        raceLogic.repairVehicle(v)
        raceLogic.holdVehiclePose(v, position, orientation, 0.6)
    end
    forceMountPlayer(v)
    if onReady then onReady(raceLogic.currVeh or v) end
end

local function vehicleNearStartOrHub(vehicle, track, maxDist)
    if not vehicle or not track then return false end
    local vehPos = nil
    pcall(function() vehPos = vehicle:GetWorldPosition() end)
    if not vehPos then return false end
    local function near(posTable)
        if not posTable or not posTable.position then return false end
        local p = ToVector4(posTable.position)
        return p and vehPos:Distance(p) <= maxDist
    end
    if near(track.startPosition) then return true end
    if near(track.hubPosition) then return true end
    if track.checkpoints and track.checkpoints[1] then
        local p = ToVector4(track.checkpoints[1].position)
        if p and vehPos:Distance(p) <= maxDist then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Full session reset (every race end path)
-- ---------------------------------------------------------------------------

local function clearRuntimeState(keepVehicle)
    raceLogic.raceInProgress = false
    raceLogic.currentCP = 0
    raceLogic.currentLap = 1
    raceLogic.numberOfLaps = 1
    raceLogic.totalCPs = 0
    raceLogic.finishVirtual = 0
    raceLogic.positions = {}
    raceLogic.playerMounted = false
    raceLogic.raceStartSimTime = nil
    raceLogic.lapStartSimTime = nil
    raceLogic.bestLapMs = nil
    raceLogic.hitSound = ""
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    raceLogic.activeProps = {}
    raceLogic._startLineEntId = nil
    if raceLogic.track then
        pcall(function() raceLogic.track.cetopen = false end)
        -- Drop cached track module so next require() is fresh
        local tname = raceLogic.track.name
        if type(tname) == "string" and tname ~= "" then
            local key = "modules/tracks/" .. removeSpaces(tname:match("^[^%-]+") or tname)
            -- Also try the formatted name without suffix
            pcall(function()
                for k, _ in pairs(package.loaded) do
                    if type(k) == "string" and k:find("modules/tracks/", 1, true) then
                        -- leave loaded; track tables are data-only and safe
                    end
                end
            end)
        end
    end
    raceLogic.track = nil
    if not keepVehicle then
        raceLogic.currVeh = nil
        raceLogic.currVehEnt = nil
    end
end

function raceLogic.resetRace()
    raceLogic._sessionId = (raceLogic._sessionId or 0) + 1
    raceLogic.despawnAllCheckpoints()
    raceLogic.despawnProps()
    pcall(destroyLifetimeIds)
    clearRuntimeState(true)  -- keep vehicle for startRace reassignment
end

function raceLogic.fullSessionCleanup()
    raceLogic._sessionId = (raceLogic._sessionId or 0) + 1
    raceLogic._priorRace = true

    local snap = raceLogic._lastTrackSnap
    if raceLogic.track then
        snap = {
            checkpoints = raceLogic.track.checkpoints,
            startPosition = raceLogic.track.startPosition,
            hubPosition = raceLogic.track.hubPosition,
        }
        raceLogic._lastTrackSnap = snap
    end

    -- Hard clear bookkeeping first so nothing re-spawns mid-cleanup
    local entsCopy = raceLogic.activeEnts
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    for _, id in pairs(entsCopy) do
        destroyId(id)
    end
    pcall(function() raceLogic.despawnAllCheckpoints() end)
    pcall(function() raceLogic.despawnProps() end)
    pcall(destroyLifetimeIds)  -- deferred retries with generation guard
    -- Local purge near player (safe). Full teleport purge only as last resort.
    pcall(function()
        local positions = {}
        if snap then
            if snap.startPosition and snap.startPosition.position then
                positions[#positions + 1] = snap.startPosition.position
            end
            if type(snap.checkpoints) == "table" then
                for _, cp in ipairs(snap.checkpoints) do
                    if cp and cp.position then positions[#positions + 1] = cp.position end
                end
            end
        end
        purgeNearPositions(positions, 8.0)
    end)
    -- Aggressive full-track purge (teleports briefly) to catch invisible leftovers
    -- that a save-reload would otherwise clear — this is the multi-lap fix.
    pcall(function() proximityPurgeTrack(snap) end)
    pcall(function() raceLogic.repairVehicle(raceLogic.currVeh) end)

    if Game.GetPlayer() then
        pcall(function()
            StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoDriving", -1)
        end)
    end

    if raceLogic.hudController then
        pcall(function()
            local evt = ForwardVehicleRaceUIEvent.new()
            evt.maxPosition = 0
            evt.maxCheckpoints = 0
            evt.mode = vehicleRaceUI.RaceEnd
            raceLogic.hudController:OnForwardVehicleRaceUIEvent(evt)
        end)
        pcall(function() raceLogic.hudController:EndRace() end)
    end
    pcall(function() Game.GetUISystem():PopGameContext("VehicleRace") end)
    pcall(function() Game.GetUISystem():ResetGameContext() end)
    pcall(function()
        Game.GetQuestsSystem():SetFact("sq024_current_race_checkpoint_fact_add", 0)
    end)
    -- Reset race position blackboard
    pcall(function()
        local defs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
        Game.GetBlackboardSystem():Get(defs):SetInt(defs.PositionInRace, 0, true)
    end)

    pcall(function() raceLogic.restoreTrafficAfterRace() end)
    pcall(runCleanupCallback)
    pcall(restoreInteractionHubs)

    if raceLogic.trackedJournalEntry and Game.GetJournalManager() then
        pcall(function()
            if not Game.GetJournalManager():GetTrackedEntry() then
                Game.GetJournalManager():TrackEntry(raceLogic.trackedJournalEntry)
            end
        end)
        raceLogic.trackedJournalEntry = nil
    end

    clearRuntimeState(false)
end

-- ---------------------------------------------------------------------------
-- Race start
-- ---------------------------------------------------------------------------

local function beginRaceWithVehicle(track, trackname, vehicle)
    raceLogic.currVeh = vehicle
    raceLogic.hitSound = nativeCpSounds[user.settings.cpSoundFx] or nativeCpSounds[1]

    raceLogic.track = track
    raceLogic._lastTrackSnap = {
        checkpoints = track.checkpoints,
        startPosition = track.startPosition,
        hubPosition = track.hubPosition,
    }
    raceLogic.totalCPs = #track.checkpoints
    raceLogic.track.totalCheckpoints = raceLogic.totalCPs

    local baseLaps = math.max(1, math.ceil(tonumber(track.numberOfLaps) or 1))
    if baseLaps > 1 then
        raceLogic.numberOfLaps = math.max(1, math.ceil(baseLaps * (tonumber(user.settings.lapCountMult) or 1.0)))
    else
        raceLogic.numberOfLaps = 1
    end

    if raceLogic.numberOfLaps > 1 then
        raceLogic.finishVirtual = (raceLogic.totalCPs + 1) * raceLogic.numberOfLaps
    else
        raceLogic.finishVirtual = raceLogic.totalCPs
    end
    raceLogic.positions = track.GetCheckpointPositions()

    local vehSys = Game.GetVehicleSystem()
    if vehSys then
        pcall(function()
            local restrictions = vehSys:GetVehicleRestrictions()
            if restrictions and #restrictions > 0 then
                for i = #restrictions, 1, -1 do
                    table.remove(restrictions, i)
                end
            end
        end)
    end

    if Game.GetJournalManager() and Game.GetJournalManager():GetTrackedEntry() then
        raceLogic.trackedJournalEntry = Game.GetJournalManager():GetTrackedEntry()
        Game.GetJournalManager():UntrackEntry()
    end

    raceLogic.raceInProgress = true
    raceLogic.currentCP = 0
    raceLogic.currentLap = 1
    raceLogic.activeProps = {}
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    track.cetopen = true

    local startPos, startOri
    if track.startPosition and track.startPosition.position and track.startPosition.rotation then
        startPos = ToVector4(track.startPosition.position)
        startOri = ToEulerAngles(track.startPosition.rotation)
    else
        startPos = ToVector4(track.checkpoints[1].position)
        startOri = ToEulerAngles(track.checkpoints[1].rotation)
    end

    raceLogic.stopTrafficForRace()
    raceLogic.clearVehiclesNearStart(startPos, startOri, raceLogic.currVeh)

    if raceLogic.currVeh and Game.GetTeleportationFacility() then
        pcall(function()
            Game.GetTeleportationFacility():Teleport(raceLogic.currVeh, startPos, startOri)
        end)
        raceLogic.repairVehicle(raceLogic.currVeh)
        raceLogic.holdVehiclePose(raceLogic.currVeh, startPos, startOri, 1.0)
    end

    raceLogic.applyStartingEffects()
    raceLogic.activateCurrentRace(startPos, startOri)
end

function raceLogic.startRace(trackname)
    if raceLogic.raceInProgress then return end

    -- Failsafe: destroy any leftover entities from a previous race before starting.
    -- Invalidate deferred destroy jobs so they cannot kill the CPs we are about to spawn.
    raceLogic._cleanupGen = (raceLogic._cleanupGen or 0) + 1
    pcall(function() raceLogic.despawnAllCheckpoints() end)
    pcall(function() raceLogic.despawnProps() end)
    pcall(destroyLifetimeIdsNow)
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    raceLogic._lifetimeIds = {}
    raceLogic._lifetimePos = {}

    local formatted = removeSpaces(trackname or "")
    if formatted == "" then
        showWarning("Unable to start race: invalid track name.", 4.0)
        return
    end

    local modulePath = "modules/tracks/" .. formatted
    local ok, track = pcall(require, modulePath)
    if not ok or type(track) ~= "table" then
        showWarning("Unable to load the selected time trial track.", 4.0)
        print("CyberTrials: failed to load track " .. tostring(modulePath) .. ": " .. tostring(track))
        return
    end

    if type(track.checkpoints) ~= "table" or #track.checkpoints < 3
       or type(track.checkpointEnts) ~= "table" or #track.checkpointEnts ~= #track.checkpoints
       or tonumber(track.totalCheckpoints) ~= #track.checkpoints then
        showWarning("This track is invalid. It needs at least 3 checkpoints and matching checkpoint entities.", 5.0)
        return
    end
    if type(track.GetCheckpointPositions) ~= "function" or type(track.spawnProps) ~= "function" then
        showWarning("This track is invalid or missing required track functions.", 5.0)
        return
    end

    raceLogic.resetRace()

    -- Active race vehicle must already have been set by an explicit enter or exit.
    local vehicle = raceLogic.currVeh
    if not vehicle then
        -- Fallback: currently mounted and driven vehicle counts as explicit.
        vehicle = raceLogic.ensurePlayerVehicle()
    end
    if not vehicle then
        showWarning("You need to enter/exit a vehicle of your choice before starting the event.", 4.0)
        return
    end

    -- Re-validate that the stored vehicle is still usable
    local stillValid = false
    pcall(function()
        if vehicle.GetEntityID and vehicle:GetEntityID() then
            stillValid = true
        end
    end)
    if not stillValid then
        raceLogic.currVeh = nil
        showWarning("You need to enter/exit a vehicle of your choice before starting the event.", 4.0)
        return
    end

    if not vehicleNearStartOrHub(vehicle, track, 50.0) then
        -- Vehicle exists but is far: teleport it to start line
        local startPos, startOri
        if track.startPosition and track.startPosition.position then
            startPos = ToVector4(track.startPosition.position)
            startOri = ToEulerAngles(track.startPosition.rotation or { roll = 0, pitch = 0, yaw = 0 })
        else
            startPos = ToVector4(track.checkpoints[1].position)
            startOri = ToEulerAngles(track.checkpoints[1].rotation or { roll = 0, pitch = 0, yaw = 0 })
        end
        if startPos and Game.GetTeleportationFacility() then
            pcall(function()
                Game.GetTeleportationFacility():Teleport(vehicle, startPos, startOri)
            end)
            raceLogic.repairVehicle(vehicle)
        end
    end
    beginRaceWithVehicle(track, trackname, vehicle)
end

function raceLogic.clearVehiclesNearStart(startPos, startOri, protectVehicle)
    local player = Game.GetPlayer()
    local tele = Game.GetTeleportationFacility()
    if not player or not tele or not startPos then return end
    local queryOri = startOri or EulerAngles.new(0, 0, 0)
    pcall(function() tele:Teleport(player, startPos, queryOri) end)

    local entities = nil
    pcall(function()
        if player.GetEntitiesAroundObject then
            entities = player:GetEntitiesAroundObject(20)
        end
    end)
    if not entities then return end

    local function sameEntity(a, b)
        if not a or not b then return false end
        if a == b then return true end
        local ok, equal = pcall(function()
            if a.GetEntityID and b.GetEntityID then
                return tostring(a:GetEntityID()) == tostring(b:GetEntityID())
            end
            return false
        end)
        return ok and equal
    end

    local protect = protectVehicle or raceLogic.currVeh or player.mountedVehicle
    local function consider(entity)
        if not entity then return end
        pcall(function()
            local gameObj = entity
            if entity.GetEntity then
                local inner = entity:GetEntity()
                if inner then gameObj = inner end
            end
            local isVeh = false
            if gameObj and gameObj.IsVehicle then
                isVeh = gameObj:IsVehicle()
            elseif entity.IsVehicle then
                isVeh = entity:IsVehicle()
            end
            if not isVeh then return end
            if sameEntity(gameObj, protect) or sameEntity(entity, protect) then return end
            if player.mountedVehicle and (sameEntity(gameObj, player.mountedVehicle) or sameEntity(entity, player.mountedVehicle)) then
                return
            end
            if sameEntity(gameObj, player) or sameEntity(entity, player) then return end
            if entity.Dispose then entity:Dispose()
            elseif gameObj.Dispose then gameObj:Dispose() end
        end)
    end
    if type(entities) == "table" then
        for _, entity in pairs(entities) do
            consider(entity)
        end
    end
end

function raceLogic.applyStartingEffects()
    GameObjectEffectHelper.StartEffectEvent(GetPlayer(), "time_skip_glitch", true, worldEffectBlackboard.new())
    StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoDriving", -1)
end

function raceLogic.activateCurrentRace(startPos, startOri)
    Game.GetQuestsSystem():SetFact("sq024_current_race_checkpoint_fact_add", 0)
    -- Start-line visual appears while the vehicle is being placed; removed on mount.
    spawnStartLineEntity()
    Cron.After(1.5, function()
        raceLogic.sendPlayerVehicleToStart(startPos, startOri, true)
    end)
end

-- ---------------------------------------------------------------------------
-- Progression
-- ---------------------------------------------------------------------------

function raceLogic.passedCheckpoint(virtualIndex)
    if not raceLogic.track or raceLogic.totalCPs == 0 then return end
    if virtualIndex ~= raceLogic.currentCP + 1 then return end

    raceLogic.hitSound = nativeCpSounds[user.settings.cpSoundFx] or raceLogic.hitSound

    -- Despawn the crossed checkpoint (ID removed from activeEnts then destroyed)
    raceLogic.despawnCheckpoint(virtualIndex)
    -- Safety: also drop any lower virtual indices that should already be gone
    local stale = {}
    for v, _ in pairs(raceLogic.activeEnts) do
        if v <= virtualIndex then
            stale[#stale + 1] = v
        end
    end
    for i = 1, #stale do
        raceLogic.despawnCheckpoint(stale[i])
    end
    if raceLogic._startLineEntId then
        despawnStartLineEntity()
    end

    raceLogic.currentCP = virtualIndex
    Game.GetQuestsSystem():SetFact("sq024_current_race_checkpoint_fact_add", raceLogic.currentCP)

    if user.settings.checkpointAudio then
        Game.GetPlayer():QueueEvent(AudioEvent.new({ eventName = raceLogic.hitSound }))
    end

    if isRaceFinish(virtualIndex) then
        raceLogic.currentLap = raceLogic.numberOfLaps + 1
        local defs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
        Game.GetBlackboardSystem():Get(defs):SetInt(defs.PositionInRace, raceLogic.currentLap, true)
        raceLogic.despawnAllCheckpoints()
        raceLogic.despawnProps()
        raceLogic.endActiveRace()
        return
    end

    if isLapEnd(virtualIndex) then
        if raceLogic.lapStartSimTime then
            local lapDelta = Game['OperatorSubtract;EngineTimeEngineTime;EngineTime'](Game.GetSimTime(), raceLogic.lapStartSimTime)
            local lapMs = math.max(0, math.floor(lapDelta:ToFloat() * 1000 + 0.5))
            if not raceLogic.bestLapMs or lapMs < raceLogic.bestLapMs then
                raceLogic.bestLapMs = lapMs
            end
            raceLogic.lapStartSimTime = Game.GetSimTime()
        end
        raceLogic.currentLap = raceLogic.currentLap + 1
        if raceLogic.currentLap == raceLogic.numberOfLaps then
            showWarning("Final Lap!!!", 3.0)
        else
            showWarning("Lap " .. tostring(raceLogic.currentLap) .. "/" .. tostring(raceLogic.numberOfLaps), 3.0)
        end
        local lapDefs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
        Game.GetBlackboardSystem():Get(lapDefs):SetInt(lapDefs.PositionInRace, raceLogic.currentLap, true)
    end

    -- Spawn the next window only (never wipe the table first)
    raceLogic.syncCheckpoints()
end

function raceLogic.checkPassed()
    if not raceLogic.track or raceLogic.totalCPs == 0 or not raceLogic.raceInProgress then return end

    local defs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
    Game.GetBlackboardSystem():Get(defs):SetInt(defs.PositionInRace, raceLogic.currentLap, true)

    local nextVirtual = raceLogic.currentCP + 1
    if nextVirtual > raceLogic.finishVirtual then return end

    local pos, _ = getCPPose(nextVirtual)
    if not pos then return end

    local playerPos = GetPlayer():GetWorldPosition()
    if playerPos:Distance(ToVector4(pos)) < 9.0 then
        raceLogic.passedCheckpoint(nextVirtual)
    end
end

function raceLogic.getAheadPosition(offset)
    local target = raceLogic.currentCP + (offset or 1)
    if raceLogic.finishVirtual > 0 and target > raceLogic.finishVirtual then
        target = raceLogic.finishVirtual
    end
    local pos, _ = getCPPose(target)
    if pos then return ToVector4(pos) end
    local positions = raceLogic.positions
    if not positions or #positions == 0 then return nil end
    local physical = toPhysical(target)
    if physical and positions[physical] then return positions[physical] end
    return positions[#positions]
end

-- ---------------------------------------------------------------------------
-- HUD / setup sequence
-- ---------------------------------------------------------------------------

local function makeRaceUIEvent(mode, checkpointCount, lapCount)
    local evt = ForwardVehicleRaceUIEvent.new()
    evt.maxPosition = lapCount or 1
    evt.maxCheckpoints = checkpointCount
    evt.mode = mode
    return evt
end

function raceLogic.SetupDone()
    raceLogic._cleanupGen = (raceLogic._cleanupGen or 0) + 1
    raceLogic._sessionId = (raceLogic._sessionId or 0) + 1
    raceLogic.currentCP = 0
    raceLogic.currentLap = 1
    raceLogic.raceInProgress = true

    local prior = raceLogic._priorRace
    raceLogic._priorRace = false
    local sid = raceLogic._sessionId

    -- Destroy any leftover entities, keeping activeEnts in sync (never blank the
    -- table without despawning the IDs it holds).
    pcall(function() raceLogic.despawnAllCheckpoints() end)
    pcall(function() raceLogic.despawnProps() end)
    pcall(destroyLifetimeIdsNow)

    pcall(function()
        local src = raceLogic.track or raceLogic._lastTrackSnap
        if not src then return end
        local positions = {}
        if src.startPosition and src.startPosition.position then
            positions[#positions + 1] = src.startPosition.position
        end
        if type(src.checkpoints) == "table" then
            for i = 1, math.min(3, #src.checkpoints) do
                if src.checkpoints[i] and src.checkpoints[i].position then
                    positions[#positions + 1] = src.checkpoints[i].position
                end
            end
        end
        purgeNearPositions(positions, 8.0)
    end)

    pcall(function() Game.GetUISystem():PushGameContext("VehicleRace") end)
    pcall(function()
        Game.GetQuestsSystem():SetFact("sq024_current_race_checkpoint_fact_add", 0)
    end)
    pcall(function()
        local defs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
        Game.GetBlackboardSystem():Get(defs):SetInt(defs.PositionInRace, 1, true)
    end)

    if raceLogic.hudController and raceLogic.finishVirtual > 0 then
        raceLogic.hudController:OnForwardVehicleRaceUIEvent(
            makeRaceUIEvent(vehicleRaceUI.PreRaceSetup, raceLogic.finishVirtual, raceLogic.numberOfLaps))
        raceLogic.hudController:OnForwardVehicleRaceUIEvent(
            makeRaceUIEvent(vehicleRaceUI.CountdownStart, raceLogic.finishVirtual, raceLogic.numberOfLaps))
    end

    local isMulti = (raceLogic.numberOfLaps or 1) > 1
    local delay = 0.2
    if prior and isMulti then
        delay = 1.5
    elseif prior then
        delay = 0.8
    elseif isMulti then
        delay = 0.4
    end

    -- Single spawn pass for the first race window (next 1–2 virtual CPs).
    -- Start line was already shown during vehicle placement and removed on mount.
    -- Never blank activeEnts here — that orphaned live entities and broke despawn-on-cross.
    Cron.After(delay, function()
        if sid ~= raceLogic._sessionId then return end
        if not raceLogic.raceInProgress then return end
        despawnStartLineEntity() -- ensure gone if mount path was skipped
        raceLogic.syncCheckpoints()
    end)

    -- One recovery pass if stream-in failed for the first window
    Cron.After(delay + SETTLE_SEC + 0.5, function()
        if sid ~= raceLogic._sessionId then return end
        if not raceLogic.raceInProgress then return end
        raceLogic.syncCheckpoints()
    end)

    if raceLogic.track and type(raceLogic.track.spawnProps) == "function" then
        raceLogic.activeProps = raceLogic.track.spawnProps() or {}
        for _, pid in ipairs(raceLogic.activeProps) do
            rememberId(pid)
        end
    end

    Cron.After(4.5, function()
        if sid ~= raceLogic._sessionId then return end
        StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoDriving", -1)
        if raceLogic.hudController then
            raceLogic.hudController:StartRace()
        end
        raceLogic.raceStartSimTime = Game.GetSimTime()
        raceLogic.lapStartSimTime  = raceLogic.raceStartSimTime
        raceLogic.bestLapMs        = nil
        if raceLogic.raceInProgress then
            raceLogic.syncCheckpoints()
        end
    end)

    local defs = Game.GetAllBlackboardDefs().UI_ActiveVehicleData
    Game.GetBlackboardSystem():Get(defs):SetInt(defs.PositionInRace, raceLogic.currentLap, true)
    if user.settings.useSpeedbreaker then
        showWarning("Speedbreaker Ability Ready - Tap your Exit Vehicle button or custom keybind to activate! This ability will have a 20 second cooldown after using.", 6.0)
    end
end

function raceLogic.mountPlayerToVehicle(entID, isRaceStart)
    local vehicle = raceLogic.currVeh
    if not vehicle then
        -- Only accept currently mounted vehicle (explicit), never invent nearby
        local player = Game.GetPlayer()
        if player and player.mountedVehicle then
            local okDriver = false
            pcall(function()
                if player.mountedVehicle:IsPlayerDriver() then okDriver = true end
            end)
            if okDriver then
                vehicle = player.mountedVehicle
                raceLogic.currVeh = vehicle
            end
        end
    end
    if not vehicle then
        raceLogic.endActiveRace(true)
        showWarning("You need to enter/exit a vehicle of your choice before starting the event.", 3.0)
        return
    end

    raceLogic.repairVehicle(vehicle)

    local destroyed = false
    pcall(function() destroyed = vehicle:IsDestroyed() end)
    if destroyed then
        showWarning("CyberTrials event has been postponed. Current vehicle destroyed. Please select a new vehicle to race.", 3.0)
        raceLogic.endActiveRace(true)
        return
    end

    local ok = forceMountPlayer(vehicle)
    if not ok then
        -- One more attempt after a tick (component may still be streaming in)
        Cron.After(0.3, function()
            local v2 = raceLogic.currVeh
            if not v2 then
                local player = Game.GetPlayer()
                if player and player.mountedVehicle then
                    local okDriver = false
                    pcall(function()
                        if player.mountedVehicle:IsPlayerDriver() then okDriver = true end
                    end)
                    if okDriver then v2 = player.mountedVehicle end
                end
            end
            if not v2 then
                raceLogic.endActiveRace(true)
                showWarning("CyberTrials event has been postponed. No vehicle found. Please select a new vehicle to race.", 3.0)
                return
            end
            raceLogic.currVeh = v2
            forceMountPlayer(v2)
            raceLogic.playerMounted = true
            if isRaceStart then
                -- Player is mounted at the start line: remove start-line CP immediately
                despawnStartLineEntity()
                Cron.NextTick(function() raceLogic.SetupDone() end)
            else
                StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoDriving", -1)
            end
        end)
        return
    end

    raceLogic.playerMounted = true
    if isRaceStart then
        -- Player is mounted at the start line: remove start-line CP immediately
        despawnStartLineEntity()
        Cron.NextTick(function() raceLogic.SetupDone() end)
    else
        StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoDriving", -1)
    end
end

function raceLogic.sendPlayerVehicleToStart(startPosition, startOrientation, isRaceStart)
    if not Game.GetVehicleSystem() or not Game.GetTeleportationFacility() then return end
    local vehicle = raceLogic.currVeh
    if not vehicle then
        raceLogic.endActiveRaceQuick()
        showWarning("You need to enter/exit a vehicle of your choice before starting the event.", 3.0)
        return
    end

    local hasComponent = false
    pcall(function()
        hasComponent = (vehicle.vehicleComponent ~= nil)
            or (vehicle.GetVehicleComponent and vehicle:GetVehicleComponent() ~= nil)
    end)
    local hasId = false
    pcall(function() hasId = vehicle:GetEntityID() ~= nil end)

    if hasComponent and hasId then
        raceLogic.repairVehicle(vehicle)
        if not vehicle:IsDestroyed() then
            Game.GetTeleportationFacility():Teleport(vehicle, startPosition, startOrientation)
            raceLogic.repairVehicle(vehicle)
            raceLogic.holdVehiclePose(vehicle, startPosition, startOrientation, 1.0)
            Cron.After(1.0, function()
                raceLogic.mountPlayerToVehicle(vehicle:GetEntityID(), isRaceStart)
            end)
        else
            showWarning("CyberTrials event has been postponed. Current vehicle destroyed. Please select a new vehicle to race.", 3.0)
            raceLogic.endActiveRaceQuick()
        end
    else
        showWarning("CyberTrials event has been postponed. No vehicle found. Please select a new vehicle to race.", 3.0)
        raceLogic.endActiveRaceQuick()
    end
end

-- ---------------------------------------------------------------------------
-- End race
-- ---------------------------------------------------------------------------
-- quick=true  -> abort / no time save / no finish messages (was endActiveRaceQuick)
-- quick=false -> normal finish: save times, show messages, optional rewards
-- ---------------------------------------------------------------------------

local function formatTimeMs(ms)
    ms = math.max(0, math.floor(ms or 0))
    local min = math.floor(ms / 60000)
    local sec = math.floor((ms % 60000) / 1000)
    local milli = ms % 1000
    return string.format("%d:%02d.%03d", min, sec, milli), min, sec, milli
end

local function getElapsedMs()
    if raceLogic.hudController and raceLogic.hudController.raceStartEngineTime then
        local delta = Game['OperatorSubtract;EngineTimeEngineTime;EngineTime'](
            Game.GetSimTime(), raceLogic.hudController.raceStartEngineTime)
        return math.max(0, math.floor(delta:ToFloat() * 1000 + 0.5))
    end
    if raceLogic.raceStartSimTime then
        local delta = Game['OperatorSubtract;EngineTimeEngineTime;EngineTime'](
            Game.GetSimTime(), raceLogic.raceStartSimTime)
        return math.max(0, math.floor(delta:ToFloat() * 1000 + 0.5))
    end
    return 0
end

--- @param quick boolean|nil  If true (default false when called as finish), skip time save & messages
function raceLogic.endActiveRace(quick)
    if quick then
        raceLogic.fullSessionCleanup()
        return
    end

    if not raceLogic.track then
        raceLogic.fullSessionCleanup()
        return
    end

    raceLogic.repairVehicle(raceLogic.currVeh)

    if raceLogic.numberOfLaps > 1 and raceLogic.lapStartSimTime then
        local lapDelta = Game['OperatorSubtract;EngineTimeEngineTime;EngineTime'](Game.GetSimTime(), raceLogic.lapStartSimTime)
        local lapMs = math.max(0, math.floor(lapDelta:ToFloat() * 1000 + 0.5))
        if not raceLogic.bestLapMs or lapMs < raceLogic.bestLapMs then
            raceLogic.bestLapMs = lapMs
        end
    end

    local elapsedMs = getElapsedMs()
    local finalTimeStr, min, sec, milli = formatTimeMs(elapsedMs)

    -- Snapshot before cleanup clears track/vehicle
    local trackKey = (raceLogic.track and raceLogic.track.name) or "Unknown"
    local completedTrack = raceLogic.track
    local vehRef = raceLogic.currVeh
    local lapsDone = raceLogic.numberOfLaps
    local bestLap = raceLogic.bestLapMs
    local positionsSnap = raceLogic.positions

    local currentVehicle = "Unknown"
    if Game.GetPlayer() and Game.GetPlayer().mountedVehicle then
        currentVehicle = tostring(Game.GetPlayer().mountedVehicle:GetDisplayName() or "Unknown")
    end

    -- Persist times while data is still available
    user.recentTimes = user.recentTimes or {}
    local entry = user.recentTimes[trackKey]
    if type(entry) == "table" and entry[1] and not entry.runs then
        local runs = {}
        local bestFull = math.huge
        for _, r in ipairs(entry) do
            local ms = r.totalMillisecs or r.totalMs or 0
            table.insert(runs, r)
            if ms > 0 and ms < bestFull then bestFull = ms end
        end
        entry = {
            runs = runs,
            bestFullMs = (bestFull < math.huge) and bestFull or nil,
            bestLapMs = nil,
            bestLaps = lapsDone,
        }
        user.recentTimes[trackKey] = entry
    end
    if type(entry) ~= "table" or not entry.runs then
        entry = { runs = {}, bestFullMs = nil, bestLapMs = nil, bestLaps = lapsDone }
        user.recentTimes[trackKey] = entry
    end

    local raceData = {
        min = min,
        sec = sec,
        milliSecs = milli,
        totalMillisecs = elapsedMs,
        currentVehicle = currentVehicle,
        laps = lapsDone,
        bestLapMs = bestLap,
        allToString = string.format("%s in %s while driving %s", trackKey, finalTimeStr, currentVehicle),
    }
    table.insert(entry.runs, raceData)

    local isNewFullBest = false
    if not entry.bestFullMs or elapsedMs < entry.bestFullMs then
        entry.bestFullMs = elapsedMs
        entry.bestLaps = lapsDone
        isNewFullBest = true
    end
    local isNewLapBest = false
    if lapsDone > 1 and bestLap then
        if not entry.bestLapMs or bestLap < entry.bestLapMs then
            entry.bestLapMs = bestLap
            isNewLapBest = true
        end
    end

    local f = io.open("modules/UserSettings/RecentTimes.json", "w")
    if f then
        f:write(json.encode(user.recentTimes))
        f:close()
    end

    if isNewFullBest then
        showNotification("New Record!!!", 5.0)
        local msg = "New Best Time!!! Final Time: " .. finalTimeStr
        if lapsDone > 1 then
            msg = msg .. " (" .. tostring(lapsDone) .. " laps)"
            if bestLap then msg = msg .. " | Best Lap: " .. formatTimeMs(bestLap) end
        end
        showWarning(msg, 8.0)
    else
        local msg = "Final Time: " .. finalTimeStr
        if lapsDone > 1 and bestLap then
            msg = msg .. " | Best Lap: " .. formatTimeMs(bestLap)
        end
        showWarning(msg .. "!", 8.0)
    end
    if isNewLapBest then
        showNotification("New Best Lap: " .. formatTimeMs(bestLap), 4.0)
    end

    if user.settings.cashReward then
        local totalDistance = 0
        if positionsSnap and #positionsSnap > 1 then
            for i = 1, #positionsSnap - 1 do
                totalDistance = totalDistance + distance(
                    {x=positionsSnap[i].x, y=positionsSnap[i].y, z=positionsSnap[i].z},
                    {x=positionsSnap[i+1].x, y=positionsSnap[i+1].y, z=positionsSnap[i+1].z})
            end
            totalDistance = totalDistance * lapsDone
        end
        local reward = math.max(2000, math.floor(75 * totalDistance * 0.5 - elapsedMs))
        Game.AddToInventory("Items.money", reward)
        showWarning("Reward: " .. tostring(reward) .. " eddies", 4.0)
    end

    if user.settings.backToStartOnFinish then
        Cron.After(3.0, function()
            if not completedTrack or not Game.GetTeleportationFacility() then return end
            local p, o
            if completedTrack.startPosition and completedTrack.startPosition.position then
                p = ToVector4(completedTrack.startPosition.position)
                o = ToEulerAngles(completedTrack.startPosition.rotation or { roll = 0, pitch = 0, yaw = 0 })
            elseif completedTrack.checkpoints and completedTrack.checkpoints[1] then
                p = ToVector4(completedTrack.checkpoints[1].position)
                o = ToEulerAngles(completedTrack.checkpoints[1].rotation or { roll = 0, pitch = 0, yaw = 0 })
            end
            if not p then return end
            local player = Game.GetPlayer()
            if player then
                local playerPos = player:GetWorldPosition()
                if playerPos and playerPos:Distance(p) < 50.0 then return end
            end
            if vehRef then
                pcall(function() Game.GetTeleportationFacility():Teleport(vehRef, p, o) end)
                raceLogic.repairVehicle(vehRef)
                raceLogic.holdVehiclePose(vehRef, p, o, 1.0)
            end
            if player then
                pcall(function() Game.GetTeleportationFacility():Teleport(player, p, o) end)
            end
        end)
    end

    -- Full teardown last
    raceLogic.fullSessionCleanup()
end

-- Back-compat alias
function raceLogic.endActiveRaceQuick()
    raceLogic.endActiveRace(true)
end

function raceLogic.update()
    if not raceLogic.raceInProgress or not raceLogic.hudController then return end
    raceLogic.checkPassed()
    raceLogic.hudController:OnVehicleForwardRaceClockUpdateEvent(VehicleForwardRaceClockUpdateEvent.new())
    raceLogic.hudController:OnVehicleForwardRaceCheckpointFactEvent(VehicleForwardRaceCheckpointFactEvent.new())
end

--- Hard reset of every raceLogic field to its initial value (CET reload / shutdown).
function raceLogic.resetAllState()
    raceLogic._cleanupGen = (raceLogic._cleanupGen or 0) + 1
    raceLogic._sessionId = (raceLogic._sessionId or 0) + 1
    pcall(function() raceLogic.despawnAllCheckpoints() end)
    pcall(function() raceLogic.despawnProps() end)
    pcall(destroyLifetimeIdsNow)
    raceLogic.raceInProgress = false
    raceLogic.track = nil
    raceLogic.numberOfLaps = 1
    raceLogic.currentLap = 1
    raceLogic.currentCP = 0
    raceLogic.totalCPs = 0
    raceLogic.finishVirtual = 0
    raceLogic.positions = {}
    raceLogic.activeEnts = {}
    raceLogic.spawnAt = {}
    raceLogic.activeProps = {}
    raceLogic.hudController = nil
    raceLogic.playerMounted = false
    raceLogic.currVeh = nil
    raceLogic.currVehEnt = nil
    raceLogic.trackedJournalEntry = nil
    raceLogic.hitSound = ""
    raceLogic.cleanupCallback = nil
    raceLogic.raceStartSimTime = nil
    raceLogic.lapStartSimTime = nil
    raceLogic.bestLapMs = nil
    raceLogic._trafficStoppedByMod = false
    raceLogic._priorRace = false
    raceLogic._lifetimeIds = {}
    raceLogic._lifetimePos = {}
    raceLogic._lastTrackSnap = nil
    raceLogic._startLineEntId = nil
end

return raceLogic
