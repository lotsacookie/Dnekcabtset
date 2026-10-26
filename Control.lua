local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")

local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
if not animator then
    animator = Instance.new("Animator")
    animator.Parent = humanoid
end

humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

local CooldownManager = require(ReplicatedStorage:WaitForChild("CooldownManager"))
local ChargeManager = require(ReplicatedStorage:WaitForChild("ChargeManager"))
ChargeManager.reset()
CooldownManager.reset()

local waterStateEvent = ReplicatedStorage:FindFirstChild("WaterState")
local stats = character:WaitForChild("Stats", 10)
local animations = character:WaitForChild("Animations", 10)

local FLY_SPEED = 80
local FLY_SMOOTH = 3
local FLY_VERTICAL_SMOOTH = 8
local FLY_TURN = 14
local FLY_MIN_HEALTH_PERCENT = 0.25
local FLY_MIN_CHARGE = 5
local FLY_CHARGE_DRAIN_RATE = 2

local SWIM_SPEED = 80
local SWIM_STRAFE = 0.6
local SWIM_ACCEL = 3.2
local SWIM_DRAG = 1.4
local SWIM_ENTRY_DRAG = 4
local SWIM_TURN = 5

local GLIDE_SPEED = 50
local GLIDE_STEER = 1.2
local GLIDE_DRAG = 0.3
local GLIDE_GRAVITY_SCALE = 0.35
local GLIDE_MAX_FALL = 45
local GLIDE_TURN = 3

local WATER_ENTER_MARGIN = 1
local BREACH_HEIGHT = 2.5
local WADE_OUT_MARGIN = 2
local WATER_REPORT_DELAY = 0.25
local MAX_PITCH = math.rad(80)

local ASCEND_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.Space }
local DESCEND_KEYS = { Enum.KeyCode.E }

local originalHipHeight = humanoid.HipHeight
local baseWalkSpeed = humanoid.WalkSpeed
local bodyHalf = math.max(character:GetExtentsSize().Y / 2, 2.5)
local GROUND_RAY = bodyHalf + 14

local mode = "Land"
local sprintOn = false
local currentAnim = "Idle"
local flightVel = Vector3.zero
local facing = Vector3.new(0, 0, -1)
local lastYaw = 0
local landLockUntil = 0
local swimBlockedUntil = 0
local swimBrakeUntil = 0
local airTrack = nil

local attachment, align, linear

local reportedWet, pendingWet, pendingSince = false, false, 0
local terrainSample = { time = 0, value = false }
local oceanPart = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.FilterDescendantsInstances = { character }

local controls = nil

task.spawn(function()
    local playerScripts = player:WaitForChild("PlayerScripts", 10)
    local playerModule = playerScripts and playerScripts:WaitForChild("PlayerModule", 10)
    if playerModule then
        local ok, result = pcall(function()
            return require(playerModule):GetControls()
        end)
        if ok then controls = result end
    end
end)

task.spawn(function()
    waterStateEvent = waterStateEvent or ReplicatedStorage:WaitForChild("WaterState", 10)
end)

local function getStat(name, fallback)
    local value = stats and stats:FindFirstChild(name)
    return value and value.Value or fallback
end

local function applyWalkSpeed()
    humanoid.WalkSpeed = sprintOn and getStat("SS", baseWalkSpeed) or getStat("WS", baseWalkSpeed)
end

local function loadTrack(name, priority)
    local animation = animations and animations:FindFirstChild(name)
    if not animation then return nil end
    local track = animator:LoadAnimation(animation)
    track.Priority = priority
    return track
end

local Idle = loadTrack("Idle", Enum.AnimationPriority.Idle)
local Walk = loadTrack("Walk", Enum.AnimationPriority.Movement)
local Sprint = loadTrack("Sprint", Enum.AnimationPriority.Movement)
local Swim = loadTrack("Swim", Enum.AnimationPriority.Movement)
local Fly = loadTrack("Fly", Enum.AnimationPriority.Movement)
    or loadTrack("Sprint", Enum.AnimationPriority.Movement)
    or loadTrack("Swim", Enum.AnimationPriority.Movement)

local function play(track, fade)
    if not track then return end
    if fade then track:Play(fade) else track:Play() end
end

local function stopTrack(track, fade)
    if track then track:Stop(fade or 0) end
