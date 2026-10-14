local Cron = require("modules/external/Cron")
local raceLogic = require("modules/utils/raceLogic")

function InitializeScript()
    HillsideHorsepowerSpeedEdition.initialWaitDone = false
    HillsideHorsepowerSpeedEdition.hasShownInitMessage = false
    HillsideHorsepowerSpeedEdition.newTime = 0
    HillsideHorsepowerSpeedEdition.lastSpeedValue = 100
    HillsideHorsepowerSpeedEdition.isKM = false
    HillsideHorsepowerSpeedEdition.veh = nil
    HillsideHorsepowerSpeedEdition.tempSpeed = 100
    HillsideHorsepowerSpeedEdition.hasExploded = false
    HillsideHorsepowerSpeedEdition.explodeTimer = nil
    HillsideHorsepowerSpeedEdition.endRaceTimer = nil
    HillsideHorsepowerSpeedEdition.initialWaitDone = false
    HillsideHorsepowerSpeedEdition.hasShownInitMessage = false
    HillsideHorsepowerSpeedEdition.gamePaused = false
end

-- Observes
Observe("inkISystemRequestsHandler", "PauseGame", function(this)
    HillsideHorsepowerSpeedEdition.gamePaused = true
end)

Observe("inkISystemRequestsHandler", "UnpauseGame", function(this)
    HillsideHorsepowerSpeedEdition.gamePaused = false
end)

Observe("hudCarController", "OnSpeedValueChanged", function(this, speedValue)
    if not raceLogic.raceInProgress or HillsideHorsepowerSpeedEdition.gamePaused then
        HillsideHorsepowerSpeedEdition.explodeTimer = nil
        HillsideHorsepowerSpeedEdition.endRaceTimer = nil
        return
    end

    HillsideHorsepowerSpeedEdition.isKM = this.kmOn

    local newSpeed = HillsideHorsepowerSpeedEdition.isKM and this.currentSpeed * 1.60934 or this.currentSpeed

    if this and this.currentSpeed then
        HillsideHorsepowerSpeedEdition.veh = Game.GetPlayer().mountedVehicle
    else
        HillsideHorsepowerSpeedEdition.veh = nil
    end

    if not HillsideHorsepowerSpeedEdition.hasShownInitMessage and this.currentSpeed >= 40 then
        ShowWarningMessage("Watch your SPEED! Someone planted a bomb on your vehicle that will explode if you drop below 75mph/136kph once you reach that speed!", 5.0)
        HillsideHorsepowerSpeedEdition.hasShownInitMessage = true
    end

    if not HillsideHorsepowerSpeedEdition.initialWaitDone then
        if HillsideHorsepowerSpeedEdition.hasShownInitMessage and this.currentSpeed >= 75 then
            HillsideHorsepowerSpeedEdition.initialWaitDone = true
        else
            return
        end
    end

    HillsideHorsepowerSpeedEdition.lastSpeedValue = newSpeed

    if HillsideHorsepowerSpeedEdition.veh then
        if this.currentSpeed == 0 or Game.GetPlayer():IsDead() or not Game.GetPlayer().mountedVehicle then
            if not HillsideHorsepowerSpeedEdition.endRaceTimer then
                HillsideHorsepowerSpeedEdition.endRaceTimer = os.time() + 5 -- 5 seconds timer
            elseif os.time() >= HillsideHorsepowerSpeedEdition.endRaceTimer then
                raceLogic.endActiveRaceQuick()
                HillsideHorsepowerSpeedEdition.endRaceTimer = nil
            end
        else
            HillsideHorsepowerSpeedEdition.endRaceTimer = nil
        end

        local currentSpeed = HillsideHorsepowerSpeedEdition.isKM and this.currentSpeed * 1.60934 or this.currentSpeed

        if currentSpeed <= 75 then
            if not HillsideHorsepowerSpeedEdition.explodeTimer then
                ShowWarningMessage('You gotta go faster or that bomb\'s gonna explode!', 2.0)
                HillsideHorsepowerSpeedEdition.explodeTimer = os.time() + 12
            elseif os.time() >= HillsideHorsepowerSpeedEdition.explodeTimer then
                ShowWarningMessage("Vehicle is about to explode if you don\'t get back over 75mph/121kph now!", 2.0)
                if HillsideHorsepowerSpeedEdition.veh:GetVehicleComponent() then
                    HillsideHorsepowerSpeedEdition.veh:GetVehicleComponent():ForceAboutToExplodeState()
                end
                HillsideHorsepowerSpeedEdition.explodeTimer = nil
            end
        else
            HillsideHorsepowerSpeedEdition.explodeTimer = nil
        end
    end
end)
-- End Observes

