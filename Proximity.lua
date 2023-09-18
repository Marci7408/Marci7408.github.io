
----------------------------------------
-- Name: Proximity
-- Description: ProximityPrompt handler
----------------------------------------

-- Import necessary modules and services
local Proximity = {} -- Create a table to hold the Proximity module's functions and data.
local import = require(game.ReplicatedStorage.Packages.import) -- Import the 'import' function from a package.
local Interactions = import("~/Interactions") -- Import a module named 'Interactions'.
local Collections = game:GetService("CollectionService") -- Get the CollectionService service from the game.
local RunService = game:GetService("RunService") -- Get the RunService service from the game.
local Players = game:GetService("Players") -- Get the Players service from the game.
local InputService = game:GetService("UserInputService") -- Get the UserInputService service from the game.
local ISEvent: RemoteEvent = import("events/ProximityInteraction") -- Import a remote event named 'ProximityInteraction' using the 'import' function.

-- Initialize the Proximity module
function Proximity:init()
    -- Data structures to track active prompts and prompt mappings
    local activePrompts = {} -- Create a table to store active prompts.
    local pMap = {} -- Create a table to map prompts to parts.
    local plr = Players.LocalPlayer -- Get the local player.
    local character = plr.Character or plr.CharacterAdded:Wait() -- Get the player's character or wait for it to be added.
    local rootPart = character:WaitForChild("HumanoidRootPart") -- Get the character's root part.

    -- Parameters for LOS (Line of Sight) raycasting
    local castParams = RaycastParams.new() -- Create parameters for raycasting.
    castParams.FilterDescendantsInstances = { character } -- Set the filter to exclude the character itself.

    -- Handle character changes
    plr.CharacterAdded:Connect(function(char)
        character = char -- Update the character reference.
        rootPart = char:WaitForChild("HumanoidRootPart") -- Update the root part reference.
        castParams.FilterDescendantsInstances = { char } -- Update the raycasting filter.
    end)

    -- Function to cast Line of Sight (LOS)
    local function CastLOS(att, RequiresLineOfSight, reqDist)
        local distance = (att.WorldPosition - rootPart.Position).Magnitude -- Calculate the distance to the attachment.
        local cast = not RequiresLineOfSight and true -- Assume LOS is not required by default.

        if RequiresLineOfSight then
            -- Check LOS using raycasting if required.
            cast = distance <= reqDist and workspace:Raycast(
                workspace.CurrentCamera.CFrame.Position,
                (att.WorldPosition - workspace.CurrentCamera.CFrame.Position),
                castParams
            ) or false
        end

        return {
            Distance = distance, -- Return the distance to the attachment.
            CastResult = not RequiresLineOfSight and true or (cast and cast.Instance and cast.Instance == att.Parent), -- Return LOS result or 'true' if not required.
        }
    end

    -- Function to deactivate prompts
    local function DeactivatePrompt(prompt, noPartDel)
        prompt.Interaction:Destroy() -- Destroy the interaction button associated with the prompt.
        activePrompts[prompt.Keycode] = nil -- Remove the prompt from the active prompts table.

        if noPartDel ~= true then
            -- If 'noPartDel' flag is not true, remove mapped prompts as well.
            for _, mappedPrompt in pairs(pMap[prompt.Part]) do
                DeactivatePrompt(mappedPrompt, true)
            end
            pMap[prompt.Part] = nil -- Remove the mapping.
        end
    end

    -- Function to activate interactions
    local function ActivateInteraction(activated: boolean, keycode: Enum.KeyCode)
        activePrompts[keycode].Interaction:SetClicked(activated) -- Set the interaction state as clicked or unclicked.

        if activated then
            if activePrompts[keycode].IsLocal == true then
                Proximity:LocalTrigger(activePrompts[keycode].Attachment) -- Trigger a local interaction.
            else
                ISEvent:FireServer(activePrompts[keycode].Attachment) -- Fire a remote event for interaction.
            end
        end
    end

    -- Function to listen for interaction activation
    local function ListenForInteractionActivation(interaction, prompt)
        local btn: TextButton = interaction.activationBtn -- Get the activation button from the interaction.

        btn.InputBegan:Connect(function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                ActivateInteraction(true, prompt.Keycode) -- Activate the interaction on mouse click or touch.
            end
        end)

        btn.InputEnded:Connect(function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                ActivateInteraction(false, prompt.Keycode) -- Deactivate the interaction on mouse release or touch release.
            end
        end)
    end

    -- RenderStepped connection
    RunService.RenderStepped:Connect(function()
        local prompts = Collections:GetTagged("Prompt") -- Get all objects tagged as prompts in the CollectionService.

        -- Goes over all active prompts and asks for re-render when changes/deletion/not-in-distance are detected
        for keycode, promptObj in pairs(activePrompts) do
            local currentEnabled = promptObj.Attachment:GetAttribute("Enabled") -- Get the current 'Enabled' attribute.
            local currentActionText = promptObj.Attachment:GetAttribute("ActionText") -- Get the current 'ActionText' attribute.
            local result = CastLOS(promptObj.Attachment, promptObj.RequiresLineOfSight, promptObj.Distance) -- Calculate LOS result.

            if
                currentEnabled ~= promptObj.Enabled -- Enabled changed
                or currentActionText ~= promptObj.ActionText -- ActionText changed
                or promptObj.Attachment.Parent == nil -- Removed
                or result.Distance >= promptObj.Distance -- Out of distance or LOS
                or result.CastResult == false
            then
                DeactivatePrompt(promptObj) -- Deactivate the prompt if conditions are met.
            end
        end

        -- Goes over all non-active prompts and activates the ones that meet all checks
        for _, promptAtt: Attachment in pairs(prompts) do
            local keycode = Enum.KeyCode[promptAtt:GetAttribute("Keycode")] -- Get the keycode attribute.
            local distance = promptAtt:GetAttribute("Distance") -- Get the distance attribute.
            local enabled = promptAtt:GetAttribute("Enabled") -- Get the enabled attribute.
            local actionText = promptAtt:GetAttribute("ActionText") -- Get the actionText attribute.
            local los = promptAtt:GetAttribute("RequiresLineOfSight") -- Get the RequiresLineOfSight attribute.
            local isLocal = promptAtt:GetAttribute("Local") -- Get the Local attribute.

            if enabled and (not activePrompts[keycode] and true or activePrompts[keycode].Attachment ~= promptAtt) then
                -- Check if the prompt should be activated.
                local result = CastLOS(promptAtt, los, distance) -- Calculate
