local ui =  {
    baseControler = nil,
    hub = nil,
    callbacks = {},
    hubShown = false,
    selectedIndex = 0,
    customHubSelected = false,
    input = false,
    lastNativeIndex = 0 -- 0=Top, 1=Bottom, used to keep track what choice is currently selected by the native internal system, to allow proper rollover when going custom <-> native (Based on internal index, either consume scroll action, or not, to get the desired internal index)
}

-- Local helpers:

---Updates the SelectedIndex on the blackboard, forcing a UI refresh
local function updateSelectedIndex(index)
    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions)
    local ibd = GetAllBlackboardDefs().UIInteractions

    ib:SetInt(ibd.SelectedIndex, index)
end

---Updates the ActiveChoiceHubID on the blackboard, forcing a UI refresh
---@param id number
local function updateSelectedHub(id)
    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions)
    local ibd = GetAllBlackboardDefs().UIInteractions

    ib:SetInt(ibd.ActiveChoiceHubID, id)
end

---@return ListChoiceHubData[]
local function getDialogChoiceHubs()
    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions)
    local ibd = GetAllBlackboardDefs().UIInteractions
    if not ib then return {} end

    local data = FromVariant(ib:GetVariant(ibd.DialogChoiceHubs))
    if type(data) ~= 'table' or type(data.choiceHubs) ~= 'table' then
        return {}
    end
    return data.choiceHubs
end

---@return number
local function getActiveChoiceHubID()
    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions)
    local ibd = GetAllBlackboardDefs().UIInteractions

    return ib:GetInt(ibd.ActiveChoiceHubID)
end

---@return number
local function getSelectedIndex()
    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions)
    local ibd = GetAllBlackboardDefs().UIInteractions

    return ib:GetInt(ibd.SelectedIndex)
end

---Get the list of choices, and the index in the list of hubs of the currently selected native hub
---@return {choices: ListChoiceData[], index: number}
local function getActiveHubData()
    local activeID = getActiveChoiceHubID()
    local hubs = getDialogChoiceHubs()
    if hubs and type(hubs) == "table" and #hubs > 0 then
        for key, hub in ipairs(hubs) do
            if hub.id == activeID then
                return {choices = hub.choices, index = key}
            end
        end
    end
    return {}
end

---Checks if the selected choice is the last one of all native hubs
---@return boolean
local function isLastChoiceSelected()
    local data = getActiveHubData()
    if type(data.choices) ~= 'table' then return false end

    if getSelectedIndex() == #data.choices - 1 then
        return data.index == #getDialogChoiceHubs()
    end

    return false
end

---Checks if the selected choice is the first one of all native hubs
---@return boolean
local function isFirstChoiceSelected()
    local data = getActiveHubData()

    if getSelectedIndex() == 0 then
        return data.index == 1
    end

    return false
end

local debug = false
local function log(text)
    if not debug then return end
    print(text)
end

---@param localizedName string
---@param icon gamedataChoiceCaptionIconPart_Record
---@param choiceType gameinteractionsChoiceType
---@return gameinteractionsvisListChoiceData
function ui.createChoice(localizedName, icon, choiceType) -- Creates and returns a choice
    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = localizedName or "Choice"
    choice.inputActionName = "None"

    if icon then
        local part = gameinteractionsChoiceCaption.new()
        part:AddPartFromRecord(icon)
        choice.captionParts = part
    end

    if choiceType then
        local choiceT = gameinteractionsChoiceTypeWrapper.new()
        choiceT:SetType(choiceType)
        choice.type = choiceT
    end

    return choice
end

---@param title string
---@param choices table
---@param activityState gameinteractionsvisEVisualizerActivityState
---@return gameinteractionsvisListChoiceHubData
function ui.createHub(title, choices, activityState) -- Creates and returns a hub
    local hub = gameinteractionsvisListChoiceHubData.new()
    if hub then
        hub.title = title or "Title"
        hub.choices = choices or {}
        hub.activityState = activityState or gameinteractionsvisEVisualizerActivityState.Active
        hub.hubPriority = -1
        hub.id = 69420 + math.random(99999)
    else
        hub = {}
    end
    return hub
end

---@param hub gameinteractionsvisListChoiceHubData
function ui.setupHub(hub) -- Setup interaction hub
    ui.hub = hub
