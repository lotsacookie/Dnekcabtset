local Combat = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local function safeRequire(name)
    local module = ReplicatedStorage:FindFirstChild(name)
    if not module then return nil end
    local ok, result = pcall(require, module)
    if not ok then
        warn("[Combat] Failed to require " .. name .. ": " .. tostring(result))
        return nil
    end
    return result
end

safeRequire("LevelGuard")
safeRequire("ChargeManager")

local function getOrCreateRemote(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end
    return remote
end

local function getGCells(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return nil end
    local gcells = leaderstats:FindFirstChild("GCells") or leaderstats:FindFirstChild("gcells")
    if gcells and gcells:IsA("IntValue") then return gcells end
    return nil
end

local function giveGCells(player, amount, isKillReward)
    local gcells = getGCells(player)
    if not gcells then return end
    if isKillReward and _G.SetKillRewardFlag then _G.SetKillRewardFlag(player) end
    if _G.GCellGuardAllow then _G.GCellGuardAllow(gcells, amount) end
    gcells.Value += amount
    if isKillReward and _G.ClearKillRewardFlag then _G.ClearKillRewardFlag(player) end
end

local function giveXP(player, minXP, maxXP)
    local character = player.Character
    local addXP = character and character:FindFirstChild("AddXP")
    if addXP and addXP:IsA("BindableEvent") then
        if _G.SetKillRewardFlag then _G.SetKillRewardFlag(player) end
        addXP:Fire(math.random(minXP, maxXP))
        if _G.ClearKillRewardFlag then _G.ClearKillRewardFlag(player) end
    end
end

local function setCreator(humanoid, player)
    local creator = humanoid:FindFirstChild("creator")
    if not creator then
        creator = Instance.new("ObjectValue")
        creator.Name = "creator"
        creator.Parent = humanoid
    end
    creator.Value = player
end

local function resolveAttackers(damages)
    local topKiller, topDamage = nil, 0
    local others = {}
    for attacker, damage in pairs(damages) do
        if damage > topDamage then
            if topKiller then table.insert(others, topKiller) end
            topKiller, topDamage = attacker, damage
        else
            table.insert(others, attacker)
        end
    end
    return topKiller, others
end

local initialized = false

local function initCombat()
    local HEALTH_THRESHOLD = 0.50
    local SLOW_PERCENT = 0.65
    local KILL_REWARD = 300
    local ASSIST_REWARD = 100
    local HEAL_PERCENT_ON_KILL = 0.80
    local KILL_XP_MIN, KILL_XP_MAX = 200, 300
    local ASSIST_XP_MIN, ASSIST_XP_MAX = 50, 100

    local damageLog = {}
    _G.CombatDamageLog = damageLog
    local lastHealth = {}
    local applyingBossBonus = {}
    local restoringHealth = {}
    local setupDone = {}

    local KILL_MESSAGES = {
        "{killer} slimed {victim}",
        "{killer} obliterated {victim}",
        "{killer} sent {victim} to Destoroyah",
        "{killer} cooked {victim}",
        "{killer} absolutely demolished {victim}",
        "{killer} made {victim} rage quit",
        "{killer} blasted {victim} into oblivion",
        "{killer} said goodnight to {victim}",
        "{killer} gave {victim} Ghidorah treatment",
        "{killer} turned {victim} into dust",
        "{killer} showed {victim} no mercy",
        "{killer} made {victim} reconsider their life choices",
        "{victim} got folded by {killer}",
        "{victim} was no match for {killer}",
        "{killer} ended {victim}'s career",
        "{killer} uhh gave laxatives to {victim} and self imploded",
        "{victim} somehow died to {killer}",
        "{victim} did something evil to {killer}",
        "{killer} transmitted a message to {victim} and told them the next kaiju added is going to be Gorosaurus",
        "{victim} used the Mechagodzilla method on {killer} and failed miserabely",
        "{killer} transformed into Lotszilla and took care of  {victim}. ",
        "{killer} found {victim}",
        "{killer} turned {victim} into a burger",
    }

    local function sendKillMessage(killerName, victimName)
        local event = ReplicatedStorage:FindFirstChild("KillMessage")
        if not event then return end
        local template = KILL_MESSAGES[math.random(1, #KILL_MESSAGES)]
        local message = (string.gsub(template, "{(%w+)}", { killer = killerName, victim = victimName }))
        event:FireAllClients(message)
    end

    local function healPlayer(player, percent)
        local character = player.Character
        if not character or character:GetAttribute("BossMode") then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        humanoid.Health = math.min(humanoid.Health + humanoid.MaxHealth * percent, humanoid.MaxHealth)
    end

    local function clearCharacter(character)
        damageLog[character] = nil
        lastHealth[character] = nil
        applyingBossBonus[character] = nil
        restoringHealth[character] = nil
        setupDone[character] = nil
    end

    local function setupCharacter(character)
        if setupDone[character] then return end
        setupDone[character] = true

        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            setupDone[character] = nil
            return
        end

        local isLowHealth = false
        local isApplyingSlow = false
        local baseWalkSpeed = nil
        lastHealth[character] = humanoid.Health
        damageLog[character] = {}

        humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if isApplyingSlow or not isLowHealth or not baseWalkSpeed then return end
            local maxAllowed = baseWalkSpeed * (1 - SLOW_PERCENT)
            if humanoid.WalkSpeed > maxAllowed then
                isApplyingSlow = true
                humanoid.WalkSpeed = maxAllowed
                isApplyingSlow = false
            end
        end)

        humanoid.HealthChanged:Connect(function(newHealth)
            if applyingBossBonus[character] or restoringHealth[character] then
                lastHealth[character] = newHealth
                return
            end
            if newHealth <= 0 then return end

            local healthPercent = newHealth / humanoid.MaxHealth
            if healthPercent <= HEALTH_THRESHOLD then
                if not isLowHealth then
                    isLowHealth = true
                    baseWalkSpeed = humanoid.WalkSpeed
                    humanoid:SetAttribute("Slowed", true)
                    isApplyingSlow = true
                    humanoid.WalkSpeed = baseWalkSpeed * (1 - SLOW_PERCENT)
                    isApplyingSlow = false
                end
            elseif isLowHealth then
                isLowHealth = false
                humanoid:SetAttribute("Slowed", false)
                isApplyingSlow = true
                humanoid.WalkSpeed = baseWalkSpeed or humanoid.WalkSpeed / (1 - SLOW_PERCENT)
                isApplyingSlow = false
                baseWalkSpeed = nil
            end

            local oldHealth = lastHealth[character] or humanoid.MaxHealth
            if newHealth < oldHealth then
                local damageDealt = oldHealth - newHealth
                local creator = humanoid:FindFirstChild("creator")
                local attacker = creator and creator.Value
                if attacker and attacker:IsA("Player") then
                    local bossSystem = _G.BossSystem
                    if bossSystem and bossSystem.active then
                        local attackerChar = attacker.Character
                        local attackerIsBoss = attackerChar and attackerChar:GetAttribute("BossMode")
                        local victimIsBoss = character:GetAttribute("BossMode")
                        if not victimIsBoss and not attackerIsBoss then
                            restoringHealth[character] = true
                            humanoid.Health = oldHealth
                            restoringHealth[character] = nil
                            lastHealth[character] = oldHealth
                            return
                        end
                    end

                    local log = damageLog[character]
                    if not log then
                        log = {}
                        damageLog[character] = log
                    end
                    log[attacker] = (log[attacker] or 0) + damageDealt

                    local attackerChar = attacker.Character
                    if attackerChar and attackerChar:GetAttribute("BossMode") then
                        local bonus = math.floor(damageDealt * 0.5)
                        if bonus > 0 then
                            task.defer(function()
                                if humanoid.Parent and humanoid.Health > 0 then
                                    applyingBossBonus[character] = true
                                    humanoid:TakeDamage(bonus)
                                    applyingBossBonus[character] = nil
                                    local current = damageLog[character]
                                    if current then
                                        current[attacker] = (current[attacker] or 0) + bonus
                                    end
                                end
                            end)
                        end
                    end
                end
            end
            lastHealth[character] = newHealth
        end)

        humanoid.Died:Connect(function()
            local charDamages = damageLog[character]
            if charDamages then
                local topKiller, others = resolveAttackers(charDamages)
                local victimPlayer = Players:GetPlayerFromCharacter(character)
                local victimName = victimPlayer and victimPlayer.Name or character.Name

                if topKiller and topKiller:IsA("Player") then
                    sendKillMessage(topKiller.Name, victimName)
                    giveGCells(topKiller, KILL_REWARD, true)
                    local stats = topKiller:FindFirstChild("leaderstats")
                    local kills = stats and stats:FindFirstChild("Kills")
                    if kills and kills:IsA("IntValue") then kills.Value += 1 end
                    giveXP(topKiller, KILL_XP_MIN, KILL_XP_MAX)
                    healPlayer(topKiller, HEAL_PERCENT_ON_KILL)
                end
                for _, attacker in ipairs(others) do
                    if attacker ~= topKiller and attacker:IsA("Player") then
                        giveGCells(attacker, ASSIST_REWARD, true)
                        giveXP(attacker, ASSIST_XP_MIN, ASSIST_XP_MAX)
                    end
                end
            end
            damageLog[character] = nil
            lastHealth[character] = nil
        end)

        character.AncestryChanged:Connect(function(_, parent)
            if not parent then clearCharacter(character) end
        end)
    end

    local function setupPlayer(player)
        player.CharacterAdded:Connect(setupCharacter)
        if player.Character then task.spawn(setupCharacter, player.Character) end
    end

    for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
    Players.PlayerAdded:Connect(setupPlayer)

    Players.PlayerRemoving:Connect(function(player)
        local character = player.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local charDamages = damageLog[character]
        if not charDamages or next(charDamages) == nil then return end

        local damagePercent = 1 - humanoid.Health / humanoid.MaxHealth
        if damagePercent <= 0 then return end

        local topKiller, others = resolveAttackers(charDamages)
        if topKiller and topKiller:IsA("Player") then
            local reward = math.floor(damagePercent * KILL_REWARD)
            if reward > 0 then
                sendKillMessage(topKiller.Name, player.Name)
                giveGCells(topKiller, reward, true)
                giveXP(topKiller, KILL_XP_MIN, KILL_XP_MAX)
            end
        end
        for _, attacker in ipairs(others) do
            if attacker ~= topKiller and attacker:IsA("Player") then
                local reward = math.floor(damagePercent * ASSIST_REWARD)
                if reward > 0 then
                    giveGCells(attacker, reward, true)
                    giveXP(attacker, ASSIST_XP_MIN, ASSIST_XP_MAX)
                end
            end
        end
        damageLog[character] = nil
        lastHealth[character] = nil
    end)
end

local function initAtomicBreath()
    local gojiraModel = workspace:FindFirstChild("GVK GOJIRA", true)
    local model = gojiraModel and gojiraModel:FindFirstChild("AtomicBreath", true)
    if not model then
        warn("[Combat] AtomicBreath model is missing; atomic breath effects disabled")
        return
    end

    local ELECTRIC_BLUE = Color3.fromRGB(0, 191, 255)
    local original = {}
    local sequence = {}

    local function collect(prefix, from, to)
        for i = from, to do
            local spike = model:FindFirstChild(prefix .. i)
            if spike and spike:IsA("BasePart") then
                table.insert(sequence, spike)
                original[spike] = { Color = spike.Color, Material = spike.Material }
            end
        end
    end
    collect("TailSpikes", 1, 11)
    collect("Spikes", 12, 19)

    local function restore(spike)
        local props = original[spike]
        if props and spike.Parent then
            spike.Color, spike.Material = props.Color, props.Material
        end
    end

    _G.AtomicBreathCharge = {
        ChargeUp = function()
            for _, spike in ipairs(sequence) do
                if spike.Parent then
                    spike.Color = ELECTRIC_BLUE
                    spike.Material = Enum.Material.Neon
                end
                task.wait(0.5)
            end
        end,
        Reset = function()
            for spike in pairs(original) do restore(spike) end
        end,
        Discharge = function()
            for i = #sequence, 1, -1 do
                restore(sequence[i])
                task.wait(0.3)
            end
        end,
    }
end

local function initPulse()
    local pulseHitEvent = getOrCreateRemote("PulseHit")
    local pulseFireEvent = getOrCreateRemote("PulseFire")

    local function getHumanoidAndPlayer(part)
        local current = part.Parent
        while current and current ~= workspace do
            local humanoid = current:FindFirstChildOfClass("Humanoid")
            if humanoid then
                return humanoid, Players:GetPlayerFromCharacter(current)
            end
            current = current.Parent
        end
        return nil, nil
    end

    _G.FirePulse = function(player, color, maxSize, duration, damage)
        local character = player and player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        pulseFireEvent:FireAllClients(player, color, maxSize, duration)

        local hitbox = Instance.new("Part")
        hitbox.Name = "PulseHitbox"
        hitbox.Shape = Enum.PartType.Ball
        hitbox.Size = Vector3.new(5, 5, 5)
        hitbox.CFrame = hrp.CFrame
        hitbox.Anchored = true
        hitbox.CanCollide = false
        hitbox.CanTouch = false
        hitbox.CanQuery = true
        hitbox.Transparency = 1
        hitbox:SetAttribute("BlastActive", true)
        hitbox:SetAttribute("Attacker", player.Name)

        local pn = Instance.new("StringValue")
        pn.Name = "PlayerName"
        pn.Value = player.Name
        pn.Parent = hitbox

        hitbox.Parent = workspace
        Debris:AddItem(hitbox, duration + 2)

        local damagePerTick = damage / 10
        local gcellsPerTick = 25
        local startSize = 50
        maxSize = math.max(maxSize, 300)
        local tickInterval = 0.5

        local overlapParams = OverlapParams.new()
        overlapParams.FilterDescendantsInstances = { character }
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude

        local startTime = os.clock()
        while os.clock() - startTime < duration do
            if not hitbox.Parent or not hrp.Parent then break end

            local progress = math.clamp((os.clock() - startTime) / duration, 0, 1)
            local size = startSize + (maxSize - startSize) * progress
            hitbox.Size = Vector3.new(size, size, size)
            hitbox.CFrame = hrp.CFrame

            local hitThisTick = {}
            for _, part in ipairs(workspace:GetPartsInPart(hitbox, overlapParams)) do
                local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
                if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitThisTick[hitPlayer] then
                    hitThisTick[hitPlayer] = true
                    setCreator(hitHumanoid, player)
                    hitHumanoid:TakeDamage(damagePerTick)
                    pulseHitEvent:FireClient(hitPlayer)
                    giveGCells(player, gcellsPerTick, false)
                end
            end

            if _G.DamageBuildingsInRadius then
                _G.DamageBuildingsInRadius(hrp.Position, size / 2, player)
            end
            task.wait(tickInterval)
        end

        if hitbox.Parent then
            hitbox:SetAttribute("BlastActive", false)
            hitbox:Destroy()
        end
    end
end

local function initLevelGuard()
    local LEVEL_THRESHOLD = 10
    local BLOCK_DURATION = 3

    local blockTimers = {}
    local killRewardFlags = {}
    local previousGCells = {}
    local changing = {}
    local hookedGCells = {}

    local function getLevel(character)
        local levelVal = character and character:FindFirstChild("Level")
        if levelVal and levelVal:IsA("IntValue") then return levelVal.Value end
        return nil
    end

    local function isBlocked(player)
        if not player or not player.Parent then return false end
        local expires = blockTimers[player]
        if not expires then return false end
        if os.clock() > expires then
            blockTimers[player] = nil
            return false
        end
        return true
    end

    _G.IsRewardBlocked = isBlocked
    _G.SetKillRewardFlag = function(player)
        if player then killRewardFlags[player] = true end
    end
    _G.ClearKillRewardFlag = function(player)
        if player then killRewardFlags[player] = nil end
    end

    local function checkAttack(attacker, targetCharacter)
        if not attacker or not attacker:IsA("Player") or not targetCharacter then return end
        local attackerLevel = getLevel(attacker.Character)
        local targetLevel = getLevel(targetCharacter)
        if not attackerLevel or not targetLevel then return end
        if attackerLevel > LEVEL_THRESHOLD and targetLevel < LEVEL_THRESHOLD then
            blockTimers[attacker] = os.clock() + BLOCK_DURATION
        end
    end

    local function hookCreator(humanoid, targetCharacter)
        local function check(creator)
            local value = creator.Value
            if value and value:IsA("Player") then checkAttack(value, targetCharacter) end
        end
        local function watch(creator)
            if not creator:IsA("ObjectValue") then return end
            creator.Changed:Connect(function() check(creator) end)
            check(creator)
        end
        local existing = humanoid:FindFirstChild("creator")
        if existing then watch(existing) end
        humanoid.ChildAdded:Connect(function(child)
            if child.Name == "creator" then watch(child) end
        end)
    end

    local function hookDPSAttacker(humanoid, targetCharacter)
        local function check()
            local attackerId = humanoid:GetAttribute("LastDPSAttacker")
            if attackerId then
                local attacker = Players:GetPlayerByUserId(attackerId)
                if attacker then checkAttack(attacker, targetCharacter) end
            end
        end
        humanoid:GetAttributeChangedSignal("LastDPSAttacker"):Connect(check)
        check()
    end

    local function hookGCells(player)
        local function setup()
            local gcells = getGCells(player)
            if not gcells or hookedGCells[gcells] then return end
            hookedGCells[gcells] = true
            previousGCells[player] = gcells.Value
            gcells.Changed:Connect(function(newValue)
                if changing[player] then return end
                if killRewardFlags[player] then
                    previousGCells[player] = newValue
                    return
                end
                if isBlocked(player) then
                    local prev = previousGCells[player] or 0
                    if newValue > prev then
                        changing[player] = true
                        gcells.Value = prev
                        changing[player] = nil
                        return
                    end
                end
                previousGCells[player] = newValue
            end)
            gcells.AncestryChanged:Connect(function(_, parent)
                if not parent then hookedGCells[gcells] = nil end
            end)
        end

        setup()
        player.ChildAdded:Connect(function(child)
            if child.Name == "leaderstats" then
                task.wait(0.1)
                setup()
            end
        end)
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            leaderstats.ChildAdded:Connect(function() task.defer(setup) end)
        end
    end

    local function hookCharacter(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        hookCreator(humanoid, character)
        hookDPSAttacker(humanoid, character)
    end

    local function hookPlayer(player)
        hookGCells(player)
        player.CharacterAdded:Connect(function(character)
            task.spawn(hookCharacter, character)
        end)
        if player.Character then task.spawn(hookCharacter, player.Character) end
    end

    for _, player in ipairs(Players:GetPlayers()) do hookPlayer(player) end
    Players.PlayerAdded:Connect(hookPlayer)
    Players.PlayerRemoving:Connect(function(player)
        blockTimers[player] = nil
        killRewardFlags[player] = nil
        previousGCells[player] = nil
        changing[player] = nil
    end)
end

local function initWaterBubbles()
    local bubblesTemplate = ReplicatedStorage:FindFirstChild("bubbles")
    if not bubblesTemplate then
        warn("[WaterBubbles] Could not find bubbles template in ReplicatedStorage")
        return
    end
    local waterStateEvent = ReplicatedStorage:FindFirstChild("WaterState")
    if not waterStateEvent then
        warn("[WaterBubbles] Could not find WaterState RemoteEvent")
        return
    end

    local BUBBLES_NAME = "bubbles"
    local HEAD_NAMES = { "FakeHead", "Fakehead", "Head" }

    local function getHead(character)
        for _, name in ipairs(HEAD_NAMES) do
            local head = character:FindFirstChild(name)
            if head and head:IsA("BasePart") then return head end
        end
        return nil
    end

    waterStateEvent.OnServerEvent:Connect(function(player, inWater)
        if type(inWater) ~= "boolean" then return end
        local character = player.Character
        if not character then return end
        local head = getHead(character)
        if not head then return end
        local existing = head:FindFirstChild(BUBBLES_NAME)
        if inWater then
            if not existing then
                local bubbles = bubblesTemplate:Clone()
                bubbles.Name = BUBBLES_NAME
                bubbles.Parent = head
            end
        elseif existing then
            existing:Destroy()
        end
    end)
end

local function initAttackHandler()
    local BeamSystem = safeRequire("BeamSystem")

    local playerDebounces = {}
    local connectedRemotes = {}

    local VALID_ATTACK_TYPES = {
        Melee = true, Pulse = true, Beam = true, FirePulse = true, BackBeam = true,
    }

    local function getHumanoidAndPlayer(part)
        if part.Name == "AttackHitbox" or part.Name == "BeamHitbox" or part.Name == "PulseHitbox" or part:GetAttribute("MeleeHit") then
            return nil, nil
        end
        local character = part.Parent
        if not character then return nil, nil end
        return character:FindFirstChildOfClass("Humanoid"), Players:GetPlayerFromCharacter(character)
    end

    local function findSounds(character)
        local sounds = character:FindFirstChild("Sounds")
        if sounds then return sounds end
        local scripts = character:FindFirstChild("CharacterScripts")
        return scripts and scripts:FindFirstChild("Sounds") or nil
    end

    local function getGlowManager(character)
        local scripts = character:FindFirstChild("CharacterScripts")
        local module = scripts and scripts:FindFirstChild("GlowManager")
        if not module then return nil end
        local ok, gm = pcall(require, module)
        return ok and gm or nil
    end

    local function playSoundFrom(character, soundName, parent)
        local sounds = findSounds(character)
        local template = sounds and sounds:FindFirstChild(soundName)
        if not template or not parent then return end
        local clone = template:Clone()
        clone.Parent = parent
        clone.Looped = false
        clone.Ended:Connect(function() clone:Destroy() end)
        clone:Play()
        Debris:AddItem(clone, 15)
    end

    local function playHitSound(character)
        playSoundFrom(character, "HitSound", character:FindFirstChild("HumanoidRootPart"))
    end

    local function playAttackAnimation(character, animName)
        local animations = character:FindFirstChild("Animations")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChild("Animator")
        local anim = animations and animations:FindFirstChild(animName)
        if animator and anim then
            local track = animator:LoadAnimation(anim)
            track.Looped = false
            track:Play()
        end
    end

    local function getAnimName(remoteName)
        if remoteName == "Attack" then return "Attack1" end
        if remoteName == "Beam" then return "Attack2" end
        return remoteName
    end

    local function getDamage(character, damageStat)
        local stats = character:FindFirstChild("Stats")
        local value = stats and stats:FindFirstChild(damageStat)
        return value and value.Value or 10
    end

    local function registerHit(attacker, attackerChar, humanoid, damage, gcells)
        setCreator(humanoid, attacker)
        humanoid:TakeDamage(damage)
        playHitSound(attackerChar)
        giveGCells(attacker, gcells, false)
    end

    local function enableHitParts(character, hitPlayers, player, damage)
        local connections, enabled = {}, {}
        for _, folder in ipairs({ character:FindFirstChild("HitParts"), character:FindFirstChild("HitParts2") }) do
            if folder then
                for _, part in ipairs(folder:GetDescendants()) do
                    if part:IsA("BasePart") and not part:FindFirstChildWhichIsA("Script") then
                        part.CanTouch = true
                        table.insert(enabled, part)
                        table.insert(connections, part.Touched:Connect(function(hit)
                            local hitHumanoid, hitPlayer = getHumanoidAndPlayer(hit)
                            if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
                                hitPlayers[hitPlayer] = true
                                registerHit(player, character, hitHumanoid, damage, 25)
                            end
                        end))
                    end
                end
            end
        end
        return connections, enabled
    end

    local function disableHitParts(connections, enabled)
        for _, conn in ipairs(connections) do conn:Disconnect() end
        for _, part in ipairs(enabled) do
            if part.Parent then part.CanTouch = false end
        end
    end

    local function executeMeleeAttack(player, character, remote, remoteName, durationOverride)
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local size = Vector3.new(
            remote:GetAttribute("HitboxSizeX") or 15,
            remote:GetAttribute("HitboxSizeY") or 15,
            remote:GetAttribute("HitboxSizeZ") or 15
        )
        local offset = CFrame.new(
            remote:GetAttribute("HitboxOffsetX") or 0,
            remote:GetAttribute("HitboxOffsetY") or 0,
            remote:GetAttribute("HitboxOffsetZ") or -10
        )
        local duration = durationOverride or remote:GetAttribute("HitboxDuration") or 0.5
        local damage = getDamage(character, remote:GetAttribute("DamageStat") or "DMG1")

        playAttackAnimation(character, getAnimName(remoteName))

        local hitbox = Instance.new("Part")
        hitbox.Name = "AttackHitbox"
        hitbox:SetAttribute("MeleeHit", true)
        hitbox.Size = size
        hitbox.Anchored = true
        hitbox.CanCollide = false
        hitbox.CanTouch = true
        hitbox.Transparency = 1
        hitbox.Color = Color3.fromRGB(255, 0, 0)
        hitbox.Material = Enum.Material.Neon
        hitbox.Parent = character
        hitbox.CFrame = hrp.CFrame * offset
        Debris:AddItem(hitbox, duration + 2)

        local hitPlayers = {}
        local partConns, partsEnabled = enableHitParts(character, hitPlayers, player, damage)

        local connection = hitbox.Touched:Connect(function(hit)
            local hitHumanoid, hitPlayer = getHumanoidAndPlayer(hit)
            if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
                hitPlayers[hitPlayer] = true
                registerHit(player, character, hitHumanoid, damage, 25)
            end
        end)

        local overlapParams = OverlapParams.new()
        overlapParams.FilterDescendantsInstances = { character }
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude

        local startTime = os.clock()
        while os.clock() - startTime < duration do
            if not character.Parent or not hrp.Parent or not hitbox.Parent then break end
            for _, part in ipairs(workspace:GetPartsInPart(hitbox, overlapParams)) do
                local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
                if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
                    hitPlayers[hitPlayer] = true
                    registerHit(player, character, hitHumanoid, damage, 25)
                end
            end
            task.wait(0.05)
        end

        connection:Disconnect()
        hitbox:Destroy()
        disableHitParts(partConns, partsEnabled)
    end

    local function executePulseAttack(player, character, remote, remoteName)
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local sizeX = remote:GetAttribute("HitboxSizeX") or 50
        local sizeY = remote:GetAttribute("HitboxSizeY") or 50
        local sizeZ = remote:GetAttribute("HitboxSizeZ") or 50
        local duration = remote:GetAttribute("HitboxDuration") or 2
        local maxSize = remote:GetAttribute("PulseMaxSize") or 500
        local tickInterval = remote:GetAttribute("PulseTickInterval") or 0.3
        local damage = getDamage(character, remote:GetAttribute("DamageStat") or "DMG3")

        playAttackAnimation(character, getAnimName(remoteName))
        playSoundFrom(character, "Beam", hrp)

        local pulsePart = Instance.new("Part")
        pulsePart.Name = "PulseHitbox"
        pulsePart.Shape = Enum.PartType.Ball
        pulsePart.Material = Enum.Material.Neon
        pulsePart.Color = Color3.fromRGB(0, 0, 0)
        pulsePart.Anchored = true
        pulsePart.CanCollide = false
        pulsePart.CanTouch = false
        pulsePart.Transparency = 0
        pulsePart.Size = Vector3.new(sizeX, sizeY, sizeZ)
        pulsePart.CFrame = hrp.CFrame
        pulsePart.Parent = workspace
        Debris:AddItem(pulsePart, duration + 2)

        local oneShotHit = {}
        local partConns, partsEnabled = enableHitParts(character, oneShotHit, player, damage)

        local numTicks = math.max(duration / tickInterval, 1)
        local damagePerTick = damage / numTicks
        local gcellsPerTick = 25 / numTicks
        local startSize = math.max(sizeX, sizeY, sizeZ)

        local overlapParams = OverlapParams.new()
        overlapParams.FilterDescendantsInstances = { character }
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude

        local startTime = os.clock()
        while os.clock() - startTime < duration do
            if not character.Parent or not hrp.Parent or not pulsePart.Parent then break end

            local progress = math.clamp((os.clock() - startTime) / duration, 0, 1)
            local currentSize = startSize + (maxSize - startSize) * progress
            pulsePart.Size = Vector3.new(currentSize, currentSize, currentSize)
            pulsePart.Transparency = progress
            pulsePart.CFrame = hrp.CFrame

            local hitThisTick = {}
            for _, part in ipairs(workspace:GetPartsInPart(pulsePart, overlapParams)) do
                local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
                if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitThisTick[hitPlayer] then
                    hitThisTick[hitPlayer] = true
                    registerHit(player, character, hitHumanoid, damagePerTick, gcellsPerTick)
                end
            end
            task.wait(tickInterval)
        end

        if pulsePart.Parent then pulsePart:Destroy() end
        disableHitParts(partConns, partsEnabled)
    end

    local function executeFirePulse(player, character, remote, remoteName)
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local damage = getDamage(character, remote:GetAttribute("DamageStat") or "DMG3")
        local windup = remote:GetAttribute("PulseWindup") or 0
        local pulseColor = remote:GetAttribute("PulseColor") or Color3.fromRGB(255, 120, 0)
        local pulseMaxSize = remote:GetAttribute("PulseMaxSize") or 300
        local pulseDuration = remote:GetAttribute("HitboxDuration") or 4

        playAttackAnimation(character, getAnimName(remoteName))
        playSoundFrom(character, "Pulse", hrp)

        if windup > 0 then task.wait(windup) end
        if _G.FirePulse then
            _G.FirePulse(player, pulseColor, pulseMaxSize, pulseDuration, damage)
        end
    end

    local function executeBeamAttack(player, character, remote, remoteName, targetPos)
        if not BeamSystem then return end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if typeof(targetPos) ~= "Vector3" then targetPos = nil end

        local duration = remote:GetAttribute("BeamDuration") or remote:GetAttribute("HitboxDuration") or 4.7
        local chargeTime = remote:GetAttribute("BeamChargeTime") or 0

        playAttackAnimation(character, getAnimName(remoteName))

        local glowManager = getGlowManager(character)
        if glowManager then glowManager.StartGlow(chargeTime) end

        playSoundFrom(character, "Beam", hrp)

        local sortedSpikes = {}
        local originalProps = {}
        local spikesFolder = character:FindFirstChild("Spikes")
        if spikesFolder then
            for _, child in ipairs(spikesFolder:GetChildren()) do
                if child:IsA("BasePart") then
                    local number = tonumber(string.match(child.Name, "%d+"))
                    if number then
                        table.insert(sortedSpikes, { part = child, number = number })
                        originalProps[child] = { Material = child.Material, UsePartColor = child.UsePartColor }
                    end
                end
            end
            table.sort(sortedSpikes, function(a, b) return a.number < b.number end)
        end

        local function resetEffects()
            task.spawn(function()
                for i = #sortedSpikes, 1, -1 do
                    local spike = sortedSpikes[i].part
                    local props = originalProps[spike]
                    if props and spike.Parent then
                        spike.Material = props.Material
                        spike.UsePartColor = props.UsePartColor
                    end
                    task.wait(0.1)
                end
                if glowManager then glowManager.EndGlow() end
            end)
        end

        if #sortedSpikes > 0 then
            local perSpikeDelay = chargeTime > 0 and chargeTime / #sortedSpikes or 0.21
            for _, data in ipairs(sortedSpikes) do
                data.part.Material = Enum.Material.Neon
                data.part.UsePartColor = true
                task.wait(perSpikeDelay)
            end
        elseif chargeTime > 0 then
            task.wait(chargeTime)
        end

        local ok, err = pcall(BeamSystem.ActivateBeam, {
            character = character,
            player = player,
            initialTargetPosition = targetPos,
            duration = duration,
        })
        if not ok then warn("[AttackHandler] ActivateBeam failed: " .. tostring(err)) end

        resetEffects()
    end

    local function executeBackBeam(player, character, remote, remoteName)
        local glowManager = getGlowManager(character)
        if glowManager then glowManager.StartGlow() end

        local windup = remote:GetAttribute("BackBeamWindup") or 0
        if windup > 0 then task.wait(windup) end

        local activeDuration = remote:GetAttribute("BackBeamActive") or remote:GetAttribute("HitboxDuration") or 0.5
        local ok, err = pcall(executeMeleeAttack, player, character, remote, remoteName, activeDuration)
        if not ok then warn("[AttackHandler] BackBeam failed: " .. tostring(err)) end

        if glowManager then glowManager.EndGlow() end
    end

    local function connectRemote(remote)
        if connectedRemotes[remote] then return end
        local attackType = remote:GetAttribute("AttackType")
        if not attackType or not VALID_ATTACK_TYPES[attackType] then return end
        connectedRemotes[remote] = true

        remote.AncestryChanged:Connect(function(_, parent)
            if not parent then connectedRemotes[remote] = nil end
        end)

        local remoteName = remote.Name
        remote.OnServerEvent:Connect(function(player, ...)
            local debounces = playerDebounces[player]
            if not debounces then
                debounces = {}
                playerDebounces[player] = debounces
            end
            if debounces[remote] then return end

            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid or humanoid.Health <= 0 then return end

            debounces[remote] = true

            local args = table.pack(...)
            local ok, err = pcall(function()
                if attackType == "Melee" then
                    executeMeleeAttack(player, char, remote, remoteName)
                elseif attackType == "Pulse" then
                    executePulseAttack(player, char, remote, remoteName)
                elseif attackType == "Beam" then
                    executeBeamAttack(player, char, remote, remoteName, args[1])
                elseif attackType == "FirePulse" then
                    executeFirePulse(player, char, remote, remoteName)
                elseif attackType == "BackBeam" then
                    executeBackBeam(player, char, remote, remoteName)
                end
            end)
            if not ok then warn("[AttackHandler] " .. attackType .. " failed: " .. tostring(err)) end

            if playerDebounces[player] then
                playerDebounces[player][remote] = nil
            end
        end)
    end

    local function scanCharacter(character)
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("RemoteEvent") then connectRemote(descendant) end
        end
    end

    local function setupPlayer(player)
        player.CharacterAdded:Connect(function(character)
            scanCharacter(character)
            character.DescendantAdded:Connect(function(descendant)
                if descendant:IsA("RemoteEvent") then
                    task.defer(connectRemote, descendant)
                end
            end)
        end)
        local character = player.Character
        if character then
            scanCharacter(character)
            character.DescendantAdded:Connect(function(descendant)
                if descendant:IsA("RemoteEvent") then
                    task.defer(connectRemote, descendant)
                end
            end)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
    Players.PlayerAdded:Connect(setupPlayer)
    Players.PlayerRemoving:Connect(function(player)
        playerDebounces[player] = nil
    end)
end

function Combat.Init()
    if initialized then return end
    initialized = true
    task.spawn(initCombat)
    task.spawn(initAtomicBreath)
    task.spawn(initLevelGuard)
    task.spawn(initWaterBubbles)
    task.spawn(initPulse)
    task.spawn(initAttackHandler)
end

return Combat