end

local function stopAnimations()
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Priority.Value < Enum.AnimationPriority.Action.Value then
            track:Stop()
        end
    end
end

local function refreshGroundAnimation()
    stopAnimations()
    if currentAnim == "Walk" then
        play(sprintOn and Sprint or Walk)
    else
        play(Idle)
    end
end

local function playFootstep()
    local scripts = character:FindFirstChild("CharacterScripts")
    local sounds = scripts and scripts:FindFirstChild("Sounds")
    local template = sounds and sounds:FindFirstChild("FootStep")
    if not template then return end
    local sound = template:Clone()
    sound.Parent = rootPart
    sound:Play()
    sound.Ended:Once(function()
        sound:Destroy()
    end)
    Debris:AddItem(sound, 10)
end

local function clampMagnitude(vector, maxMagnitude)
    if vector.Magnitude > maxMagnitude then
        return vector.Unit * maxMagnitude
    end
    return vector
end

local function safeFlat(primary, fallback)
    local flat = Vector3.new(primary.X, 0, primary.Z)
    if flat.Magnitude > 0.05 then return flat.Unit end
    flat = Vector3.new(fallback.X, 0, fallback.Z)
    if flat.Magnitude > 0.05 then return flat.Unit end
    return Vector3.new(0, 0, -1)
end

local function facingCFrame(direction)
    if Vector3.new(direction.X, 0, direction.Z).Magnitude > 1e-3 then
        lastYaw = math.atan2(-direction.X, -direction.Z)
    end
    local pitch = math.asin(math.clamp(direction.Y, -1, 1))
    pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
    return CFrame.fromEulerAnglesYXZ(pitch, lastYaw, 0)
end

local function getOcean()
    if oceanPart and oceanPart.Parent then return oceanPart end
    local found = workspace:FindFirstChild("Ocean")
    if found and found:IsA("BasePart") then
        oceanPart = found
        rayParams.FilterDescendantsInstances = { character, found }
    else
        oceanPart = nil
    end
    return oceanPart
end

local function regionHasWater(terrain, region)
    local ok, materials = pcall(terrain.ReadVoxels, terrain, region, 4)
    if not ok then return false end
    for x = 1, #materials do
        for y = 1, #materials[x] do
            for z = 1, #materials[x][y] do
                if materials[x][y][z] == Enum.Material.Water then
                    return true
                end
            end
        end
    end
    return false
end

local function terrainHasWater(position, now)
    if now - terrainSample.time < 0.1 then return terrainSample.value end
    terrainSample.time = now
    local region = Region3.new(position - Vector3.new(2, 3, 2), position + Vector3.new(2, 3, 2)):ExpandToGrid(4)
    terrainSample.value = regionHasWater(workspace.Terrain, region)
    return terrainSample.value
end

local function sampleWater(position, now)
    local ocean = getOcean()
    if ocean then
        local level = ocean.Position.Y + ocean.Size.Y / 2
        return position.Y < level + WATER_ENTER_MARGIN, level
    end
    return terrainHasWater(position, now), nil
end

local function trackWater(wet, now)
    if wet ~= pendingWet then
        pendingWet = wet
        pendingSince = now
    end
    if pendingWet ~= reportedWet and now - pendingSince >= WATER_REPORT_DELAY then
        reportedWet = pendingWet
        if waterStateEvent then
            waterStateEvent:FireServer(reportedWet)
        end
    end
end

local function getMoveInput()
    if UserInputService:GetFocusedTextBox() then return 0, 0 end
    if controls then
        local move = controls:GetMoveVector()
        return -move.Z, move.X
    end
    local forward, right = 0, 0
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then right += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then right -= 1 end
    return forward, right
end

local function getVerticalInput()
    if UserInputService:GetFocusedTextBox() then return 0 end
    local up, down = false, false
    for _, key in ipairs(ASCEND_KEYS) do
        if UserInputService:IsKeyDown(key) then up = true break end
    end
    for _, key in ipairs(DESCEND_KEYS) do
        if UserInputService:IsKeyDown(key) then down = true break end
    end
    return (up and 1 or 0) - (down and 1 or 0)
end

