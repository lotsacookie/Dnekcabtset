local Combat = {}
local LevelGuard = require(game:GetService("ReplicatedStorage"):FindFirstChild("LevelGuard"))
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--[[local siphonEvent = ReplicatedStorage:FindFirstChild("Siphon")
--if not siphonEvent then
--	siphonEvent = Instance.new("RemoteEvent")
--	siphonEvent.Name = "Siphon"
--	siphonEvent.Parent = ReplicatedStorage
--end]]
local ChargeManager = require(ReplicatedStorage:FindFirstChild("ChargeManager"))
function Combat.Init()
	local function initCombat()
		local HEALTH_THRESHOLD = 0.50
		local SLOW_PERCENT = 0.65
		local KILL_REWARD = 300
		local ASSIST_REWARD = 100
		local HEAL_PERCENT_ON_KILL = 0.80
		local KILL_XP_MIN = 200
		local KILL_XP_MAX = 300
		local ASSIST_XP_MIN = 50
		local ASSIST_XP_MAX = 100
		--local KILL_SIPHON = 65
		--local ASSIST_SIPHON = 25
		local damageLog = {}
		_G.CombatDamageLog = damageLog
		local lastHealth = {}
		local applyingBossBonus = {}
		local restoringHealth = {}
		local restoringHealth = {}
		local function giveGCells(player, amount)
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end
			local gcells = leaderstats:FindFirstChild("GCells") or leaderstats:FindFirstChild("gcells")
			if gcells and gcells:IsA("IntValue") then
				if _G.SetKillRewardFlag then _G.SetKillRewardFlag(player) end
				if _G.GCellGuardAllow then _G.GCellGuardAllow(gcells, amount) end
				gcells.Value += amount
				if _G.ClearKillRewardFlag then _G.ClearKillRewardFlag(player) end
			end
		end
		local function giveKill(player)
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end
			local kills = leaderstats:FindFirstChild("Kills")
			if kills and kills:IsA("IntValue") then
				kills.Value += 1
			end
		end
		local function giveXP(player, minXP, maxXP)
			local character = player.Character
			if not character then return end
			local addXPEvent = character:FindFirstChild("AddXP")
			if addXPEvent and addXPEvent:IsA("BindableEvent") then
				local amount = math.random(minXP, maxXP)
				if _G.SetKillRewardFlag then _G.SetKillRewardFlag(player) end
				addXPEvent:Fire(amount)
				if _G.ClearKillRewardFlag then _G.ClearKillRewardFlag(player) end
			end
		end
		local function healPlayer(player, percent)
			local character = player.Character
			if not character then return end
			if character:GetAttribute("BossMode") then return end
			local humanoid = character:FindFirstChild("Humanoid")
			if not humanoid or humanoid.Health <= 0 then return end
			local healAmount = humanoid.MaxHealth * percent
			humanoid.Health = math.min(humanoid.Health + healAmount, humanoid.MaxHealth)
		end
		local function sendMessage(message)
			local killMessageEvent = ReplicatedStorage:FindFirstChild("KillMessage")
			if killMessageEvent then
				killMessageEvent:FireAllClients(message)
			end
		end
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
			local template = KILL_MESSAGES[math.random(1, #KILL_MESSAGES)]
			local message = string.gsub(template, "{killer}", killerName)
			message = string.gsub(message, "{victim}", victimName)
			sendMessage(message)
		end
		local function setupCharacter(character)
			local humanoid = character:WaitForChild("Humanoid")
			local isLowHealth = false
			local isApplyingSlow = false
			local baseWalkSpeed = nil
			lastHealth[character] = humanoid.Health
			damageLog[character] = {}
			humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if isApplyingSlow then return end
				if isLowHealth and baseWalkSpeed then
					local maxAllowedSpeed = baseWalkSpeed * (1 - SLOW_PERCENT)
					if humanoid.WalkSpeed > maxAllowedSpeed then
						isApplyingSlow = true
						humanoid.WalkSpeed = maxAllowedSpeed
						isApplyingSlow = false
					end
				end
			end)
			humanoid.HealthChanged:Connect(function(newHealth)
				if applyingBossBonus[character] or restoringHealth[character] then
					lastHealth[character] = newHealth
					return
				end
				if newHealth <= 0 then
					return
				end
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
				else
					if isLowHealth then
						isLowHealth = false
						humanoid:SetAttribute("Slowed", false)
						isApplyingSlow = true
						humanoid.WalkSpeed = baseWalkSpeed or humanoid.WalkSpeed / (1 - SLOW_PERCENT)
						isApplyingSlow = false
						baseWalkSpeed = nil
					end
				end
				local oldHealth = lastHealth[character] or humanoid.MaxHealth
				if newHealth < oldHealth then
					local damageDealt = oldHealth - newHealth
					local creator = humanoid:FindFirstChild("creator")
					if creator and creator.Value and creator.Value:IsA("Player") then
						local attacker = creator.Value
						local bossSystem = _G.BossSystem
						if bossSystem and bossSystem.active then
							local attackerChar = attacker.Character
							local attackerIsBoss = attackerChar and attackerChar:GetAttribute("BossMode")
							local victimIsBoss = character:GetAttribute("BossMode")
							if not victimIsBoss and not attackerIsBoss then
								restoringHealth[character] = true
								humanoid.Health = oldHealth
								restoringHealth[character] = false
								lastHealth[character] = oldHealth
								return
							end
						end
						if not damageLog[character] then
							damageLog[character] = {}
						end
						damageLog[character][attacker] = (damageLog[character][attacker] or 0) + damageDealt
							local attackerChar = attacker.Character
							if attackerChar and attackerChar:GetAttribute("BossMode") then
								local bonusDamage = math.floor(damageDealt * 0.5)
								if bonusDamage > 0 then
									task.defer(function()
										if humanoid and humanoid.Parent and humanoid.Health > 0 then
											applyingBossBonus[character] = true
											humanoid:TakeDamage(bonusDamage)
											if damageLog[character] then
												damageLog[character][attacker] = (damageLog[character][attacker] or 0) + bonusDamage
											end
											applyingBossBonus[character] = false
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
				if not charDamages then return end
				local topKiller = nil
				local topDamage = 0
				local otherAttackers = {}
				for attacker, damage in pairs(charDamages) do
					if damage > topDamage then
						if topKiller then
							table.insert(otherAttackers, topKiller)
						end
						topKiller = attacker
						topDamage = damage
					else
						table.insert(otherAttackers, attacker)
					end
				end
				local victimPlayer = Players:GetPlayerFromCharacter(character)
				local victimName = victimPlayer and victimPlayer.Name or character.Name
				if topKiller and topKiller:IsA("Player") then
					sendKillMessage(topKiller.Name, victimName)
					giveGCells(topKiller, KILL_REWARD)
					giveKill(topKiller)
					giveXP(topKiller, KILL_XP_MIN, KILL_XP_MAX)
					healPlayer(topKiller, HEAL_PERCENT_ON_KILL)
					--siphonEvent:FireClient(topKiller, KILL_SIPHON)
				end
				for _, attacker in ipairs(otherAttackers) do
					if attacker ~= topKiller and attacker:IsA("Player") then
						giveGCells(attacker, ASSIST_REWARD)
						giveXP(attacker, ASSIST_XP_MIN, ASSIST_XP_MAX)
						--siphonEvent:FireClient(attacker, ASSIST_SIPHON)
					end
				end
				damageLog[character] = nil
				lastHealth[character] = nil
			end)
			character.AncestryChanged:Connect(function(_, parent)
				if not parent then
					damageLog[character] = nil
					lastHealth[character] = nil
					applyingBossBonus[character] = nil
					restoringHealth[character] = nil
				end
			end)
		end
		local function setupPlayer(player)
			player.CharacterAdded:Connect(setupCharacter)
			if player.Character then
				setupCharacter(player.Character)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			setupPlayer(player)
		end
		Players.PlayerAdded:Connect(setupPlayer)
		Players.PlayerRemoving:Connect(function(player)
			local character = player.Character
			if not character then return end
			local humanoid = character:FindFirstChild("Humanoid")
			if not humanoid or humanoid.Health <= 0 then return end
			local charDamages = damageLog[character]
			if not charDamages then return end
			local hasAttackers = false
			for _ in pairs(charDamages) do
				hasAttackers = true
				break
			end
			if not hasAttackers then return end
			local healthPercent = humanoid.Health / humanoid.MaxHealth
			local damagePercent = 1 - healthPercent
			if damagePercent <= 0 then return end
			local topKiller = nil
			local topDamage = 0
			local otherAttackers = {}
			for attacker, damage in pairs(charDamages) do
				if damage > topDamage then
					if topKiller then
						table.insert(otherAttackers, topKiller)
					end
					topKiller = attacker
					topDamage = damage
				else
					table.insert(otherAttackers, attacker)
				end
			end
			if topKiller and topKiller:IsA("Player") then
				local proportionalKillReward = math.floor(damagePercent * KILL_REWARD)
				if proportionalKillReward > 0 then
					local template = KILL_MESSAGES[math.random(1, #KILL_MESSAGES)]
					local message = string.gsub(template, "{killer}", topKiller.Name)
					message = string.gsub(message, "{victim}", player.Name)
					sendMessage(message)
					giveGCells(topKiller, proportionalKillReward)
					giveXP(topKiller, KILL_XP_MIN, KILL_XP_MAX)
				end
			end
			for _, attacker in ipairs(otherAttackers) do
				if attacker ~= topKiller and attacker:IsA("Player") then
					local proportionalAssistReward = math.floor(damagePercent * ASSIST_REWARD)
					if proportionalAssistReward > 0 then
						giveGCells(attacker, proportionalAssistReward)
						giveXP(attacker, ASSIST_XP_MIN, ASSIST_XP_MAX)
					end
				end
			end
			damageLog[character] = nil
			lastHealth[character] = nil
		end)
	end
	local function initAtomicBreath()
		local gojiraModel = workspace:FindFirstChild("GVK GOJIRA",true)
		local AtomicBreathModel = gojiraModel and gojiraModel:FindFirstChild("AtomicBreath",true)
		if not AtomicBreathModel then
			warn("[Combat] AtomicBreath model is missing; atomic breath effects disabled")
			return
		end
		local ELECTRIC_BLUE = Color3.fromRGB(0, 191, 255)
		local originalProperties = {}
		local spikeSequence = {}
		for i = 1, 11 do
			local spike = AtomicBreathModel:FindFirstChild("TailSpikes" .. i)
			if spike then
				table.insert(spikeSequence, spike)
				originalProperties[spike] = {
					Color = spike.Color,
					Material = spike.Material
				}
			end
		end
		for i = 12, 19 do
			local spike = AtomicBreathModel:FindFirstChild("Spikes" .. i)
			if spike then
				table.insert(spikeSequence, spike)
				originalProperties[spike] = {
					Color = spike.Color,
					Material = spike.Material
				}
			end
		end
		local function chargeUp()
			for i, spike in ipairs(spikeSequence) do
				spike.Color = ELECTRIC_BLUE
				spike.Material = Enum.Material.Neon
				task.wait(0.5)
			end
			print("Atomic Breath fully charged!")
		end
		local function resetSpikes()
			for spike, props in pairs(originalProperties) do
				spike.Color = props.Color
				spike.Material = props.Material
			end
			print("Spikes reset to original state.")
		end
		local function discharge()
			for i = #spikeSequence, 1, -1 do
				local spike = spikeSequence[i]
				local original = originalProperties[spike]
				if original then
					spike.Color = original.Color
					spike.Material = original.Material
				end
				task.wait(0.3)
			end
			print("Discharge complete.")
		end
		_G.AtomicBreathCharge = {
			ChargeUp = chargeUp,
			Reset = resetSpikes,
			Discharge = discharge
		}
		print("AtomicBreath charge effect loaded. Use _G.AtomicBreathCharge.ChargeUp() to test.")
		task.wait(2)
		chargeUp()
		task.wait(3)
		discharge()
	end
	local function initPulse()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local pulseHitEvent = ReplicatedStorage:FindFirstChild("PulseHit")
	if not pulseHitEvent then
		pulseHitEvent = Instance.new("RemoteEvent")
		pulseHitEvent.Name = "PulseHit"
		pulseHitEvent.Parent = ReplicatedStorage
	end
	local pulseFireEvent = ReplicatedStorage:FindFirstChild("PulseFire")
	if not pulseFireEvent then
		pulseFireEvent = Instance.new("RemoteEvent")
		pulseFireEvent.Name = "PulseFire"
		pulseFireEvent.Parent = ReplicatedStorage
	end
	local function getHumanoidAndPlayer(part)
		local current = part.Parent
		while current and current ~= workspace do
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local player = Players:GetPlayerFromCharacter(current)
				return humanoid, player
			end
			current = current.Parent
		end
		return nil, nil
	end
	_G.FirePulse = function(player, color, maxSize, duration, damage)
		local character = player.Character
		if not character then return end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		-- Tell all clients to render the visual pulse
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
		hitbox.Parent = workspace
		hitbox:SetAttribute("BlastActive", true)
		local pn = Instance.new("StringValue")
		pn.Name = "PlayerName"
		pn.Value = player.Name
		pn.Parent = hitbox
		hitbox:SetAttribute("Attacker", player.Name)
		local startTime = tick()
		local tickInterval = 0.5
		local damagePerTick = damage / 10
		local gcellsPerTick = 25
		local startSize = 50
		maxSize = math.max(maxSize, 300)
				-- pulseCleanupGuard: ensure hitbox is destroyed even if the loop errors
		local pulseHitboxRef = hitbox
		task.spawn(function()
			task.wait(duration + 2)
			if pulseHitboxRef and pulseHitboxRef.Parent then
				pulseHitboxRef:SetAttribute("BlastActive", false)
				pulseHitboxRef:Destroy()
			end
		end)
while tick() - startTime < duration do
			local progress = math.clamp((tick() - startTime) / duration, 0, 1)
			local currentSize = startSize + (maxSize - startSize) * progress
			hitbox.Size = Vector3.new(currentSize, currentSize, currentSize)
			hitbox.CFrame = hrp.CFrame
			local hitThisTick = {}
			local overlapParams = OverlapParams.new()
			overlapParams.FilterDescendantsInstances = {character}
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			local overlappingParts = workspace:GetPartsInPart(hitbox, overlapParams)
			for _, part in ipairs(overlappingParts) do
				local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
				if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitThisTick[hitPlayer] then
					hitThisTick[hitPlayer] = true
					local _c = hitHumanoid:FindFirstChild("creator")
					if not _c then
						_c = Instance.new("ObjectValue")
						_c.Name = "creator"
						_c.Parent = hitHumanoid
					end
					_c.Value = player
					hitHumanoid:TakeDamage(damagePerTick)
					pulseHitEvent:FireClient(hitPlayer)
					local leaderstats = player:FindFirstChild("leaderstats")
					if leaderstats then
						local gcells = leaderstats:FindFirstChild("GCells") or leaderstats:FindFirstChild("gcells")
						if gcells and gcells:IsA("IntValue") then
							if _G.GCellGuardAllow then _G.GCellGuardAllow(gcells, gcellsPerTick) end
							gcells.Value = gcells.Value + gcellsPerTick
						end
					end
				end
			end
			-- Damage buildings in range
			if _G.DamageBuildingsInRadius then
				_G.DamageBuildingsInRadius(hrp.Position, currentSize / 2, player)
			end
			task.wait(tickInterval)
		end
		hitbox:SetAttribute("BlastActive", false)
		hitbox:Destroy()
	end
end
local function initLevelGuard()
		local LEVEL_THRESHOLD = 10
		local BLOCK_DURATION = 3
		local blockTimers = {}
		local killRewardFlags = {}
		local previousGCells = {}
		local changing = {}
		local function getPlayerLevel(player)
			if not player or not player.Parent then return nil end
			local char = player.Character
			if not char then return nil end
			local levelVal = char:FindFirstChild("Level")
			if levelVal and levelVal:IsA("IntValue") then
				return levelVal.Value
			end
			return nil
		end
		local function getCharacterLevel(character)
			if not character then return nil end
			local levelVal = character:FindFirstChild("Level")
			if levelVal and levelVal:IsA("IntValue") then
				return levelVal.Value
			end
			return nil
		end
		local function isBlocked(player)
			if not player or not player.Parent then return false end
			local timer = blockTimers[player]
			if not timer then return false end
			if tick() > timer then
				blockTimers[player] = nil
				return false
			end
			return true
		end
		_G.IsRewardBlocked = isBlocked
		_G.SetKillRewardFlag = function(player)
			if player then
				killRewardFlags[player] = true
			end
		end
		_G.ClearKillRewardFlag = function(player)
			if player then
				killRewardFlags[player] = nil
			end
		end
		local function checkAttack(attackerPlayer, targetCharacter)
			if not attackerPlayer or not attackerPlayer:IsA("Player") then return end
			if not targetCharacter then return end
			local attackerLevel = getPlayerLevel(attackerPlayer)
			local targetLevel = getCharacterLevel(targetCharacter)
			if not attackerLevel or not targetLevel then return end
			if attackerLevel > LEVEL_THRESHOLD and targetLevel < LEVEL_THRESHOLD then
				blockTimers[attackerPlayer] = tick() + BLOCK_DURATION
			end
		end
		local function hookCreator(humanoid, targetCharacter)
			local function checkExisting()
				local creator = humanoid:FindFirstChild("creator")
				if creator and creator:IsA("ObjectValue") then
					if creator.Value and creator.Value:IsA("Player") then
						checkAttack(creator.Value, targetCharacter)
					end
				end
			end
			checkExisting()
			humanoid.ChildAdded:Connect(function(child)
				if child.Name == "creator" and child:IsA("ObjectValue") then
					child.Changed:Connect(function()
						if child.Value and child.Value:IsA("Player") then
							checkAttack(child.Value, targetCharacter)
						end
					end)
					checkExisting()
				end
			end)
			local existing = humanoid:FindFirstChild("creator")
			if existing and existing:IsA("ObjectValue") then
				existing.Changed:Connect(function()
					if existing.Value and existing.Value:IsA("Player") then
						checkAttack(existing.Value, targetCharacter)
					end
				end)
			end
		end
		local function hookDPSAttacker(humanoid, targetCharacter)
			local function checkAttribute()
				local attackerId = humanoid:GetAttribute("LastDPSAttacker")
				if attackerId then
					local attacker = Players:GetPlayerByUserId(attackerId)
					if attacker then
						checkAttack(attacker, targetCharacter)
					end
				end
			end
			humanoid:GetAttributeChangedSignal("LastDPSAttacker"):Connect(checkAttribute)
			checkAttribute()
		end
		local function hookGCells(player)
			local function setup()
				local leaderstats = player:FindFirstChild("leaderstats")
				if not leaderstats then return end
				local gcells = leaderstats:FindFirstChild("GCells") or leaderstats:FindFirstChild("gcells")
				if not gcells or not gcells:IsA("IntValue") then return end
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
							changing[player] = false
							previousGCells[player] = prev
							return
						end
					end
					previousGCells[player] = newValue
				end)
			end
			setup()
			player.ChildAdded:Connect(function(child)
				if child.Name == "leaderstats" then
					task.wait(0.1)
					setup()
				end
			end)
		end
		local function hookCharacter(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if not humanoid then return end
			hookCreator(humanoid, character)
			hookDPSAttacker(humanoid, character)
		end
		local function cleanupPlayer(player)
			blockTimers[player] = nil
			killRewardFlags[player] = nil
			previousGCells[player] = nil
			changing[player] = nil
		end
		local function hookPlayer(player)
			hookGCells(player)
			player.CharacterAdded:Connect(function(character)
				task.spawn(function()
					hookCharacter(character)
				end)
			end)
			if player.Character then
				task.spawn(function()
					hookCharacter(player.Character)
				end)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			hookPlayer(player)
		end
		Players.PlayerAdded:Connect(hookPlayer)
		Players.PlayerRemoving:Connect(cleanupPlayer)
		print("[LevelGuard] Initialized - blocking rewards for players over level " .. LEVEL_THRESHOLD .. " attacking players under level " .. LEVEL_THRESHOLD)
	end
	local function initWaterBubbles()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")
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
		local function getHead(character)
			if not character then return nil end
			local head = character:FindFirstChild("FakeHead")
			if head and head:IsA("BasePart") then return head end
			head = character:FindFirstChild("Fakehead")
			if head and head:IsA("BasePart") then return head end
			head = character:FindFirstChild("Head")
			if head and head:IsA("BasePart") then return head end
			return nil
		end
		local function addBubbles(character)
			local head = getHead(character)
			if not head then return end
			-- Don't add if already exists
			if head:FindFirstChild(BUBBLES_NAME) then return end
			local bubbles = bubblesTemplate:Clone()
			bubbles.Name = BUBBLES_NAME
			bubbles.Parent = head
		end
		local function removeBubbles(character)
			local head = getHead(character)
			if not head then return end
			local bubbles = head:FindFirstChild(BUBBLES_NAME)
			if bubbles then
				bubbles.Parent = nil
			end
		end
		waterStateEvent.OnServerEvent:Connect(function(player, inWater)
			-- Validate the inWater parameter
			if type(inWater) ~= "boolean" then return end
			local character = player.Character
			if not character then return end
			if inWater then
				addBubbles(character)
			else
				removeBubbles(character)
			end
		end)
		print("[WaterBubbles] Initialized - bubbles will appear on characters when swimming")
	end
	local function initAttackHandler()
		local BeamSystemModule = ReplicatedStorage:FindFirstChild("BeamSystem")
		local BeamSystem = BeamSystemModule and pcall(require, BeamSystemModule) and require(BeamSystemModule) or nil
		local playerDebounces = {}
		local function getHumanoidAndPlayer(part)
			if part.Name == "AttackHitbox" or part.Name == "BeamHitbox" or part.Name == "PulseHitbox" or part:GetAttribute("MeleeHit") then
				return nil, nil
			end
			local character = part.Parent
			if not character then return nil, nil end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local player = Players:GetPlayerFromCharacter(character)
			return humanoid, player
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
		local function giveGCells(player, amount)
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end
			local gcells = leaderstats:FindFirstChild("GCells") or leaderstats:FindFirstChild("gcells")
			if gcells and gcells:IsA("IntValue") then
				if _G.GCellGuardAllow then _G.GCellGuardAllow(gcells, amount) end
				gcells.Value = gcells.Value + amount
			end
		end
		local function findSounds(character)
				local sounds = character:FindFirstChild("Sounds")
				if sounds then return sounds end
				local charScripts = character:FindFirstChild("CharacterScripts")
				if charScripts then
					sounds = charScripts:FindFirstChild("Sounds")
					if sounds then return sounds end
				end
				return nil
			end
		local function getGlowManager(character)
			local charScripts = character:FindFirstChild("CharacterScripts")
			if not charScripts then return nil end
			local module = charScripts:FindFirstChild("GlowManager")
			if not module then return nil end
			local ok, gm = pcall(require, module)
			if ok then return gm end
			return nil
		end
		local function playHitSound(character)
			local sounds = findSounds(character)
			if not sounds then return end
			local hitSound = sounds:FindFirstChild("HitSound")
			if not hitSound then return end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local clone = hitSound:Clone()
			clone.Parent = hrp
			clone.Looped = false
			clone:Play()
			clone.Ended:Connect(function() clone:Destroy() end)
		end
		local function playAttackAnimation(character, animName)
			local animations = character:FindFirstChild("Animations")
			if not animations then return end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end
			local animator = humanoid:FindFirstChild("Animator")
			if not animator then return end
			local anim = animations:FindFirstChild(animName)
			if anim then
				local track = animator:LoadAnimation(anim)
				track.Looped = false
				track:Play()
			end
		end
		local function getAnimName(remoteName)
			if remoteName == "Attack" then return "Attack1"
			elseif remoteName == "Beam" then return "Attack2"
			else return remoteName end
		end
		local function getDamage(character, damageStat)
			local damage = 10
			local stats = character:FindFirstChild("Stats")
			if stats then
				local dmgValue = stats:FindFirstChild(damageStat)
				if dmgValue then damage = dmgValue.Value end
			end
			return damage
		end
		local function enableHitParts(character, hitPlayers, player, damage, isOneShot)
			local hitPartConnections = {}
			local hitPartsEnabled = {}
			for _, folder in ipairs({character:FindFirstChild("HitParts"), character:FindFirstChild("HitParts2")}) do
				if folder then
					for _, part in ipairs(folder:GetDescendants()) do
						if part:IsA("BasePart") and not part:FindFirstChildWhichIsA("Script") then
							part.CanTouch = true
							table.insert(hitPartsEnabled, part)
							local conn = part.Touched:Connect(function(hit)
								local hitHumanoid, hitPlayer = getHumanoidAndPlayer(hit)
								if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
									hitPlayers[hitPlayer] = true
									setCreator(hitHumanoid, player)
									hitHumanoid:TakeDamage(damage)
									playHitSound(character)
									giveGCells(player, 25)
								end
							end)
							table.insert(hitPartConnections, conn)
						end
					end
				end
			end
			return hitPartConnections, hitPartsEnabled
		end
		local function disableHitParts(hitPartConnections, hitPartsEnabled)
			for _, conn in ipairs(hitPartConnections) do conn:Disconnect() end
			for _, part in ipairs(hitPartsEnabled) do
				if part.Parent then part.CanTouch = false end
			end
		end
		local function executeMeleeAttack(player, character, remote, remoteName, durationOverride)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local sizeX = remote:GetAttribute("HitboxSizeX") or 15
			local sizeY = remote:GetAttribute("HitboxSizeY") or 15
			local sizeZ = remote:GetAttribute("HitboxSizeZ") or 15
			local offsetX = remote:GetAttribute("HitboxOffsetX") or 0
			local offsetY = remote:GetAttribute("HitboxOffsetY") or 0
			local offsetZ = remote:GetAttribute("HitboxOffsetZ") or -10
			local duration = durationOverride or remote:GetAttribute("HitboxDuration") or 0.5
			local damageStat = remote:GetAttribute("DamageStat") or "DMG1"
			local damage = getDamage(character, damageStat)
			playAttackAnimation(character, getAnimName(remoteName))
			local hitbox = Instance.new("Part")
			hitbox.Name = "AttackHitbox"
			hitbox:SetAttribute("MeleeHit", true)
			hitbox.Size = Vector3.new(sizeX, sizeY, sizeZ)
			hitbox.Anchored = true
			hitbox.CanCollide = false
			hitbox.CanTouch = true
			hitbox.Transparency = 1
			hitbox.Color = Color3.fromRGB(255, 0, 0)
			hitbox.Material = Enum.Material.Neon
			hitbox.Parent = character
			hitbox.CFrame = hrp.CFrame * CFrame.new(offsetX, offsetY, offsetZ)
			local hitPlayers = {}
			local hitPartConnections, hitPartsEnabled = enableHitParts(character, hitPlayers, player, damage, true)
			local connection = hitbox.Touched:Connect(function(hit)
				local hitHumanoid, hitPlayer = getHumanoidAndPlayer(hit)
				if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
					hitPlayers[hitPlayer] = true
					setCreator(hitHumanoid, player)
					hitHumanoid:TakeDamage(damage)
					playHitSound(character)
					giveGCells(player, 25)
				end
			end)
			local startTime = tick()
			while tick() - startTime < duration do
				if not character.Parent or not character:FindFirstChild("HumanoidRootPart") then break end
				local overlapParams = OverlapParams.new()
				overlapParams.FilterDescendantsInstances = {character}
				overlapParams.FilterType = Enum.RaycastFilterType.Exclude
				local overlappingParts = workspace:GetPartsInPart(hitbox, overlapParams)
				for _, part in ipairs(overlappingParts) do
					local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
					if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer] then
						hitPlayers[hitPlayer] = true
						setCreator(hitHumanoid, player)
						hitHumanoid:TakeDamage(damage)
						playHitSound(character)
						giveGCells(player, 25)
					end
				end
				task.wait(0.05)
			end
			connection:Disconnect()
			hitbox:Destroy()
			disableHitParts(hitPartConnections, hitPartsEnabled)
		end
		local function executePulseAttack(player, character, remote, remoteName)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local sizeX = remote:GetAttribute("HitboxSizeX") or 50
			local sizeY = remote:GetAttribute("HitboxSizeY") or 50
			local sizeZ = remote:GetAttribute("HitboxSizeZ") or 50
			local duration = remote:GetAttribute("HitboxDuration") or 2
			local damageStat = remote:GetAttribute("DamageStat") or "DMG3"
			local maxSize = remote:GetAttribute("PulseMaxSize") or 500
			local tickInterval = remote:GetAttribute("PulseTickInterval") or 0.3
			local damage = getDamage(character, damageStat)
			playAttackAnimation(character, getAnimName(remoteName))
			local sounds = findSounds(character)
			if sounds then
				local beamSound = sounds:FindFirstChild("Beam")
				if beamSound then
					local clone = beamSound:Clone()
					clone.Parent = hrp
					clone.Looped = false
					clone:Play()
					clone.Ended:Connect(function() clone:Destroy() end)
				end
			end
			-- Pulse starts as a base hitbox like melee, then expands
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
			local hitPlayersOneShot = {}
			local hitPartConnections, hitPartsEnabled = enableHitParts(character, hitPlayersOneShot, player, damage, true)
			local startTime = tick()
			local numTicks = duration / tickInterval
			local damagePerTick = damage / numTicks
			local gcellsPerTick = 25 / numTicks
			local startSize = math.max(sizeX, sizeY, sizeZ)
			while tick() - startTime < duration do
				if not character.Parent or not character:FindFirstChild("HumanoidRootPart") then break end
				local progress = math.clamp((tick() - startTime) / duration, 0, 1)
				local currentSize = startSize + (maxSize - startSize) * progress
				pulsePart.Size = Vector3.new(currentSize, currentSize, currentSize)
				pulsePart.Transparency = progress
				pulsePart.CFrame = hrp.CFrame
				local hitThisTick = {}
				local overlapParams = OverlapParams.new()
				overlapParams.FilterDescendantsInstances = {character}
				overlapParams.FilterType = Enum.RaycastFilterType.Exclude
				local overlappingParts = workspace:GetPartsInPart(pulsePart, overlapParams)
				for _, part in ipairs(overlappingParts) do
					local hitHumanoid, hitPlayer = getHumanoidAndPlayer(part)
					if hitHumanoid and hitPlayer and hitPlayer ~= player and not hitThisTick[hitPlayer] then
						hitThisTick[hitPlayer] = true
						setCreator(hitHumanoid, player)
						hitHumanoid:TakeDamage(damagePerTick)
						playHitSound(character)
						giveGCells(player, gcellsPerTick)
					end
				end
				task.wait(tickInterval)
			end
			if pulsePart and pulsePart.Parent then pulsePart.Parent = nil end
			disableHitParts(hitPartConnections, hitPartsEnabled)
		end
		local function executeFirePulse(player, character, remote, remoteName)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local damageStat = remote:GetAttribute("DamageStat") or "DMG3"
			local damage = getDamage(character, damageStat)
			local windup = remote:GetAttribute("PulseWindup") or 0
			local pulseColor = remote:GetAttribute("PulseColor") or Color3.fromRGB(255, 120, 0)
			local pulseMaxSize = remote:GetAttribute("PulseMaxSize") or 300
			local pulseDuration = remote:GetAttribute("HitboxDuration") or 4
			playAttackAnimation(character, getAnimName(remoteName))
			local sounds = findSounds(character)
			if sounds then
				local pulseSound = sounds:FindFirstChild("Pulse")
				if pulseSound then
					local clone = pulseSound:Clone()
					clone.Parent = hrp
					clone.Looped = false
					clone:Play()
					clone.Ended:Connect(function() clone:Destroy() end)
				end
			end
			if windup > 0 then
				task.wait(windup)
			end
			if _G.FirePulse then
				_G.FirePulse(player, pulseColor, pulseMaxSize, pulseDuration, damage)
			end
		end
		local function executeBeamAttack(player, character, remote, remoteName, targetPos)
			if not BeamSystem then return end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local duration = remote:GetAttribute("BeamDuration") or remote:GetAttribute("HitboxDuration") or 4.7
			playAttackAnimation(character, getAnimName(remoteName))
			-- Charge time from the remote (drives the glow tween and the fire delay)
			local chargeTime = remote:GetAttribute("BeamChargeTime") or 0
			-- Start glow charge effect (GlowManager / BeamCharge)
			-- The glow tweens in over the charge duration instead of snapping instantly
			local glowManager = getGlowManager(character)
			if glowManager then
				glowManager.StartGlow(chargeTime)
			end
			-- Play beam sound immediately (not delayed by the charge-up)
			local sounds = findSounds(character)
			if sounds then
				local beamSound = sounds:FindFirstChild("Beam")
				if beamSound then
					local clone = beamSound:Clone()
					clone.Parent = hrp
					clone.Looped = false
					clone:Play()
					clone.Ended:Connect(function() clone:Destroy() end)
				end
			end
			-- Glow spikes if present
			local spikesFolder = character:FindFirstChild("Spikes")
			local sortedSpikes = {}
			local originalProperties = {}
			if spikesFolder then
				for _, child in ipairs(spikesFolder:GetChildren()) do
					if child:IsA("BasePart") then
						local number = tonumber(string.match(child.Name, "%d+"))
						if number then
							table.insert(sortedSpikes, {part = child, number = number})
							originalProperties[child] = {
								Material = child.Material,
								UsePartColor = child.UsePartColor
							}
						end
					end
				end
				table.sort(sortedSpikes, function(a, b) return a.number < b.number end)
			end
			-- Charge up the dorsal spikes progressively so they add up to the
			-- charge time: each dorsal takes chargeTime / count, so the glow
			-- sequence finishes exactly when the beam fires.
			if #sortedSpikes > 0 then
				local perSpikeDelay = 0.21
				if chargeTime > 0 then
					perSpikeDelay = chargeTime / #sortedSpikes
				end
				for _, spikeData in ipairs(sortedSpikes) do
					spikeData.part.Material = Enum.Material.Neon
					spikeData.part.UsePartColor = true
					task.wait(perSpikeDelay)
				end
			elseif chargeTime > 0 then
				-- No dorsal spikes (or none numbered): just wait out the charge time
				task.wait(chargeTime)
			end
			BeamSystem.ActivateBeam({
				character = character,
				player = player,
				initialTargetPosition = targetPos,
				duration = duration,
			})
		-- Reset spikes non-blocking after beam ends
			task.spawn(function()
				for i = #sortedSpikes, 1, -1 do
					local spike = sortedSpikes[i].part
					if originalProperties[spike] then
						spike.Material = originalProperties[spike].Material
						spike.UsePartColor = originalProperties[spike].UsePartColor
					end
					task.wait(0.1)
				end
				-- End glow charge effect
				if glowManager then
					glowManager.EndGlow()
				end
			end)
		end
		local function connectRemote(remote, remoteName)
			local attackType = remote:GetAttribute("AttackType")
			if not attackType then return end
			if attackType ~= "Melee" and attackType ~= "Pulse" and attackType ~= "Beam" and attackType ~= "FirePulse" and attackType ~= "BackBeam" then return end
			remote.OnServerEvent:Connect(function(player, ...)
				if not playerDebounces[player] then playerDebounces[player] = {} end
				if playerDebounces[player][remote] then return end
				playerDebounces[player][remote] = true
				local char = player.Character
				if not char then
					playerDebounces[player][remote] = nil
					return
				end
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then
					playerDebounces[player][remote] = nil
					return
				end
				if attackType == "Melee" then
					executeMeleeAttack(player, char, remote, remoteName)
				elseif attackType == "Pulse" then
					executePulseAttack(player, char, remote, remoteName)
				elseif attackType == "Beam" then
					executeBeamAttack(player, char, remote, remoteName, ...)
				elseif attackType == "FirePulse" then
					executeFirePulse(player, char, remote, remoteName)
				elseif attackType == "BackBeam" then
					-- BackBeam: start glow, wait windup, then melee attack
					local glowManager = getGlowManager(char)
					if glowManager then
						glowManager.StartGlow()
					end
					local windup = remote:GetAttribute("BackBeamWindup") or 0
					if windup > 0 then
						task.wait(windup)
					end
					local activeDuration = remote:GetAttribute("BackBeamActive") or remote:GetAttribute("HitboxDuration") or 0.5
					executeMeleeAttack(player, char, remote, remoteName, activeDuration)
					if glowManager then
						glowManager.EndGlow()
					end
				end
				playerDebounces[player][remote] = nil
			end)
		end
		local function scanCharacter(character)
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("RemoteEvent") and descendant:GetAttribute("AttackType") then
					connectRemote(descendant, descendant.Name)
				end
			end
		end
		local function setupPlayer(player)
			player.CharacterAdded:Connect(function(character)
				scanCharacter(character)
				character.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("RemoteEvent") and descendant:GetAttribute("AttackType") then
						connectRemote(descendant, descendant.Name)
					end
				end)
			end)
			if player.Character then
				scanCharacter(player.Character)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			setupPlayer(player)
		end
		Players.PlayerAdded:Connect(setupPlayer)
		Players.PlayerRemoving:Connect(function(player)
			playerDebounces[player] = nil
		end)
		print("[AttackHandler] Initialized - centralized attack handling active")
	end
	task.spawn(initCombat)
	task.spawn(initAtomicBreath)
	task.spawn(initLevelGuard)
	task.spawn(initWaterBubbles)
	task.spawn(initPulse)
	task.spawn(initAttackHandler)
end
return Combat