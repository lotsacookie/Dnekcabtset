local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local ocean = workspace:WaitForChild("Ocean", 30)
if not ocean or not ocean:IsA("BasePart") then return end

local LEVEL_OFFSET = 0
local UPDATE_RATE = 30
local WAVE_SPEED = 0.5

local RING_SEGMENTS = 96
local DETAIL_RADIUS = 560
local DETAIL_SPACING = 14
local OUTER_RADIUS = 3600
local OUTER_RINGS = 10
local WAVE_RADIUS = 1400

local WAVE_DEFS = {
    { angle = 15,   length = 260, amp = 0.55, fade = 1400 },
    { angle = -40,  length = 150, amp = 0.38, fade = 900 },
    { angle = 70,   length = 95,  amp = 0.22, fade = 600 },
    { angle = -110, length = 62,  amp = 0.12, fade = 380 },
}

local waves = {}
for i, def in ipairs(WAVE_DEFS) do
    local a = math.rad(def.angle)
    local k = 2 * math.pi / def.length
    waves[i] = {
        dx = math.cos(a),
        dz = math.sin(a),
        k = k,
        w = math.sqrt(workspace.Gravity * k) * WAVE_SPEED,
        amp = def.amp,
        phase = i * 1.7,
        fadeStart = def.fade * 0.5,
        fadeEnd = def.fade,
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

local function buildSurface()
    local radii = {}
    local detailRings = math.floor(DETAIL_RADIUS / DETAIL_SPACING)
    for j = 1, detailRings do
        radii[#radii + 1] = j * DETAIL_SPACING
    end
    local ratio = OUTER_RADIUS / (detailRings * DETAIL_SPACING)
    for k = 1, OUTER_RINGS do
        radii[#radii + 1] = detailRings * DETAIL_SPACING * ratio ^ (k / OUTER_RINGS)
    end

    local mesh = AssetService:CreateEditableMesh()
    local uv = mesh:AddUV(Vector2.new(0, 0))

    local vertexIds, normalIds, lx, lz, rad = {}, {}, {}, {}, {}
    local function addVertex(x, z, r)
        local n = #vertexIds + 1
        vertexIds[n] = mesh:AddVertex(Vector3.new(x, 0, z))
        normalIds[n] = mesh:AddNormal(Vector3.yAxis)
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
    part.Color = ocean.Color
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
        lx = lx,
        lz = lz,
        rad = rad,
        activeCount = activeCount,
    }
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

hideOriginal()

local mesh = surface.mesh
local part = surface.part
local vertexIds = surface.vertexIds
local normalIds = surface.normalIds
local lx, lz, rad = surface.lx, surface.lz, surface.rad
local activeCount = surface.activeCount

local step = 1 / UPDATE_RATE
local accumulator = 0

RunService.RenderStepped:Connect(function(dt)
    accumulator += dt
    if accumulator < step then return end
    accumulator %= step

    local camera = workspace.CurrentCamera
    if not camera then return end
    local camPos = camera.CFrame.Position
    local cx, cz = camPos.X, camPos.Z
    local t = workspace:GetServerTimeNow()

    part.CFrame = CFrame.new(cx, getLevel(), cz)

    for n = 1, activeCount do
        local x, z = lx[n], lz[n]
        local h, gx, gz = sample(cx + x, cz + z, t, rad[n])
        mesh:SetPosition(vertexIds[n], Vector3.new(x, h, z))
        local inv = 1 / math.sqrt(gx * gx + 1 + gz * gz)
        mesh:SetNormal(normalIds[n], Vector3.new(-gx * inv, inv, -gz * inv))
    end
end)
