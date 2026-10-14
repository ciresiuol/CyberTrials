-------------------------------------------------------------------------------------------------------------------------------
-- This file was created by keanuWheeze from CP2077 Modding Tools Discord and modified slightly by the Mod author
-------------------------------------------------------------------------------------------------------------------------------
local raceLogic = require("modules/utils/raceLogic")
local world = {
    interactions = {}
}

function world.addInteraction(id, position, interactionRange, angle, icon, iconRange, iconColor, callback) -- Add a in-world interaction with callback for hide / show, icon is optional
    world.interactions[id] = {
        pos = position,
        interactionRange = interactionRange,
        icon = icon,
        iconRange = iconRange or 0,
        iconColor = iconColor,
        angle = angle,
        callback = callback,
        pinID = nil,
        shown = false,
        hideIcon = false
    }
end

function world.init()
    ObserveAfter("BaseMappinBaseController", "UpdateRootState", function(this) -- Custom pin texture
        if not Game.GetPlayer() then return end
        if Game.GetPlayer().mountedVehicle then return end
        local mappin = this:GetMappin()
        if not mappin then return end
        local pos = mappin:GetWorldPosition()
        for _, interaction in pairs(world.interactions) do
            if Vector4.Distance(pos, interaction.pos) < 0.05 then
                local record = TweakDBInterface.GetUIIconRecord(interaction.icon)
                if record and this.iconWidget then
                    this.iconWidget:SetAtlasResource(record:AtlasResourcePath())
                    this.iconWidget:SetTexturePart(record:AtlasPartName())
                    this.iconWidget:SetTintColor(interaction.iconColor or HDRColor.new({ Red = 0.15829999744892, Green = 1.3033000230789, Blue = 1.4141999483109, Alpha = 1.0 }))
                end
            end
        end
    end)
end

local posPlayer = { x = 1, y = 1, z = 1, w = 1 }

function world.update()
    if not Game.GetPlayer() then return end
    if Game.GetPlayer().mountedVehicle or Game.GetPlayer():IsInCombat() then return end

    local playerPos = Game.GetPlayer():GetWorldPosition()
    if playerPos then
        posPlayer = playerPos
        posPlayer.z = posPlayer.z + 1
    else
        local transform = Game.GetPlayer():GetWorldTransform()
        if transform then
            local wp = transform:GetWorldPosition()
            if wp then
                posPlayer = wp:ToVector4()
                posPlayer.z = posPlayer.z + 1
            end
        end
    end

    for _, interaction in pairs(world.interactions) do
        local update = interaction.shown
        if (Vector4.Distance(posPlayer, interaction.pos) < interaction.interactionRange) and not raceLogic.raceInProgress then
            update = true
        else
            update = false
        end
        if update ~= interaction.shown then
            interaction.shown = update
            if interaction.callback then
                interaction.callback(interaction.shown)
            end
        end

        -- World pin visibility (iconRange metres). Skip while a race is active.
        if interaction.icon and not interaction.hideIcon and not raceLogic.raceInProgress then
            if Vector4.Distance(posPlayer, interaction.pos) < interaction.iconRange then
                world.togglePin(interaction, true)
            else
                world.togglePin(interaction, false)
            end
        elseif interaction.icon and raceLogic.raceInProgress then
            world.togglePin(interaction, false)
        end
    end
end

function world.togglePin(interaction, state)
    if not interaction.icon or interaction.hideIcon then return end
    if not state and interaction.pinID then
        Game.GetMappinSystem():UnregisterMappin(interaction.pinID)
        interaction.pinID = nil
        return
    elseif not interaction.pinID and state then
        local data = MappinData.new({
            mappinType = 'Mappins.DefaultStaticMappin',
            variant = gamedataMappinVariant.UseVariant,
            visibleThroughWalls = false
        })
        interaction.pinID = Game.GetMappinSystem():RegisterMappin(data, interaction.pos)
    end
end

function world.onSessionStart() -- Save loaded, all pins are gone
    for _, interaction in pairs(world.interactions) do
        interaction.shown = false
        interaction.pinID = nil
        interaction.hideIcon = false
    end
end

return world
