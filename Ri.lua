local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ocean = workspace:WaitForChild("Ocean", 30)
if not ocean or not ocean:IsA("BasePart") then return end

local LEVEL_OFFSET = 0
local UPDATE_RATE = 30
local WAVE_SPEED = 0.7
local WAVE_HEIGHT = 0.45
local NORMAL_STRENGTH = 5
local DARKEN = 0.85

local RIPPLE_HEIGHT = 0.4
local RIPPLE_SPEED = 9
local RIPPLE_WIDTH = 4
local RIPPLE_LIFE = 1.8
local RIPPLE_BRIGHTNESS = 1
local MAX_RIPPLES = 32

local MAX_TRIANGLES = 14000
local RING_SEGMENTS = 72
local DETAIL_RADIUS = 320
local DETAIL_POWER = 1.3
local DETAIL_RINGS = 40
local OUTER_RADIUS = 1000
local OUTER_RINGS = 6
local FAR_DROP = 3

local function countTriangles(detailRings)
    local rings = detailRings + OUTER_RINGS
    return ((rings - 1) * RING_SEGMENTS * 2 + RING_SEGMENTS) * 2
end

local detailRings = DETAIL_RINGS
while detailRings > 8 and countTriangles(detailRings) > MAX_TRIANGLES do
    detailRings -= 1
end

local WAVE_RADIUS = DETAIL_RADIUS

local WAVE_DEFS = {
    { angle = 15,   length = 160, amp = 1.6,  fade = 1.00 },
    { angle = -40,  length = 95,  amp = 1.1,  fade = 0.85 },
    { angle = 70,   length = 60,  amp = 0.65, fade = 0.65 },
    { angle = -110, length = 42,  amp = 0.35, fade = 0.5 },
}

local waves = {}
for i, def in ipairs(WAVE_DEFS) do
    local a = math.rad(def.angle)
    local k = 2 * math.pi / def.length
    local fadeEnd = WAVE_RADIUS * def.fade
    waves[i] = {
        dx = math.cos(a),
        dz = math.sin(a),
        k = k,
        w = math.sqrt(workspace.Gravity * k) * WAVE_SPEED,
        amp = def.amp * WAVE_HEIGHT,
        phase = i * 1.7,
        fadeStart = fadeEnd * 0.4,
        fadeEnd = fadeEnd,
    }
end
local waveCount = #waves

local function sample(x, z, t, dist)
    local h, gx, gz = 0, 0, 0
    for i = 1, waveCount do
        local wv = waves[i]
        local f = 1 - math.clamp((dist - wv.fadeStart) / (wv.fadeEnd - wv.fadeStart), 0, 1)
        if f > 0 then
            f = f * f * (3 - 2 * f)
            local a = wv.amp * f
            local phase = wv.k * (wv.dx * x + wv.dz * z) - wv.w * t + wv.phase
            h += a * math.sin(phase)
            local d = a * wv.k * math.cos(phase)
            gx += d * wv.dx
            gz += d * wv.dz
        end
    end
    return h, gx, gz
end

local function getLevel()
    return ocean.Position.Y + ocean.Size.Y / 2 + LEVEL_OFFSET
end

local function baseHeight(r)
    if r <= WAVE_RADIUS then return 0 end
    local u = math.clamp((r - WAVE_RADIUS) / (OUTER_RADIUS - WAVE_RADIUS), 0, 1)
    u = u * u * (3 - 2 * u)
    return -FAR_DROP * u
end