local function buildRig()
    flightVel = rootPart.AssemblyLinearVelocity
    facing = rootPart.CFrame.LookVector
    lastYaw = math.atan2(-facing.X, -facing.Z)

    attachment = Instance.new("Attachment")
    attachment.Name = "FlyAttachment"
    attachment.Parent = rootPart

    align = Instance.new("AlignOrientation")
    align.Name = "FlyAlignOrientation"
    align.Mode = Enum.OrientationAlignmentMode.OneAttachment
    align.Attachment0 = attachment
    align.RigidityEnabled = false
    align.MaxTorque = 1e9
    align.Responsiveness = 25
    align.CFrame = rootPart.CFrame.Rotation
    align.Parent = rootPart

    linear = Instance.new("LinearVelocity")
    linear.Name = "FlyVelocity"
    linear.Attachment0 = attachment
    linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linear.RelativeTo = Enum.ActuatorRelativeTo.World
    linear.MaxForce = math.huge
    linear.VectorVelocity = flightVel
    linear.Parent = rootPart

    humanoid.PlatformStand = true
    humanoid.AutoRotate = false
end

local function destroyRig()
    if linear then linear:Destroy() linear = nil end
    if align then align:Destroy() align = nil end
    if attachment then attachment:Destroy() attachment = nil end
end

local function refreshAirTrack(fade)
    local track = (mode == "Fly") and Fly or (Swim or Fly)
    if track == airTrack then return end
    stopTrack(airTrack, fade)
    airTrack = track
    play(track, fade)
end

local function enterAir(newMode, fade)
    if mode == newMode or humanoid.Health <= 0 then return end
    fade = fade or 0
    local previous = mode
    mode = newMode
    if previous == "Land" then
        buildRig()
        ChargeManager.setFlying(true)
        stopTrack(Idle, fade)
        stopTrack(Walk, fade)
        stopTrack(Sprint, fade)
    end
    if newMode == "Swim" and previous == "Glide" then
        swimBrakeUntil = os.clock() + 0.5
    end
    refreshAirTrack(fade)
end

local function endFlight(keepMomentum, fade)
    if mode == "Land" then return end
    fade = fade or 0
    local previous = mode
    local velocity = flightVel
    local position = rootPart.Position
    mode = "Land"

    destroyRig()
    ChargeManager.setFlying(false)
    humanoid.PlatformStand = false
    humanoid.AutoRotate = true
    humanoid.HipHeight = originalHipHeight
    applyWalkSpeed()

    stopTrack(airTrack, fade)
    airTrack = nil

    if humanoid.Health > 0 then
        currentAnim = "Idle"
        stopAnimations()
        play(Idle, fade)
        landLockUntil = os.clock() + 0.5
        rootPart.CFrame = CFrame.new(position) * CFrame.Angles(0, lastYaw, 0)
        if keepMomentum then
            rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.5, 0, velocity.Z * 0.5)
        else
            rootPart.AssemblyLinearVelocity = Vector3.zero
        end
    end

    if previous ~= "Fly" then
        swimBlockedUntil = os.clock() + 0.35
    end
end

local function startManualFly(fade)
    if mode == "Fly" or humanoid.Health <= 0 then return end
    if humanoid.MaxHealth > 0 and humanoid.Health < humanoid.MaxHealth * FLY_MIN_HEALTH_PERCENT then return end
    if ChargeManager.getCharge() < FLY_MIN_CHARGE then return end
    enterAir("Fly", fade or 0)
end

local function stopManualFly()
    if mode ~= "Fly" then return end
    local wet = sampleWater(head.Position, os.clock())
    if wet then
        enterAir("Swim", 0.3)
    else
        endFlight(false, 0)
    end
end

local function updateLand(now, wet)
    if now >= landLockUntil then
        local velocity = rootPart.AssemblyLinearVelocity
        local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        local moving = humanoid.MoveDirection.Magnitude > 0.05
        if currentAnim ~= "Walk" and moving and speed > 1.5 then
            currentAnim = "Walk"
            refreshGroundAnimation()
        elseif currentAnim == "Walk" and (not moving or speed < 1) then
            currentAnim = "Idle"
            refreshGroundAnimation()
        end
    end
    if wet and now >= swimBlockedUntil then
        enterAir("Swim", 0.3)
    end
end

