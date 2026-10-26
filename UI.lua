local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local gui = script.Parent
gui.ResetOnSpawn = false

if player:GetAttribute("HasMorphed") then
    gui.Enabled = false
    return
end

local clickSound = gui:FindFirstChild("Button")
local mainMenu = gui:FindFirstChild("MainMenu")
local kaijusFrame = gui:FindFirstChild("Kaijus")
local settingsFrame = gui:FindFirstChild("Settings")

local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local loadingTweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local sliderTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Exponential)

local MENU_HIDDEN = UDim2.new(-1.1, 0, 0, 0)
local MENU_SHOWN = UDim2.new(0, 0, 0, 0)

local activeTweens = {}

local function cancelTween(instance)
    local existing = activeTweens[instance]
    if existing then
        existing:Cancel()
        activeTweens[instance] = nil
    end
end

local function playTween(instance, info, properties)
    cancelTween(instance)
    local tween = TweenService:Create(instance, info, properties)
    activeTweens[instance] = tween
    tween.Completed:Connect(function()
        if activeTweens[instance] == tween then
            activeTweens[instance] = nil
        end
    end)
    tween:Play()
    return tween
end

local function playClickSound()
    if clickSound then
        clickSound:Play()
    end
end

for _, descendant in ipairs(gui:GetDescendants()) do
    if descendant:IsA("GuiButton") then
        descendant.MouseButton1Click:Connect(playClickSound)
    end
end

local buttonContainer = mainMenu and mainMenu:FindFirstChild("Button")

local introCancelled = false

if mainMenu then
    mainMenu.Position = UDim2.new(0, 0, -1, 0)
    task.spawn(function()
        local deadline = os.clock() + 60
        while not player:GetAttribute("PreloadingDone") and os.clock() < deadline do
            task.wait(0.1)
        end
        task.wait(0.1)
        if introCancelled or player:GetAttribute("HasMorphed") then return end
        if mainMenu.Parent and mainMenu.Position.Y.Scale < -0.5 then
            playTween(mainMenu, tweenInfo, { Position = MENU_SHOWN })
        end
    end)
end

local settingsPanel = settingsFrame and settingsFrame:FindFirstChild("SettingsPanel")
local sliderBackgroundFOV = settingsPanel and settingsPanel:FindFirstChild("FOVBack")
local sliderFOV = sliderBackgroundFOV and sliderBackgroundFOV:FindFirstChild("FOVFront")
local fovUpdater = settingsPanel and settingsPanel:FindFirstChild("FOVUpdater")
local fovShowcase = settingsPanel and settingsPanel:FindFirstChild("FOVText")
local fovValue = fovUpdater and fovUpdater:FindFirstChild("FOV")

local FOV_MIN = 70
local FOV_MAX = 120
local fovSliderActive = false
local currentFOV = math.clamp(math.round(camera.FieldOfView), FOV_MIN, FOV_MAX)
local textResetToken = 0

local function fovToAlpha(value)
    return (value - FOV_MIN) / (FOV_MAX - FOV_MIN)
end

if sliderFOV and fovShowcase and fovValue then
    fovValue.Value = currentFOV / 100
    fovShowcase.Text = tostring(currentFOV)
    sliderFOV.Size = UDim2.fromScale(fovToAlpha(currentFOV), 1)

    local function updateSliderFOV()
        local width = sliderBackgroundFOV.AbsoluteSize.X
        if width <= 0 then return end
        local alpha = math.clamp((mouse.X - sliderBackgroundFOV.AbsolutePosition.X) / width, 0, 1)
        local newFOV = math.round(FOV_MIN + alpha * (FOV_MAX - FOV_MIN))
        if newFOV ~= currentFOV then
            currentFOV = newFOV
            fovValue.Value = newFOV / 100
            fovShowcase.Text = tostring(newFOV)
        end
        playTween(sliderFOV, sliderTweenInfo, { Size = UDim2.fromScale(alpha, 1) })
    end

    local function activateSlider()
        if fovSliderActive then return end
        fovSliderActive = true
        while fovSliderActive and sliderFOV.Parent do
            updateSliderFOV()
            task.wait()
        end
    end

    local function updateFromTextBox()
        textResetToken += 1
        local number = tonumber(fovShowcase.Text)
        if not number then
            fovShowcase.Text = "Must be a number!"
            local token = textResetToken
            task.delay(3, function()
                if token == textResetToken then
                    fovShowcase.Text = tostring(currentFOV)
                end
            end)
            return
        end
        currentFOV = math.clamp(math.round(number), FOV_MIN, FOV_MAX)
        fovValue.Value = currentFOV / 100
        fovShowcase.Text = tostring(currentFOV)
        playTween(sliderFOV, sliderTweenInfo, { Size = UDim2.fromScale(fovToAlpha(currentFOV), 1) })
    end

    fovUpdater.MouseButton1Down:Connect(activateSlider)

    fovShowcase.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            updateFromTextBox()
        else
            textResetToken += 1
            fovShowcase.Text = tostring(currentFOV)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            fovSliderActive = false
        end
    end)
