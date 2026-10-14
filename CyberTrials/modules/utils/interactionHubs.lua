local world = require("modules/external/world")
local raceLogic = require("modules/utils/raceLogic")
local interaction = require("modules/external/interactionUI")
local user = require("modules/UserSettings/config/user")

local interactionHubs = {}

local hub = nil
local mappinIDs = {}

---@param tracks table
function interactionHubs.onSessionStart(tracks)
    -- Rebuild all world interactions for the loaded tracks
    world.interactions = {}
    if type(tracks) ~= "table" then return end
    for i, track in ipairs(tracks) do
        if track and track.startInteraction and track.startInteraction.position then
            interactionHubs.setupChoiceHUD(i, track.startInteraction.position, track.name)
        end
    end
end

function interactionHubs.clearMappins()
    local mappinSystem = Game.GetMappinSystem()
    if not mappinSystem then return end

    for index = #mappinIDs, 1, -1 do
        local mappinID = mappinIDs[index]
        if mappinID then
            mappinSystem:UnregisterMappin(mappinID)
        end
        mappinIDs[index] = nil
    end
end

function interactionHubs.setupMappins(tracks)
    -- UpdateRootState can fire repeatedly. Never rebuild the pins on every
    -- controller update: unregistering/registering them causes visible
    -- flickering when the player is looking toward a race hub.
    if raceLogic and raceLogic.raceInProgress then
        interactionHubs.clearMappins()
        return
    end

    -- Mappins are persistent for the current session. If they already exist,
    -- this call is a no-op.
    if #mappinIDs > 0 then return end

    local mappinSystem = Game.GetMappinSystem()
    if not mappinSystem then return end

    local data = MappinData.new({
        mappinType = 'Mappins.QuestDynamicMappinDefinition',
        variant = gamedataMappinVariant.Zzz18_RacingVariant,
        visibleThroughWalls = false,
        active = true
    })

    for _, track in ipairs(tracks or {}) do
        local hubdata = track.startInteraction
        if hubdata and hubdata.position then
            local mappinID = mappinSystem:RegisterMappin(
                data,
                Vector4.new(hubdata.position.x, hubdata.position.y, hubdata.position.z + 1)
            )
            table.insert(mappinIDs, mappinID)
        end
    end
end

--- Force hubs to re-evaluate range after a race ends so choices can show again
--- without requiring the player to leave and re-enter the interaction zone.
function interactionHubs.restoreAfterRace()
    for _, interactionData in pairs(world.interactions) do
        interactionData.shown = false
        interactionData.hideIcon = false
        -- Drop any leftover world pin so world.update can re-register it
        if interactionData.pinID then
            local mappinSystem = Game.GetMappinSystem()
            if mappinSystem then
                mappinSystem:UnregisterMappin(interactionData.pinID)
            end
            interactionData.pinID = nil
        end
    end
    -- Allow map mappins to be recreated on the next UpdateRootState
    interactionHubs.clearMappins()
end

---@param index int
---@param position table
---@param trackname string
function interactionHubs.setupChoiceHUD(index, position, trackname)
    if raceLogic and raceLogic.raceInProgress then return end
    local posStart = ToVector4(position)
    local interactionRange = 3
    local icon = "ChoiceIcon.VehicleIcon"
    -- iconRange controls how far away the world pin is visible.
    -- 0 effectively prevents the pin from ever appearing.
    local iconRange = 25
    local iconColor = HDRColor.new({Red = 1, Green = 219 / 255, Blue = 78 / 255})
    local angle = 360

    world.addInteraction(index, posStart, interactionRange, angle, icon, iconRange, iconColor, function(state)
        -- Block hub UI while a race is actively running (not merely because a
        -- track reference still exists after a finished race).
        if raceLogic and raceLogic.raceInProgress then return end

        if state == true then
            local choiceFlavor = gameinteractionsChoiceType.Blueline
            local choice = interaction.createChoice(
                "Start Time Trial Event",
                TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts.VehicleAccelerateIcon"),
                choiceFlavor
            )
            hub = interaction.createHub(trackname, {choice})
            interaction.setupHub(hub)
            interaction.showHub()

            interaction.callbacks[1] = function()
                world.togglePin(world.interactions[index], false)
                interaction.hideHub()
                -- Always clear any previous race progress before starting a new one
                if raceLogic.raceInProgress then
                    raceLogic.endActiveRace(true)
                else
                    raceLogic.resetRace()
                end
                -- startRace requires player to have entered/exited a vehicle already
                raceLogic.startRace(trackname)
                hub = nil
            end
        else
            interaction.hideHub()
            hub = nil
        end
    end)
end



--- Fully tear down all interaction hubs, world pins, map mappins, and UI hubs.
function interactionHubs.shutdown()
    interactionHubs.clearMappins()
    local mappinSystem = Game.GetMappinSystem()
    for id, interactionData in pairs(world.interactions or {}) do
        if interactionData then
            if interactionData.pinID and mappinSystem then
                pcall(function() mappinSystem:UnregisterMappin(interactionData.pinID) end)
                interactionData.pinID = nil
            end
            interactionData.shown = false
            interactionData.hideIcon = true
            interactionData.callback = nil
        end
        world.interactions[id] = nil
    end
    world.interactions = {}
    pcall(function()
        interaction.hideHub()
    end)
    pcall(function()
        interaction.clearCallbacks()
    end)
    hub = nil
    mappinIDs = {}
end

return interactionHubs
