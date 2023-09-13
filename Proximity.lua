----------------------------------------
-- Name: Proximity
-- Description: ProximityPrompt handler
----------------------------------------

-- Import necessary modules and services
local Proximity = {}
local import = require(game.ReplicatedStorage.Packages.import)
local Interactions = import("~/Interactions")
local Collections = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local InputService = game:GetService("UserInputService")
local ISEvent: RemoteEvent = import("events/ProximityInteraction")

-- Initialize the Proximity module
function Proximity:init()
    local activePrompts = {}
    local pMap = {}
    local plr = Players.LocalPlayer
    local character = plr.Character or plr.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")

    local castParams = RaycastParams.new()
    castParams.FilterDescendantsInstances = { character }

    -- Handle character changes
    plr.CharacterAdded:Connect(function(char)
        character = char
        rootPart = char:WaitForChild("HumanoidRootPart")
        castParams.FilterDescendantsInstances = { char }
    end)

    -- Function to cast Line of Sight (LOS)
    local function CastLOS(att, RequiresLineOfSight, reqDist)
        local distance = (att.WorldPosition - rootPart.Position).Magnitude
        local cast = not RequiresLineOfSight and true
            or (
                distance <= reqDist
                    and workspace:Raycast(
                        workspace.CurrentCamera.CFrame.Position,
                        (att.WorldPosition - workspace.CurrentCamera.CFrame.Position),
                        castParams
                    )
                or false
            )

        return {
            Distance = distance,
            CastResult = not RequiresLineOfSight and true or (cast and cast.Instance and cast.Instance == att.Parent),
        }
    end

    -- Function to deactivate prompts
    local function DeactivatePrompt(prompt, noPartDel)
        prompt.Interaction:Destroy()
        activePrompts[prompt.Keycode] = nil

        if noPartDel ~= true then
            for _, mappedPrompt in pairs(pMap[prompt.Part]) do
                DeactivatePrompt(mappedPrompt, true)
            end
            pMap[prompt.Part] = nil
        end
    end

    -- Function to activate interactions
    local function ActivateInteraction(activated: boolean, keycode: Enum.KeyCode)
        activePrompts[keycode].Interaction:SetClicked(activated)
        if activated then
            if activePrompts[keycode].IsLocal == true then
                Proximity:LocalTrigger(activePrompts[keycode].Attachment)
            else
                ISEvent:FireServer(activePrompts[keycode].Attachment)
            end
        end
    end

    -- Function to listen for interaction activation
    local function ListenForInteractionActivation(interaction, prompt)
        local btn: TextButton = interaction.activationBtn
        btn.InputBegan:Connect(function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                ActivateInteraction(true, prompt.Keycode)
            end
        end)

        btn.InputEnded:Connect(function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                ActivateInteraction(false, prompt.Keycode)
            end
        end)
    end

    -- RenderStepped connection
    RunService.RenderStepped:Connect(function()
        local prompts = Collections:GetTagged("Prompt")

        -- Goes over all active prompts and asks for re-render when changes/deletion/not-in-distance are detected
        for keycode, promptObj in pairs(activePrompts) do
            local currentEnabled = promptObj.Attachment:GetAttribute("Enabled")
            local currentActionText = promptObj.Attachment:GetAttribute("ActionText")
            local result = CastLOS(promptObj.Attachment, promptObj.RequiresLineOfSight, promptObj.Distance)

            if
                currentEnabled ~= promptObj.Enabled -- Enabled changed
                or currentActionText ~= promptObj.ActionText -- ActionText changed
                or promptObj.Attachment.Parent == nil -- Removed
                or result.Distance >= promptObj.Distance
                or result.CastResult == false
            then
                DeactivatePrompt(promptObj)
            end
        end

        -- Goes over all non-active prompts and activates the ones that meet all checks
        for _, promptAtt: Attachment in pairs(prompts) do
            local keycode = Enum.KeyCode[promptAtt:GetAttribute("Keycode")]
            local distance = promptAtt:GetAttribute("Distance")
            local enabled = promptAtt:GetAttribute("Enabled")
            local actionText = promptAtt:GetAttribute("ActionText")
            local los = promptAtt:GetAttribute("RequiresLineOfSight")
            local isLocal = promptAtt:GetAttribute("Local")

            if enabled and (not activePrompts[keycode] and true or activePrompts[keycode].Attachment ~= promptAtt) then
                local result = CastLOS(promptAtt, los, distance)
                -- Distance check
                if result.Distance <= distance and result.CastResult == true then
                    -- Make sure there isn't a closer prompt, if the current one is closer then deactivate the further
                    if activePrompts[keycode] then
                        local activeResult = CastLOS(activePrompts[keycode].Attachment, los, distance)
                        if activeResult.Distance < result.Distance then
                            continue
                        else
                            DeactivatePrompt(activePrompts[keycode])
                        end
                    end

                    activePrompts[keycode] = {
                        Keycode = keycode,
                        Distance = distance,
                        Enabled = enabled,
                        Attachment = promptAtt,
                        RequiresLineOfSight = los,
                        Part = promptAtt.Parent,
                        IsLocal = isLocal,
                        ActionText = actionText,
                        Interaction = Interactions:Create(
                            actionText,
                            keycode,
                            promptAtt,
                            pMap[promptAtt.Parent] and #pMap[promptAtt.Parent] * 0.8 or 0
                        ),
                    }

                    ListenForInteractionActivation(activePrompts[keycode].Interaction, activePrompts[keycode])

                    if pMap[promptAtt.Parent] then
                        table.insert(pMap[promptAtt.Parent], activePrompts[keycode])
                    else
                        pMap[promptAtt.Parent] = { activePrompts[keycode] }
                    end
                end
            end
        end
    end)

    -- Input connections
    InputService.InputBegan:Connect(function(input, gameProcessedEvent)
        if
            input.UserInputState == Enum.UserInputState.Begin
            and input.UserInputType == Enum.UserInputType.Keyboard
            and not gameProcessedEvent
            and activePrompts[input.KeyCode]
        then
            ActivateInteraction(true, input.KeyCode)
        end
    end)

    InputService.InputEnded:Connect(function(input, gameProcessedEvent)
        if
            input.UserInputState == Enum.UserInputState.End
            and input.UserInputType == Enum.UserInputType.Keyboard
            and not gameProcessedEvent
            and activePrompts[input.KeyCode]
        then
            ActivateInteraction(false, input.KeyCode)
        end
    end)
end

----------------------------------------
-- Name: LocalProximityRegistry
-- Description: "Emulates" the server
----------------------------------------

local registered = {}

-- Function to trigger local proximity events
function Proximity:LocalTrigger(part: BasePart)
    local plr = Players.LocalPlayer

    if
        registered[part]
        and plr.Character
        and plr.Character.HumanoidRootPart
        and (part.WorldPosition - plr.Character.HumanoidRootPart.Position).Magnitude < registered[part].Distance
    then
        registered[part].Triggered(plr)
    end
end

-- Function to register proximity prompts
function Proximity:Register(prompt)
    registered[prompt.Attachment] = prompt
end

-- Function to unregister proximity prompts
function Proximity:Unregister(prompt)
    if registered[prompt.Attachment] == prompt then
        registered[prompt.Attachment] = nil
    end
end

-- Return the Proximity module
return Proximity

