local World = {}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local state = { IsRaining = false }
local initialized = false
local windowApi = {}
local savedWindowState = setmetatable({}, { __mode = "k" })

local function lerp(a, b, t) return a + (b - a) * t end

local function rand(a, b) return a + math.random() * (b - a) end

local function shuffle(list)
    local copy = table.clone(list)
    for i = #copy, 2, -1 do
        local j = math.random(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function maxAxis(part)
    return math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
end

local function easeLinear(p) return p end
local function easeInOut(p)
    if p < 0.5 then return 2 * p * p end
    return 1 - (-2 * p + 2) ^ 2 / 2
end
local function easeCollapse(p) return p ^ 2.4 end
local function easeTilt(p) return p ^ 1.6 end

local function initDayNight()
    local DAY_LENGTH_MIN = 12
    local START_MINUTES = 720
    local timeRatio = (24 * 60) / (math.max(DAY_LENGTH_MIN, 1) * 60)
    local t0 = os.clock()

    local DAY = {
        Brightness = 2, Ambient = Color3.new(0.5, 0.5, 0.5),
        OutdoorAmbient = Color3.new(0.25, 0.28, 0.21),
        ColorShift_Top = Color3.new(1, 0.75, 0.57),
        ColorShift_Bottom = Color3.new(0.15, 0.15, 0.2),
        FogColor = Color3.new(0.61, 0.67, 0.77), FogEnd = 5500,
        Density = 0.3, AtmColor = Color3.new(0.7, 0.75, 0.85), Haze = 2,
        Cloud = Color3.new(1, 1, 1),
    }
    local NIGHT = {
        Brightness = 1.2, Ambient = Color3.new(0.28, 0.32, 0.45),
        OutdoorAmbient = Color3.new(0.15, 0.18, 0.3),
        ColorShift_Top = Color3.new(0.12, 0.15, 0.28),
        ColorShift_Bottom = Color3.new(0.06, 0.07, 0.14),
        FogColor = Color3.new(0.18, 0.21, 0.3), FogEnd = 3000,
        Density = 0.4, AtmColor = Color3.new(0.1, 0.1, 0.18), Haze = 3,
        Cloud = Color3.new(0.12, 0.12, 0.16),
    }
    local RAIN = {
        FogEndMul = 0.4, DensityAdd = 0.15, HazeAdd = 1,
        FogColor = Color3.new(0.35, 0.37, 0.4),
        AtmColor = Color3.new(0.4, 0.42, 0.45),
        Cloud = Color3.new(0.15, 0.15, 0.18),
    }

    local function dayFactor(m)
        if m >= 420 and m <= 1020 then return 1
        elseif m >= 1140 or m <= 300 then return 0
        elseif m < 420 then return (m - 300) / 120
        else return 1 - (m - 1020) / 120 end
    end

    while true do
        local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
        local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")

        local minutes = (START_MINUTES + (os.clock() - t0) * timeRatio) % 1440
        Lighting:SetMinutesAfterMidnight(minutes)
        local t = dayFactor(minutes)

        Lighting.Brightness = lerp(NIGHT.Brightness, DAY.Brightness, t)
        Lighting.Ambient = NIGHT.Ambient:Lerp(DAY.Ambient, t)
        Lighting.OutdoorAmbient = NIGHT.OutdoorAmbient:Lerp(DAY.OutdoorAmbient, t)
        Lighting.ColorShift_Top = NIGHT.ColorShift_Top:Lerp(DAY.ColorShift_Top, t)
        Lighting.ColorShift_Bottom = NIGHT.ColorShift_Bottom:Lerp(DAY.ColorShift_Bottom, t)

        local fogEnd = lerp(NIGHT.FogEnd, DAY.FogEnd, t)
        local density = lerp(NIGHT.Density, DAY.Density, t)
        local haze = lerp(NIGHT.Haze, DAY.Haze, t)

        if state.IsRaining then
            Lighting.FogColor = RAIN.FogColor
            Lighting.FogEnd = fogEnd * RAIN.FogEndMul
            if atmosphere then
                atmosphere.Density = density + RAIN.DensityAdd
                atmosphere.Color = RAIN.AtmColor
                atmosphere.Haze = haze + RAIN.HazeAdd
            end
            if clouds then clouds.Color = RAIN.Cloud end
        else
            Lighting.FogColor = NIGHT.FogColor:Lerp(DAY.FogColor, t)
            Lighting.FogEnd = fogEnd
            if atmosphere then
                atmosphere.Density = density
                atmosphere.Color = NIGHT.AtmColor:Lerp(DAY.AtmColor, t)
                atmosphere.Haze = haze
            end
            if clouds then clouds.Color = NIGHT.Cloud:Lerp(DAY.Cloud, t) end
        end

        task.wait(1 / 15)
    end
end

local function initWindowLights()
    local LIT = Color3.fromRGB(197, 166, 89)
    local DARK = Color3.new(0, 0, 0)

    local windowsOn = false
    local epoch = 0
    local saved = savedWindowState
    local lights = {}
    local buildings = {}
    local pool = {}
    local winToken = setmetatable({}, { __mode = "k" })

    local function owningBuilding(inst)
        local p = inst.Parent
        while p do
            if p:IsA("Model") and p.Name:find("Building") then return p end
            p = p.Parent
        end
    end

    local function register(inst)
        if inst:IsA("UnionOperation") and inst.Name:find("Windows") then
            local b = owningBuilding(inst)
            if b then
                buildings[b] = buildings[b] or {}
                if not table.find(buildings[b], inst) then
                    table.insert(buildings[b], inst)
                end
            end
        end
    end

    for _, d in workspace:GetDescendants() do register(d) end
    workspace.DescendantAdded:Connect(register)
    workspace.DescendantRemoving:Connect(function(inst)
        saved[inst] = nil
        for b, list in buildings do
            local i = table.find(list, inst)
            if i then
                table.remove(list, i)
                if #list == 0 then buildings[b] = nil end
                break
            end
        end
    end)

    local function isDestroyed(building)
        local base = building:FindFirstChild("BuildingBase")
        return base and base:IsA("BasePart") and base.Material == Enum.Material.CorrodedMetal or false
    end

    local function windowsOf(building)
        local list = {}
        for _, d in building:GetDescendants() do
            if d:IsA("BasePart") and d.Name:lower():find("window", 1, true) then
                table.insert(list, d)
            end
        end
        return list
    end

    local function capture(window)
        if not saved[window] then
            saved[window] = { Material = window.Material, Color = window.Color }
        end
    end

    local function setWindow(window, lit)
        if not window.Parent then return end
        capture(window)
        window.Material = Enum.Material.Neon
        window.Color = lit and LIT or DARK
    end

    local function restoreWindow(window)
        if not window.Parent then return end
        local s = saved[window]
        if s then
            window.Material, window.Color = s.Material, s.Color
        else
            window.Material, window.Color = Enum.Material.Glass, DARK
        end
    end

    local function flickerWindow(window, duration, final)
        if not window.Parent then return end
        capture(window)
        winToken[window] = (winToken[window] or 0) + 1
        local mine = winToken[window]
        task.spawn(function()
            local stop = os.clock() + duration
            while winToken[window] == mine and window.Parent and os.clock() < stop do
                window.Material = Enum.Material.Neon
                window.Color = math.random() < 0.5 and LIT or DARK
                task.wait(0.03 + math.random() * 0.09)
            end
            if winToken[window] ~= mine or not window.Parent then return end
            if final == "lit" then
                setWindow(window, true)
            elseif final == "dark" then
                setWindow(window, false)
            else
                restoreWindow(window)
            end
        end)
    end

    local function ensureLight(base)
        if lights[base] or not base.Parent then return end
        local l = Instance.new("PointLight")
        l.Name = "BuildingGlowLight"
        l.Color = LIT
        l.Brightness = 0.8
        l.Range = 40
        l.Shadows = false
        l.Parent = base
        lights[base] = l
    end

    local function removeLight(base)
        local l = lights[base]
        if l then l:Destroy() lights[base] = nil end
    end

    local function lightBuilding(building, windows, myEpoch)
        local destroyed = isDestroyed(building)
        local base = building:FindFirstChild("BuildingBase")
        if not destroyed and base and base:IsA("BasePart") then ensureLight(base) end

        local function step(delay)
            task.wait(delay)
            return epoch == myEpoch
        end

        if not destroyed then
            for _, w in windows do
                if not step(math.random() * 0.3 + 0.8) then return end
                flickerWindow(w, 0.3 + math.random() * 0.6, "lit")
            end
        elseif #windows == 1 then
            if not step(math.random() * 0.3 + 8) then return end
            flickerWindow(windows[1], 0.3 + math.random() * 0.6, "dark")
        else
            for i, w in shuffle(windows) do
                if not step(math.random() * 0.3 + 0.8) then return end
                flickerWindow(w, 0.3 + math.random() * 0.6, i <= 2 and "lit" or "dark")
            end
        end
    end

    local function turnOn()
        if windowsOn then return end
        windowsOn = true
        epoch += 1
        local myEpoch = epoch
        for building, windows in buildings do
            task.spawn(lightBuilding, building, table.clone(windows), myEpoch)
        end
    end

    local function turnOff()
        if not windowsOn then return end
        windowsOn = false
        epoch += 1
        for base in lights do removeLight(base) end
        pool = {}
        for _, windows in buildings do
            for _, w in windows do
                winToken[w] = (winToken[w] or 0) + 1
                task.delay(math.random() * 0.3 + 0.2, restoreWindow, w)
            end
        end
    end

    local function syncLights()
        local newPool = {}
        for building, windows in buildings do
            local base = building:FindFirstChild("BuildingBase")
            if base and base:IsA("BasePart") then
                if isDestroyed(building) then
                    removeLight(base)
                else
                    ensureLight(base)
                    for _, w in windows do table.insert(newPool, { w, building }) end
                end
            end
        end
        pool = newPool
        for base in lights do
            if not base.Parent then removeLight(base) end
        end
    end

    windowApi.flickerBuilding = function(building, duration, ruined)
        local list = windowsOf(building)
        if #list == 0 then return end
        local darkCount = #list == 1 and 1 or math.random(1, math.min(#list, 3))
        for i, w in shuffle(list) do
            local final
            if ruined then
                if windowsOn then
                    final = i <= 2 and "lit" or "dark"
                else
                    final = i <= darkCount and "dark" or "restore"
                end
            else
                final = windowsOn and "lit" or "restore"
            end
            flickerWindow(w, duration * (0.7 + math.random() * 0.3), final)
        end
    end

    windowApi.resetBuilding = function(building)
        for _, w in windowsOf(building) do
            winToken[w] = (winToken[w] or 0) + 1
            if windowsOn then setWindow(w, true) else restoreWindow(w) end
        end
    end

    game:BindToClose(function()
        for _, windows in buildings do
            for _, w in windows do restoreWindow(w) end
        end
    end)

    local lastNight, counter = nil, 0
    while true do
        local m = Lighting:GetMinutesAfterMidnight()
        local night = m >= 1080 or m < 360
        if night ~= lastNight then
            lastNight = night
            if night then turnOn() else turnOff() end
        end
        if windowsOn then
            counter += 1
            if counter >= 3 then counter = 0 syncLights() end
            if #pool > 0 and math.random() < 0.6 then
                local pick = pool[math.random(1, #pool)]
                if pick[1].Parent and not isDestroyed(pick[2]) then
                    flickerWindow(pick[1], 0.15 + math.random() * 0.45, "lit")
                end
            end
        end
        task.wait(1)
    end
end

local function initRain()
    local rainySky = ReplicatedFirst:FindFirstChild("Rainy")
    local toggleRain = ReplicatedStorage:FindFirstChild("ToggleRain")

    while true do
        task.wait(math.random(120, 200))

        local originalSky = Lighting:FindFirstChildOfClass("Sky")
        local clonedSky
        state.IsRaining = true
        if toggleRain then toggleRain:FireAllClients(true) end
        if rainySky then
            clonedSky = rainySky:Clone()
            clonedSky.Parent = Lighting
            if originalSky then originalSky.Parent = nil end
        end

        task.wait(math.random(20, 120))

        state.IsRaining = false
        if toggleRain then toggleRain:FireAllClients(false) end
        if clonedSky then clonedSky:Destroy() end
        if originalSky then originalSky.Parent = Lighting end
    end
end

local function initBuilding()
    local RUMBLE_TIME = 0.8
    local COLLAPSE_TIME = 3.8
    local RESPAWN_DELAY = 60
    local DEBRIS_CHUNKS = 10

    local touchingParts = {}
    local hitboxOwners = {}
    local destroyed = {}
    local buildingRefs = {}
    local beamLoops, blastLoops = {}, {}

    local DAMAGE_KEYWORDS = { "hitbox", "beam", "blast", "firebomb" }

    local function isValidDamager(name)
        name = name:lower()
        for _, k in DAMAGE_KEYWORDS do
            if name:find(k, 1, true) then return true end
        end
        return false
    end

    local function isHitPart(part)
        local cur = part.Parent
        while cur and cur ~= game do
            local n = cur.Name:lower()
            if n == "hitparts" or n == "hitparts2" then return true end
            cur = cur.Parent
        end
        return false
    end

    local function getPlayerFromHitbox(hit)
        local cur = hit.Parent
        while cur do
            if cur:FindFirstChildOfClass("Humanoid") then
                return Players:GetPlayerFromCharacter(cur)
            end
            cur = cur.Parent
        end
        local attacker = hit:GetAttribute("Attacker")
        if not attacker then
            local dps = hit:FindFirstChild("DPS")
            attacker = dps and dps:GetAttribute("Attacker")
        end
        return attacker and Players:FindFirstChild(attacker) or nil
    end

    local function playHitSound(base)
        local template = script:FindFirstChild("HitSound")
        if template and base and base.Parent then
            local s = template:Clone()
            s.Parent = base
            s:Play()
            Debris:AddItem(s, 5)
        end
    end

    local function reward(player, cells)
        if not player then return end
        local ls = player:FindFirstChild("leaderstats")
        local gcells = ls and (ls:FindFirstChild("GCells") or ls:FindFirstChild("gcells"))
        if gcells and gcells:IsA("IntValue") then
            if _G.GCellGuardAllow then _G.GCellGuardAllow(gcells, 3) end
            gcells.Value += cells
        end
        local char = player.Character
        local xp = char and char:FindFirstChild("AddXP")
        if xp and xp:IsA("BindableEvent") then xp:Fire(math.random(1, 3)) end
    end

    local function liveRefs()
        return coroutine.wrap(function()
            for building, refs in buildingRefs do
                if not destroyed[building] and refs.base and refs.base.Parent then
                    coroutine.yield(building, refs)
                end
            end
        end)
    end

    local function startBlastCheck(blast)
        if blastLoops[blast] then return end
        blastLoops[blast] = true
        task.spawn(function()
            while blast.Parent and blast:GetAttribute("BlastActive") do
                local pos, r = blast.Position, maxAxis(blast)
                for _, refs in liveRefs() do
                    if (pos - refs.pos).Magnitude <= r + refs.radius then
                        playHitSound(refs.base)
                        refs.HP.Value = 0
                        refs.onDestroyed()
                    end
                end
                task.wait(0.15)
            end
            blastLoops[blast] = nil
        end)
    end

    local function trackBlast(part)
        if part:GetAttribute("BlastTrackingSetup") then return end
        part:SetAttribute("BlastTrackingSetup", true)
        if part:GetAttribute("BlastActive") then startBlastCheck(part) end
        local conn = part:GetAttributeChangedSignal("BlastActive"):Connect(function()
            if part:GetAttribute("BlastActive") then startBlastCheck(part) end
        end)
        part.AncestryChanged:Connect(function(_, p)
            if not p then conn:Disconnect() end
        end)
    end

    local function startBeamCheck(hitbox)
        if beamLoops[hitbox] then return end
        beamLoops[hitbox] = true
        task.spawn(function()
            while hitbox.Parent do
                local pos, r = hitbox.Position, maxAxis(hitbox)
                for building, refs in liveRefs() do
                    local set = touchingParts[building]
                    if set then
                        if (pos - refs.pos).Magnitude <= r + refs.radius then
                            if not set[hitbox] then
                                set[hitbox] = true
                                playHitSound(refs.base)
                                refs.startDamageLoop()
                            end
                        else
                            set[hitbox] = nil
                        end
                    end
                end
                task.wait(0.15)
            end
            beamLoops[hitbox] = nil
        end)
    end

    local function setupBuilding(building)
        if not building.Name:lower():find("building") or buildingRefs[building] then return end

        local leftovers = {}
        for _, c in building:GetChildren() do
            if c:IsA("BasePart") and c.Name:lower():find("leftover") then
                table.insert(leftovers, c)
            end
        end
        local base = building:FindFirstChild("BuildingBase")
        local stats = building:FindFirstChild("Stats")
        local HP = stats and stats:FindFirstChild("HP")
        if #leftovers == 0 or not base or not HP then return end

        for _, l in leftovers do
            l.CanCollide, l.Transparency, l.Anchored = false, 1, true
        end
        for _, name in { "Fire", "Smoke" } do
            local e = base:FindFirstChild(name)
            if e and e:IsA("ParticleEmitter") then
                e.Enabled = false
                e.Parent = leftovers[1]
            end
        end

        local parts, original, origCFs = {}, {}, {}
        local minY = math.huge
        for _, d in building:GetDescendants() do
            if d:IsA("BasePart") and not d.Name:lower():find("leftover") then
                table.insert(parts, d)
                table.insert(origCFs, d.CFrame)
                original[d] = { Material = d.Material, Color = d.Color }
                minY = math.min(minY, d.Position.Y - d.Size.Y / 2)
                if d.Name:lower():find("window", 1, true) and not savedWindowState[d] then
                    savedWindowState[d] = { Material = d.Material, Color = d.Color }
                end
            end
        end

        local basePos = base.Position
        local pivot = Vector3.new(basePos.X, minY, basePos.Z)
        local footW, footD = base.Size.X, base.Size.Z
        local shakeScale = math.clamp(maxAxis(base) / 25, 0.4, 2.5)
        local dustScale = math.clamp(math.max(footW, footD) / 8, 3, 14)

        local pose = { sink = 0, tx = 0, tz = 0 }
        local anim, jolt = nil, nil
        local rendering = false
        local seed = math.random() * 1000
        local cframes = table.create(#parts)

        local function apply(sx, sy, sz, rx, rz)
            local rot = CFrame.Angles(pose.tx + rx, 0, pose.tz + rz)
            local offset = CFrame.new(sx, sy - pose.sink, sz) * CFrame.new(pivot) * rot * CFrame.new(-pivot)
            for i = 1, #parts do cframes[i] = offset * origCFs[i] end
            pcall(workspace.BulkMoveTo, workspace, parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
        end

        local function render()
            if rendering then return end
            rendering = true
            task.spawn(function()
                while base.Parent do
                    local now = os.clock()
                    local amp = 0
                    if anim then
                        local p = math.clamp((now - anim.t0) / anim.dur, 0, 1)
                        local e = anim.ease(p)
                        local te = anim.tiltEase(p)
                        pose.sink = lerp(anim.from.sink, anim.to.sink, e)
                        pose.tx = lerp(anim.from.tx, anim.to.tx, te)
                        pose.tz = lerp(anim.from.tz, anim.to.tz, te)
                        amp = anim.amp * math.sin(math.pi * p ^ 0.6)
                        if p >= 1 then anim = nil end
                    end
                    if jolt then
                        local jp = (now - jolt.t0) / jolt.dur
                        if jp >= 1 then
                            jolt = nil
                        else
                            amp += jolt.amp * (1 - jp) ^ 2
                        end
                    end
                    local sx, sy, sz, rx, rz = 0, 0, 0, 0, 0
                    if amp > 0.001 then
                        local t = now * 24
                        local ts = amp * shakeScale
                        sx = math.noise(t, seed, 0.5) * 2 * ts
                        sy = math.noise(t, seed, 10.5) * ts
                        sz = math.noise(t, seed, 20.5) * 2 * ts
                        rx = math.noise(t, seed, 30.5) * 0.012 * amp
                        rz = math.noise(t, seed, 40.5) * 0.012 * amp
                    end
                    apply(sx, sy, sz, rx, rz)
                    if not anim and not jolt then break end
                    task.wait(1 / 30)
                end
                rendering = false
            end)
        end

        local function startAnim(sink, tx, tz, dur, amp, ease, tiltEase)
            seed = math.random() * 1000
            anim = {
                from = { sink = pose.sink, tx = pose.tx, tz = pose.tz },
                to = { sink = sink, tx = tx, tz = tz },
                t0 = os.clock(), dur = dur, amp = amp,
                ease = ease, tiltEase = tiltEase or ease,
            }
            render()
        end

        local function addJolt(amp, dur)
            if jolt and jolt.amp * (1 - (os.clock() - jolt.t0) / jolt.dur) > amp then return end
            seed = math.random() * 1000
            jolt = { amp = amp, dur = dur, t0 = os.clock() }
            render()
        end

        local function dust(count, sources)
            for _ = 1, sources do
                local att = Instance.new("Attachment")
                att.Parent = workspace.Terrain
                att.WorldPosition = pivot + Vector3.new(rand(-footW / 2, footW / 2) * 0.8, 0.5, rand(-footD / 2, footD / 2) * 0.8)
                local e = Instance.new("ParticleEmitter")
                e.Texture = "rbxasset://textures/particles/smoke_main.dds"
                e.Rate = 0
                e.Lifetime = NumberRange.new(2, 4)
                e.Speed = NumberRange.new(8, 26)
                e.SpreadAngle = Vector2.new(75, 75)
                e.EmissionDirection = Enum.NormalId.Top
                e.Rotation = NumberRange.new(0, 360)
                e.RotSpeed = NumberRange.new(-40, 40)
                e.Drag = 2
                e.Acceleration = Vector3.new(0, 1.5, 0)
                e.Color = ColorSequence.new(Color3.fromRGB(155, 145, 130), Color3.fromRGB(105, 105, 105))
                e.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, dustScale * 0.4),
                    NumberSequenceKeypoint.new(1, dustScale * 1.6),
                })
                e.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.5),
                    NumberSequenceKeypoint.new(0.6, 0.75),
                    NumberSequenceKeypoint.new(1, 1),
                })
                e.Parent = att
                e:Emit(count)
                Debris:AddItem(att, 7)
            end
        end

        local function throwChunks(count)
            for _ = 1, count do
                local chunk = Instance.new("Part")
                chunk.Name = "CollapseChunk"
                chunk.Size = Vector3.new(rand(1, 3.5), rand(1, 3.5), rand(1, 3.5))
                chunk.Material = Enum.Material.CorrodedMetal
                chunk.Color = base.Color
                chunk.CanTouch = false
                chunk.CanQuery = false
                chunk.CFrame = CFrame.new(pivot + Vector3.new(rand(-footW / 2, footW / 2), rand(2, 15), rand(-footD / 2, footD / 2)))
                    * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6))
                chunk.Parent = workspace
                chunk.AssemblyLinearVelocity = Vector3.new(rand(-1, 1), rand(0.4, 1.2), rand(-1, 1)).Unit * rand(25, 60)
                chunk.AssemblyAngularVelocity = Vector3.new(rand(-8, 8), rand(-8, 8), rand(-8, 8))
                Debris:AddItem(chunk, 5)
            end
        end

        local function setLeftoverEffects(on)
            for _, l in leftovers do
                for _, d in l:GetDescendants() do
                    if d:IsA("ParticleEmitter") then d.Enabled = on end
                end
            end
        end

        local halfTriggered = false
        local lastFlicker = 0
        HP.Value = 100
        touchingParts[building] = {}

        local function respawn()
            if not base.Parent then return end
            anim, jolt = nil, nil
            pose.sink, pose.tx, pose.tz = 0, 0, 0
            apply(0, 0, 0, 0, 0)
            HP.Value = 100
            halfTriggered = false
            for _, l in leftovers do l.Transparency, l.CanCollide = 1, false end
            setLeftoverEffects(false)
            local sound = base:FindFirstChildOfClass("Sound")
            if sound then sound:Stop() end
            for _, p in parts do
                local o = original[p]
                p.Material, p.Color = o.Material, o.Color
            end
            destroyed[building] = nil
            if windowApi.resetBuilding then windowApi.resetBuilding(building) end
        end

        local function onDestroyed()
            if destroyed[building] then return end
            destroyed[building] = true

            for _, p in parts do p.Material = Enum.Material.CorrodedMetal end
            local sound = base:FindFirstChildOfClass("Sound")
            if sound then sound:Play() end

            startAnim(pose.sink, pose.tx, pose.tz, RUMBLE_TIME, 2.6, easeLinear)
            dust(20, 2)
            if windowApi.flickerBuilding then
                windowApi.flickerBuilding(building, RUMBLE_TIME + COLLAPSE_TIME, true)
            end

            task.delay(RUMBLE_TIME, function()
                if not base.Parent then return end
                for _, l in leftovers do l.Transparency, l.CanCollide = 0, false end
                setLeftoverEffects(true)

                local ang = math.rad(rand(10, 22))
                local dir = math.random() * math.pi * 2
                startAnim(base.Size.Y, ang * math.cos(dir), ang * math.sin(dir), COLLAPSE_TIME, 3.4, easeCollapse, easeTilt)
                dust(35, 4)

                task.delay(COLLAPSE_TIME, function()
                    if not base.Parent then return end
                    dust(80, 5)
                    throwChunks(DEBRIS_CHUNKS)
                    addJolt(5, 0.9)
                    task.delay(RESPAWN_DELAY, respawn)
                end)
            end)
        end

        local function halfCollapse()
            halfTriggered = true
            for _, p in parts do p.Material = Enum.Material.CorrodedMetal end
            local ang = math.rad(rand(3, 8))
            local dir = math.random() * math.pi * 2
            startAnim(base.Size.Y * rand(0.25, 0.75), ang * math.cos(dir), ang * math.sin(dir), 1.6, 1.8, easeInOut)
            dust(25, 2)
        end

        local function applyDamage(amount, rewardsByPlayer)
            if HP.Value <= 0 or destroyed[building] then return false end
            HP.Value -= amount
            if HP.Value <= 50 and not halfTriggered then halfCollapse() end
            addJolt(1 + (100 - math.max(HP.Value, 0)) / 60, 0.45)
            dust(6, 1)
            if windowApi.flickerBuilding and os.clock() - lastFlicker > 0.35 then
                lastFlicker = os.clock()
                windowApi.flickerBuilding(building, 0.45, false)
            end
            playHitSound(base)
            for player, cells in rewardsByPlayer do reward(player, cells) end
            if HP.Value <= 0 then
                HP.Value = 0
                onDestroyed()
            end
            return true
        end

        local damaging = false
        local function startDamageLoop()
            if damaging then return end
            damaging = true
            task.spawn(function()
                while true do
                    local set = touchingParts[building]
                    if not set or HP.Value <= 0 or destroyed[building] then break end

                    local rewards, any = {}, false
                    for hit in set do
                        if not hit.Parent then
                            set[hit] = nil
                            hitboxOwners[hit] = nil
                        else
                            any = true
                            local owner = hitboxOwners[hit]
                            if owner then rewards[owner] = (rewards[owner] or 0) + 1 end
                        end
                    end
                    if not any then break end

                    applyDamage(20, rewards)
                    task.wait(0.5)
                end
                damaging = false
            end)
        end

        buildingRefs[building] = {
            base = base, HP = HP,
            pos = base.Position, radius = maxAxis(base),
            startDamageLoop = startDamageLoop,
            onDestroyed = onDestroyed,
            damageBuilding = function(attacker)
                applyDamage(20, attacker and { [attacker] = 3 } or {})
            end,
        }

        base.Touched:Connect(function(hit)
            if not (isValidDamager(hit.Name) or isHitPart(hit)) then return end
            local player = getPlayerFromHitbox(hit)
            if player then hitboxOwners[hit] = player end

            if hit.Name:lower():find("blast") then
                playHitSound(base)
                HP.Value = 0
                onDestroyed()
                return
            end
            local set = touchingParts[building]
            if set then
                set[hit] = true
                playHitSound(base)
                startDamageLoop()
            end
        end)

        base.TouchEnded:Connect(function(hit)
            if isHitPart(hit) then return end
            local set = touchingParts[building]
            if set then set[hit] = nil end
            hitboxOwners[hit] = nil
        end)

        building.AncestryChanged:Connect(function(_, parent)
            if not parent then
                touchingParts[building] = nil
                buildingRefs[building] = nil
                destroyed[building] = nil
            end
        end)
    end

    local Map = workspace:WaitForChild("Map")
    for _, b in Map:GetChildren() do
        if b:IsA("Model") then
            setupBuilding(b)
            task.wait()
        end
    end
    Map.DescendantAdded:Connect(function(d)
        if d:IsA("Model") and d.Name:lower():find("building") then
            task.wait(0.1)
            setupBuilding(d)
        end
    end)

    workspace.DescendantAdded:Connect(function(d)
        if not d:IsA("BasePart") or not isValidDamager(d.Name) then return end
        task.defer(function()
            if not d.Parent then return end
            local lname = d.Name:lower()
            local isBlast = lname:find("blast") ~= nil

            local player = getPlayerFromHitbox(d)
            if player then hitboxOwners[d] = player end

            local pos, r = d.Position, maxAxis(d)
            for building, refs in liveRefs() do
                if (pos - refs.pos).Magnitude <= r + refs.radius then
                    if isBlast then
                        playHitSound(refs.base)
                        refs.HP.Value = 0
                        refs.onDestroyed()
                    elseif touchingParts[building] then
                        touchingParts[building][d] = true
                        refs.startDamageLoop()
                    end
                end
            end

            if isBlast then
                trackBlast(d)
            elseif lname:find("beam") or lname:find("hitbox") then
                startBeamCheck(d)
            end

            d.AncestryChanged:Connect(function(_, parent)
                if parent then return end
                for building in buildingRefs do
                    local set = touchingParts[building]
                    if set then set[d] = nil end
                end
                hitboxOwners[d] = nil
            end)
        end)
    end)

    local function scanCharacter(char)
        for _, d in char:GetDescendants() do
            if d:IsA("BasePart") and d.Name:lower():find("blast") then trackBlast(d) end
        end
    end
    local function hookPlayer(player)
        player.CharacterAdded:Connect(function(char)
            task.wait(0.5)
            scanCharacter(char)
        end)
        if player.Character then scanCharacter(player.Character) end
    end
    Players.PlayerAdded:Connect(hookPlayer)
    for _, p in Players:GetPlayers() do hookPlayer(p) end

    _G.DamageBuildingsInRadius = function(position, radius, attacker)
        for _, refs in liveRefs() do
            if (position - refs.pos).Magnitude <= radius + refs.radius then
                refs.damageBuilding(attacker)
            end
        end
    end
end

local function initCollisions()
    local INVISIBLE_THRESHOLD = 0.9

    local function fixPart(part)
        if part:IsA("BasePart") and part.CanCollide and part.Transparency >= INVISIBLE_THRESHOLD then
            part.CanCollide = false
        end
    end

    local function fixTree(root)
        fixPart(root)
        for _, d in root:GetDescendants() do fixPart(d) end
    end

    fixTree(workspace)

    workspace.DescendantAdded:Connect(function(d)
        task.defer(fixPart, d)
    end)

    while true do
        task.wait(30)
        local n = 0
        for _, d in workspace:GetDescendants() do
            fixPart(d)
            n += 1
            if n % 2000 == 0 then task.wait() end
        end
    end
end

function World.Init()
    if initialized then return end
    initialized = true
    task.spawn(initDayNight)
    task.spawn(initWindowLights)
    task.spawn(initRain)
    task.spawn(initBuilding)
    task.spawn(initCollisions)
end

function World.IsRaining()
    return state.IsRaining
end

return World
