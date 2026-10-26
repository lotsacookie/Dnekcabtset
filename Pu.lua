local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local pulseFireEvent = ReplicatedStorage:WaitForChild("PulseFire", 10)
if not pulseFireEvent then return end

local BURST_TIME = 0.4
local SUSTAIN_TIME = 0.5
local DISSIPATE_TIME = 0.6
local BURST_OVERSHOOT = 1.1
local DISSIPATE_GROWTH = 1.25
local MAX_ACTIVE = 12
local DEFAULT_COLOR = Color3.fromRGB(255, 120, 0)

local PART_SPIN = {
    Shock     = Vector3.new(0,   90,  0),
    Shockwave = Vector3.new(0,  -55,  0),
    Sphere    = Vector3.new(25,  70,  0),
    Sphere2   = Vector3.new(0,  -85, 30),
}
local SPHERE_NAMES = { Sphere = true, Sphere2 = true }
local SHOCK_NAME = "Shockwave"

local active = {}

local function removeActive(entry)
    local i = table.find(active, entry)
    if i then table.remove(active, i) end
end

local function destroyEntry(entry)
    removeActive(entry)
    if entry.clone and entry.clone.Parent then
        entry.clone:Destroy()
    end
end

local function getBaseDimension(clone)
    local ok, scale = pcall(clone.GetScale, clone)
    if not ok or not scale or scale <= 0 then scale = 1 end
    local _, size = clone:GetBoundingBox()
    local dim = math.max(size.X, size.Y, size.Z) / scale
    if dim <= 0 then dim = 1 end
    return dim
end

local function easeOutQuart(p) return 1 - (1 - p) ^ 4 end
local function easeInPow(p) return p ^ 2.2 end
local function rand(a, b) return a + math.random() * (b - a) end

