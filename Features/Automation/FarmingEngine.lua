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
	local lastDungeonTravel = {}
	local automationDecisions = {}
	local lastLoopWarnings = {}
	local targetLocks = {}
	local lootWindows = {}
	local engagementStates = {}
	local targetBlacklists = {}
	local recoveryStates = {}

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

		return {
			Mode = runtime.State:Get("Farming.TargetMode", "Nearest"),
			Range = bypassConfiguredRange and requestedRange or math.min(requestedRange, configuredRange),
			BossOnly = runtime.State:Get("Farming.BossOnly", false),
			EliteOnly = runtime.State:Get("Farming.EliteOnly", false),
			NameFilter = runtime.State:Get("Farming.NameFilter", ""),
			IncludeOwned = false,
			OriginPosition = originPosition,
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
				lootWindows[runtime] = os.clock()
					+ math.max(0, tonumber(runtime.State:Get("Loot.AfterKillSweepDuration", 2.5)) or 2.5)
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
		options.CFrameFlightSpeed = math.min(
			90,
			tonumber(runtime.State:Get("Farming.CFrameFlightSpeed", 90)) or 90
		)
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

		if
			not runtime.State:Get("Farming.AutoApproach", true)
			or not distance
			or typeof(descriptor.Position) ~= "Vector3"
		then
			return false
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		local stopDistance, canKite = getPreferredDistance(runtime, adapter)
		local targetPosition = descriptor.Position
		local root = runtime.Game.GetRootPart()
		local heightOffset = tonumber(runtime.State:Get("Farming.TargetHeightOffset", 0)) or 0

		if not root then
			return false
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
					}), movementOverrides)
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
			}), movementOverrides)
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

	local function canAttemptSlot(runtime, adapter, slot, descriptor)
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

		if slot == "Ultimate" and runtime.Energy.IsFull() ~= true then
			return false
		end

		local attempts = lastSlotAttempts[runtime] or {}
		lastSlotAttempts[runtime] = attempts
		local retryInterval = tonumber(runtime.State:Get("Farming.SkillRetryInterval", 0.2)) or 0.2

		if attempts[slot] and os.clock() - attempts[slot] < retryInterval then
			return false
		end

		if adapter and type(adapter.CanUse) == "function" then
			local ok, canUse = pcall(adapter.CanUse, slot)
			return ok and canUse == true
		end

		return runtime.Actions.IsOnCooldown(slot) ~= true
	end

	local function attemptSlot(runtime, adapter, slot, descriptor)
		if not canAttemptSlot(runtime, adapter, slot, descriptor) then
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
			return attemptSlot(runtime, adapter, "Primary", descriptor)
		elseif mode == "Selected Slot" then
			return attemptSlot(
				runtime,
				adapter,
				runtime.State:Get("Farming.AttackSlot", "Primary"),
				descriptor
			)
		end

		local rotation = buildRotation(runtime)

		if #rotation == 0 then
			return attemptSlot(runtime, adapter, "Primary", descriptor)
		end

		local cursor = rotationCursors[runtime] or 1

		for offset = 0, #rotation - 1 do
			local index = ((cursor + offset - 1) % #rotation) + 1
			local slot = rotation[index]

			if attemptSlot(runtime, adapter, slot, descriptor) then
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

	local function routeDungeon(runtime, dungeonState)
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
			and dungeonState.StartPosition
		then
			return moveDungeonPoint(dungeonState.StartPosition, 0, "TowerEntry")
		elseif
			dungeonState.Phase == "TowerAdvance"
			and runtime.State:Get("Dungeons.AutoTowerProgression", true)
			and dungeonState.ProgressionPosition
		then
			return moveDungeonPoint(dungeonState.ProgressionPosition, 0, "TowerPortal")
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
						FlightGroundSafety = progressionRoute.FlightGroundSafety,
						FlightCruiseHeight = progressionRoute.FlightCruiseHeight,
						FlightNoclip = progressionRoute.FlightNoclip,
					}
				)
			end

			return moveDungeonPoint(dungeonState.ProgressionPosition, 0, "DungeonProgression")
		elseif
			dungeonState.Phase == "TowerWaiting"
			and runtime.State:Get("Dungeons.HoldDefense", true)
			and dungeonState.HoldPosition
		then
			return moveDungeonPoint(dungeonState.HoldPosition, 8, "TowerWaiting")
		elseif
			dungeonState.Phase == "BetweenWaves"
			and runtime.State:Get("Dungeons.HoldDefense", true)
			and dungeonState.HoldPosition
		then
			return moveDungeonPoint(dungeonState.HoldPosition, 10, "DungeonDefense")
		elseif dungeonState.Phase == "BetweenWaves" then
			runtime.Navigator.Stop()
			return true, "dungeon_waiting_for_wave"
		end

		return false, "dungeon_mechanic_unresolved:" .. tostring(dungeonState.Phase)
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

		local recovery = recoveryStates[runtime]
		local resumeThreshold = math.max(
			retreatThreshold,
			tonumber(runtime.State:Get("Farming.RecoveryResumeThreshold", 85)) or 85
		) / 100
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
			and (recovery or (threat and threat.Nearest))
			and not (statusState and statusState.MovementBlocked)
			and (recovery or currentRatio <= retreatThreshold / 100)
		then
			local root = runtime.Game.GetRootPart()

			if not root then
				return true
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
				local height = runtime.State:Get("Farming.AirRecovery", true)
						and (tonumber(runtime.State:Get("Farming.AirRecoveryHeight", 70)) or 70)
					or 0

				recovery = {
					Character = root.Parent,
					Position = root.Position
						+ direction * distance
						+ Vector3.new(0, height, 0),
					StartedAt = os.clock(),
				}
				recoveryStates[runtime] = recovery
			end

			local retreatOptions = getNavigationOptions(runtime)
			retreatOptions.Owner = "EmergencyRecovery"
			retreatOptions.StopDistance = 2

			if runtime.State:Get("Farming.AirRecovery", true) then
				retreatOptions.MovementMode = "Smooth Flight"
				retreatOptions.FlightNoclip = true
				retreatOptions.FlightGroundSafety = true
				retreatOptions.FlightCruiseHeight = 8
			end

			runtime.Navigator.MoveTo(recovery.Position, retreatOptions)
			return true
		end

		if recovery then
			recoveryStates[runtime] = nil
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
							local dungeonState = nil

							if runtime.DungeonsAPI then
								local dungeonOk, resolvedDungeonState =
									pcall(runtime.DungeonsAPI.GetState)

								if dungeonOk then
									dungeonState = resolvedDungeonState
								end
							end

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
							local dungeonOrigin = dungeonState
								and dungeonState.Active
								and runtime.State:Get("Dungeons.DefensePriority", true)
								and dungeonState.PriorityOrigin
								or nil

							if
								not questHandled
								and not questRequiresRouting(questState)
								and (runtime.State:Get("Farming.Enabled", false) or unrestrictedCombat)
							then
								farmTarget, farmDescriptor = Engine.GetTarget(
									runtime,
									unrestrictedCombat and math.huge or nil,
									unrestrictedCombat,
									dungeonOrigin
								)
							end

							local target = questTarget or farmTarget
							local descriptor = questDescriptor or farmDescriptor
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
									and not questHandled
									and getCollectible(runtime, target ~= nil, questState)
								or nil
							local collecting, collectionError = collect(runtime, collectible)
							local routing = false
							local routeError = nil

							if
								not collecting
								and not retreating
								and not questHandled
							then
								if combatRoute then
									routing, routeError = moveToPoint(
										runtime,
										combatRoute.Position,
										combatRoute.StopDistance,
										questCombatRoute and "QuestInteriorRoute" or "DungeonInteriorRoute",
										{
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
								if not retreating and not collecting and not routing then
									local rootPart = runtime.Game.GetRootPart()
									local undergroundMovement = dungeonState
											and dungeonState.Active
											and rootPart
											and typeof(descriptor.Position) == "Vector3"
											and (
												rootPart.Position.Y < 10
												or descriptor.Position.Y < 10
											)
											and {
												FlightGroundSafety = false,
												FlightCruiseHeight = 6,
												FlightNoclip = true,
											}
										or nil

									approachTarget(runtime, descriptor, undergroundMovement)
								end

								if
									not retreating
									and not collecting
									and not routing
									and not statusState.SkillsBlocked
								then
									useFarmAttack(runtime, target, descriptor)
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
			lastDodgeAttempts[runtime] = nil
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