local function updateAir(dt, now, wet, level)
    local camera = workspace.CurrentCamera
    if not camera then return end

    local headPos = head.Position
    local position = rootPart.Position

    local groundDistance = nil
    local hit = workspace:Raycast(position, Vector3.new(0, -GROUND_RAY, 0), rayParams)
    if hit then groundDistance = hit.Distance end
    local grounded = groundDistance ~= nil and groundDistance < bodyHalf + 2

    if mode == "Fly" then
        local lowHealth = humanoid.MaxHealth > 0 and humanoid.Health < humanoid.MaxHealth * FLY_MIN_HEALTH_PERCENT
        if lowHealth or ChargeManager.getCharge() <= 0 then
            stopManualFly()
            if mode == "Land" then return end
        end
    end

    if mode == "Swim" then
        if level then
            if grounded and headPos.Y > level + WADE_OUT_MARGIN then
                endFlight(true, 0.2)
                return
            end
            if position.Y > level + BREACH_HEIGHT then
                enterAir("Glide", 0.25)
            end
        elseif not wet then
            if grounded then
                endFlight(true, 0.2)
                return
            end
            enterAir("Glide", 0.25)
        end
    elseif mode == "Glide" then
        if wet then
            enterAir("Swim", 0.25)
        elseif grounded and groundDistance < bodyHalf + 1 and flightVel.Y <= 0 then
            endFlight(true, 0.2)
            return
        end
    end

    if not align or not linear then return end

    local cf = camera.CFrame
    local look = cf.LookVector
    local rightFlat = safeFlat(cf.RightVector, Vector3.new(1, 0, 0))
    local flatLook = safeFlat(look, facing)
    local forwardIn, rightIn = getMoveInput()
    local vertical = getVerticalInput()

    local desired
    local turn

    if mode == "Fly" then
        local moveDir = clampMagnitude(look * forwardIn + rightFlat * rightIn, 1)
        local target = moveDir * FLY_SPEED + Vector3.new(0, vertical * FLY_SPEED, 0)
        local alpha = 1 - math.exp(-FLY_SMOOTH * dt)
        local alphaY = 1 - math.exp(-FLY_VERTICAL_SMOOTH * dt)
        flightVel = Vector3.new(
            flightVel.X + (target.X - flightVel.X) * alpha,
            flightVel.Y + (target.Y - flightVel.Y) * alphaY,
            flightVel.Z + (target.Z - flightVel.Z) * alpha
        )
        desired = look
        turn = FLY_TURN
        ChargeManager.drainCharge(dt * FLY_CHARGE_DRAIN_RATE)

    elseif mode == "Swim" then
        local moveDir = clampMagnitude(look * forwardIn + rightFlat * (rightIn * SWIM_STRAFE), 1)
        local target = moveDir * SWIM_SPEED + Vector3.new(0, vertical * SWIM_SPEED, 0)
        local hasInput = moveDir.Magnitude > 0.05 or vertical ~= 0
        local rate = SWIM_ACCEL
        if not hasInput then
            rate = (now < swimBrakeUntil) and SWIM_ENTRY_DRAG or SWIM_DRAG
        end
        flightVel = flightVel:Lerp(target, 1 - math.exp(-rate * dt))

        local flatFacing = safeFlat(facing, flatLook)
        if moveDir.Magnitude > 0.05 then
            desired = moveDir
        elseif vertical ~= 0 then
            desired = flatFacing * 0.6 + Vector3.new(0, vertical, 0)
        else
            desired = flatFacing
        end
        turn = SWIM_TURN

    else
        local horizontal = Vector3.new(flightVel.X, 0, flightVel.Z)
        local steer = flatLook * forwardIn + rightFlat * (rightIn * 0.5)
        if steer.Magnitude > 0.1 then
            local targetHorizontal = clampMagnitude(steer, 1) * GLIDE_SPEED
            horizontal = horizontal:Lerp(targetHorizontal, 1 - math.exp(-GLIDE_STEER * dt))
        else
            horizontal = horizontal * math.exp(-GLIDE_DRAG * dt)
        end
        local fall = flightVel.Y - workspace.Gravity * GLIDE_GRAVITY_SCALE * dt
        fall = math.max(fall, -GLIDE_MAX_FALL)
        flightVel = Vector3.new(horizontal.X, fall, horizontal.Z)

        local flatFacing = safeFlat(facing, flatLook)
        if flightVel.Magnitude > 8 then
            desired = flightVel.Unit
        else
            desired = flatFacing + Vector3.new(0, -0.3, 0)
        end
        if groundDistance then
            local flare = 1 - math.clamp((groundDistance - bodyHalf) / 8, 0, 1)
            desired = desired:Lerp(safeFlat(desired, flatFacing), flare)
        end
        turn = GLIDE_TURN
    end

    if groundDistance and (mode == "Swim" or (mode == "Fly" and wet)) and groundDistance < bodyHalf + 3 then
        local limit = math.min((bodyHalf + 1 - groundDistance) * 5, 14)
        if flightVel.Y < limit then
            flightVel = Vector3.new(flightVel.X, limit, flightVel.Z)
        end
    end

    if desired.Magnitude < 1e-3 then desired = facing end
    desired = desired.Unit
    local mixed = facing:Lerp(desired, 1 - math.exp(-turn * dt))
    facing = mixed.Magnitude > 1e-3 and mixed.Unit or desired

    align.CFrame = facingCFrame(facing)
    linear.VectorVelocity = flightVel

    if airTrack and not airTrack.IsPlaying then
        airTrack:Play(0.1)
    end
