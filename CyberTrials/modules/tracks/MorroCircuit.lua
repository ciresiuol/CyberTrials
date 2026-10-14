local Cron = require("modules/external/Cron")

--Observes
    Observe('VehicleObject', 'OnDamageReceived', function(self, event)
        MorroCircuit.hasHit = true
    end)
    Observe('VehicleObject', 'OnVehicleBumpEvent', function(self, event)
        MorroCircuit.hasHit = true
    end)
    Observe('VehicleObject', 'OnHitSounds', function(self, event)
        MorroCircuit.hasHit = true
    end)
    Observe('VehicleObject', 'OnStuckEvent', function(self, event)
        MorroCircuit.hasHit = true
    end)
    Observe('VehicleObject', 'ReactToHitProcess', function(self, event)
        MorroCircuit.hasHit = true
    end)
    Observe('VehicleObject', 'DamagePipelineFinalized', function(self, event)
        MorroCircuit.hasHit = true
    end)
--End Observes

MorroCircuit = {
    name = "Morro Circuit",
    hasCustomWindow = true,
    cetopen = false,
    isDrifting = false,
    driftScore = 0,
    hasHit = false,
    description = "5 laps around the spaceport. Recommended to have traffic on. - - - Created By: TheManualEnhancer",
    creator = "TheManualEnhancer",
    numberOfLaps = 5,
    hubPosition = {
        position = { x = -3502.5246582031, y = 471.17504882813, z = 31.828010559082 },
        rotation = { roll = 0, pitch = 0, yaw = 28.607028961182 }
    },
    startPosition = {
        position = { x = -3491.4860839844, y = 449.61145019531, z = 31.368467330933 },
        rotation = { roll = 0, pitch = 0, yaw = 122.65698242188 }
    },
    checkpoints = {
        {position = { x = -3530.5395507813, y = 424.81362915039, z = 31.365186691284 }, rotation = { roll = 0, pitch = 0, yaw = 166.71449279785 }},
        {position = { x = -3532.396484375, y = 389.14108276367, z = 31.368804931641 }, rotation = { roll = 0, pitch = 0, yaw = 178.83096313477 }},
        {position = { x = -3530.4411621094, y = 342.01412963867, z = 31.36107635498 }, rotation = { roll = 0, pitch = 0, yaw = -135.50430297852 }},
        {position = { x = -3501.5952148438, y = 322.04058837891, z = 31.368474960327 }, rotation = { roll = 0, pitch = 0, yaw = -119.29695129395 }},
        {position = { x = -3458.7744140625, y = 300.80459594727, z = 31.363439559937 }, rotation = { roll = 0, pitch = 0, yaw = -70.134147644043 }},
        {position = { x = -3389.271484375, y = 338.76708984375, z = 31.369659423828 }, rotation = { roll = 0, pitch = 0, yaw = -25.20877456665 }},
        {position = { x = -3385.0710449219, y = 382.33676147461, z = 31.348035812378 }, rotation = { roll = 0, pitch = 0, yaw = -0.2828785777092 }},
        {position = { x = -3384.8806152344, y = 420.99057006836, z = 31.355897903442 }, rotation = { roll = 0, pitch = 0, yaw = 29.027786254883 }},
        {position = { x = -3421.1254882813, y = 446.70501708984, z = 31.379199981689 }, rotation = { roll = 0, pitch = 0, yaw = 60.013809204102 }},
        {position = { x = -3458.0903320313, y = 465.43423461914, z = 31.369842529297 }, rotation = { roll = 0, pitch = 0, yaw = 98.437629699707 }},
        {position = { x = -3492.39453125, y = 449.00036621094, z = 31.368467330933 }, rotation = { roll = 0, pitch = 0, yaw = 118.97780609131 }},
    },
    checkpointEnts = {
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint.ent",
        "base\\gameplay\\devices\\street_signs\\race_checkpoint\\race_checkpoint_finish.ent",
    },
    totalCheckpoints = 11,
    props = {
    },
    propEnts = {
    },
    totalProps = 0,
}