local function runPulse(firingPlayer, color, maxSize)
    if typeof(color) ~= "Color3" then color = DEFAULT_COLOR end
    if type(maxSize) ~= "number" then maxSize = 300 end
    maxSize = math.clamp(maxSize, 5, 2000)

    if not firingPlayer or not firingPlayer.Parent then return end
    local character = firingPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local template = ReplicatedStorage:FindFirstChild("Pulse")
    if not template then return end

    local clone = template:Clone()
    local entry = { clone = clone }

    while #active >= MAX_ACTIVE do
        destroyEntry(active[1])
    end
    table.insert(active, entry)
    Debris:AddItem(clone, BURST_TIME + SUSTAIN_TIME + DISSIPATE_TIME + 5)

    local ok, err = pcall(function()
        local parts, emitters, baseTransparency = {}, {}, {}
        local spinParts = {}
        local sphereSet = {}
        local shockParts = {}

        for _, desc in ipairs(clone:GetDescendants()) do
            if desc:IsA("BasePart") then
                baseTransparency[desc] = desc.Name == "WD" and 1 or desc.Transparency
                desc.Color = color
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
                desc.Anchored = true
                desc.CastShadow = false
                if desc.Name == "WD" then desc.Transparency = 1 end
                table.insert(parts, desc)

                if PART_SPIN[desc.Name] then
                    table.insert(spinParts, { part = desc, spin = PART_SPIN[desc.Name] })
                end
                if SPHERE_NAMES[desc.Name] then
                    sphereSet[desc] = true
                end
            elseif desc:IsA("ParticleEmitter") then
                desc.Enabled = true
                desc.Color = ColorSequence.new(color)
                table.insert(emitters, desc)
            end
        end

        if not clone.PrimaryPart then
            local sw = clone:FindFirstChild("Shockwave", true)
            clone.PrimaryPart = (sw and sw:IsA("BasePart") and sw) or clone:FindFirstChildWhichIsA("BasePart", true)
        end
        if not clone.PrimaryPart then
            clone:Destroy()
            return
        end

        local light = Instance.new("PointLight")
        light.Color = color
        light.Brightness = 10
        light.Range = 80
        light.Shadows = false
        light.Parent = clone.PrimaryPart

        pcall(clone.ScaleTo, clone, 1)
        local baseDim = getBaseDimension(clone)

        for _, p in ipairs(parts) do
            if p.Name == SHOCK_NAME then
                table.insert(shockParts, { part = p, baseSize = p.Size })
            end
        end

        local lastPosition = hrp.Position
        local function currentPosition()
            if hrp and hrp.Parent then
                lastPosition = hrp.Position
            else
                local newChar = firingPlayer.Parent and firingPlayer.Character
                local newHrp = newChar and newChar:FindFirstChild("HumanoidRootPart")
                if newHrp then hrp = newHrp lastPosition = hrp.Position end
            end
            return lastPosition
        end

        local seed = math.random() * 1000
        local lastTick = os.clock()

        local function setPose(size, shake, spinMult, shockExtra)
            local now = os.clock()
            local dt = math.min(now - lastTick, 0.05)
            lastTick = now

            local scale = math.max(0.01, size / baseDim)
            local jitterScale = 1 + math.noise(now * 8, seed, 1) * 0.03 * shake
            pcall(clone.ScaleTo, clone, scale * jitterScale)

            for _, s in ipairs(shockParts) do
                s.part.Size = s.baseSize * (scale * jitterScale * shockExtra)
            end

            local tiltX = math.noise(now * 6, seed, 2) * 0.05 * shake
            local tiltZ = math.noise(now * 6, seed, 3) * 0.05 * shake
            local offset = Vector3.new(
                math.noise(now * 9, seed, 4) * shake * size * 0.005,
                math.noise(now * 9, seed, 5) * shake * size * 0.005,
                math.noise(now * 9, seed, 6) * shake * size * 0.005
            )
            clone:PivotTo(CFrame.new(currentPosition() + offset) * CFrame.Angles(tiltX, 0, tiltZ))

            for _, s in ipairs(spinParts) do
                local d = s.spin * (spinMult * dt)
                s.part.CFrame = s.part.CFrame * CFrame.Angles(math.rad(d.X), math.rad(d.Y), math.rad(d.Z))
            end
        end

        local function setTransparency(level, sphereLevel)
            for _, p in ipairs(parts) do
                local base = baseTransparency[p] or 0
                local l = sphereSet[p] and sphereLevel or level
                p.Transparency = base + (1 - base) * math.clamp(l, 0, 1)
            end
        end

        local function runPhase(duration, step)
            local t0 = os.clock()
            while clone.Parent do
                local e = os.clock() - t0
                if e >= duration then break end
                step(e / duration)
                RunService.Heartbeat:Wait()
            end
        end

        clone:PivotTo(CFrame.new(lastPosition))
        pcall(clone.ScaleTo, clone, 0.05)
        clone.Parent = workspace

        for _, e in ipairs(emitters) do
            e:Emit(math.max(1, math.floor(e:GetAttribute("EmitCount") or 25)))
        end

        local startSize = 2
        local peak = maxSize * BURST_OVERSHOOT

        runPhase(BURST_TIME, function(p)
            local size = startSize + (peak - startSize) * easeOutQuart(p)
            setPose(size, 1.2 * (1 - p * 0.4), 1.6 * (1 - p * 0.4), 1 + 0.15 * easeOutQuart(p))
            light.Brightness = 10 - 7 * p
            setTransparency(0, 0)
        end)
        if not clone.Parent then return end

        runPhase(SUSTAIN_TIME, function(p)
            local size = peak + (maxSize - peak) * p
            setPose(size, 1 - p * 0.5, 1.0 - p * 0.3, 1.15 + 0.10 * p)
            light.Brightness = 3 - p
            setTransparency(0, 0.35 * p)
        end)
        if not clone.Parent then return end

        for _, e in ipairs(emitters) do e.Enabled = false end

        runPhase(DISSIPATE_TIME, function(p)
            local grow = maxSize + (maxSize * DISSIPATE_GROWTH - maxSize) * easeOutQuart(p)
            setPose(grow, 0.5 * (1 - p), 0.7 * (1 - p), 1.25 + 0.30 * easeOutQuart(p))
            local level = easeInPow(p)
            local sphereLevel = 0.35 + p * 1.1
            setTransparency(level, sphereLevel)
            for _, e in ipairs(emitters) do
                e.Transparency = NumberSequence.new(level)
            end
            light.Brightness = 2 * (1 - p) ^ 2
        end)
    end)

    if not ok then
        warn("[Pulse] visual failed: " .. tostring(err))
    end

    destroyEntry(entry)
end

pulseFireEvent.OnClientEvent:Connect(function(firingPlayer, color, maxSize)
    task.spawn(runPulse, firingPlayer, color, maxSize)
end)