local function buildSurface()
    local radii = {}
    for j = 1, detailRings do
        radii[#radii + 1] = DETAIL_RADIUS * (j / detailRings) ^ DETAIL_POWER
    end
    local ratio = OUTER_RADIUS / DETAIL_RADIUS
    for k = 1, OUTER_RINGS do
        radii[#radii + 1] = DETAIL_RADIUS * ratio ^ (k / OUTER_RINGS)
    end

    local mesh = AssetService:CreateEditableMesh()
    local uv = mesh:AddUV(Vector2.new(0, 0))

    local colorsOk = true
    local baseShade = Color3.new(DARKEN, DARKEN, DARKEN)
    local vertexIds, normalIds, colorIds, lx, lz, rad = {}, {}, {}, {}, {}, {}

    local function addVertex(x, z, r)
        local n = #vertexIds + 1
        vertexIds[n] = mesh:AddVertex(Vector3.new(x, baseHeight(r), z))
        normalIds[n] = mesh:AddNormal(Vector3.yAxis)
        if colorsOk then
            local ok, id = pcall(mesh.AddColor, mesh, baseShade, 1)
            if ok then
                colorIds[n] = id
            else
                colorsOk = false
            end
        end
        lx[n], lz[n], rad[n] = x, z, r
    end

    addVertex(0, 0, 0)
    for _, r in ipairs(radii) do
        for i = 0, RING_SEGMENTS - 1 do
            local a = i / RING_SEGMENTS * 2 * math.pi
            addVertex(r * math.cos(a), r * math.sin(a), r)
        end
    end

    local function index(ring, i)
        return 1 + (ring - 1) * RING_SEGMENTS + (i % RING_SEGMENTS) + 1
    end

    local function addFace(a, b, c)
        local f = mesh:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
        mesh:SetFaceNormals(f, { normalIds[a], normalIds[b], normalIds[c] })
        mesh:SetFaceUVs(f, { uv, uv, uv })
        if colorsOk then
            local ok = pcall(mesh.SetFaceColors, mesh, f, { colorIds[a], colorIds[b], colorIds[c] })
            if not ok then colorsOk = false end
        end
    end

    local function addTriangle(a, b, c)
        addFace(a, b, c)
        addFace(a, c, b)
    end

    for i = 0, RING_SEGMENTS - 1 do
        addTriangle(1, index(1, i + 1), index(1, i))
    end
    for ring = 1, #radii - 1 do
        for i = 0, RING_SEGMENTS - 1 do
            addTriangle(index(ring, i), index(ring + 1, i + 1), index(ring + 1, i))
            addTriangle(index(ring, i), index(ring, i + 1), index(ring + 1, i + 1))
        end
    end

    local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    part.Name = "OceanSurface"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    if colorsOk then
        part.Color = ocean.Color
    else
        part.Color = ocean.Color:Lerp(Color3.new(0, 0, 0), 1 - DARKEN)
    end
    part.Material = ocean.Material
    part.Reflectance = ocean.Reflectance
    part.Transparency = ocean.Transparency
    part.CFrame = CFrame.new(ocean.Position.X, getLevel(), ocean.Position.Z)
    part.Parent = workspace

    local activeCount = 1
    for n = 1, #rad do
        if rad[n] <= WAVE_RADIUS then activeCount = n end
    end

    return {
        mesh = mesh,
        part = part,
        vertexIds = vertexIds,
        normalIds = normalIds,
        colorIds = colorIds,
        colorsOk = colorsOk,
        lx = lx,
        lz = lz,
        rad = rad,
        activeCount = activeCount,
    }
end

local function buildFarWater()
    local far = ocean:Clone()
    far.Name = "OceanFar"
    far.Anchored = true
    far.CanCollide = false
    far.CanQuery = false
    far.CanTouch = false
    far.CastShadow = false
    far.Color = ocean.Color:Lerp(Color3.new(0, 0, 0), 1 - DARKEN)
    far.CFrame = ocean.CFrame + Vector3.new(0, LEVEL_OFFSET - FAR_DROP - 0.15, 0)
    far.Parent = workspace
    return far
end

local function hideOriginal()
    ocean.LocalTransparencyModifier = 1
    for _, d in ipairs(ocean:GetDescendants()) do
        if d:IsA("BasePart") then
            d.LocalTransparencyModifier = 1
        end
    end
end

local function runFallback()
    local base = ocean.CFrame
    RunService.RenderStepped:Connect(function()
        local t = workspace:GetServerTimeNow()
        local bob = math.sin(t * 0.9) * 0.2 + math.sin(t * 0.37 + 1.3) * 0.15
        ocean.CFrame = base + Vector3.new(0, bob, 0)
    end)
end

local ok, surface = pcall(buildSurface)
if not ok then
    warn("[OceanWaves] EditableMesh unavailable, using fallback bob: " .. tostring(surface))
    runFallback()
    return
end

buildFarWater()
hideOriginal()

local mesh = surface.mesh
local part = surface.part
local vertexIds = surface.vertexIds
local normalIds = surface.normalIds
local colorIds = surface.colorIds
local colorsOk = surface.colorsOk
local lx, lz, rad = surface.lx, surface.lz, surface.rad
local activeCount = surface.activeCount

local lastShade = table.create(activeCount, DARKEN)
local ripples = {}
local partState = setmetatable({}, { __mode = "k" })

local function spawnRipple(x, z, amp, r0, clock)
    if #ripples >= MAX_RIPPLES then
        table.remove(ripples, 1)
    end
    ripples[#ripples + 1] = {
        x = x,
        z = z,
        amp0 = amp,
        r0 = r0,
        t0 = clock,
        radius = r0,
        width = RIPPLE_WIDTH,
        amp = amp,
        kk = 1.1 / RIPPLE_WIDTH,
        strength = 1,
        lo2 = 0,
        hi2 = 0,
    }
end

local function collectSources(cx, cz, level, t, clock, stepDt)
    local limit = WAVE_RADIUS * WAVE_RADIUS * 0.7
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char then
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.95 then
                    local pos = p.Position
                    local dx, dz = pos.X - cx, pos.Z - cz
                    local d2 = dx * dx + dz * dz
                    local st = partState[p]
                    if not st then
                        st = { pos = pos, t = 0 }
                        partState[p] = st
                    end
                    local speed = math.min((pos - st.pos).Magnitude / math.max(stepDt, 1e-3), 40)
                    st.pos = pos
                    if d2 < limit then
                        local half = math.max(p.Size.X, p.Size.Y, p.Size.Z) * 0.5
                        local h = sample(pos.X, pos.Z, t, math.sqrt(d2))
                        local surfaceY = level + h
                        if math.abs(pos.Y - surfaceY) < half * 0.8 + 0.3 then
                            local interval = math.clamp(0.7 - speed * 0.03, 0.18, 0.7)
                            if clock - st.t >= interval then
                                st.t = clock
                                local amp = RIPPLE_HEIGHT
                                    * math.clamp(0.4 + speed / 18, 0.4, 1.3)
                                    * math.clamp(half / 2, 0.5, 1.4)
                                spawnRipple(pos.X, pos.Z, amp, half * 0.8, clock)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function updateRipples(clock)
    for i = #ripples, 1, -1 do
        local rp = ripples[i]
        local age = clock - rp.t0
        if age >= RIPPLE_LIFE then
            table.remove(ripples, i)
        else
            local fade = 1 - age / RIPPLE_LIFE
            fade *= fade
            local radius = rp.r0 + RIPPLE_SPEED * age
            local width = RIPPLE_WIDTH * (1 + age * 0.6)
            rp.radius = radius
            rp.width = width
            rp.kk = 1.1 / width
            rp.amp = rp.amp0 * fade / (1 + radius * 0.05)
            rp.strength = fade * math.min(1, rp.amp0 / RIPPLE_HEIGHT)
            local lo = math.max(0, radius - width * 3)
            local hi = radius + width * 3
            rp.lo2 = lo * lo
            rp.hi2 = hi * hi
        end
    end
end

local step = 1 / UPDATE_RATE
local accumulator = 0
local lastUpdate = os.clock()

RunService.RenderStepped:Connect(function(dt)
    accumulator += dt
    if accumulator < step then return end
    accumulator %= step

    local camera = workspace.CurrentCamera
    if not camera then return end
    local camPos = camera.CFrame.Position
    local cx, cz = camPos.X, camPos.Z
    local t = workspace:GetServerTimeNow()
    local clock = os.clock()
    local stepDt = clock - lastUpdate
    lastUpdate = clock
    local level = getLevel()

    part.CFrame = CFrame.new(cx, level, cz)

    collectSources(cx, cz, level, t, clock, stepDt)
    updateRipples(clock)
    local rc = #ripples

    for n = 1, activeCount do
        local x, z = lx[n], lz[n]
        local wx, wz = cx + x, cz + z
        local h, gx, gz = sample(wx, wz, t, rad[n])
        local bright = 0

        for i = 1, rc do
            local rp = ripples[i]
            local dx, dz = wx - rp.x, wz - rp.z
            local d2 = dx * dx + dz * dz
            if d2 >= rp.lo2 and d2 <= rp.hi2 then
                local d = math.sqrt(d2)
                local w = rp.width
                local u = d - rp.radius
                local q = u / w
                local env = math.exp(-q * q)
                local ph = u * rp.kk
                local c = math.cos(ph)
                local hh = rp.amp * env
                h += hh * c
                local dh = hh * (-2 * q / w * c - rp.kk * math.sin(ph))
                if d > 1e-3 then
                    gx += dh * dx / d
                    gz += dh * dz / d
                end
                local slope = math.min(1, math.abs(dh) * w / math.max(rp.amp, 1e-4) * 1.16)
                bright += rp.strength * (0.5 * env + 0.5 * slope)
            end
        end

        mesh:SetPosition(vertexIds[n], Vector3.new(x, h, z))
        local sx, sz = gx * NORMAL_STRENGTH, gz * NORMAL_STRENGTH
        local inv = 1 / math.sqrt(sx * sx + 1 + sz * sz)
        mesh:SetNormal(normalIds[n], Vector3.new(-sx * inv, inv, -sz * inv))

        if colorsOk then
            local shade = DARKEN + (1 - DARKEN) * math.min(bright * RIPPLE_BRIGHTNESS, 1)
            if math.abs(shade - lastShade[n]) > 0.002 then
                lastShade[n] = shade
                mesh:SetColor(colorIds[n], Color3.new(shade, shade, shade))
            end
        end
    end
end)