HillsideHorsepowerSpeedEdition = {
    gamePaused = false,
    newTime = 0,
    lastSpeedValue = 100,
    isKM = false,
    veh = nil,
    tempSpeed = 100,
    hasExploded = false,
    explodeTimer = nil,
    endRaceTimer = nil,
    initialWaitDone = false,
    hasShownInitMessage = false,
    name = "Hillside Horsepower Speed Edition",
    description = "Alternate variant of Hillside Horsepower, with an explosively Speed-tastic twist!",
    creator = "Gullii",
    numberOfLaps = 1,
    hubPosition = {
        position = { x = 156.37086, y = 522.6848, z = 116.873, w = 1 },
        rotation = { roll = 0, pitch = 0, yaw = -75.537170410156 }
    },
    startPosition = {
        position = { x = 153.97326660156, y = 554.43084716797, z = 117.06666564941 },
        rotation = { roll = 0, pitch = 0, yaw = 27.162811279297 }
    },
    checkpoints = {
        {position = { x = 138.39009094238, y = 588.01989746094, z = 116.94621276755 }, rotation = { roll = 0, pitch = 0, yaw = 8.8628129959106 }},
        {position = { x = 157.31527709961, y = 650.427734375, z = 116.67039489746 }, rotation = { roll = 0, pitch = 0, yaw = -25.837169647217 }},
        {position = { x = 238.5048828125, y = 651.65838623047, z = 117.9621963501 }, rotation = { roll = 0, pitch = 0, yaw = -79.237106323242 }},
        {position = { x = 293.86340332031, y = 781.76245117188, z = 145.47543334961 }, rotation = { roll = 0, pitch = 0, yaw = 10.162902832031 }},
        {position = { x = 214.48204040527, y = 962.15631103516, z = 183.3030090332 }, rotation = { roll = 0, pitch = 0, yaw = 53.962752478027 }},
        {position = { x = 235.67501831055, y = 1078.2319335938, z = 200.38603210449 }, rotation = { roll = 0, pitch = 0, yaw = -47.937168121338 }},
        {position = { x = 482.07223510742, y = 1129.1431884766, z = 208.61123657227 }, rotation = { roll = 0, pitch = 0, yaw = -60.434215545654 }},
        {position = { x = 547.92260742188, y = 1109.7650146484, z = 216.61227416992 }, rotation = { roll = 0, pitch = 0, yaw = -138.23419189453 }},
        {position = { x = 557.12231445313, y = 1153.5787353516, z = 225.41912841797 }, rotation = { roll = 0, pitch = 0, yaw = 51.865756987525 }},
        {position = { x = 498.3088684082, y = 1229.1737060547, z = 229.25505065918 }, rotation = { roll = 0, pitch = 0, yaw = 75.565696716309 }},
        {position = { x = 436.29833984375, y = 1230.5865477516, z = 225.0705871582 }, rotation = { roll = 0, pitch = 0, yaw = 86.765640258789 }},
        {position = { x = 417.98672475352, y = 1349.8304443359, z = 200.48065175547 }, rotation = { roll = 0, pitch = 0, yaw = -21.734420776367 }},
        {position = { x = 353.08053588867, y = 1389.7596191406, z = 184.93664550781 }, rotation = { roll = 0, pitch = 0, yaw = 144.36557532715 }},
        {position = { x = 310.55822753906, y = 1262.2301025391, z = 168.09944152832 }, rotation = { roll = 0, pitch = 0, yaw = 165.16558837891 }},
        {position = { x = 247.61775888672, y = 1262.1918945313, z = 161.28170776367 }, rotation = { roll = 0, pitch = 0, yaw = 45.665580749512 }},
        {position = { x = 116.30864715576, y = 1257.2437744141, z = 144.7560333252 }, rotation = { roll = 0, pitch = 0, yaw = 123.76570129395 }},
        {position = { x = 49.884380340576, y = 1138.6732177734, z = 139.56817626953 }, rotation = { roll = 0, pitch = 0, yaw = 164.0657043457 }},
        {position = { x = 5.4260115623474, y = 1150.3480224609, z = 137.83915710449 }, rotation = { roll = 0, pitch = 0, yaw = 47.365695953369 }},
        {position = { x = 2.4733275903931, y = 1235.6153564453, z = 124.13945007324 }, rotation = { roll = 0, pitch = 0, yaw = 18.26568031311 }},
        {position = { x = -60.901889801025, y = 1268.8717041016, z = 114.40723419189 }, rotation = { roll = 0, pitch = 0, yaw = 98.165657043457 }},
        {position = { x = -78.920227050781, y = 1313.5251464844, z = 113.23881530762 }, rotation = { roll = 0, pitch = 0, yaw = 6.465672492981 }},
        {position = { x = -71.731391906738, y = 1452.0417480469, z = 112.0894317627 }, rotation = { roll = 0, pitch = 0, yaw = -24.934328079224 }},
        {position = { x = -39.842098236084, y = 1605.4577636719, z = 118.04917144775 }, rotation = { roll = 0, pitch = 0, yaw = -3.9343256950378 }},
        {position = { x = -7.0824546813965, y = 1686.2442626953, z = 119.53565216064 }, rotation = { roll = 0, pitch = 0, yaw = -56.234275817871 }},
        {position = { x = 87.95238494873, y = 1710.0317382813, z = 106.25793457031 }, rotation = { roll = 0, pitch = 0, yaw = -78.034172058105 }},
        {position = { x = 125.3337020874, y = 1775.1794433594, z = 96.384223937988 }, rotation = { roll = 0, pitch = 0, yaw = 8.6658849716187 }},
        {position = { x = -1.1790904998779, y = 1933.28125, z = 99.809844970703 }, rotation = { roll = 0, pitch = 0, yaw = 63.465881347656 }},
        {position = { x = -41.707584381104, y = 2031.9755957031, z = 101.11741638184 }, rotation = { roll = 0, pitch = 0, yaw = -13.734127998352 }},
        {position = { x = -40.634994506836, y = 2128.9187011719, z = 101.18087531494 }, rotation = { roll = 0, pitch = 0, yaw = 15.66918182373 }},
        {position = { x = -73.91325378418, y = 2077.4643554688, z = 86.646133422752 }, rotation = { roll = 0, pitch = 0, yaw = -175.93081665039 }},
        {position = { x = -132.88162231445, y = 2118.9946289063, z = 71.184829711914 }, rotation = { roll = 0, pitch = 0, yaw = 57.369178771973 }},
        {position = { x = -189.51170349121, y = 2163.1281738281, z = 62.495590209961 }, rotation = { roll = 0, pitch = 0, yaw = 50.369167327881 }},
        {position = { x = -183.35275949707, y = 2092.1682128906, z = 48.582683563232 }, rotation = { roll = 0, pitch = 0, yaw = -149.03075327148 }},
        {position = { x = -275.42260742188, y = 2093.2414550781, z = 36.279987335205 }, rotation = { roll = 0, pitch = 0, yaw = 102.66912841797 }},
        {position = { x = -315.87023925781, y = 2052.7175292969, z = 36.426261901755 }, rotation = { roll = 0, pitch = 0, yaw = -171.03077697754 }},
        {position = { x = -377.15710449219, y = 2016.4694824219, z = 36.105911254883 }, rotation = { roll = 0, pitch = 0, yaw = 89.669235229492 }},
    },
    checkpointEnts = {
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_left.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_right.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_finish.ent",
    },
    totalCheckpoints = 36,
    props = {
    },
    propEnts = {
    },
    totalProps = 0,
}

