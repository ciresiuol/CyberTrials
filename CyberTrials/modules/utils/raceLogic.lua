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
    end

-- (continued) SetupDone and start logic

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
            for i = 1, math.min(6, #src.checkpoints) do
                if src.checkpoints[i] and src.checkpoints[i].position then
                    positions[#positions + 1] = src.checkpoints[i].position
                end
            end
        end
        purgeNearPositions(positions, 12.0)
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
        raceLogic.endActiveRace(true)
        showWarning("Your vehicle is destroyed. Please repair or select another vehicle.", 3.0)
        return
    end

    -- (rest of file unchanged)
end

return raceLogic
