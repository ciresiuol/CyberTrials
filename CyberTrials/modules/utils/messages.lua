--[[
    CyberTrials - Message helpers
    Thin wrappers around the game's native notification system.
]]

local messages = {}

function messages.ShowWarning(message, duration)
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

-- Alias used by trackEditor / older code
messages.ShowWarningMessage = messages.ShowWarning

function messages.ShowNotification(message, duration)
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

return messages
