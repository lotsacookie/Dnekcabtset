local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = script.Parent

gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100

local function releaseMenu()
    player:SetAttribute("PreloadingDone", true)
    if not player:GetAttribute("HasMorphed") then
        local menuGui = playerGui:FindFirstChild("NEWMenu")
        if menuGui then menuGui.Enabled = true end
    end
end

local function shutDown()
    gui.Enabled = false
    releaseMenu()
end

if player:GetAttribute("PreloadingDone") or player:GetAttribute("HasMorphed") then
    shutDown()
    return
end

local mainFrame = gui:FindFirstChild("Preloading")
local preloadText = mainFrame and mainFrame:FindFirstChild("PreloadText")
local bar = mainFrame and mainFrame:FindFirstChild("Bar")
local barMain = bar and bar:FindFirstChild("Main")
local mover = barMain and barMain:FindFirstChild("Mover")
local clicky = mainFrame and mainFrame:FindFirstChild("Clicky")

if not mainFrame or not preloadText or not mover or not clicky then
    warn("[Preload] Missing Preloading, PreloadText, Mover or Clicky")
    shutDown()
    return
end

local WORKER_COUNT = 8
local ASSET_TIMEOUT = 3

local moverXOffset = mover.Size.X.Offset
local moverYScale = mover.Size.Y.Scale
local moverYOffset = mover.Size.Y.Offset

local assetTypeSet = {
    Decal = true,
    Texture = true,
    Sound = true,
    MeshPart = true,
    SpecialMesh = true,
    ImageLabel = true,
    ImageButton = true,
    SurfaceAppearance = true,
}

local assetsToPreload = {}
for _, descendant in ipairs(game:GetDescendants()) do
    if assetTypeSet[descendant.ClassName] and not descendant:IsDescendantOf(gui) then
        table.insert(assetsToPreload, descendant)
    end
end

local totalAssets = #assetsToPreload
local loadedAssets = 0
local nextIndex = 0
local activeWorkers = 0
local cancelled = false
local finished = false

mainFrame.Visible = true
mainFrame.Position = UDim2.new(0, 0, 0, 0)
mover.Size = UDim2.new(0, moverXOffset, moverYScale, moverYOffset)
preloadText.Text = string.format("Preloading Assets (0/%d)", totalAssets)
gui.Enabled = true

local function updateProgress()
    if finished then return end
    preloadText.Text = string.format("Preloading Assets (%d/%d)", loadedAssets, totalAssets)
    local progress = totalAssets > 0 and math.clamp(loadedAssets / totalAssets, 0, 1) or 1
    mover.Size = UDim2.new(progress, moverXOffset, moverYScale, moverYOffset)
end

local function finish()
    if finished then return end
    finished = true

    mover.Size = UDim2.new(1, moverXOffset, moverYScale, moverYOffset)
    releaseMenu()

    local tween = TweenService:Create(
        mainFrame,
        TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
        { Position = UDim2.new(0, 0, -1.1, 0) }
    )
    tween:Play()
    tween.Completed:Wait()

    gui.Enabled = false
    gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if gui.Enabled then gui.Enabled = false end
    end)
end

clicky.Activated:Connect(function()
    cancelled = true
end)

local function worker()
    activeWorkers += 1
    while not cancelled do
        nextIndex += 1
        local asset = assetsToPreload[nextIndex]
        if not asset then break end

        local isDone = false
        task.spawn(function()
            pcall(ContentProvider.PreloadAsync, ContentProvider, { asset })
            isDone = true
        end)

        local timeout = os.clock() + ASSET_TIMEOUT
        while not isDone and not cancelled and os.clock() < timeout do
            task.wait(0.05)
        end

        loadedAssets += 1
        updateProgress()
    end
    activeWorkers -= 1
end

task.spawn(function()
    if totalAssets == 0 then
        task.wait(0.5)
        finish()
        return
    end

    for _ = 1, math.min(WORKER_COUNT, totalAssets) do
        task.spawn(worker)
    end

    while (activeWorkers > 0 or nextIndex == 0) and not cancelled do
        task.wait(0.05)
    end

    finish()
end)