function HillsideHorsepowerSpeedEdition.init()
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, point in ipairs(HillsideHorsepowerSpeedEdition.checkpoints) do
        trans:SetPosition(ToVector4(point.position))
        trans:SetOrientation(ToEulerAngles(point.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(HillsideHorsepowerSpeedEdition.checkpointEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function HillsideHorsepowerSpeedEdition.spawnProps()
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, prop in ipairs(HillsideHorsepowerSpeedEdition.props) do
        trans:SetPosition(ToVector4(prop.position))
        trans:SetOrientation(ToEulerAngles(prop.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(HillsideHorsepowerSpeedEdition.propEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function HillsideHorsepowerSpeedEdition.GetCheckpointPositions()
    InitializeScript()
    HillsideHorsepowerSpeedEdition.hasExploded = false
    if HillsideHorsepowerSpeedEdition.explodeTimer then
        Cron.Halt(HillsideHorsepowerSpeedEdition.explodeTimer)
        HillsideHorsepowerSpeedEdition.explodeTimer = nil
        HillsideHorsepowerSpeedEdition.hasExploded = false
    end
    local val = {}
    for _, point in ipairs(HillsideHorsepowerSpeedEdition.checkpoints) do
        table.insert(val, ToVector4(point.position))
    end
    return val
end

function HillsideHorsepowerSpeedEdition.GetPropPositions()
    local propVal = {}
    for _, prop in ipairs(HillsideHorsepowerSpeedEdition.props) do
        table.insert(propVal, ToVector4(prop.position))
    end
    return propVal
end

function HillsideHorsepowerSpeedEdition.GetCheckpointRotations()
    local rotVal = {}
    for _, point in ipairs(HillsideHorsepowerSpeedEdition.checkpoints) do
        table.insert(rotVal, ToEulerAngles(point.rotation))
    end
    return rotVal
end

function HillsideHorsepowerSpeedEdition.GetPropRotations()
    local propRotVal = {}
    for _, prop in ipairs(HillsideHorsepowerSpeedEdition.props) do
        table.insert(propRotVal, ToEulerAngles(prop.rotation))
    end
    return propRotVal
end

function HillsideHorsepowerSpeedEdition.GetCheckpointEntities()
    local entVal = {}
    for _, path in ipairs(HillsideHorsepowerSpeedEdition.checkpointEnts) do
        table.insert(entVal, path)
    end
    return entVal
end

function HillsideHorsepowerSpeedEdition.GetPropEntities()
    local propEntVal = {}
    for _, path in ipairs(HillsideHorsepowerSpeedEdition.propEnts) do
        table.insert(propEntVal, path)
    end
    return propEntVal
end

return HillsideHorsepowerSpeedEdition