end

function ui.showHub() -- Shows the hub previously set using setupHub()
    if not ui.hub or not ui.baseControler then print('Got no Basecontroller')return end
    ui.hubShown = true
    ui.customHubSelected = false
    ui.selectedIndex = 0
    ui.lastNativeIndex = 0

    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions);
    local ibd = GetAllBlackboardDefs().UIInteractions;

    local data = ib:GetVariant(ibd.DialogChoiceHubs)
    -- Force UI to refresh, causing the OnDialogsData override to inject the custom hub
    -- Since we cant change the internal choice index, we do not change the active index to be on our custom hub, all index changing has to happen by user input (Up/Down scroll)
    ui.baseControler:OnDialogsData(data)
end

function ui.hideHub() -- Hides the hub
    if not ui.hub or not ui.baseControler then return end

    ui.hubShown = false
    ui.hub = nil

    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions);
    local ibd = GetAllBlackboardDefs().UIInteractions;

    local data = ib:GetVariant(ibd.DialogChoiceHubs)
    ui.baseControler:OnDialogsData(data)

    if not ui.customHubSelected then return end
    ui.customHubSelected = false

    local hubs = getDialogChoiceHubs()
    if hubs then
        if #hubs ~= 0 then
            -- Update UI to reflect the last native index
            local lastHubIndex = 1
            local lastNativeChoiceIndex = 0

            if ui.lastNativeIndex == 1 then
                lastHubIndex = #hubs
                lastNativeChoiceIndex = #hubs[#hubs].choices - 1
            end
            updateSelectedHub(hubs[lastHubIndex].id)
            updateSelectedIndex(lastNativeChoiceIndex)
        end
    end
end

function ui.registerChoiceCallback(choiceIndex, callback) -- Register a callback for a choice via index, starting at 1
    ui.callbacks[choiceIndex] = callback
end

function ui.clearCallbacks() -- Remove all callbacks
    ui.callbacks = {}
end

