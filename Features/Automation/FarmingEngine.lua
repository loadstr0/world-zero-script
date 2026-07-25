return function()
	local Engine = {}

	local activeLoops = {}
	local movementWarnings = {}
	local rotationCursors = {}
	local lastSlotAttempts = {}
	local lastDodgeAttempts = {}
	local lastHealAttempts = {}
	local farmSprinting = {}
	local boostedCharacters = {}
	local speedBoostWarnings = {}
	local damageListeners = {}
	local recentDamage = {}
	local fatalStatusWarnings = {}
	local lastQuestClaims = {}
	local visitedCollectibles = {}
	local lastWorldTravel = {}
	local automationDecisions = {}
	local lastLoopWarnings = {}

	local SPEED_MULTIPLIER_KEY = "WORLDZERO_AUTOMATION"

	local SPECIAL_SLOT_ORDER = {
		"Ultimate",
		"Skill1",
		"Skill2",
		"Skill3",
		"Skill4",
		"Primary",
	}

	local UTILITY_SLOTS = {
		Dodge = true,
		Sheath = true,
		SwapPerk = true,
	}

	function Engine.GetOptions(runtime, rangeOverride)
		local configuredRange = tonumber(runtime.State:Get("Farming.TargetRange", 120)) or 120

		return {
			Mode = runtime.State:Get("Farming.TargetMode", "Nearest"),
			Range = math.min(tonumber(rangeOverride) or configuredRange, configuredRange),
			BossOnly = runtime.State:Get("Farming.BossOnly", false),
			EliteOnly = runtime.State:Get("Farming.EliteOnly", false),
			NameFilter = runtime.State:Get("Farming.NameFilter", ""),
			IncludeOwned = false,
		}
	end

	local function refreshDescriptor(runtime, target, descriptor)
		if typeof(target) ~= "Instance" or type(descriptor) ~= "table" then
			return nil, "invalid_target_descriptor"
		end

		local root = runtime.Game.GetRootPart()
		local targetPart = runtime.MobsAPI.GetTargetPart(target)
		local position = targetPart and targetPart.Position or descriptor.Position

		if not root or typeof(position) ~= "Vector3" then
			return nil, "target_position_unavailable"
		end

		descriptor.Position = position
		descriptor.Distance = (position - root.Position).Magnitude
		return descriptor
	end

	function Engine.GetTarget(runtime, rangeOverride)
		local target, descriptorOrError = runtime.MobsAPI.SelectTarget(Engine.GetOptions(runtime, rangeOverride))

		if not target then
			return nil, descriptorOrError
		end

		local descriptor, descriptorError = refreshDescriptor(runtime, target, descriptorOrError)

		if not descriptor then
			return nil, descriptorError
		end

		return target, descriptor
	end

	function Engine.GetQuestTarget(runtime, questState, rangeOverride)
		if
			not questState
			or questState.ObjectiveType ~= "KillMob"
			or type(questState.AllowedMobNames) ~= "table"
			or #questState.AllowedMobNames == 0
		then
			return nil, "quest_has_no_mob_target"
		end

		local target, descriptorOrError = runtime.MobsAPI.SelectTarget({
			Mode = "Nearest",
			Range = math.min(
				tonumber(rangeOverride) or math.huge,
				tonumber(runtime.State:Get("Quests.SearchRange", 500)) or 500
			),
			BossOnly = false,
			EliteOnly = false,
			NameFilter = table.concat(questState.AllowedMobNames, ","),
			ExactNames = questState.AllowedMobNames,
			IncludeOwned = false,
		})

		if not target then
			return nil, descriptorOrError
		end

		local descriptor, descriptorError = refreshDescriptor(runtime, target, descriptorOrError)

		if not descriptor then
			return nil, descriptorError
		end

		return target, descriptor
	end

	function Engine.GetActiveTarget(runtime, rangeOverride)
		if runtime.State:Get("Quests.Enabled", false) and runtime.QuestsAPI then
			local currentWorldOrder = runtime.TeleportAPI.GetCurrentWorldOrder()
			local questState = runtime.QuestsAPI.GetCurrent(currentWorldOrder)
			local target, descriptor = Engine.GetQuestTarget(runtime, questState, rangeOverride)

			if target and descriptor then
				return target, descriptor
			end
		end

		if runtime.State:Get("Farming.Enabled", false) then
			return Engine.GetTarget(runtime, rangeOverride)
		end

		return nil, "automation_has_no_mob_target"
	end

	function Engine.GetStatus(runtime)
		return automationDecisions[runtime]
	end

	function Engine.IsEnabled(runtime)
		return runtime.State:Get("Farming.Enabled", false)
			or runtime.State:Get("Quests.Enabled", false)
			or runtime.State:Get("Loot.DropsEnabled", false)
			or runtime.State:Get("Loot.ChestsEnabled", false)
	end

	function Engine.Reconcile(runtime)
		local provider = runtime.AutomationTargetProvider

		if Engine.IsEnabled(runtime) then
			if provider then
				runtime.Actions.SetTargetProvider(provider)
			end

			Engine.Start(runtime, provider)
		elseif provider then
			runtime.Actions.ClearTargetProvider(provider)
			Engine.Stop(runtime)
			Engine.ClearSpeedBoost(runtime)
		end
	end

	function Engine.StopSprint(runtime)
		if farmSprinting[runtime] then
			runtime.Actions.StopSprint()
			farmSprinting[runtime] = nil
		end
	end

	function Engine.Stop(runtime)
		runtime.Navigator.Stop()
		Engine.StopSprint(runtime)
	end

	function Engine.ClearSpeedBoost(runtime)
		local boosted = boostedCharacters[runtime]

		if boosted and boosted.Character then
			runtime.Walkspeed.RemoveMultiplier(SPEED_MULTIPLIER_KEY, boosted.Character)
		end

		boostedCharacters[runtime] = nil
		speedBoostWarnings[runtime] = nil
	end

	local function updateSpeedBoost(runtime, statusState)
		local character = runtime.Game.GetCharacter()
		local boosted = boostedCharacters[runtime]
		local enabled = runtime.State:Get("Farming.SpeedBoostEnabled", false)
		local multiplier = tonumber(runtime.State:Get("Farming.SpeedBoostMultiplier", 1.5)) or 1.5
		local statusSpeedMultiplier = tonumber(statusState and statusState.WalkspeedMultiplier)

		if
			runtime.State:Get("Farming.SpeedBoostCounterSlows", true)
			and statusSpeedMultiplier
			and statusSpeedMultiplier > 0
			and statusSpeedMultiplier < 1
		then
			multiplier = math.min(3, multiplier / statusSpeedMultiplier)
		end

		if boosted and (boosted.Character ~= character or not enabled) then
			Engine.ClearSpeedBoost(runtime)
			boosted = nil
		end

		if not enabled or not character or (boosted and boosted.Multiplier == multiplier) then
			return
		end

		local previousFailure = speedBoostWarnings[runtime]

		if previousFailure and previousFailure.Character == character and previousFailure.Multiplier == multiplier then
			return
		end

		local applied, applyError = runtime.Walkspeed.ApplyMultiplier(SPEED_MULTIPLIER_KEY, multiplier, character)

		if applied then
			boostedCharacters[runtime] = {
				Character = character,
				Multiplier = multiplier,
			}
			speedBoostWarnings[runtime] = nil
		else
			speedBoostWarnings[runtime] = {
				Character = character,
				Multiplier = multiplier,
			}
			runtime.UI:Notify("Automation speed", "Walkspeed multiplier was rejected: " .. tostring(applyError), 5, 0)
		end
	end

	local function disconnectDamageListener(runtime)
		local listener = damageListeners[runtime]

		if listener and listener.Connection then
			local connection = listener.Connection
			local disconnect = connection.Disconnect or connection.disconnect or connection.Destroy

			if type(disconnect) == "function" then
				pcall(disconnect, connection)
			end
		end

		damageListeners[runtime] = nil
		recentDamage[runtime] = nil
	end

	local function updateDamageListener(runtime)
		local character = runtime.Game.GetCharacter()
		local listener = damageListeners[runtime]

		if listener and listener.Character ~= character then
			disconnectDamageListener(runtime)
			listener = nil
		end

		if listener or not character then
			return
		end

		local connection = runtime.Health.ObserveHits(function(attacker, amount)
			recentDamage[runtime] = {
				At = os.clock(),
				Attacker = attacker,
				Amount = tonumber(amount) or 0,
			}
		end, character)

		if connection then
			damageListeners[runtime] = {
				Character = character,
				Connection = connection,
			}
		end
	end

	local function getPreferredDistance(runtime, adapter)
		local stoppingDistance = tonumber(runtime.State:Get("Farming.StopDistance", 10)) or 10

		if
			not runtime.State:Get("Farming.AdaptiveKiting", true)
			or not adapter
			or type(adapter.Describe) ~= "function"
		then
			return stoppingDistance, false
		end

		local ok, metadata = pcall(adapter.Describe)
		local primaryRange = ok
				and type(metadata) == "table"
				and type(metadata.Primary) == "table"
				and tonumber(metadata.Primary.Range)
			or nil

		if not primaryRange or primaryRange < 30 then
			return stoppingDistance, false
		end

		local kiteDistance = tonumber(runtime.State:Get("Farming.KiteDistance", 28)) or 28
		local attackRange = tonumber(runtime.State:Get("Farming.AttackRange", 45)) or 45
		local preferred = math.min(kiteDistance, primaryRange - 5, attackRange - 3)

		return math.max(stoppingDistance, preferred), true
	end

	local function addMovementMode(runtime, options)
		options.MovementMode = runtime.State:Get("Farming.MovementMode", "Pathfinding")
		options.CFrameStepDistance = tonumber(runtime.State:Get("Farming.CFrameStepDistance", 18)) or 18
		options.ZeroVelocity = runtime.State:Get("Farming.CFrameZeroVelocity", true)
		return options
	end

	local function approachTarget(runtime, descriptor)
		local distance = tonumber(descriptor and descriptor.Distance)

		if
			not runtime.State:Get("Farming.AutoApproach", true)
			or not distance
			or typeof(descriptor.Position) ~= "Vector3"
		then
			return false
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		local stopDistance, canKite = getPreferredDistance(runtime, adapter)

		if canKite and distance < stopDistance - 3 then
			local playerSpeed = tonumber(runtime.Walkspeed.Get())
			local targetSpeed = tonumber(runtime.Walkspeed.Get(descriptor.Model))

			if playerSpeed and (not targetSpeed or playerSpeed >= targetSpeed * 0.9) then
				runtime.Navigator.RetreatFrom(
					descriptor.Position,
					math.max(8, stopDistance - distance + 6),
					addMovementMode(runtime, {
						Owner = "CombatKite",
						AutoJump = runtime.State:Get("Farming.AutoJump", true),
						RepathInterval = tonumber(runtime.State:Get("Farming.RepathInterval", 1.25)) or 1.25,
						StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
						TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
					})
				)
				return true
			end
		end

		if runtime.State:Get("Farming.AutoSprint", true) and distance > stopDistance + 5 then
			if not farmSprinting[runtime] then
				runtime.Actions.Sprint()
				farmSprinting[runtime] = true
			end
		elseif farmSprinting[runtime] then
			runtime.Actions.StopSprint()
			farmSprinting[runtime] = nil
		end

		local moved, movementError = runtime.Navigator.MoveTo(
			descriptor.Position,
			addMovementMode(runtime, {
				Owner = "Combat",
				StopDistance = stopDistance,
				AutoJump = runtime.State:Get("Farming.AutoJump", true),
				RepathInterval = tonumber(runtime.State:Get("Farming.RepathInterval", 1.25)) or 1.25,
				StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
				TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
			})
		)

		if not moved and movementError == "movement_controller_unavailable" and not movementWarnings[runtime] then
			movementWarnings[runtime] = true
			runtime.UI:Notify(
				"Auto approach",
				"This character has no client Humanoid movement controller. Targeting and attacks remain active.",
				5,
				0
			)
		end

		return moved
	end

	local function buildRotation(runtime)
		local available = {}
		local extras = {}

		for _, skill in ipairs(runtime.Skills.List()) do
			local slot = skill.Slot

			if slot and not UTILITY_SLOTS[slot] then
				available[slot] = true

				local preferred = false

				for _, preferredSlot in ipairs(SPECIAL_SLOT_ORDER) do
					if slot == preferredSlot then
						preferred = true
						break
					end
				end

				if not preferred then
					table.insert(extras, slot)
				end
			end
		end

		table.sort(extras)
		local result = {}

		for _, slot in ipairs(SPECIAL_SLOT_ORDER) do
			if available[slot] then
				table.insert(result, slot)
			end
		end

		for _, slot in ipairs(extras) do
			table.insert(result, slot)
		end

		return result
	end

	local function canAttemptSlot(runtime, adapter, slot)
		if slot == "Ultimate" and not runtime.State:Get("Farming.UseUltimate", true) then
			return false
		end

		if slot == "Ultimate" and runtime.Energy.IsFull() ~= true then
			return false
		end

		local attempts = lastSlotAttempts[runtime] or {}
		lastSlotAttempts[runtime] = attempts
		local retryInterval = tonumber(runtime.State:Get("Farming.SkillRetryInterval", 0.6)) or 0.6

		if attempts[slot] and os.clock() - attempts[slot] < retryInterval then
			return false
		end

		if adapter and type(adapter.CanUse) == "function" then
			local ok, canUse = pcall(adapter.CanUse, slot)
			return ok and canUse == true
		end

		return runtime.Actions.IsOnCooldown(slot) ~= true
	end

	local function attemptSlot(runtime, adapter, slot)
		if not canAttemptSlot(runtime, adapter, slot) then
			return false
		end

		lastSlotAttempts[runtime][slot] = os.clock()

		if adapter and type(adapter.Use) == "function" then
			pcall(adapter.Use, slot)
		elseif slot == "Primary" and adapter and type(adapter.UsePrimary) == "function" then
			pcall(adapter.UsePrimary)
		else
			pcall(runtime.Actions.UseSkill, slot)
		end

		return true
	end

	local function useFarmAttack(runtime, target, descriptor)
		local distance = tonumber(descriptor and descriptor.Distance)
		local attackRange = tonumber(runtime.State:Get("Farming.AttackRange", 45)) or 45

		if
			not runtime.State:Get("Farming.AutoAttack", true)
			or not distance
			or distance > attackRange
			or runtime.Actions.IsBusy() == true
		then
			return false
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()

		if adapter and type(adapter.EnsureUnsheathed) == "function" then
			local ok, ready = pcall(adapter.EnsureUnsheathed)

			if not ok or not ready then
				return false
			end
		end

		if runtime.State:Get("Combat.AutoAim", true) then
			runtime.Actions.AimAtTarget(target, tonumber(runtime.State:Get("Combat.AimDuration", 0.2)) or 0.2)
		end

		local mode = runtime.State:Get("Farming.RotationMode", "Full Rotation")

		if mode == "Primary Only" then
			return attemptSlot(runtime, adapter, "Primary")
		elseif mode == "Selected Slot" then
			return attemptSlot(runtime, adapter, runtime.State:Get("Farming.AttackSlot", "Primary"))
		end

		local rotation = buildRotation(runtime)

		if #rotation == 0 then
			return attemptSlot(runtime, adapter, "Primary")
		end

		local cursor = rotationCursors[runtime] or 1

		for offset = 0, #rotation - 1 do
			local index = ((cursor + offset - 1) % #rotation) + 1
			local slot = rotation[index]

			if attemptSlot(runtime, adapter, slot) then
				rotationCursors[runtime] = (index % #rotation) + 1
				return true
			end
		end

		return false
	end

	function Engine.GetHealthRatio(runtime)
		local health = runtime.Health.GetState()

		if health then
			return tonumber(health.Ratio) or 1
		end

		local humanoid = runtime.Game.GetHumanoid()

		if humanoid and humanoid.MaxHealth > 0 then
			return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		end

		return 1
	end

	function Engine.GetSurvivalState(runtime)
		local health = runtime.Health.GetState()

		if health then
			local healthRatio = tonumber(health.Ratio) or 1

			return {
				HealthRatio = healthRatio,
				ProtectionRatio = tonumber(health.ProtectionRatio) or healthRatio,
				Barrier = tonumber(health.Barrier) or 0,
			}
		end

		local ratio = Engine.GetHealthRatio(runtime)

		return {
			HealthRatio = ratio,
			ProtectionRatio = ratio,
			Barrier = 0,
		}
	end

	local function getNavigationOptions(runtime)
		return addMovementMode(runtime, {
			AutoJump = runtime.State:Get("Farming.AutoJump", true),
			RepathInterval = tonumber(runtime.State:Get("Farming.RepathInterval", 1.25)) or 1.25,
			StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
			TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
		})
	end

	local function moveToPoint(runtime, position, stopDistance, owner)
		if not runtime.State:Get("Farming.AutoApproach", true) then
			return false, "auto_approach_disabled"
		elseif typeof(position) ~= "Vector3" then
			return false, "invalid_target_position"
		end

		stopDistance = tonumber(stopDistance) or 0
		local root = runtime.Game.GetRootPart()
		local distance = root and (root.Position - position).Magnitude or 0

		if runtime.State:Get("Farming.AutoSprint", true) and distance > stopDistance + 5 then
			if not farmSprinting[runtime] then
				runtime.Actions.Sprint()
				farmSprinting[runtime] = true
			end
		else
			Engine.StopSprint(runtime)
		end

		local options = getNavigationOptions(runtime)
		options.StopDistance = stopDistance
		options.Owner = owner or "Automation"
		return runtime.Navigator.MoveTo(position, options)
	end

	local function getCollectible(runtime, hasCombatTarget)
		local dropsEnabled = runtime.State:Get("Loot.DropsEnabled", false)
		local chestsEnabled = runtime.State:Get("Loot.ChestsEnabled", false)

		if not dropsEnabled and not chestsEnabled then
			return nil
		end

		local range = tonumber(runtime.State:Get("Loot.CollectionRange", 120)) or 120

		if hasCombatTarget then
			range = math.min(range, tonumber(runtime.State:Get("Loot.CombatPriorityRange", 35)) or 35)
		end

		local visited = visitedCollectibles[runtime]

		if not visited then
			visited = {}
			visitedCollectibles[runtime] = visited
		end

		local now = os.clock()

		for instance, expiresAt in pairs(visited) do
			if not instance.Parent or (tonumber(expiresAt) or 0) <= now then
				visited[instance] = nil
			end
		end

		local drop = nil
		local chest = nil

		if dropsEnabled and runtime.DropsAPI then
			local drops = runtime.DropsAPI.List(range)
			drop = drops[1]
		end

		if chestsEnabled and runtime.ChestsAPI then
			local chests = runtime.ChestsAPI.List(range)

			for _, candidate in ipairs(chests) do
				if not visited[candidate.Instance] then
					chest = candidate
					break
				end
			end
		end

		if drop and chest then
			local dropDistance = tonumber(drop.Distance) or math.huge
			local chestDistance = tonumber(chest.Distance) or math.huge
			return dropDistance <= chestDistance and drop or chest
		end

		return drop or chest
	end

	local function collect(runtime, candidate)
		if not candidate then
			return false
		end

		local isValid = candidate.Kind == "Chest" and runtime.ChestsAPI and runtime.ChestsAPI.IsValid(candidate)
			or candidate.Kind == "Drop" and runtime.DropsAPI and runtime.DropsAPI.IsValid(candidate)

		if not isValid then
			return false
		end

		local stopDistance = candidate.Kind == "Chest" and 8 or 2.5
		local moved, movementError = moveToPoint(runtime, candidate.Position, stopDistance, "Loot")

		if not moved then
			return false, movementError
		end

		if candidate.Kind == "Chest" and (tonumber(candidate.Distance) or math.huge) <= stopDistance + 1 then
			local visited = visitedCollectibles[runtime] or {}
			visitedCollectibles[runtime] = visited
			visited[candidate.Instance] = os.clock() + 8
		end

		return true
	end

	local function claimQuest(runtime, questState)
		if not questState or not questState.ReadyToClaim then
			return false
		end

		if not runtime.State:Get("Quests.AutoClaim", true) then
			return true
		end

		local now = os.clock()
		local previous = lastQuestClaims[runtime]

		if previous and previous.ID == questState.ID and now - previous.At < 5 then
			return true
		end

		lastQuestClaims[runtime] = {
			ID = questState.ID,
			At = now,
		}

		local ok, claimError = runtime.QuestsAPI.Claim(questState.ID)

		if ok then
			runtime.UI:Notify("Quest automation", "Claim request sent for " .. questState.Name .. ".", 4, 0)
		else
			runtime.UI:Notify("Quest automation", "Claim failed: " .. tostring(claimError), 5, 0)
		end

		return true
	end

	local function queueBootstrapAfterTeleport(runtime)
		if not runtime.Executor.QueueOnTeleport then
			return false, "queue_on_teleport_unavailable"
		end

		local bootstrapUrl = runtime.Context.Base
			.. "Bootstrap.lua?cache="
			.. tostring(os.time())
			.. tostring(math.random(1000, 9999))
		local source = "loadstring(game:HttpGet(" .. string.format("%q", bootstrapUrl) .. "))()"
		local ok, queueError = pcall(runtime.Executor.QueueOnTeleport, source)

		return ok, ok and nil or "queue_on_teleport_failed:" .. tostring(queueError)
	end

	local function routeQuest(runtime, questState, currentWorldOrder)
		if not questState then
			return false, "no_active_quest"
		end

		if
			runtime.State:Get("Quests.AutoWorldTravel", true)
			and questState.LinkedWorld
			and currentWorldOrder
			and questState.LinkedWorld ~= currentWorldOrder
		then
			local previous = lastWorldTravel[runtime]
			local now = os.clock()

			if previous and previous.WorldOrder == questState.LinkedWorld and now - previous.At < 20 then
				return true, "world_travel_pending"
			end

			local world, worldError = runtime.TeleportAPI.FindOpenWorldByOrder(questState.LinkedWorld)

			if not world then
				return false, worldError
			end

			local queued, queueError = queueBootstrapAfterTeleport(runtime)
			local traveled, travelError = runtime.TeleportAPI.ToWorld(world.ID)

			if not traveled then
				return false, travelError
			end

			lastWorldTravel[runtime] = {
				WorldOrder = questState.LinkedWorld,
				At = now,
			}
			runtime.UI:Notify(
				"Quest world travel",
				"Traveling to "
					.. tostring(world.Name)
					.. (
						queued and "; automation is queued to resume."
						or (". Re-execute after arrival because " .. tostring(queueError))
					),
				7,
				0
			)
			return true, "world_travel_requested"
		end

		if not runtime.State:Get("Quests.RouteToArea", true) then
			return false, "quest_routing_disabled"
		elseif not questState.Location then
			return false, questState.LocationError or "quest_location_unavailable"
		end

		local locationRange = tonumber(questState.Location.Range) or 15
		local stopDistance = math.min(25, math.max(10, locationRange))

		return moveToPoint(runtime, questState.Location.Position, stopDistance, "Quest")
	end

	local function dodgeThreat(runtime, adapter, threat, healthRatio, statusState)
		local damage = recentDamage[runtime]
		local reactionWindow = tonumber(runtime.State:Get("Farming.DamageReactionWindow", 1.25)) or 1.25
		local dodgeThreshold = (tonumber(runtime.State:Get("Farming.DodgeHealthThreshold", 70)) or 70) / 100
		local damagedRecently = runtime.State:Get("Farming.DodgeAfterDamage", true)
			and damage
			and os.clock() - (tonumber(damage.At) or 0) <= reactionWindow

		if
			not runtime.State:Get("Farming.AutoDodge", true)
			or (statusState and statusState.SkillsBlocked)
			or ((not threat or (tonumber(threat.Count) or 0) <= 0) and not damagedRecently)
			or ((not threat or (tonumber(threat.AttackingCount) or 0) <= 0) and (tonumber(healthRatio) or 1) > dodgeThreshold and not damagedRecently)
			or runtime.Actions.IsBusy() == true
		then
			return false
		end

		local lastAttempt = lastDodgeAttempts[runtime] or 0

		if os.clock() - lastAttempt < 0.5 then
			return false
		end

		if runtime.Actions.IsOnCooldown("Dodge") == true then
			return false
		end

		lastDodgeAttempts[runtime] = os.clock()

		if adapter and type(adapter.UseDodge) == "function" then
			pcall(adapter.UseDodge)
		else
			pcall(runtime.Actions.UseSkill, "Dodge")
		end

		return true
	end

	local function useEmergencyHeal(runtime, healthRatio, statusState)
		healthRatio = tonumber(healthRatio) or 1
		local threshold = tonumber(runtime.State:Get("Farming.HealItemHealthThreshold", 40)) or 40

		if runtime.State:Get("Farming.DebuffSurvival", true) and statusState and statusState.HasDamageOverTime then
			threshold = math.max(threshold, tonumber(runtime.State:Get("Farming.DebuffSafetyThreshold", 60)) or 60)
		end

		if
			not runtime.State:Get("Farming.AutoHealItem", false)
			or (statusState and statusState.HealingBlocked)
			or healthRatio > threshold / 100
		then
			return false
		end

		if statusState and statusState.HasHealingOverTime then
			local projectedRatio = healthRatio
				+ math.max(
						0,
						(tonumber(statusState.HealingPerSecond) or 0) - (tonumber(statusState.DamagePerSecond) or 0)
					)
					* 2

			if projectedRatio > threshold / 100 then
				return false
			end
		end

		local itemName = tostring(runtime.State:Get("Farming.HealItemName", ""))

		if itemName == "" then
			return false
		end

		local retryInterval = tonumber(runtime.State:Get("Farming.HealItemRetryInterval", 5)) or 5
		local lastAttempt = lastHealAttempts[runtime] or 0

		if os.clock() - lastAttempt < retryInterval then
			return false
		end

		lastHealAttempts[runtime] = os.clock()
		pcall(runtime.Actions.UseQuickItem, itemName)
		return true
	end

	local function handleDefense(runtime, statusState)
		local threat = runtime.MobsAPI.GetThreatState(tonumber(runtime.State:Get("Farming.ThreatRadius", 25)) or 25)
		local survival = Engine.GetSurvivalState(runtime)
		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		useEmergencyHeal(runtime, survival.HealthRatio, statusState)
		dodgeThreat(runtime, adapter, threat, survival.ProtectionRatio, statusState)
		local retreatThreshold = tonumber(runtime.State:Get("Farming.RetreatHealthThreshold", 30)) or 30

		if
			runtime.State:Get("Farming.DebuffSurvival", true)
			and statusState
			and (statusState.HasDamageOverTime or statusState.HasDefenseDebuff)
		then
			retreatThreshold =
				math.max(retreatThreshold, tonumber(runtime.State:Get("Farming.DebuffSafetyThreshold", 60)) or 60)
		end

		if
			runtime.State:Get("Farming.EmergencyRetreat", true)
			and threat
			and threat.Nearest
			and not (statusState and statusState.MovementBlocked)
			and (tonumber(survival.ProtectionRatio) or 1) <= retreatThreshold / 100
		then
			local retreatOptions = getNavigationOptions(runtime)
			retreatOptions.Owner = "EmergencyRetreat"
			runtime.Navigator.RetreatFrom(
				threat.Nearest.Position,
				tonumber(runtime.State:Get("Farming.RetreatDistance", 35)) or 35,
				retreatOptions
			)
			return true
		end

		return false
	end

	local function updateFatalStatusWarning(runtime, statusState)
		if statusState and statusState.HasFatalStatus then
			if not fatalStatusWarnings[runtime] then
				fatalStatusWarnings[runtime] = true
				runtime.UI:Notify(
					"Death Mark detected",
					"The supplied status source says Death Mark kills when its countdown ends. No verified client cleanse exists, so automation will not pretend Dodge or retreat can remove it.",
					8,
					0
				)
			end
		else
			fatalStatusWarnings[runtime] = nil
		end
	end

	local function getFrozenTeammate(runtime)
		if not runtime.State:Get("Farming.AutoThawFreezeTag", true) then
			return nil
		end

		local root = runtime.Game.GetRootPart()

		if not root then
			return nil
		end

		local nearest = nil
		local nearestDistance = tonumber(runtime.State:Get("Farming.FreezeTagRescueRange", 120)) or 120
		local localPlayer = runtime.Game.GetLocalPlayer()

		for _, player in ipairs(runtime.Context.Services.Players:GetPlayers()) do
			if player ~= localPlayer then
				local character = player.Character
				local targetRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)

				if targetRoot then
					local frozen = runtime.Status.Has("FrozenFreezeTag", character)

					if frozen then
						local distance = (targetRoot.Position - root.Position).Magnitude

						if distance < nearestDistance then
							nearestDistance = distance
							nearest = {
								Player = player,
								Character = character,
								Position = targetRoot.Position,
								Distance = distance,
							}
						end
					end
				end
			end
		end

		return nearest
	end

	local function rescueFrozenTeammate(runtime)
		local teammate = getFrozenTeammate(runtime)

		if not teammate then
			return false
		end

		if (tonumber(teammate.Distance) or math.huge) >= 12 then
			local moved = runtime.Navigator.MoveTo(
				teammate.Position,
				addMovementMode(runtime, {
					Owner = "Rescue",
					StopDistance = 10,
					AutoJump = runtime.State:Get("Farming.AutoJump", true),
					RepathInterval = 0.5,
					StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
					TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
				})
			)

			return moved == true
		else
			Engine.StopSprint(runtime)
			runtime.Navigator.Stop()
			return true
		end
	end

	function Engine.Start(runtime, targetProvider)
		if activeLoops[runtime] then
			return
		end

		local loopToken = {}
		activeLoops[runtime] = loopToken

		task.spawn(function()
			local loopOk, loopError = xpcall(function()
				while not runtime.Stopped and activeLoops[runtime] == loopToken and Engine.IsEnabled(runtime) do
					local statusState = runtime.Status.GetAutomationState()
						or {
							MovementBlocked = false,
							SkillsBlocked = false,
						}
					updateSpeedBoost(runtime, statusState)
					updateDamageListener(runtime)
					updateFatalStatusWarning(runtime, statusState)
					local retreating = handleDefense(runtime, statusState)

					if statusState.MovementBlocked then
						runtime.Navigator.Stop()
						Engine.StopSprint(runtime)
					else
						local rescuing = not retreating and rescueFrozenTeammate(runtime)

						if not rescuing then
							local questState = nil
							local currentWorldOrder = nil

							if runtime.State:Get("Quests.Enabled", false) and runtime.QuestsAPI then
								currentWorldOrder = runtime.TeleportAPI.GetCurrentWorldOrder()
								questState = runtime.QuestsAPI.GetCurrent(currentWorldOrder)
							end

							local questHandled = claimQuest(runtime, questState)
							local questTarget = nil
							local questDescriptor = nil

							if not questHandled and questState and questState.ObjectiveType == "KillMob" then
								questTarget, questDescriptor = Engine.GetQuestTarget(runtime, questState)
							end

							local farmTarget = nil
							local farmDescriptor = nil

							if not questHandled and runtime.State:Get("Farming.Enabled", false) then
								farmTarget, farmDescriptor = Engine.GetTarget(runtime)
							end

							local target = questTarget or farmTarget
							local descriptor = questDescriptor or farmDescriptor

							local collectible = not retreating
									and not questHandled
									and getCollectible(runtime, target ~= nil or questState ~= nil)
								or nil
							local collecting, collectionError = collect(runtime, collectible)
							local routing = false
							local routeError = nil

							if
								not collecting
								and not retreating
								and not questHandled
								and questState
								and not questTarget
							then
								routing, routeError = routeQuest(runtime, questState, currentWorldOrder)
							end

							if target and descriptor then
								if not retreating and not collecting and not routing then
									approachTarget(runtime, descriptor)
								end

								if not statusState.SkillsBlocked then
									useFarmAttack(runtime, target, descriptor)
								end
							elseif not retreating and not collecting and not routing and not questHandled then
								Engine.Stop(runtime)
							end

							automationDecisions[runtime] = {
								Quest = questState,
								QuestTarget = questDescriptor,
								FarmTarget = farmDescriptor,
								Collectible = collectible,
								Collecting = collecting == true,
								CollectionError = collectionError,
								Routing = routing == true,
								RouteError = routeError,
								CurrentWorldOrder = currentWorldOrder,
								Navigator = runtime.Navigator.GetState(),
							}
						end
					end

					local updateInterval = tonumber(runtime.State:Get("Farming.UpdateInterval", 0.2)) or 0.2
					task.wait(math.max(0.03, updateInterval))
				end
			end, function(runError)
				return tostring(runError)
			end)

			if not loopOk and not runtime.Stopped then
				local now = os.clock()
				local previous = lastLoopWarnings[runtime]
				local shouldNotify = not previous or previous.Message ~= loopError or now - previous.At >= 15

				lastLoopWarnings[runtime] = {
					Message = loopError,
					At = now,
				}

				if shouldNotify then
					pcall(function()
						runtime.UI:Notify(
							"Automation recovered",
							"The movement loop stopped after an error and will restart if automation is still enabled: "
								.. tostring(loopError),
							7,
							0
						)
					end)
				end
			end

			Engine.Stop(runtime)
			Engine.ClearSpeedBoost(runtime)
			disconnectDamageListener(runtime)
			if targetProvider then
				runtime.Actions.ClearTargetProvider(targetProvider)
			end

			if activeLoops[runtime] == loopToken then
				activeLoops[runtime] = nil
			end

			movementWarnings[runtime] = nil
			rotationCursors[runtime] = nil
			lastSlotAttempts[runtime] = nil
			lastDodgeAttempts[runtime] = nil
			lastHealAttempts[runtime] = nil
			speedBoostWarnings[runtime] = nil
			fatalStatusWarnings[runtime] = nil
			lastQuestClaims[runtime] = nil
			visitedCollectibles[runtime] = nil
			lastWorldTravel[runtime] = nil
			automationDecisions[runtime] = nil

			if runtime.Stopped then
				lastLoopWarnings[runtime] = nil
			end

			if not runtime.Stopped and Engine.IsEnabled(runtime) then
				if targetProvider then
					runtime.Actions.SetTargetProvider(targetProvider)
				end

				task.delay(1, function()
					if not runtime.Stopped and Engine.IsEnabled(runtime) then
						Engine.Start(runtime, targetProvider)
					end
				end)
			end
		end)
	end

	return Engine
end
