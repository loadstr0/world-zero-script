return function()
	local Engine = {}

	local activeLoops = {}
	local movementWarnings = {}
	local rotationCursors = {}
	local lastSlotAttempts = {}
	local activeSlotTasks = {}
	local activePetTasks = {}
	local lastDodgeAttempts = {}
	local dodgeAttackStates = {}
	local lastDodgedDamage = {}
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
	local lastDungeonTravel = {}
	local automationDecisions = {}
	local lastLoopWarnings = {}
	local targetLocks = {}
	local lootWindows = {}
	local engagementStates = {}
	local targetBlacklists = {}
	local recoveryStates = {}
	local hazardStates = {}
	local funnelStates = {}
	local learnedAttackTimings = {}
	local dungeonChestStates = {}
	local towerTransitionStates = {}
	local towerEntryTouchStates = {}
	local lastDirectAuraAttempts = {}

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

	local function questUsesGenericCombat(questState)
		if not questState then
			return false
		end

		return questState.IsDungeonObjective == true
			or questState.ObjectiveType == "LevelUp"
			or questState.ObjectiveType == "KillAnyMob"
			or questState.ObjectiveType == "KillMobInWorld"
			or questState.ObjectiveType == "ItemPickup"
			or questState.ObjectiveType == "BPXPPickup"
			or questState.ObjectiveType == "CollectQuestCurrency"
			or questState.ObjectiveType == "CompleteWorldEvent"
	end

	local function questRequiresRouting(questState)
		if not questState then
			return false
		elseif questState.ObjectiveType == "WorldJoin" then
			return true
		elseif
			questState.ObjectiveType == "KillMob"
			or questState.ObjectiveType == "LevelUp"
			or questState.IsDungeonObjective
			or questUsesGenericCombat(questState)
		then
			return false
		end

		return questState.Location ~= nil
	end

	local function questNeedsDrops(questState)
		return questState
			and (
				questState.ObjectiveType == "ItemPickup"
				or questState.ObjectiveType == "BPXPPickup"
				or questState.ObjectiveType == "CollectQuestCurrency"
				or questState.ObjectiveType == "WorldEggHunt"
			)
	end

	function Engine.GetOptions(runtime, rangeOverride, bypassConfiguredRange, originPosition)
		local configuredRange = tonumber(runtime.State:Get("Farming.TargetRange", 500)) or 500
		local requestedRange = tonumber(rangeOverride) or configuredRange
		local auraEnabled = runtime.State:Get("Combat.AuraEnabled", true)

		return {
			Mode = auraEnabled and "Crowd Priority" or runtime.State:Get("Farming.TargetMode", "Nearest"),
			Range = bypassConfiguredRange and requestedRange or math.min(requestedRange, configuredRange),
			BossOnly = runtime.State:Get("Farming.BossOnly", false),
			EliteOnly = runtime.State:Get("Farming.EliteOnly", false),
			NameFilter = runtime.State:Get("Farming.NameFilter", ""),
			IncludeOwned = false,
			OriginPosition = originPosition,
			ClusterRadius = tonumber(runtime.State:Get("Combat.AuraClusterRadius", 24)) or 24,
			PrioritizeRangedThreats = runtime.State:Get("Combat.PrioritizeRangedThreats", true),
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

	local function selectTarget(runtime, key, options)
		local locks = targetLocks[runtime]
		local blacklist = targetBlacklists[runtime]

		if blacklist then
			local now = os.clock()

			for target, expiresAt in pairs(blacklist) do
				if not target.Parent or (tonumber(expiresAt) or 0) <= now then
					blacklist[target] = nil
				end
			end

			options.ExcludedTargets = blacklist
		end

		if not locks then
			locks = {}
			targetLocks[runtime] = locks
		end

		local locked = locks[key]
		local lootWindowUntil = tonumber(lootWindows[runtime]) or 0

		if lootWindowUntil > os.clock() then
			return nil, "post_combat_loot_window"
		end

		if runtime.State:Get("Farming.StickyTargets", true) and locked then
			local root = runtime.Game.GetRootPart()
			local descriptor = root and runtime.MobsAPI.GetDescriptor(locked.Target, root.Position) or nil

			if descriptor and runtime.MobsAPI.IsValidTarget(descriptor, options) then
				if options.PrioritizeRangedThreats and not descriptor.IsRangedThreat then
					local priorityTarget, priorityDescriptor = runtime.MobsAPI.SelectTarget(options)

					if
						priorityTarget
						and priorityDescriptor
						and priorityDescriptor.IsRangedThreat
						and priorityTarget ~= locked.Target
					then
						locks[key] = {
							Target = priorityTarget,
							Descriptor = priorityDescriptor,
						}
						return priorityTarget, priorityDescriptor
					end
				end

				locked.Descriptor = descriptor
				return locked.Target, descriptor
			end

			locks[key] = nil

			if
				runtime.State:Get("Loot.AfterKillSweep", true)
				and (
					runtime.State:Get("Loot.DropsEnabled", false)
					or runtime.State:Get("Loot.ChestsEnabled", false)
					or runtime.State:Get("Quests.Enabled", false)
				)
			then
				local sweepDuration =
					math.max(0, tonumber(runtime.State:Get("Loot.AfterKillSweepDuration", 2.5)) or 2.5)

				if
					runtime.State:Get("Combat.AuraEnabled", true)
					and runtime.State:Get("Combat.AuraMapSweep", true)
					and not (runtime.CurrentDungeonState and runtime.CurrentDungeonState.Active)
				then
					sweepDuration = math.min(
						sweepDuration,
						tonumber(runtime.State:Get("Combat.AuraRetargetDelay", 0.15)) or 0.15
					)
				end

				lootWindows[runtime] = os.clock() + sweepDuration
				return nil, "post_combat_loot_window"
			end
		end

		local target, descriptorOrError = runtime.MobsAPI.SelectTarget(options)

		if target then
			locks[key] = {
				Target = target,
				Descriptor = descriptorOrError,
			}
		end

		return target, descriptorOrError
	end

	local function skipStalledTarget(runtime, target, descriptor)
		if
			not runtime.State:Get("Farming.SkipStalledTargets", true)
			or not target
			or not descriptor
			or not descriptor.Health
		then
			return false
		end

		local distance = tonumber(descriptor.Distance) or math.huge
		local attackRange = tonumber(runtime.State:Get("Farming.AttackRange", 45)) or 45
		local now = os.clock()
		local state = engagementStates[runtime]
		local health = tonumber(descriptor.Health.Current)

		if not state or state.Target ~= target then
			engagementStates[runtime] = {
				Target = target,
				Health = health,
				LastProgressAt = now,
			}
			return false
		end

		if health and (not state.Health or health < state.Health - 0.001) then
			state.Health = health
			state.LastProgressAt = now
			return false
		elseif distance > attackRange then
			state.Health = health
			state.LastProgressAt = now
			return false
		end

		local timeout = math.max(3, tonumber(runtime.State:Get("Farming.NoDamageTimeout", 5)) or 5)

		if now - (tonumber(state.LastProgressAt) or now) < timeout then
			return false
		end

		local blacklist = targetBlacklists[runtime]

		if not blacklist then
			blacklist = setmetatable({}, { __mode = "k" })
			targetBlacklists[runtime] = blacklist
		end

		blacklist[target] = now
			+ math.max(5, tonumber(runtime.State:Get("Farming.StalledTargetRetryDelay", 5)) or 5)
		engagementStates[runtime] = nil

		local locks = targetLocks[runtime]

		if locks then
			for key, lock in pairs(locks) do
				if lock.Target == target then
					locks[key] = nil
				end
			end
		end

		return true
	end

	function Engine.GetTarget(runtime, rangeOverride, bypassConfiguredRange, originPosition)
		local mapWide = runtime.State:Get("Farming.MapWideTargets", true)
			or (
				runtime.State:Get("Combat.AuraEnabled", true)
				and runtime.State:Get("Combat.AuraMapSweep", true)
			)
		local options =
			Engine.GetOptions(
				runtime,
				mapWide and math.huge or rangeOverride,
				mapWide or bypassConfiguredRange == true,
				originPosition
			)
		local target, descriptorOrError = selectTarget(runtime, "Farm", options)

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

		local searchRange = runtime.State:Get("Quests.MapWideSearch", true) and math.huge
			or (tonumber(runtime.State:Get("Quests.SearchRange", 10000)) or 10000)
		local options = {
			Mode = "Nearest",
			Range = math.min(tonumber(rangeOverride) or math.huge, searchRange),
			BossOnly = false,
			EliteOnly = false,
			NameFilter = table.concat(questState.AllowedMobNames, ","),
			ExactNames = questState.AllowedMobNames,
			IncludeOwned = false,
			PrioritizeRangedThreats = runtime.State:Get("Combat.PrioritizeRangedThreats", true),
		}
		local target, descriptorOrError = selectTarget(runtime, "Quest:" .. tostring(questState.ID), options)

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

			if questUsesGenericCombat(questState) then
				return Engine.GetTarget(runtime, math.huge, true)
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

	function Engine.GetRecentDamage(runtime)
		local damage = recentDamage[runtime]

		if not damage then
			return nil
		end

		local attacker = damage.Attacker

		return {
			Age = math.max(0, os.clock() - (tonumber(damage.At) or os.clock())),
			Amount = tonumber(damage.Amount) or 0,
			Attacker = typeof(attacker) == "Instance" and attacker.Name or tostring(attacker or ""),
		}
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
		local enabled = runtime.State:Get("Farming.SpeedBoostEnabled", true)
		local multiplier = tonumber(runtime.State:Get("Farming.SpeedBoostMultiplier", 3)) or 3
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
		options.MovementMode = runtime.State:Get("Farming.MovementMode", "Smooth Flight")
		local flightSpeed = tonumber(runtime.State:Get("Farming.CFrameFlightSpeed", 90)) or 90
		local speedLimit = 90

		if
			runtime.State:Get("Combat.AuraEnabled", true)
			and runtime.State:Get("Combat.AuraMapSweep", true)
		then
			flightSpeed = math.max(
				flightSpeed,
				tonumber(runtime.State:Get("Combat.AuraFlightSpeed", 120)) or 120
			)
			speedLimit = 180
		end

		options.CFrameFlightSpeed = math.min(speedLimit, flightSpeed)
		options.ZeroVelocity = runtime.State:Get("Farming.CFrameZeroVelocity", true)
		options.FlightNoclip = runtime.State:Get("Farming.FlightNoclip", true)
		options.FlightGroundSafety = runtime.State:Get("Farming.FlightGroundSafety", true)
		options.FlightCruiseHeight = tonumber(runtime.State:Get("Farming.FlightCruiseHeight", 35)) or 35
		options.FlightGroundClearance = tonumber(runtime.State:Get("Farming.FlightGroundClearance", 3)) or 3
		return options
	end

	local function addOverrides(options, overrides)
		for key, value in pairs(overrides or {}) do
			options[key] = value
		end

		return options
	end

	local function approachTarget(runtime, descriptor, movementOverrides)
		local distance = tonumber(descriptor and descriptor.Distance)

		if not runtime.State:Get("Farming.AutoApproach", true) then
			return false, "auto_approach_disabled"
		elseif not distance then
			return false, "target_distance_unavailable"
		elseif typeof(descriptor.Position) ~= "Vector3" then
			return false, "target_position_unavailable"
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		local stopDistance, canKite = getPreferredDistance(runtime, adapter)
		local targetPosition = descriptor.Position
		local root = runtime.Game.GetRootPart()
		local heightOffset = tonumber(runtime.State:Get("Farming.TargetHeightOffset", 0)) or 0
		local finalMovementOverrides = {}
		local currentClass = runtime.ClassRegistry.GetCurrentClass()

		for key, value in pairs(movementOverrides or {}) do
			finalMovementOverrides[key] = value
		end

		if not root then
			return false, "character_root_unavailable"
		end

		if
			runtime.State:Get("Combat.BlatantMode", true)
			and runtime.State:Get("Combat.AirOrbit", true)
		then
			local orbitRadius = math.max(3, tonumber(runtime.State:Get("Combat.OrbitRadius", 8)) or 8)
			local orbitHeight = math.max(2, tonumber(runtime.State:Get("Combat.OrbitHeight", 6)) or 6)

			if
				currentClass == "MageOfLight"
				and runtime.State:Get("Class.MageOfLight.AerialCombat", true)
			then
				orbitRadius = math.min(orbitRadius, 6)
				orbitHeight = math.max(
					orbitHeight,
					tonumber(
						runtime.State:Get(
							"Class.MageOfLight.AerialCombatHeight",
							60
						)
					) or 60
				)
			end

			local attackRange = tonumber(runtime.State:Get("Farming.AttackRange", 45)) or 45
			local maximumReach = attackRange
			local ok, metadata = adapter and type(adapter.Describe) == "function" and pcall(adapter.Describe)

			if
				currentClass == "MageOfLight"
				and runtime.State:Get("Class.MageOfLight.VerticalTargetBypass", true)
			then
				maximumReach = math.max(
					maximumReach,
					tonumber(
						runtime.State:Get(
							"Class.MageOfLight.ServerSafeRange",
							90
						)
					) or 90
				)
			elseif ok and type(metadata) == "table" and type(metadata.Primary) == "table" then
				maximumReach = math.min(maximumReach, tonumber(metadata.Primary.Range) or maximumReach)
			end

			local orbitReach = math.max(5, maximumReach - 2)
			local requestedReach = math.sqrt(orbitRadius * orbitRadius + orbitHeight * orbitHeight)

			if requestedReach > orbitReach then
				local scale = orbitReach / requestedReach
				orbitRadius *= scale
				orbitHeight *= scale
			end

			local angle = os.clock() * (tonumber(runtime.State:Get("Combat.OrbitSpeed", 2.5)) or 2.5)
			targetPosition += Vector3.new(
				math.cos(angle) * orbitRadius,
				orbitHeight,
				math.sin(angle) * orbitRadius
			)
			distance = (targetPosition - root.Position).Magnitude
			stopDistance = 1.5
			canKite = false
			finalMovementOverrides.MovementMode = "Smooth Flight"
			finalMovementOverrides.FlightGroundSafety = true
			finalMovementOverrides.FlightCruiseHeight = orbitHeight
			finalMovementOverrides.FlightNoclip = true
			finalMovementOverrides.TargetMoveThreshold = 1
		elseif heightOffset ~= 0 then
			targetPosition += Vector3.new(0, heightOffset, 0)
			distance = (targetPosition - root.Position).Magnitude
		end

		if canKite and distance < stopDistance - 3 then
			local playerSpeed = tonumber(runtime.Walkspeed.Get())
			local targetSpeed = tonumber(runtime.Walkspeed.Get(descriptor.Model))

			if playerSpeed and (not targetSpeed or playerSpeed >= targetSpeed * 0.9) then
				runtime.Navigator.RetreatFrom(
					targetPosition,
					math.max(8, stopDistance - distance + 6),
					addOverrides(addMovementMode(runtime, {
						Owner = "CombatKite",
						AutoJump = runtime.State:Get("Farming.AutoJump", true),
						RepathInterval = tonumber(runtime.State:Get("Farming.RepathInterval", 1.25)) or 1.25,
						StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
						TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
					}), finalMovementOverrides)
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
			targetPosition,
			addOverrides(addMovementMode(runtime, {
				Owner = "Combat",
				StopDistance = stopDistance,
				AutoJump = runtime.State:Get("Farming.AutoJump", true),
				RepathInterval = tonumber(runtime.State:Get("Farming.RepathInterval", 1.25)) or 1.25,
				StuckTimeout = tonumber(runtime.State:Get("Farming.StuckTimeout", 1.4)) or 1.4,
				TargetMoveThreshold = tonumber(runtime.State:Get("Farming.TargetMoveThreshold", 10)) or 10,
			}), finalMovementOverrides)
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

		return moved, movementError
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

	local function canAttemptSlot(runtime, adapter, slot, descriptor)
		local activeTasks = activeSlotTasks[runtime]

		if activeTasks and activeTasks[slot] then
			return false
		end

		if slot == "Ultimate" and not runtime.State:Get("Farming.UseUltimate", true) then
			return false
		end

		if
			slot == "Ultimate"
			and runtime.ClassRegistry.GetCurrentClass() == "DualWielder"
			and runtime.State:Get("Class.DualWielder.UltimateBossOnly", true)
			and not (descriptor and descriptor.IsBoss)
		then
			return false
		end

		if runtime.ClassRegistry.GetCurrentClass() == "MageOfLight" then
			local health = runtime.MageOfLight.GetHealthState()
			local healthRatio = health and (tonumber(health.Ratio) or 1) or 1

			if slot == "Skill1" then
				if
					not runtime.State:Get("Class.MageOfLight.AutoHealingCircle", true)
					or healthRatio
						> (
							tonumber(
								runtime.State:Get(
									"Class.MageOfLight.HealingThreshold",
									75
								)
							) or 75
						) / 100
				then
					return false
				end
			elseif slot == "Skill2" then
				if not runtime.State:Get("Class.MageOfLight.AutoInfuse", true) then
					return false
				end

				local canInfuse = runtime.MageOfLight.CanInfuse(
					tonumber(
						runtime.State:Get(
							"Class.MageOfLight.InfuseMinimumOrbs",
							10
						)
					) or 10,
					(
						tonumber(
							runtime.State:Get(
								"Class.MageOfLight.InfuseHealthFloor",
								50
							)
						) or 50
					) / 100
				)

				if not canInfuse then
					return false
				end
			elseif slot == "Skill3" then
				local barrier = runtime.MageOfLight.GetBarrier()
				local barrierThreshold =
					(
						tonumber(
							runtime.State:Get(
								"Class.MageOfLight.BarrierHealthThreshold",
								90
							)
						) or 90
					) / 100

				if
					not runtime.State:Get("Class.MageOfLight.AutoBarrier", true)
					or barrier == nil
					or barrier > 0
					or healthRatio > barrierThreshold
				then
					return false
				end
			elseif slot == "Ultimate" then
				if not runtime.State:Get("Class.MageOfLight.AutoGrace", true) then
					return false
				end

				if runtime.State:Get("Class.MageOfLight.SaveGraceForEmergency", false) then
					local emergencyThreshold =
						(
							tonumber(
								runtime.State:Get(
									"Class.MageOfLight.GraceEmergencyThreshold",
									40
								)
							) or 40
						) / 100

					if healthRatio > emergencyThreshold then
						return false
					end
				else
					local minimumTargets =
						tonumber(
							runtime.State:Get(
								"Class.MageOfLight.GraceMinimumTargets",
								1
							)
						) or 1
					local targetCount = tonumber(
						descriptor and descriptor.ClusterCount
					)

					if
						targetCount == nil
						and descriptor
						and typeof(descriptor.Position) == "Vector3"
					then
						local matching = runtime.MobsAPI.GetMatching({
							Range = tonumber(
								runtime.State:Get(
									"Combat.AuraClusterRadius",
									24
								)
							) or 24,
							OriginPosition = descriptor.Position,
							IncludeOwned = false,
						})

						targetCount = type(matching) == "table"
								and #matching
							or 1
					end

					if descriptor and (targetCount or 1) < minimumTargets then
						return false
					end
				end
			end
		end

		if slot == "Ultimate" and runtime.Energy.IsFull() ~= true then
			return false
		end

		local attempts = lastSlotAttempts[runtime] or {}
		lastSlotAttempts[runtime] = attempts
		local retryInterval = tonumber(runtime.State:Get("Farming.SkillRetryInterval", 0.2)) or 0.2

		if runtime.State:Get("Combat.AuraEnabled", true) then
			retryInterval = math.min(
				retryInterval,
				tonumber(runtime.State:Get("Combat.AuraRetryInterval", 0.1)) or 0.1
			)
		end

		if attempts[slot] and os.clock() - attempts[slot] < retryInterval then
			return false
		end

		if adapter and type(adapter.CanUse) == "function" then
			local ok, canUse = pcall(adapter.CanUse, slot)
			return ok and canUse == true
		end

		return runtime.Actions.IsOnCooldown(slot) ~= true
	end

	local function attemptSlot(runtime, adapter, slot, descriptor, target)
		if not canAttemptSlot(runtime, adapter, slot, descriptor) then
			return false
		end

		lastSlotAttempts[runtime][slot] = os.clock()
		local activeTasks = activeSlotTasks[runtime]

		if not activeTasks then
			activeTasks = {}
			activeSlotTasks[runtime] = activeTasks
		end

		activeTasks[slot] = true
		task.spawn(function()
			if target then
				pcall(runtime.Actions.SetInternalTarget, target, 2)
			end

			if adapter and type(adapter.PrepareTargetedSkill) == "function" then
				pcall(adapter.PrepareTargetedSkill, slot, target)
			end

			if adapter and type(adapter.Use) == "function" then
				pcall(adapter.Use, slot)
			elseif slot == "Primary" and adapter and type(adapter.UsePrimary) == "function" then
				pcall(adapter.UsePrimary)
			else
				pcall(runtime.Actions.UseSkill, slot)
			end

			local currentTasks = activeSlotTasks[runtime]

			if currentTasks then
				currentTasks[slot] = nil
			end
		end)

		return true
	end

	local function useFarmAttack(runtime, target, descriptor)
		local distance = tonumber(descriptor and descriptor.Distance)
		local attackRange = tonumber(runtime.State:Get("Farming.AttackRange", 45)) or 45
		local petAttackRange = tonumber(runtime.State:Get("Farming.PetAttackRange", 100)) or 100
		local petAttempted = false

		if
			runtime.ClassRegistry.GetCurrentClass() == "MageOfLight"
			and runtime.State:Get("Class.MageOfLight.VerticalTargetBypass", true)
		then
			attackRange = math.max(
				attackRange,
				tonumber(
					runtime.State:Get(
						"Class.MageOfLight.ServerSafeRange",
						90
					)
				) or 90
			)
		end

		local directAuraAttempted = false

		if
			runtime.ClassRegistry.GetCurrentClass() == "MageOfLight"
			and runtime.State:Get("Combat.DirectMageAura", true)
			and descriptor
			and typeof(descriptor.Position) == "Vector3"
			and distance
				<= (
					tonumber(
						runtime.State:Get(
							"Combat.DirectMageAuraRange",
							90
						)
					) or 90
				)
		then
			local now = os.clock()
			local interval = math.max(
				1.1,
				tonumber(
					runtime.State:Get(
						"Combat.DirectMageAuraInterval",
						1.1
					)
				) or 1.1
			)

			if
				now - (tonumber(lastDirectAuraAttempts[runtime]) or 0)
					>= interval
			then
				lastDirectAuraAttempts[runtime] = now
				directAuraAttempted = true
				task.spawn(function()
					runtime.CombatAPI.AttackWithAcceptedSkill(
						"MageOfLight",
						descriptor.Position
					)
				end)
			end
		end

		if
			not runtime.State:Get("Farming.AutoAttack", true)
			or not distance
		then
			return directAuraAttempted
		end

		if
			runtime.State:Get("Farming.AutoPetAbility", true)
			and runtime.PetsAPI
			and distance <= petAttackRange
			and not activePetTasks[runtime]
		then
			activePetTasks[runtime] = true
			petAttempted = true
			task.spawn(function()
				pcall(runtime.PetsAPI.UseSkill, target)
				activePetTasks[runtime] = nil
			end)
		end

		if distance > attackRange or runtime.Actions.IsBusy() == true then
			return directAuraAttempted or petAttempted
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()

		if adapter and type(adapter.EnsureUnsheathed) == "function" then
			local ok, ready = pcall(adapter.EnsureUnsheathed)

			if not ok or not ready then
				return petAttempted
			end
		end

		if runtime.State:Get("Combat.AutoAim", true) then
			runtime.Actions.AimAtTarget(target, tonumber(runtime.State:Get("Combat.AimDuration", 0.2)) or 0.2)
		end

		local mode = runtime.State:Get("Farming.RotationMode", "Full Rotation")

		if mode == "Primary Only" then
				return attemptSlot(runtime, adapter, "Primary", descriptor, target)
					or directAuraAttempted
					or petAttempted
		elseif mode == "Selected Slot" then
			return attemptSlot(
				runtime,
				adapter,
				runtime.State:Get("Farming.AttackSlot", "Primary"),
				descriptor,
				target
			) or directAuraAttempted or petAttempted
		end

		local rotation = buildRotation(runtime)

		if #rotation == 0 then
			return attemptSlot(runtime, adapter, "Primary", descriptor, target)
				or directAuraAttempted
				or petAttempted
		end

		local cursor = rotationCursors[runtime] or 1

		for offset = 0, #rotation - 1 do
			local index = ((cursor + offset - 1) % #rotation) + 1
			local slot = rotation[index]

			if attemptSlot(runtime, adapter, slot, descriptor, target) then
				rotationCursors[runtime] = (index % #rotation) + 1
				return true
			end
		end

		return directAuraAttempted or petAttempted
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

	local function moveToPoint(runtime, position, stopDistance, owner, overrides)
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

		for key, value in pairs(overrides or {}) do
			options[key] = value
		end

		return runtime.Navigator.MoveTo(position, options)
	end

	local function getCollectible(runtime, hasCombatTarget, questState)
		local dropsEnabled = runtime.State:Get("Loot.DropsEnabled", false) or questNeedsDrops(questState)
		local chestsEnabled = runtime.State:Get("Loot.ChestsEnabled", false)

		if not dropsEnabled and not chestsEnabled then
			return nil
		elseif hasCombatTarget and not runtime.State:Get("Loot.CollectDuringCombat", false) then
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

	local function getDungeonRewardChest(runtime, chestState)
		if
			not runtime.State:Get("Combat.PrioritizeDungeonChests", true)
			or not runtime.ChestsAPI
			or not runtime.CurrentDungeonState
			or not runtime.CurrentDungeonState.Active
		then
			return nil
		end

		local chests = runtime.ChestsAPI.List(math.huge)
		local now = os.clock()

		for _, candidate in ipairs(chests or {}) do
			local ignoredUntil = chestState.Ignored[candidate.Instance]

			if
				not candidate.IsWorldChest
				and not chestState.Processed[candidate.Instance]
				and (not ignoredUntil or ignoredUntil <= now)
				and runtime.ChestsAPI.IsValid(candidate)
			then
				return candidate
			end
		end

		return nil
	end

	local function collectDungeonRewardChest(runtime)
		local dungeonState = runtime.CurrentDungeonState

		if not dungeonState or not dungeonState.Active then
			dungeonChestStates[runtime] = nil
			return false
		end

		local chestState = dungeonChestStates[runtime]

		if not chestState then
			chestState = {
				Ignored = setmetatable({}, { __mode = "k" }),
				Processed = setmetatable({}, { __mode = "k" }),
				OpenedCount = 0,
			}
			dungeonChestStates[runtime] = chestState
		end

		local now = os.clock()
		local batchKey = table.concat({
			tostring(dungeonState.MissionID or "mission"),
			tostring(dungeonState.TowerFloor or dungeonState.ProgressionName or "run"),
		}, ":")

		if chestState.BatchKey ~= batchKey then
			chestState.BatchKey = batchKey
			chestState.Ignored = setmetatable({}, { __mode = "k" })
			chestState.Processed = setmetatable({}, { __mode = "k" })
			chestState.OpenedCount = 0
			chestState.Instance = nil
			chestState.FirstSeenAt = nil
			chestState.ArrivedAt = nil
		end

		if not chestState.PassChecked then
			chestState.PassChecked = true
			chestState.HasExtraChestPass = false

			pcall(function()
				chestState.HasExtraChestPass = game:GetService("MarketplaceService"):UserOwnsGamePassAsync(
					game:GetService("Players").LocalPlayer.UserId,
					8136250
				) == true
			end)
		end

		local maximumChests = chestState.HasExtraChestPass and 3 or 2

		if (tonumber(chestState.OpenedCount) or 0) >= maximumChests then
			return false, "reward_chest_limit_reached"
		end

		for instance, ignoredUntil in pairs(chestState.Ignored) do
			if not instance.Parent or ignoredUntil <= now then
				chestState.Ignored[instance] = nil
			end
		end

		local candidate = getDungeonRewardChest(runtime, chestState)

		if not candidate then
			chestState.Instance = nil
			chestState.FirstSeenAt = nil
			chestState.ArrivedAt = nil
			return false
		end

		if chestState.Instance ~= candidate.Instance then
			chestState.Instance = candidate.Instance
			chestState.FirstSeenAt = now
			chestState.ArrivedAt = nil
		end

		local root = runtime.Game.GetRootPart()

		if not root then
			return true, "reward_chest_character_unavailable", candidate
		end

		candidate.Distance = (candidate.Position - root.Position).Magnitude
		local moved, movementError = moveToPoint(runtime, candidate.Position, 3, "DungeonRewardChest", {
			MovementMode = "Smooth Flight",
			CFrameFlightSpeed = math.max(
				90,
				tonumber(runtime.State:Get("Combat.AuraFlightSpeed", 120)) or 120
			),
			FlightCruiseHeight = 6,
			FlightGroundSafety = true,
			FlightNoclip = true,
			TargetMoveThreshold = 2,
		})

		if candidate.Distance <= 5 then
			chestState.ArrivedAt = chestState.ArrivedAt or now

			if now - chestState.ArrivedAt >= 1.5 then
				-- Proximity opens the chest immediately; its visual model remains for about ten seconds.
				chestState.Processed[candidate.Instance] = true
				chestState.Ignored[candidate.Instance] = now + 20
				chestState.OpenedCount = (tonumber(chestState.OpenedCount) or 0) + 1
				chestState.Instance = nil
				chestState.FirstSeenAt = nil
				chestState.ArrivedAt = nil
				return true, "reward_chest_opened", candidate
			end

			return true, "waiting_for_reward_chest_to_open", candidate
		end

		return true, moved and "approaching_reward_chest" or movementError, candidate
	end

	local function handleMobFunnel(runtime, dungeonState)
		if
			not runtime.State:Get("Combat.BlatantMode", true)
			or not runtime.State:Get("Combat.MobFunnel", true)
			or not dungeonState
			or not dungeonState.Active
			or dungeonState.Phase ~= "Combat"
		then
			funnelStates[runtime] = nil
			return false
		end

		if
			runtime.ClassRegistry.GetCurrentClass() == "MageOfLight"
			and runtime.State:Get("Class.MageOfLight.AerialCombat", true)
		then
			-- A ground-level aggro sweep defeats the class's ranged aerial
			-- advantage and briefly leaves the navigator idle between points.
			-- The normal map-wide target sweep already reaches every wave.
			funnelStates[runtime] = nil
			return false, "mage_aerial_combat_bypasses_funnel"
		end

		local root = runtime.Game.GetRootPart()

		if not root then
			return false
		end

		local descriptors = runtime.MobsAPI.GetMatching({
			Range = math.huge,
			IncludeOwned = false,
			OriginPosition = root.Position,
		}) or {}
		local minimumTargets =
			math.max(2, tonumber(runtime.State:Get("Combat.FunnelMinimumTargets", 3)) or 3)

		if runtime.State:Get("Combat.PrioritizeRangedThreats", true) then
			for _, descriptor in ipairs(descriptors) do
				if descriptor.IsRangedThreat then
					funnelStates[runtime] = nil
					return false, "ranged_threat_bypasses_funnel", descriptor
				end
			end
		end

		if #descriptors < minimumTargets then
			funnelStates[runtime] = nil
			return false
		end

		local state = funnelStates[runtime]
		local now = os.clock()

		if state and state.Completed then
			local hasNewTarget = false

			for _, descriptor in ipairs(descriptors) do
				if not state.Known[descriptor.Model] then
					hasNewTarget = true
					break
				end
			end

			if not hasNewTarget then
				return false
			end

			state = nil
		end

		if not state then
			state = {
				StartedAt = now,
				Known = setmetatable({}, { __mode = "k" }),
				Visited = setmetatable({}, { __mode = "k" }),
			}
			funnelStates[runtime] = state
		end

		local aggroRange = math.max(6, tonumber(runtime.State:Get("Combat.FunnelAggroRange", 16)) or 16)
		local selected = nil

		for _, descriptor in ipairs(descriptors) do
			state.Known[descriptor.Model] = true

			if (tonumber(descriptor.Distance) or math.huge) <= aggroRange then
				state.Visited[descriptor.Model] = true
			elseif
				not state.Visited[descriptor.Model]
				and (
					not selected
					or (tonumber(descriptor.Distance) or math.huge)
						< (tonumber(selected.Distance) or math.huge)
				)
			then
				selected = descriptor
			end
		end

		local timeout = math.max(2, tonumber(runtime.State:Get("Combat.FunnelTimeout", 6)) or 6)

		if not selected or now - state.StartedAt >= timeout then
			state.Completed = true
			state.CompletedAt = now
			return false, selected and "mob_funnel_timeout" or "mob_funnel_complete"
		end

		local targetPosition = selected.Position + Vector3.new(0, 4, 0)
		local moved, movementError = moveToPoint(
			runtime,
			targetPosition,
			math.max(4, aggroRange - 3),
			"MobFunnel",
			{
				MovementMode = "Smooth Flight",
				CFrameFlightSpeed = math.max(
					90,
					tonumber(runtime.State:Get("Combat.AuraFlightSpeed", 120)) or 120
				),
				FlightCruiseHeight = 4,
				FlightGroundSafety = false,
				FlightNoclip = true,
				TargetMoveThreshold = 3,
			}
		)

		if moved and (tonumber(selected.Distance) or math.huge) <= aggroRange + 4 then
			state.Visited[selected.Model] = true
		end

		return true, moved and "sweeping_mob_aggro" or movementError, selected
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

	local function routeQuest(runtime, questState, currentWorldOrder)
		if not questState then
			return false, "no_active_quest"
		end

		if questState.ObjectiveType == "WorldJoin" then
			if not runtime.State:Get("Quests.AutoWorldTravel", true) then
				return false, "world_travel_disabled"
			end

			local destinationOrder = tonumber(questState.DestinationWorldOrder)
				or tonumber(questState.Arguments and questState.Arguments[1])

			if not destinationOrder then
				return false, "quest_world_destination_unavailable"
			elseif tonumber(currentWorldOrder) == destinationOrder then
				runtime.Navigator.Stop()
				return true, "world_join_progress_pending"
			end

			local previous = lastWorldTravel[runtime]
			local now = os.clock()

			if previous and previous.WorldOrder == destinationOrder and now - previous.At < 20 then
				return true, "world_travel_pending"
			end

			local world, worldError = runtime.TeleportAPI.FindOpenWorldByOrder(destinationOrder)

			if not world then
				return false, worldError
			end

			local traveled, travelError, queued, queueError = runtime.TeleportAPI.ToWorld(world.ID)

			if not traveled then
				return false, travelError
			end

			lastWorldTravel[runtime] = {
				WorldOrder = destinationOrder,
				At = now,
			}
			runtime.UI:Notify(
				"Story world travel",
				"Using the teleporter to enter "
					.. tostring(world.Name)
					.. (
						queued and "; automation is queued to resume."
						or (". Re-execute after arrival because " .. tostring(queueError))
					),
				7,
				0
			)
			return true, "world_join_travel_requested"
		end

		if questState.IsDungeonObjective and runtime.State:Get("Quests.AutoDungeonTravel", true) then
			local missionID = tonumber(questState.DungeonID)
			local difficultyID = tonumber(questState.DungeonDifficulty) or 1

			if not missionID then
				local worldOrder = tonumber(questState.LinkedWorld) or tonumber(currentWorldOrder)
				local mission, missionError = runtime.MissionsAPI.FindEasiestForWorld(worldOrder, difficultyID)

				if not mission then
					return false, missionError
				end

				missionID = mission.ID
			end

			local currentMission = runtime.MissionsAPI.GetCurrent()

			if currentMission then
				return false, "quest_dungeon_active"
			end

			local previous = lastDungeonTravel[runtime]
			local now = os.clock()

			if previous and previous.MissionID == missionID and now - previous.At < 20 then
				return true, "dungeon_travel_pending"
			end

			local traveled, travelError, queued, queueError = runtime.TeleportAPI.ToMission(missionID, difficultyID)

			if not traveled then
				return false, travelError
			end

			lastDungeonTravel[runtime] = {
				MissionID = missionID,
				At = now,
			}
			runtime.UI:Notify(
				"Quest dungeon travel",
				"Starting mission "
					.. tostring(missionID)
					.. " at difficulty "
					.. tostring(difficultyID)
					.. (
						queued and "; automation is queued to resume."
						or (". Re-execute after arrival because " .. tostring(queueError))
					),
				7,
				0
			)
			return true, "dungeon_travel_requested"
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

			local traveled, travelError, queued, queueError = runtime.TeleportAPI.ToWorld(world.ID)

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

		if questState.ObjectiveType == "LevelUp" then
			return false, "objective_progresses_by_farming"
		elseif not runtime.State:Get("Quests.RouteToArea", true) then
			return false, "quest_routing_disabled"
		elseif not questState.Location then
			return false, questState.LocationError or "quest_location_unavailable"
		end

		local locationRange = tonumber(questState.Location.Range) or 15
		local stopDistance = math.min(25, math.max(10, locationRange))

		return moveToPoint(runtime, questState.Location.Position, stopDistance, "Quest")
	end

	local function settleTowerFloorTransition(runtime, dungeonState)
		if
			not dungeonState
			or not dungeonState.Active
			or not dungeonState.IsCelestialTower
			or tonumber(dungeonState.TowerFloor) == nil
		then
			towerTransitionStates[runtime] = nil
			return false
		end

		local floor = tonumber(dungeonState.TowerFloor)
		local state = towerTransitionStates[runtime]
		local now = os.clock()

		if not state then
			state = {
				Floor = floor,
				HoldUntil = 0,
			}
			towerTransitionStates[runtime] = state
		elseif state.Floor ~= floor then
			state.Floor = floor
			state.HoldUntil = now + 0.45
			runtime.Navigator.Stop()
			Engine.StopSprint(runtime)
		end

		if now < (tonumber(state.HoldUntil) or 0) then
			local survival = Engine.GetSurvivalState(runtime) or {}
			local healthRatio = math.min(
				tonumber(survival.HealthRatio) or 1,
				tonumber(survival.ProtectionRatio) or 1
			)
			local retreatThreshold =
				(tonumber(runtime.State:Get("Farming.RetreatHealthThreshold", 35)) or 35) / 100

			-- A floor can change while the previous recovery is still active.
			-- Do not freeze a critically low character for the normal visual
			-- settle window while the next wave is already able to attack.
			if recoveryStates[runtime] or healthRatio <= retreatThreshold then
				state.HoldUntil = 0
				return false
			end

			local root = runtime.Game.GetRootPart()

			if root then
				pcall(function()
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end)
			end

			runtime.Navigator.Stop()
			return true
		end

		return false
	end

	local function routeDungeon(runtime, dungeonState)
		local function holdCurrentAerialPosition(owner)
			local root = runtime.Game.GetRootPart()

			if not root then
				return false, "character_root_unavailable"
			end

			return moveToPoint(runtime, root.Position, 0, owner, {
				MovementMode = "Smooth Flight",
				ZeroVelocity = true,
				FlightGroundSafety = true,
				FlightCruiseHeight = tonumber(
					runtime.State:Get(
						"Class.MageOfLight.AerialCombatHeight",
						60
					)
				) or 60,
				FlightNoclip = true,
				TargetMoveThreshold = 2,
			})
		end

		local mageAerialCombat =
			runtime.ClassRegistry.GetCurrentClass() == "MageOfLight"
			and runtime.State:Get("Class.MageOfLight.AerialCombat", true)

		local function moveDungeonPoint(position, stopDistance, owner)
			local root = runtime.Game.GetRootPart()
			local overrides = root
					and typeof(position) == "Vector3"
					and root.Position.Y - position.Y >= 18
					and {
						FlightGroundSafety = false,
						FlightCruiseHeight = 6,
						FlightNoclip = true,
					}
				or nil

			return moveToPoint(runtime, position, stopDistance, owner, overrides)
		end

		if not dungeonState or not dungeonState.Active then
			return false, "dungeon_not_active"
		elseif dungeonState.Phase == "Rewards" then
			runtime.Navigator.Stop()
			return true, "dungeon_rewards"
		elseif dungeonState.MissionOver then
			runtime.Navigator.Stop()
			return true, dungeonState.MissionSucceeded and "dungeon_completed" or "dungeon_failed"
		elseif
			dungeonState.Phase == "WaitingForStart"
			and runtime.State:Get("Dungeons.AutoStart", true)
			and dungeonState.StartPosition
		then
			return moveDungeonPoint(dungeonState.StartPosition, 0, "DungeonStart")
		elseif
			dungeonState.Phase == "TowerEnter"
			and runtime.State:Get("Dungeons.AutoTowerProgression", true)
			and (dungeonState.HoldPosition or dungeonState.StartPosition)
		then
			-- The gate API exposes the closest point on the trigger surface.
			-- Stopping a few studs short of that point can leave the character
			-- hovering outside the volume forever (observed on floor 70).
			-- Prefer crossing into the authoritative arena spawn; when it has
			-- not streamed yet, touch the gate surface with no stop margin.
			local hasHoldPosition = typeof(dungeonState.HoldPosition) == "Vector3"
			local entryPosition = hasHoldPosition
					and (dungeonState.HoldPosition + Vector3.new(0, 3, 0))
				or dungeonState.StartPosition
			local fireTouch = runtime.Executor.FireTouchInterest
			local trigger = dungeonState.StartTrigger
			local character = runtime.Game.GetCharacter()
			local touchPart = character
				and (
					character:FindFirstChild("Collider")
					or character:FindFirstChild("HumanoidRootPart")
					or character.PrimaryPart
				)
			local now = os.clock()

			if
				type(fireTouch) == "function"
				and typeof(trigger) == "Instance"
				and trigger:IsA("BasePart")
				and typeof(touchPart) == "Instance"
				and touchPart:IsA("BasePart")
				and now - (tonumber(towerEntryTouchStates[runtime]) or -math.huge) >= 0.75
			then
				towerEntryTouchStates[runtime] = now
				task.spawn(function()
					pcall(fireTouch, touchPart, trigger, 0)
					task.wait(0.1)
					pcall(fireTouch, touchPart, trigger, 1)
				end)
			end

			return moveToPoint(runtime, entryPosition, 0, "TowerEntry", {
				MovementMode = "Smooth Flight",
				FlightGroundSafety = false,
				FlightCruiseHeight = 0,
				FlightNoclip = true,
				FlightRouteThreshold = math.huge,
				ZeroVelocity = true,
			})
		elseif
			dungeonState.Phase == "TowerAdvance"
			and runtime.State:Get("Dungeons.AutoTowerProgression", true)
			and dungeonState.ProgressionPosition
		then
			return moveToPoint(runtime, dungeonState.ProgressionPosition, 3, "TowerPortal", {
				MovementMode = "Smooth Flight",
				FlightGroundSafety = false,
				FlightCruiseHeight = 0,
				FlightNoclip = false,
				FlightRouteThreshold = math.huge,
				ZeroVelocity = true,
			})
		elseif
			dungeonState.Phase == "Objective"
			and runtime.State:Get("Dungeons.AutoProgression", true)
			and dungeonState.ProgressionPosition
		then
			local activated, activationStatus =
				runtime.DungeonsAPI.ActivateObjective(dungeonState)

			if activated then
				runtime.Navigator.Stop()
				return true, activationStatus
			end

			return moveDungeonPoint(dungeonState.ProgressionPosition, 0, "DungeonObjective")
		elseif
			dungeonState.Phase == "Progression"
			and runtime.State:Get("Dungeons.AutoProgression", true)
			and dungeonState.ProgressionPosition
		then
			local progressionRoute = runtime.DungeonsAPI.GetProgressionRoute(dungeonState)

			if progressionRoute then
				return moveToPoint(
					runtime,
					progressionRoute.Position,
					progressionRoute.StopDistance,
					"DungeonStageRoute",
					{
						MovementMode = progressionRoute.MovementMode,
						ZeroVelocity = progressionRoute.ZeroVelocity,
						FlightGroundSafety = progressionRoute.FlightGroundSafety,
						FlightCruiseHeight = progressionRoute.FlightCruiseHeight,
						FlightNoclip = progressionRoute.FlightNoclip,
					}
				)
			end

			return moveDungeonPoint(dungeonState.ProgressionPosition, 0, "DungeonProgression")
		elseif
			dungeonState.Phase == "TowerWaiting"
			and dungeonState.IsCelestialTower
			and dungeonState.RequiresArenaEntry
			and runtime.State:Get("Dungeons.AutoTowerProgression", true)
			and dungeonState.StartPosition
		then
			-- Empty tower rooms do not register their mobs until the live arena
			-- is crossed. Once the wave materializes, unrestricted dungeon
			-- targeting immediately abandons this route and flies to a live mob.
			return moveToPoint(runtime, dungeonState.StartPosition, 0, "TowerWaitingEntry", {
				MovementMode = "Smooth Flight",
				FlightGroundSafety = false,
				FlightCruiseHeight = 0,
				FlightNoclip = true,
				FlightRouteThreshold = math.huge,
				ZeroVelocity = true,
			})
		elseif
			dungeonState.Phase == "TowerWaiting"
			and not mageAerialCombat
			and runtime.State:Get("Dungeons.HoldDefense", true)
			and dungeonState.HoldPosition
		then
			return moveDungeonPoint(dungeonState.HoldPosition, 8, "TowerWaiting")
		elseif
			dungeonState.Phase == "BetweenWaves"
			and not mageAerialCombat
			and runtime.State:Get("Dungeons.HoldDefense", true)
			and dungeonState.HoldPosition
		then
			return moveDungeonPoint(dungeonState.HoldPosition, 10, "DungeonDefense")
		elseif
			mageAerialCombat
			and (
				dungeonState.Phase == "Combat"
				or dungeonState.Phase == "TowerWaiting"
				or dungeonState.Phase == "BetweenWaves"
			)
		then
			-- Keep the last safe orbit pinned while the next target is
			-- replicating. Calling Navigator.Stop here allows gravity to undo
			-- the aerial stance between waves.
			return holdCurrentAerialPosition("MageAerialHold")
		elseif dungeonState.Phase == "BetweenWaves" then
			runtime.Navigator.Stop()
			return true, "dungeon_waiting_for_wave"
		end

		return false, "dungeon_mechanic_unresolved:" .. tostring(dungeonState.Phase)
	end

	local function dodgeThreat(runtime, adapter, threat, healthRatio, statusState)
		local damage = recentDamage[runtime]
		local reactionWindow = tonumber(runtime.State:Get("Farming.DamageReactionWindow", 1.25)) or 1.25
		local damagedRecently = runtime.State:Get("Farming.DodgeAfterDamage", true)
			and damage
			and os.clock() - (tonumber(damage.At) or 0) <= reactionWindow
		local attackStates = dodgeAttackStates[runtime]
		local now = os.clock()

		if not attackStates then
			attackStates = setmetatable({}, { __mode = "k" })
			dodgeAttackStates[runtime] = attackStates
		end

		local activeAttacks = setmetatable({}, { __mode = "k" })
		local attacking = nil
		local predictive = runtime.State:Get("Combat.BlatantMode", true)
			and runtime.State:Get("Combat.PredictiveDodge", true)
		local lead = math.max(0, tonumber(runtime.State:Get("Combat.PredictiveDodgeLead", 0.12)) or 0.12)
		local fallback =
			math.max(0.05, tonumber(runtime.State:Get("Combat.PredictiveDodgeFallback", 0.25)) or 0.25)
		local newDamage = damagedRecently and lastDodgedDamage[runtime] ~= damage.At

		local function damageCameFrom(model)
			local attacker = damage and damage.Attacker

			if typeof(attacker) ~= "Instance" or typeof(model) ~= "Instance" then
				return false
			elseif attacker == model then
				return true
			end

			local ok, matches = pcall(function()
				return attacker:IsDescendantOf(model) or model:IsDescendantOf(attacker)
			end)

			return ok and matches == true
		end

		for _, candidate in ipairs(threat and threat.Attacking or {}) do
			local model = candidate.Model
			local name = tostring(candidate.CurrentAttack or "")

			if model and name ~= "" then
				local record = attackStates[model]

				if type(record) ~= "table" or record.Name ~= name then
					record = {
						Name = name,
						StartedAt = now,
						Dodged = false,
					}
					attackStates[model] = record
				end

				record.Key = tostring(candidate.Type or candidate.ModelName or "Mob") .. "|" .. name
				activeAttacks[model] = record

				if
					newDamage
					and damageCameFrom(model)
					and record.LastLearnedDamageAt ~= damage.At
				then
					local sample = (tonumber(damage.At) or now) - (tonumber(record.StartedAt) or now)

					if sample >= 0.05 and sample <= 3 then
						local previous = tonumber(learnedAttackTimings[record.Key])
						learnedAttackTimings[record.Key] = previous and previous * 0.7 + sample * 0.3 or sample
						record.LastLearnedDamageAt = damage.At
					end
				end

				local learnedDelay = tonumber(learnedAttackTimings[record.Key]) or fallback
				local triggerDelay = math.max(0.03, learnedDelay - lead)
				local ready = not record.Dodged
					and (
						not predictive
						or now - (tonumber(record.StartedAt) or now) >= triggerDelay
						or (newDamage and damageCameFrom(model))
					)

				if
					ready
					and (
						not attacking
						or (tonumber(candidate.Distance) or math.huge)
							< (tonumber(attacking.Distance) or math.huge)
					)
				then
					attacking = candidate
				end
			end
		end

		for model in pairs(attackStates) do
			if activeAttacks[model] == nil then
				attackStates[model] = nil
			end
		end

		local attackName = attacking and tostring(attacking.CurrentAttack or "") or ""
		local newAttack = attacking and attackName ~= ""

		if
			not runtime.State:Get("Farming.AutoDodge", true)
			or (statusState and statusState.SkillsBlocked)
			or (not newAttack and not newDamage)
			or runtime.Actions.IsBusy() == true
		then
			return false
		end

		local lastAttempt = lastDodgeAttempts[runtime] or 0
		local minimumInterval = tonumber(runtime.State:Get("Farming.DodgeMinimumInterval", 0.85)) or 0.85

		if runtime.State:Get("Combat.BlatantMode", true) then
			minimumInterval = math.min(minimumInterval, 0.45)
		end

		if now - lastAttempt < minimumInterval then
			return false
		end

		if runtime.Actions.IsOnCooldown("Dodge") == true then
			return false
		end

		lastDodgeAttempts[runtime] = now
		if newAttack then
			local record = attackStates[attacking.Model]

			if type(record) == "table" then
				record.Dodged = true
			end
		end
		if newDamage then
			lastDodgedDamage[runtime] = damage.At
		end

		if adapter and type(adapter.UseDodge) == "function" then
			pcall(adapter.UseDodge)
		else
			pcall(runtime.Actions.UseSkill, "Dodge")
		end

		return true
	end

	local function escapeFloorHazard(runtime, adapter, statusState, recoveringInAir)
		if
			not runtime.State:Get("Farming.ProactiveSpellDodge", true)
			or not runtime.HazardsAPI
			or (statusState and statusState.MovementBlocked)
		then
			hazardStates[runtime] = nil
			return false
		end

		local root = runtime.Game.GetRootPart()

		if not root then
			return false
		end

		local padding = tonumber(runtime.State:Get("Farming.HazardPadding", 4)) or 4
		local projectToGround = recoveringInAir == true
			and runtime.State:Get("Farming.MobileAirRecovery", true)
		local hazardOptions = {
			Projected = projectToGround,
		}
		local state = runtime.HazardsAPI.GetState(root.Position, padding, hazardOptions)
		local previous = hazardStates[runtime]

		if not state or (tonumber(state.InsideCount) or 0) <= 0 then
			local indicatorStillActive = false

			for _, hazard in ipairs(previous and previous.Hazards or {}) do
				if hazard.Instance and hazard.Instance.Parent then
					indicatorStillActive = true
					break
				end
			end

			if
				indicatorStillActive
				and os.clock() - (tonumber(previous.At) or 0)
					<= (tonumber(runtime.State:Get("Farming.HazardMaximumHold", 15)) or 15)
			then
				runtime.Navigator.Stop()
				return false, true
			end

			hazardStates[runtime] = nil
			return false
		end

		local escapeBuffer = tonumber(runtime.State:Get("Farming.HazardEscapeDistance", 10)) or 10
		local position, escapeError =
			runtime.HazardsAPI.FindEscape(root.Position, state, padding, escapeBuffer, hazardOptions)

		hazardStates[runtime] = {
			At = os.clock(),
			Count = state.InsideCount,
			Name = state.Nearest and state.Nearest.Name or "Floor indicator",
			Position = position,
			Error = escapeError,
			Hazards = state.Inside,
			Projected = projectToGround,
		}
		local escapeMode = runtime.State:Get("Farming.HazardEscapeMode", "Smooth Flight")

		if
			runtime.State:Get("Farming.HazardUseDodge", true)
			and escapeMode ~= "Instant CFrame"
			and not (statusState and statusState.SkillsBlocked)
			and runtime.Actions.IsBusy() ~= true
			and runtime.Actions.IsOnCooldown("Dodge") ~= true
		then
			local lastAttempt = lastDodgeAttempts[runtime] or 0

			if os.clock() - lastAttempt >= 0.5 then
				lastDodgeAttempts[runtime] = os.clock()

				if adapter and type(adapter.UseDodge) == "function" then
					pcall(adapter.UseDodge)
				else
					pcall(runtime.Actions.UseSkill, "Dodge")
				end
			end
		end

		if typeof(position) ~= "Vector3" then
			return true, false
		end

		runtime.Navigator.MoveTo(position, {
			Owner = "FloorHazardEscape",
			MovementMode = escapeMode,
			StopDistance = 0,
			ZeroVelocity = true,
			FlightNoclip = true,
			FlightGroundSafety = true,
			FlightCruiseHeight = 8,
			FlightGroundClearance = 3,
		})
		return true, false
	end

	local function useEmergencyHeal(runtime, healthRatio, statusState)
		healthRatio = tonumber(healthRatio) or 1
		local threshold = tonumber(runtime.State:Get("Farming.HealItemHealthThreshold", 40)) or 40

		if runtime.State:Get("Farming.DebuffSurvival", true) and statusState and statusState.HasDamageOverTime then
			threshold = math.max(threshold, tonumber(runtime.State:Get("Farming.DebuffSafetyThreshold", 45)) or 45)
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

	local function useClassRecoverySkill(runtime, adapter, survival, statusState)
		if
			runtime.ClassRegistry.GetCurrentClass() ~= "MageOfLight"
			or not adapter
			or (statusState and statusState.SkillsBlocked)
			or runtime.Actions.IsBusy() == true
		then
			return false
		end

		local healthRatio = tonumber(survival and survival.HealthRatio) or 1
		local graceThreshold =
			(
				tonumber(
					runtime.State:Get(
						"Class.MageOfLight.GraceEmergencyThreshold",
						40
					)
				) or 40
			) / 100

		if
			healthRatio <= graceThreshold
			and runtime.State:Get("Class.MageOfLight.AutoGrace", true)
			and attemptSlot(runtime, adapter, "Ultimate", nil, nil)
		then
			return true
		end

		local healingThreshold =
			(
				tonumber(
					runtime.State:Get(
						"Class.MageOfLight.HealingThreshold",
						75
					)
				) or 75
			) / 100

		if
			healthRatio <= healingThreshold
			and runtime.State:Get("Class.MageOfLight.AutoHealingCircle", true)
			and attemptSlot(runtime, adapter, "Skill1", nil, nil)
		then
			return true
		end

		local barrier = runtime.MageOfLight.GetBarrier()
		local barrierThreshold =
			(
				tonumber(
					runtime.State:Get(
						"Class.MageOfLight.BarrierHealthThreshold",
						90
					)
				) or 90
			) / 100

		if
			barrier ~= nil
			and barrier <= 0
			and healthRatio <= barrierThreshold
			and runtime.State:Get("Class.MageOfLight.AutoBarrier", true)
		then
			return attemptSlot(runtime, adapter, "Skill3", nil, nil)
		end

		return false
	end

	local function getSafeRecoveryHeight(runtime, root, requestedHeight)
		local height = math.max(0, tonumber(requestedHeight) or 0)
		local workspace = runtime.Context.Services.Workspace

		if height <= 0 or not workspace then
			return height
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent }
		local hit = nil

		pcall(function()
			hit = workspace:Raycast(
				root.Position + Vector3.new(0, 2, 0),
				Vector3.new(0, height + 8, 0),
				params
			)
		end)

		if hit then
			height = math.max(0, math.min(height, hit.Distance - 7))
		end

		return height
	end

	local function handleDefense(runtime, statusState, dungeonState)
		local threatRadius = tonumber(runtime.State:Get("Farming.ThreatRadius", 25)) or 25

		-- Blatant dungeon movement can engage ranged enemies before their
		-- client-side Target field is populated. Scan the full UI-supported
		-- radius so casts are recognized before the first hit lands.
		if dungeonState and dungeonState.Active then
			threatRadius = math.max(threatRadius, 60)
		end

		local threat = runtime.MobsAPI.GetThreatState(threatRadius)
		local survival = Engine.GetSurvivalState(runtime)
		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		local currentClass = runtime.ClassRegistry.GetCurrentClass()
		local recoveringInAir = recoveryStates[runtime] ~= nil
			and runtime.State:Get("Farming.AirRecovery", true)
		local escapingHazard, holdingHazard =
			escapeFloorHazard(runtime, adapter, statusState, recoveringInAir)
		useEmergencyHeal(runtime, survival.HealthRatio, statusState)

		if escapingHazard then
			return true, false
		end

		useClassRecoverySkill(runtime, adapter, survival, statusState)
		dodgeThreat(runtime, adapter, threat, survival.ProtectionRatio, statusState)
		local retreatThreshold = tonumber(runtime.State:Get("Farming.RetreatHealthThreshold", 35)) or 35

		if runtime.State:Get("Farming.ConservativeRecovery", false) then
			retreatThreshold = math.max(retreatThreshold, 50)
		end

		if
			runtime.State:Get("Farming.DebuffSurvival", true)
			and statusState
			and (statusState.HasDamageOverTime or statusState.HasDefenseDebuff)
		then
			retreatThreshold =
				math.max(retreatThreshold, tonumber(runtime.State:Get("Farming.DebuffSafetyThreshold", 45)) or 45)
		end

		local previousDecision = automationDecisions[runtime]
		local previousTarget = previousDecision and previousDecision.FarmTarget
		local hasBossThreat = (threat and (tonumber(threat.BossCount) or 0) > 0)
			or (type(previousTarget) == "table" and previousTarget.IsBoss == true)
		local timedBoss = runtime.State:Get("Farming.BossTimerSurvival", true)
			and threat
			and hasBossThreat
			and dungeonState
			and dungeonState.Active
			and tonumber(dungeonState.RemainingTime) ~= nil

		if timedBoss then
			local bossThreshold =
				tonumber(runtime.State:Get("Farming.BossRetreatHealthThreshold", 25)) or 25
			local remainingTime = tonumber(dungeonState.RemainingTime) or math.huge
			local urgentTime =
				tonumber(runtime.State:Get("Farming.BossUrgentTimeThreshold", 45)) or 45

			if remainingTime <= urgentTime then
				bossThreshold = math.max(12, bossThreshold - 7)
			end

			if
				statusState
				and (statusState.HasDamageOverTime or statusState.HasDefenseDebuff)
			then
				bossThreshold = math.max(bossThreshold, 35)
			end

			retreatThreshold = math.min(retreatThreshold, bossThreshold)
		end

		local recovery = recoveryStates[runtime]
		local currentTowerFloor = dungeonState
			and dungeonState.IsCelestialTower
			and tonumber(dungeonState.TowerFloor)
			or nil

		if
			recovery
			and recovery.TowerFloor
			and currentTowerFloor
			and recovery.TowerFloor ~= currentTowerFloor
		then
			-- Never fly toward a recovery point in the previous arena after a
			-- tower portal moves the character thousands of studs away.
			recoveryStates[runtime] = nil
			recovery = nil
		end
		local resumePercent = math.max(
			retreatThreshold,
			tonumber(runtime.State:Get("Farming.RecoveryResumeThreshold", 60)) or 60
		)

		if runtime.State:Get("Farming.ConservativeRecovery", false) then
			resumePercent = math.max(resumePercent, 75)
		end

		if timedBoss then
			resumePercent = math.max(
				retreatThreshold + 15,
				tonumber(runtime.State:Get("Farming.BossRecoveryResumeThreshold", 45)) or 45
			)
		end

		local resumeThreshold = math.clamp(resumePercent, retreatThreshold, 100) / 100
		local currentRatio = math.min(
			tonumber(survival.HealthRatio) or 1,
			tonumber(survival.ProtectionRatio) or 1
		)

		if recovery and currentRatio >= resumeThreshold then
			recoveryStates[runtime] = nil
			recovery = nil
		end

		if
			runtime.State:Get("Farming.EmergencyRetreat", true)
			and not (statusState and statusState.MovementBlocked)
			and (recovery or currentRatio <= retreatThreshold / 100)
		then
			local root = runtime.Game.GetRootPart()

			if not root then
				return true, false
			end

			if not recovery or recovery.Character ~= root.Parent then
				local threatPosition = threat
					and threat.Nearest
					and threat.Nearest.Position
					or (root.Position - root.CFrame.LookVector * 10)
				local offset = root.Position - threatPosition
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				local direction = flatOffset.Magnitude > 0
						and flatOffset.Unit
					or Vector3.new(0, 0, 1)
				local distance = tonumber(runtime.State:Get("Farming.RetreatDistance", 35)) or 35
				local inDungeon = dungeonState and dungeonState.Active == true
				local useAirRecovery = runtime.State:Get("Farming.AirRecovery", true)
				local lightAerialHold = currentClass == "MageOfLight"
					and useAirRecovery
					and threat
					and (tonumber(threat.ReachableRangedCount) or 0) <= 0

				if lightAerialHold then
					distance = 0
				end

				local requestedHeight = useAirRecovery
						and (tonumber(runtime.State:Get("Farming.AirRecoveryHeight", 45)) or 45)
					or 0

				if inDungeon then
					requestedHeight = math.min(requestedHeight, 35)
				end

				local height = getSafeRecoveryHeight(runtime, root, requestedHeight)

				recovery = {
					Character = root.Parent,
					Position = root.Position
						+ direction * distance
						+ Vector3.new(0, height, 0),
					StartedAt = os.clock(),
					LastDamageAt = recentDamage[runtime] and recentDamage[runtime].At or 0,
					Relocations = 0,
					RetreatThreshold = retreatThreshold,
					ResumeThreshold = resumePercent,
					TimedBoss = timedBoss == true,
					TowerFloor = currentTowerFloor,
				}
				recoveryStates[runtime] = recovery
			end

			if
				dungeonState
				and dungeonState.Phase == "TowerAdvance"
				and typeof(dungeonState.HoldPosition) == "Vector3"
				and not recovery.PortalHold
			then
				-- Heal at the arena spawn, far from the next-floor portal.
				-- Otherwise the recovery flight can brush the interaction and
				-- carry critical health directly into a fresh wave.
				local holdHeight = runtime.State:Get("Farming.AirRecovery", true)
						and math.min(
							35,
							tonumber(runtime.State:Get("Farming.AirRecoveryHeight", 45)) or 45
						)
					or 0

				recovery.Position = dungeonState.HoldPosition + Vector3.new(0, holdHeight, 0)
				recovery.PortalHold = true
				runtime.Navigator.Stop()
			end

			local damage = recentDamage[runtime]
			local damageAt = tonumber(damage and damage.At) or 0
			local now = os.clock()

			if
				runtime.State:Get("Farming.MobileAirRecovery", true)
				and damageAt > (tonumber(recovery.LastDamageAt) or 0)
				and now - damageAt
					<= (tonumber(runtime.State:Get("Farming.DamageReactionWindow", 1.25)) or 1.25)
				and now - (tonumber(recovery.LastRelocatedAt) or 0) >= 0.35
			then
				local attackerPart = nil

				if typeof(damage.Attacker) == "Instance" then
					attackerPart = runtime.MobsAPI.GetTargetPart(damage.Attacker)
				end

				local threatPosition = attackerPart and attackerPart.Position
					or threat
						and threat.Nearest
						and threat.Nearest.Position
					or (root.Position - root.CFrame.LookVector * 10)
				local away = root.Position - threatPosition
				local flatAway = Vector3.new(away.X, 0, away.Z)
				local direction = flatAway.Magnitude > 0.01
						and flatAway.Unit
					or Vector3.new(0, 0, 1)
				local side = Vector3.new(-direction.Z, 0, direction.X)
				local sideSign = ((tonumber(recovery.Relocations) or 0) % 2 == 0) and 1 or -1
				local evasiveDirection = (direction + side * 0.75 * sideSign).Unit
				local relocationDistance = math.max(
					25,
					tonumber(runtime.State:Get("Farming.RecoveryRelocationDistance", 45)) or 45
				)
				local verticalOffset = math.max(0, recovery.Position.Y - root.Position.Y)

				recovery.Position = root.Position
					+ evasiveDirection * relocationDistance
					+ Vector3.new(0, verticalOffset, 0)
				recovery.LastDamageAt = damageAt
				recovery.LastRelocatedAt = now
				recovery.Relocations = (tonumber(recovery.Relocations) or 0) + 1
				runtime.Navigator.Stop()
			end

			if
				runtime.State:Get("Farming.MobileAirRecovery", true)
				and not (
					currentClass == "MageOfLight"
					and threat
					and (tonumber(threat.ReachableRangedCount) or 0) <= 0
				)
				and threat
				and (
					(tonumber(threat.AttackingCount) or 0) > 0
					or (tonumber(threat.Count) or 0) > 0
				)
				and now - (tonumber(recovery.LastRelocatedAt) or 0) >= 0.9
			then
				-- Boss adds can keep applying small hits without producing a
				-- fresh replicated hit event every frame. Keep the recovery
				-- path moving laterally instead of reaching one point and
				-- descending into a predictable hover.
				local nearestPosition = threat.Nearest
					and threat.Nearest.Position
					or (root.Position - root.CFrame.LookVector * 10)
				local away = root.Position - nearestPosition
				local flatAway = Vector3.new(away.X, 0, away.Z)
				local direction = flatAway.Magnitude > 0.01
						and flatAway.Unit
					or Vector3.new(0, 0, 1)
				local side = Vector3.new(-direction.Z, 0, direction.X)
				local sideSign = ((tonumber(recovery.Relocations) or 0) % 2 == 0) and 1 or -1
				local evasiveDirection = (direction + side * 0.9 * sideSign).Unit
				local relocationDistance = math.max(
					25,
					math.min(
						40,
						tonumber(runtime.State:Get("Farming.RecoveryRelocationDistance", 45)) or 45
					)
				)
				local targetPosition = root.Position + evasiveDirection * relocationDistance
				local holdPosition = dungeonState and dungeonState.HoldPosition

				if typeof(holdPosition) == "Vector3" then
					local fromHold = targetPosition - holdPosition
					local flatFromHold = Vector3.new(fromHold.X, 0, fromHold.Z)
					local arenaRadius = 140

					if flatFromHold.Magnitude > arenaRadius then
						local bounded = flatFromHold.Unit * arenaRadius
						targetPosition = Vector3.new(
							holdPosition.X + bounded.X,
							targetPosition.Y,
							holdPosition.Z + bounded.Z
						)
					end
				end

				recovery.Position = Vector3.new(
					targetPosition.X,
					math.max(root.Position.Y, recovery.Position.Y),
					targetPosition.Z
				)
				recovery.LastRelocatedAt = now
				recovery.Relocations = (tonumber(recovery.Relocations) or 0) + 1
				recovery.ProactiveEvasion = true
				runtime.Navigator.Stop()
			end

			local retreatOptions = getNavigationOptions(runtime)
			retreatOptions.Owner = "EmergencyRecovery"
			retreatOptions.StopDistance = 2

			if runtime.State:Get("Farming.AirRecovery", true) then
				retreatOptions.MovementMode = "Smooth Flight"
				retreatOptions.FlightNoclip = true
				retreatOptions.FlightGroundSafety = true
				retreatOptions.FlightCruiseHeight = 8
				retreatOptions.FlightGroundClearance = 4
			end

			runtime.Navigator.MoveTo(recovery.Position, retreatOptions)
			return true, false
		end

		if recovery then
			recoveryStates[runtime] = nil
		end

		return false, holdingHazard == true
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
		local nearestDistance = tonumber(runtime.State:Get("Farming.FreezeTagRescueRange", 300)) or 300
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
					local humanoid = runtime.Game.GetHumanoid()
					local root = runtime.Game.GetRootPart()

					if not humanoid or not root or tonumber(humanoid.Health) == nil or humanoid.Health <= 0 then
						Engine.Stop(runtime)
						automationDecisions[runtime] = {
							Waiting = "character_respawn",
							Navigator = runtime.Navigator.GetState(),
						}
						task.wait(0.5)
						continue
					end

					local dungeonState = nil

					if runtime.DungeonsAPI then
						local dungeonOk, resolvedDungeonState =
							pcall(runtime.DungeonsAPI.GetState)

						if dungeonOk then
							dungeonState = resolvedDungeonState
						end
					end

					runtime.CurrentDungeonState = dungeonState

					if settleTowerFloorTransition(runtime, dungeonState) then
						automationDecisions[runtime] = {
							Dungeon = dungeonState,
							Waiting = "tower_floor_transition_settle",
							Navigator = runtime.Navigator.GetState(),
						}
						task.wait(0.05)
						continue
					end

					local statusState = runtime.Status.GetAutomationState()
						or {
							MovementBlocked = false,
							SkillsBlocked = false,
						}
					updateSpeedBoost(runtime, statusState)
					updateDamageListener(runtime)
					updateFatalStatusWarning(runtime, statusState)
					local retreating, hazardHolding = handleDefense(runtime, statusState, dungeonState)

					if statusState.MovementBlocked then
						runtime.Navigator.Stop()
						Engine.StopSprint(runtime)
					else
						local rescuing = not retreating and rescueFrozenTeammate(runtime)

						if not rescuing then
							local claimingDungeonChest = false
							local dungeonChestStatus = nil
							local dungeonChest = nil

							if not retreating and not hazardHolding then
								claimingDungeonChest, dungeonChestStatus, dungeonChest =
									collectDungeonRewardChest(runtime)
							end

							if claimingDungeonChest then
								automationDecisions[runtime] = {
									Dungeon = dungeonState,
									DungeonRewardChest = dungeonChest,
									Collecting = true,
									CollectionError = dungeonChestStatus,
									Retreating = false,
									HazardHolding = false,
									Navigator = runtime.Navigator.GetState(),
								}
								task.wait(0.05)
								continue
							end

							local funneling, funnelStatus, funnelTarget = false, nil, nil

							if not retreating and not hazardHolding then
								funneling, funnelStatus, funnelTarget =
									handleMobFunnel(runtime, dungeonState)
							end

							if funneling then
								automationDecisions[runtime] = {
									Dungeon = dungeonState,
									FunnelTarget = funnelTarget,
									Funneling = true,
									RouteError = funnelStatus,
									Retreating = false,
									HazardHolding = false,
									Navigator = runtime.Navigator.GetState(),
								}
								task.wait(0.05)
								continue
							end

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

							local questNeedsGenericCombat = questUsesGenericCombat(questState)
							local dungeonNeedsGenericCombat = dungeonState and dungeonState.Active == true
							local unrestrictedCombat = questNeedsGenericCombat or dungeonNeedsGenericCombat
							local towerHoldPosition = dungeonState
								and dungeonState.IsCelestialTower
								and dungeonState.Tower
								and dungeonState.Tower.HoldPosition
								or nil
							local dungeonOrigin = towerHoldPosition

							if
								dungeonState
								and dungeonState.Active
								and runtime.State:Get("Dungeons.DefensePriority", true)
								and dungeonState.PriorityOrigin
							then
								dungeonOrigin = dungeonState.PriorityOrigin
							end

							local dungeonCombatRange = typeof(towerHoldPosition) == "Vector3" and 350
								or math.huge

							if
								not questHandled
								and not questRequiresRouting(questState)
								and (runtime.State:Get("Farming.Enabled", false) or unrestrictedCombat)
							then
								farmTarget, farmDescriptor = Engine.GetTarget(
									runtime,
									unrestrictedCombat and dungeonCombatRange or nil,
									unrestrictedCombat,
									dungeonOrigin
								)
							end

							local target = nil
							local descriptor = nil

							if questTarget then
								target = questTarget
								descriptor = questDescriptor
							elseif farmTarget then
								target = farmTarget
								descriptor = farmDescriptor
							end
							local questCombatRoute = nil
							local dungeonCombatRoute = nil

							if target and descriptor and skipStalledTarget(runtime, target, descriptor) then
								target = nil
								descriptor = nil
								questTarget = nil
								questDescriptor = nil
								farmTarget = nil
								farmDescriptor = nil
							end

							if
								questTarget
								and questDescriptor
								and runtime.QuestsAPI
								and runtime.State:Get("Quests.RouteToArea", true)
							then
								local routeOk, resolvedRoute =
									pcall(runtime.QuestsAPI.GetCombatRoute, questState, questDescriptor)

								if routeOk then
									questCombatRoute = resolvedRoute
								end
							end

							if
								not questCombatRoute
								and
								target
								and descriptor
								and dungeonState
								and dungeonState.Active
								and runtime.DungeonsAPI
								and runtime.State:Get("Dungeons.AutoProgression", true)
							then
								local routeOk, resolvedRoute =
									pcall(runtime.DungeonsAPI.GetCombatRoute, dungeonState, descriptor)

								if routeOk then
									dungeonCombatRoute = resolvedRoute
								end
							end

							local combatRoute = questCombatRoute or dungeonCombatRoute
							local collectible = not combatRoute
									and not retreating
									and not hazardHolding
									and not questHandled
									and getCollectible(runtime, target ~= nil, questState)
								or nil
							local collecting, collectionError = collect(runtime, collectible)
							local routing = false
							local routeError = nil
							local approaching = false
							local approachError = nil
							local attackAttempted = false

							if
								not collecting
								and not retreating
								and not hazardHolding
								and not questHandled
							then
								if combatRoute then
									routing, routeError = moveToPoint(
										runtime,
										combatRoute.Position,
										combatRoute.StopDistance,
										questCombatRoute and "QuestInteriorRoute" or "DungeonInteriorRoute",
										{
											MovementMode = combatRoute.MovementMode,
											FlightGroundSafety = combatRoute.FlightGroundSafety,
											FlightCruiseHeight = combatRoute.FlightCruiseHeight,
											FlightNoclip = combatRoute.FlightNoclip,
										}
									)
								elseif not target and dungeonState and dungeonState.Active then
									routing, routeError = routeDungeon(runtime, dungeonState)
								elseif not target and questState and not questTarget then
									routing, routeError = routeQuest(runtime, questState, currentWorldOrder)
								end
							end

							if target and descriptor then
								if not retreating and not hazardHolding and not collecting and not routing then
									local rootPart = runtime.Game.GetRootPart()
									local undergroundMovement = dungeonState
											and dungeonState.Active
											and rootPart
											and typeof(descriptor.Position) == "Vector3"
											and not runtime.State:Get("Combat.BlatantMode", true)
											and (
												rootPart.Position.Y < 10
												or descriptor.Position.Y < 10
											)
											and {
												MovementMode = "Pathfinding",
												FlightGroundSafety = false,
												FlightCruiseHeight = 6,
												FlightNoclip = true,
											}
										or nil

									local moved, movementError =
										approachTarget(runtime, descriptor, undergroundMovement)
									approaching = moved == true
									approachError = movementError
								end

								if
									not retreating
									and not collecting
									and not routing
									and not statusState.SkillsBlocked
								then
									attackAttempted = useFarmAttack(runtime, target, descriptor) == true
								end
							elseif not retreating and not collecting and not routing and not questHandled then
								Engine.Stop(runtime)
							end

							automationDecisions[runtime] = {
								Quest = questState,
								Dungeon = dungeonState,
								QuestTarget = questDescriptor,
								FarmTarget = farmDescriptor,
								Collectible = collectible,
								Collecting = collecting == true,
								CollectionError = collectionError,
								Routing = routing == true,
								Approaching = approaching,
								ApproachError = approachError,
								AttackAttempted = attackAttempted,
								Funneling = false,
								AuraEnabled = runtime.State:Get("Combat.AuraEnabled", true),
								AuraClusterCount = type(descriptor) == "table"
										and tonumber(descriptor.ClusterCount)
									or nil,
								Retreating = retreating == true,
								HazardHolding = hazardHolding == true,
								RouteError = routeError,
								DungeonCombatRoute = dungeonCombatRoute,
								QuestCombatRoute = questCombatRoute,
								CurrentWorldOrder = currentWorldOrder,
								Navigator = runtime.Navigator.GetState(),
							}
						end
					end

					local updateInterval = tonumber(runtime.State:Get("Farming.UpdateInterval", 0.1)) or 0.1
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
			activeSlotTasks[runtime] = nil
			activePetTasks[runtime] = nil
			lastDodgeAttempts[runtime] = nil
			dodgeAttackStates[runtime] = nil
			lastDodgedDamage[runtime] = nil
			lastHealAttempts[runtime] = nil
			speedBoostWarnings[runtime] = nil
			fatalStatusWarnings[runtime] = nil
			lastQuestClaims[runtime] = nil
			visitedCollectibles[runtime] = nil
			lastWorldTravel[runtime] = nil
			lastDungeonTravel[runtime] = nil
			targetLocks[runtime] = nil
			lootWindows[runtime] = nil
			engagementStates[runtime] = nil
			targetBlacklists[runtime] = nil
			recoveryStates[runtime] = nil
			hazardStates[runtime] = nil
			funnelStates[runtime] = nil
			dungeonChestStates[runtime] = nil
			towerTransitionStates[runtime] = nil
			towerEntryTouchStates[runtime] = nil
			lastDirectAuraAttempts[runtime] = nil
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