end

RunService.Heartbeat:Connect(function(dt)
    if humanoid.Health <= 0 or not rootPart.Parent then return end
    dt = math.min(dt, 0.1)
    local now = os.clock()
    local wet, level = sampleWater(head.Position, now)
    trackWater(wet, now)
    if mode == "Land" then
        updateLand(now, wet)
    else
        updateAir(dt, now, wet, level)
    end
end)

humanoid.Died:Connect(function()
    endFlight(false, 0)
end)

task.spawn(function()
    local pulseHit = ReplicatedStorage:FindFirstChild("PulseHit") or ReplicatedStorage:WaitForChild("PulseHit", 10)
    if pulseHit then
        pulseHit.OnClientEvent:Connect(function()
            if mode == "Fly" or mode == "Glide" then
                endFlight(false, 0)
            end
        end)
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.F then return end
    local canFly = character:FindFirstChild("canFly")
    if not (canFly and canFly.Value == true and sprintOn) then return end
    if mode == "Fly" then
        stopManualFly()
    else
        startManualFly(0)
    end
end)

local runFolder = script:FindFirstChild("Run")
if not runFolder then
    runFolder = Instance.new("Folder")
    runFolder.Name = "Run"
    runFolder.Parent = script
end

local runValue = runFolder:FindFirstChild("Running")
if not runValue then
    runValue = Instance.new("BoolValue")
    runValue.Name = "Running"
    runValue.Value = false
    runValue.Parent = runFolder
end

local function onRunChanged()
    if runValue.Value then
        if humanoid:GetAttribute("Slowed") then
            runValue.Value = false
            return
        end
        sprintOn = true
        applyWalkSpeed()
        if mode == "Land" and currentAnim == "Walk" then
            refreshGroundAnimation()
        end
        local canFly = character:FindFirstChild("canFly")
        if canFly and canFly.Value == true then
            startManualFly(0)
        end
    else
        sprintOn = false
        applyWalkSpeed()
        if mode == "Fly" then
            stopManualFly()
        end
        if mode == "Land" and currentAnim == "Walk" then
            refreshGroundAnimation()
        end
        humanoid.HipHeight = originalHipHeight
    end
end

runValue:GetPropertyChangedSignal("Value"):Connect(onRunChanged)

ContextActionService:BindAction("RunBind", function(_, inputState)
    if inputState ~= Enum.UserInputState.Begin then return end
    if humanoid:GetAttribute("Slowed") then return end
    runValue.Value = not runValue.Value
end, false, Enum.KeyCode.LeftShift)

humanoid:GetAttributeChangedSignal("Slowed"):Connect(function()
    if humanoid:GetAttribute("Slowed") and runValue.Value then
        runValue.Value = false
    end
end)

task.spawn(function()
    while character.Parent do
        task.wait(sprintOn and 1.1 or 1.5)
        if mode == "Land"
            and currentAnim == "Walk"
            and humanoid.HipHeight <= originalHipHeight
            and humanoid.FloorMaterial ~= Enum.Material.Air then
            playFootstep()
        end
    end
end)

play(Idle)