function MorroCircuit.init()
    MorroCircuit.driftScore = 0
    MorroCircuit.hasHit = false
    MorroCircuit.isDrifting = false
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, point in ipairs(MorroCircuit.checkpoints) do
        trans:SetPosition(ToVector4(point.position))
        trans:SetOrientation(ToEulerAngles(point.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(MorroCircuit.checkpointEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function MorroCircuit.spawnProps()
    local val = {}
    local trans = WorldTransform.new()
    local checkId = nil
    for _, prop in ipairs(MorroCircuit.props) do
        trans:SetPosition(ToVector4(prop.position))
        trans:SetOrientation(ToEulerAngles(prop.rotation):ToQuat())
        checkId = exEntitySpawner.Spawn(MorroCircuit.propEnts[_], trans)
        table.insert(val, _, checkId)
    end
    return val
end

function MorroCircuit.GetCheckpointPositions()
    MorroCircuit.driftScore = 0
    MorroCircuit.hasHit = false
    MorroCircuit.isDrifting = false
    local val = {}
    for _, point in ipairs(MorroCircuit.checkpoints) do
        table.insert(val, ToVector4(point.position))
    end
    return val
end

function MorroCircuit.GetPropPositions()
    local propVal = {}
    for _, prop in ipairs(MorroCircuit.props) do
        table.insert(propVal, ToVector4(prop.position))
    end
    return propVal
end

function MorroCircuit.GetCheckpointRotations()
    local rotVal = {}
    for _, point in ipairs(MorroCircuit.checkpoints) do
        table.insert(rotVal, ToEulerAngles(point.rotation))
    end
    return rotVal
end

function MorroCircuit.GetPropRotations()
    local propRotVal = {}
    for _, prop in ipairs(MorroCircuit.props) do
        table.insert(propRotVal, ToEulerAngles(prop.rotation))
    end
    return propRotVal
end

function MorroCircuit.GetCheckpointEntities()
    local entVal = {}
    for _, path in ipairs(MorroCircuit.checkpointEnts) do
        table.insert(entVal, path)
    end
    return entVal
end

function MorroCircuit.GetPropEntities()
    local propEntVal = {}
    for _, path in ipairs(MorroCircuit.propEnts) do
        table.insert(propEntVal, path)
    end
    return propEntVal
end

local veh = nil
local hitTimer = nil
local flags = ImGuiWindowFlags.NoTitleBar or ImGuiWindowFlags.NoNavInputs or ImGuiWindowFlags.NoDecoration

function MorroCircuit.DrawCustomWindow()
    if MorroCircuit.cetopen == false then return end
    local width, height = GetDisplayResolution()
    ImGui.PushStyleColor(ImGuiCol.Header, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Button, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.BorderShadow, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarBg, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrab, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrabHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ScrollbarGrabActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Separator, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.SeparatorHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.SeparatorActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGrip, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGripHovered, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.ResizeGripActive, 0.0, 0.0, 0.0, 0.0)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.0, 1.0, 1.0, 1.1)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 0.0, 1.0, 1.0, 1.1)
    ImGui.SetNextWindowBgAlpha(0)
    ImGui.SetNextWindowPos(width / 40, height / 1.75, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(width / 5, height / 1.75, ImGuiCond.Always)
    if ImGui.Begin('Drift Score', true, flags) then
        ImGui.SetWindowFontScale(2.0)
        veh = Game.GetPlayer().mountedVehicle
        if veh then
            if veh:GetCurrentSpeed() > 10 then
                MorroCircuit.isDrifting = veh:IsSkidding(3.5)
            else
                MorroCircuit.isDrifting = false
            end                
            if MorroCircuit.hasHit == true then
                if not hitTimer then
                    hitTimer = Cron.After(3.0, function()
                        MorroCircuit.hasHit = false
                        hitTimer = nil
                    end)
                else
                    MorroCircuit.hasHit = false
                    Cron.Halt(hitTimer)
                    hitTimer = nil
                end
            else
                if MorroCircuit.isDrifting == true then
                    MorroCircuit.driftScore = math.max(MorroCircuit.driftScore + 50, 0)
                    Game.AddToInventory('Items.money', 25)
                end
            end
        end
        local totalScore = tostring(MorroCircuit.driftScore) or 0
        local totalEddies = tostring(totalScore / 2) or 0
        ImGui.Text('Total Drift Score: ' .. totalScore)
        ImGui.Text('Total Eddies Earned: ' .. totalScore / 2)
    ImGui.End()
    end
    ImGui.PopStyleColor(28)
end

return MorroCircuit