function ui.init() -- Register needed observers
    -- Inject custom hub
    Override("InteractionUIBase", "OnDialogsData", function (_, value, wrapped)
        if not Game.GetPlayer() then return wrapped(value) end
        local success = pcall(function ()
            local data = FromVariant(value)

            if ui.hubShown then
                local hubs = data.choiceHubs
                table.insert(hubs, ui.hub) -- Append as last, ensures custom hub is always last
                data.choiceHubs = hubs
            end

            wrapped(ToVariant(data))
        end)
        if not success then wrapped(value) end
    end)

    Observe("InteractionUIBase", "OnDialogsData", function(this)
        ui.baseControler = this
    end)
    
    Observe("InteractionUIBase", "OnInitialize", function(this)
        ui.baseControler = this
    end)

    Observe("PlayerPuppet", "OnAction", function(_, action, consumer)
        if not ui.hubShown or not Game.GetPlayer() then return end
        if Game.GetPlayer().mountedVehicle then return end

        local actionName = Game.NameToString(action:GetName(action))
        local actionType = action:GetType(action).value

        if actionName == "ChoiceScrollDown" and actionType == "BUTTON_PRESSED" then
            log("---------------- Got a scroll down event ----------------")
            if ui.input then
                log("Already had an input this frame, consuming and returning")
                consumer:Consume()
                return
            end

            if ui.customHubSelected then
                log("Custom hub is selected")
                if ui.selectedIndex == #ui.hub.choices - 1 then -- Last option of custom hub, wrap around to first choice
                    log("We are on the last option")
                    ui.selectedIndex = 0 -- Next UI index is always 0

                    local hubs = getDialogChoiceHubs()
                    if #hubs ~= 0 then -- If there are native hubs, use first native hub, otherwise activeHub stays the custom one
                        log("There are native hubs")
                        ui.customHubSelected = false
                        updateSelectedHub(hubs[1].id)

                        -- We go down, so if the next choice is the first native one, if that is also what is already stored as native index, we should ignore / consume this action
                        if ui.lastNativeIndex == 0 then
                            ui.input = true
                        end

                        -- If there is only one hub with one choice, we dont need to change anything, since nativeIndex is always the one choice
                        if #hubs[1].choices == 1 and #hubs == 1 then
                            ui.input = true
                        end
                    else
                        consumer:Consume()
                        log("There only is a custom hub, consuming input")
                    end
                else
                    ui.selectedIndex = ui.selectedIndex + 1 -- Scroll within custom hub
                    updateSelectedHub(ui.hub.id)
                    consumer:Consume() -- Avoid native scroll
                    log("Not the last option, going down one index, then consuming")
                end
                updateSelectedIndex(ui.selectedIndex) -- Refresh UI
                log("End of scroll down handling, selecting index " .. ui.selectedIndex)
            else
                log("Custom hub is not active")
                if isLastChoiceSelected() then -- Go from last native choice to first custom hub choice
                    consumer:Consume()
                    ui.customHubSelected = true
                    ui.selectedIndex = 0
                    ui.lastNativeIndex = 1 -- Store that the native index is at the last choice
                    updateSelectedHub(ui.hub.id)
                    updateSelectedIndex(ui.selectedIndex)
                    log("Last choice was selected, going to custom hub and consuming input")
                end
            end
        end

        if actionName == "ChoiceScrollUp" and actionType == "BUTTON_PRESSED" then
            log("---------------- Got a scroll up event ----------------")
            if ui.input then
                log("Already had an input this frame, consuming and returning")
                consumer:Consume()
                return
            end

            if ui.customHubSelected then
                log("Custom hub is selected")
                if ui.selectedIndex == 0 then -- First option, wrap around to last one
                    log("We are on the first option")
                    local hubs = getDialogChoiceHubs()
                    if #hubs ~= 0 then -- If there are native hubs, use last native hub, otherwise activeHub stays the custom one
                        local hub = hubs[#hubs]

                        ui.customHubSelected = false
                        ui.selectedIndex = #hub.choices - 1
                        updateSelectedHub(hub.id)
                        log("There are native hubs, not consuming input")

                        if ui.lastNativeIndex == 1 then
                            ui.input = true
                        end

                        if #hubs[1].choices == 1 and #hubs == 1 then
                            ui.input = true
                        end
                    else
                        ui.selectedIndex = #ui.hub.choices - 1
                        consumer:Consume()
                        log("There only is a custom hub, consuming input")
                    end
                else
                    ui.selectedIndex = ui.selectedIndex - 1 -- Scroll within custom hub
                    updateSelectedHub(ui.hub.id)
                    consumer:Consume() -- Avoid native scroll
                    log("Not the first option, going up one index, then consuming")
                end
                updateSelectedIndex(ui.selectedIndex)
                log("End of scroll up handling, selecting index " .. ui.selectedIndex)
            else
                log("Custom hub is not active")
                if isFirstChoiceSelected() then -- Go from last native choice to first custom hub choice
                    consumer:Consume()
                    ui.customHubSelected = true
                    ui.selectedIndex = #ui.hub.choices - 1
                    ui.lastNativeIndex = 0
                    updateSelectedHub(ui.hub.id)
                    updateSelectedIndex(ui.selectedIndex)
                    log("First choice was selected, going to custom hub and consuming input")
                end
            end
        end

        if actionName == "ChoiceApply" then
            if actionType == "BUTTON_PRESSED"then
                log("Apply input, custom hub active:" .. tostring(ui.customHubSelected))
                if ui.customHubSelected then
                    consumer:Consume() -- Avoid native option from getting triggered
                    if ui.callbacks[ui.selectedIndex + 1] then
                        ui.callbacks[ui.selectedIndex + 1]()
                    end
                end
                ui.input = true
            end
        end
    end)

end

function ui.update() -- Run every frame to avoid unwanted changes
    if not Game.GetPlayer() then return end
    if Game.GetPlayer().mountedVehicle then return end

    local hubs = getDialogChoiceHubs()
    if type(hubs) ~= 'table' then return end

    if ui.hubShown and ui.customHubSelected and #hubs == 0 then
        updateSelectedHub(ui.hub.id)
        updateSelectedIndex(ui.selectedIndex)
    elseif ui.hubShown then
        ui.customHubSelected = getActiveChoiceHubID() == ui.hub.id

        if #hubs == 0 then
            updateSelectedHub(ui.hub.id)
            updateSelectedIndex(0)
            ui.customHubSelected = true
            ui.selectedIndex = 0
        end
    end

    ui.input = false
end

return ui