end

if buttonContainer and settingsFrame then
    local settingsBtn = buttonContainer:FindFirstChild("Settings")
    if settingsBtn then
        settingsBtn.MouseButton1Click:Connect(function()
            cancelTween(settingsFrame)
            settingsFrame.Visible = true
            settingsFrame.Position = UDim2.new(0, 0, -1.1, 0)
            playTween(settingsFrame, tweenInfo, { Position = UDim2.new(0.15, 0, 0.15, 0) })
            playTween(mainMenu, tweenInfo, { Position = MENU_HIDDEN })
        end)
    end

    local settingsBack = settingsFrame:FindFirstChild("Back")
    if settingsBack then
        settingsBack.MouseButton1Click:Connect(function()
            local tween = playTween(settingsFrame, tweenInfo, { Position = UDim2.new(-1.1, 0, 0, 0) })
            playTween(mainMenu, tweenInfo, { Position = MENU_SHOWN })
            tween.Completed:Connect(function(state)
                if state == Enum.PlaybackState.Completed then
                    settingsFrame.Visible = false
                end
            end)
        end)
    end
end

if buttonContainer and kaijusFrame then
    local kaijusBtn = buttonContainer:FindFirstChild("Kaijus")
    if kaijusBtn then
        kaijusBtn.MouseButton1Click:Connect(function()
            kaijusFrame.Visible = true
            playTween(kaijusFrame, tweenInfo, { Position = UDim2.new(0, 0, 0, 0) })
            playTween(mainMenu, tweenInfo, { Position = MENU_HIDDEN })
        end)
    end
end

local function getSelectedMorphName()
    local stats = kaijusFrame and kaijusFrame:FindFirstChild("Stats")
    local name = stats and stats:GetAttribute("CurrentMorph")
    if type(name) == "string" and name ~= "" then
        return name
    end
    local func = ReplicatedStorage:FindFirstChild("GetSelectedKaiju")
    if func and func:IsA("RemoteFunction") then
        local ok, result = pcall(function()
            return func:InvokeServer()
        end)
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end
    return nil
end

local function findMorphFireRemote()
    local supplies = ReplicatedStorage:FindFirstChild("MorphSupplies")
    local events = supplies and supplies:FindFirstChild("Events")
    return events and events:FindFirstChild("Fire")
end

local function waitForMorphReady(timeout)
    local deadline = os.clock() + timeout
    local morphReady = ReplicatedStorage:FindFirstChild("MorphReady")
    while not morphReady and os.clock() < deadline do
        task.wait(0.1)
        morphReady = ReplicatedStorage:FindFirstChild("MorphReady")
    end
    while morphReady and not morphReady.Value and os.clock() < deadline do
        task.wait(0.1)
    end
    return morphReady ~= nil and morphReady.Value == true
end

local playing = false

local function startPlay()
    if playing then return end
    playing = true
    introCancelled = true

    local selectedMorphName = getSelectedMorphName()
    if not selectedMorphName then
        warn("No kaiju selected! Please select a kaiju first.")
        playing = false
        return
    end

    local supplies = ReplicatedStorage:FindFirstChild("MorphSupplies")
    local morphs = supplies and supplies:FindFirstChild("Morphs")
    if not morphs then
        playing = false
        return
    end
    if not morphs:FindFirstChild(selectedMorphName) then
        warn("Could not find morph model: " .. tostring(selectedMorphName))
        playing = false
        return
    end

    local playerGui = player:FindFirstChild("PlayerGui")
    local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
    local gameMainFrame = gameGui and gameGui:FindFirstChild("MainFrame")
    local loadingFrame = gameMainFrame and gameMainFrame:FindFirstChild("Loading")
    local gameInterface = gameMainFrame and gameMainFrame:FindFirstChild("Interface")

    local slideInConnection

    local function restoreMenu()
        if slideInConnection then
            slideInConnection:Disconnect()
            slideInConnection = nil
        end
        if loadingFrame then
            cancelTween(loadingFrame)
            loadingFrame.Visible = false
        end
        if gameGui then gameGui.Enabled = false end
        if mainMenu then
            cancelTween(mainMenu)
            mainMenu.Position = MENU_SHOWN
            mainMenu.Visible = true
        end
        player:SetAttribute("IsMorphing", false)
        playing = false
    end

    if mainMenu then
        cancelTween(mainMenu)
    end

    if gameGui then
        gameGui.Enabled = true
        if gameInterface then gameInterface.Visible = false end
    end

    if loadingFrame then
        loadingFrame.Visible = true
        loadingFrame.Position = UDim2.new(0, 0, -1, 0)
        local slideIn = playTween(loadingFrame, loadingTweenInfo, { Position = MENU_SHOWN })
        slideInConnection = slideIn.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed and mainMenu then
                mainMenu.Visible = false
            end
        end)
    elseif mainMenu then
        mainMenu.Visible = false
    end

    if not waitForMorphReady(15) then
        restoreMenu()
        warn("Morph server is not ready")
        return
    end

    local fireEvent = findMorphFireRemote()
    local morphResultEvent = ReplicatedStorage:FindFirstChild("MorphResult")
    if not fireEvent then
        restoreMenu()
        warn("Morph event is not ready")
        return
    end

    local morphSucceeded = false
    local morphResultReceived = false
    local failReason = nil
    local previousCharacter = player.Character

    local characterConnection = player.CharacterAdded:Connect(function(character)
        if character ~= previousCharacter then
            morphSucceeded = true
            morphResultReceived = true
        end
    end)

    local morphResultConnection
    if morphResultEvent then
        morphResultConnection = morphResultEvent.OnClientEvent:Connect(function(success, morphName, message)
            if morphName == selectedMorphName or success == false then
                morphSucceeded = success == true
                if not success and type(message) == "string" then
                    failReason = message
                end
                morphResultReceived = true
            end
        end)
    end

    player:SetAttribute("IsMorphing", true)
    fireEvent:FireServer(selectedMorphName)

    local deadline = os.clock() + 15
    while not morphResultReceived and os.clock() < deadline do
        task.wait()
    end

    if morphResultConnection then morphResultConnection:Disconnect() end
    characterConnection:Disconnect()

    if not morphSucceeded then
        restoreMenu()
        if failReason then
            warn("Morph request failed: " .. failReason)
        else
            warn("Morph request timed out - no response from server")
        end
        return
    end

    player:SetAttribute("HasMorphed", true)
    task.wait(0.25)

    if loadingFrame then
        local slideOut = playTween(loadingFrame, loadingTweenInfo, { Position = UDim2.new(0, 0, -1, 0) })
        slideOut.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed then
                loadingFrame.Visible = false
            end
        end)
    end

    if mainMenu then
        cancelTween(mainMenu)
        mainMenu.Visible = false
    end
    if kaijusFrame then
        cancelTween(kaijusFrame)
        kaijusFrame.Visible = false
    end
    if settingsFrame then
        cancelTween(settingsFrame)
        settingsFrame.Visible = false
    end
    gui.Enabled = false

    if playerGui then
        for _, child in ipairs(playerGui:GetChildren()) do
            if child:IsA("ScreenGui") and (child.Name == "NEWMenu" or child.Name == "oldMenu") then
                child.Enabled = false
            end
        end
    end

    if gameGui then
        gameGui.Enabled = true
        if gameInterface then gameInterface.Visible = true end
    end

    if playerGui then
        local touchGui = playerGui:FindFirstChild("TouchGui")
        if touchGui then touchGui.Enabled = true end

        if UserInputService.TouchEnabled and gameInterface then
            local mobile = gameInterface:FindFirstChild("Mobile")
            if mobile then mobile.Visible = true end
        end
    end

    playing = false
end

local playBtn = buttonContainer and buttonContainer:FindFirstChild("Play")
if playBtn then
    playBtn.MouseButton1Click:Connect(startPlay)
end
