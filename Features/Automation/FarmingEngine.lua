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
		local configuredRange =
			runtime.State:Get("Farming.TargetRange", 120)

		return {
			Mode = runtime.State:Get("Farming.TargetMode", "Nearest"),
			Range = math.min(
				tonumber(rangeOverride) or configuredRange,
				configuredRange
			),
			BossOnly = runtime.State:Get("Farming.BossOnly", false),
			EliteOnly = runtime.State:Get("Farming.EliteOnly", false),
			NameFilter = runtime.State:Get("Farming.NameFilter", ""),
			IncludeOwned = false,
		}
	end

	function Engine.GetTarget(runtime, rangeOverride)
		return runtime.MobsAPI.SelectTarget(
			Engine.GetOptions(runtime, rangeOverride)
		)
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
			runtime.Walkspeed.RemoveMultiplier(
				SPEED_MULTIPLIER_KEY,
				boosted.Character
			)
		end

		boostedCharacters[runtime] = nil
		speedBoostWarnings[runtime] = nil
	end

	local function updateSpeedBoost(runtime)
		local character = runtime.Game.GetCharacter()
		local boosted = boostedCharacters[runtime]
		local enabled =
			runtime.State:Get("Farming.SpeedBoostEnabled", false)
		local multiplier =
			runtime.State:Get("Farming.SpeedBoostMultiplier", 1.5)

		if
			boosted
			and (
				boosted.Character ~= character
				or not enabled
			)
		then
			Engine.ClearSpeedBoost(runtime)
			boosted = nil
		end

		if
			not enabled
			or not character
			or (
				boosted
				and boosted.Multiplier == multiplier
			)
		then
			return
		end

		local previousFailure = speedBoostWarnings[runtime]

		if
			previousFailure
			and previousFailure.Character == character
			and previousFailure.Multiplier == multiplier
		then
			return
		end

		local applied, applyError = runtime.Walkspeed.ApplyMultiplier(
			SPEED_MULTIPLIER_KEY,
			multiplier,
			character
		)

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
			runtime.UI:Notify(
				"Automation speed",
				"Walkspeed multiplier was rejected: "
					.. tostring(applyError),
				5,
				0
			)
		end
	end

	local function disconnectDamageListener(runtime)
		local listener = damageListeners[runtime]

		if listener and listener.Connection then
			local connection = listener.Connection
			local disconnect =
				connection.Disconnect
				or connection.disconnect
				or connection.Destroy

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

		local connection = runtime.Health.ObserveHits(
			function(attacker, amount)
				recentDamage[runtime] = {
					At = os.clock(),
					Attacker = attacker,
					Amount = tonumber(amount) or 0,
				}
			end,
			character
		)

		if connection then
			damageListeners[runtime] = {
				Character = character,
				Connection = connection,
			}
		end
	end

	local function getPreferredDistance(runtime, adapter)
		local stoppingDistance =
			runtime.State:Get("Farming.StopDistance", 10)

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

		local preferred = math.min(
			runtime.State:Get("Farming.KiteDistance", 28),
			primaryRange - 5,
			runtime.State:Get("Farming.AttackRange", 45) - 3
		)

		return math.max(stoppingDistance, preferred), true
	end

	local function approachTarget(runtime, descriptor)
		if not runtime.State:Get("Farming.AutoApproach", true) then
			return false
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		local stopDistance, canKite =
			getPreferredDistance(runtime, adapter)

		if
			canKite
			and descriptor.Distance < stopDistance - 3
		then
			local playerSpeed = runtime.Walkspeed.Get()
			local targetSpeed =
				runtime.Walkspeed.Get(descriptor.Model)

			if
				playerSpeed
				and (
					not targetSpeed
					or playerSpeed >= targetSpeed * 0.9
				)
			then
				runtime.Navigator.RetreatFrom(
					descriptor.Position,
					math.max(
						8,
						stopDistance - descriptor.Distance + 6
					),
					{
						AutoJump = runtime.State:Get(
							"Farming.AutoJump",
							true
						),
						RepathInterval = runtime.State:Get(
							"Farming.RepathInterval",
							1.25
						),
						StuckTimeout = runtime.State:Get(
							"Farming.StuckTimeout",
							0.9
						),
					}
				)
				return true
			end
		end

		if
			runtime.State:Get("Farming.AutoSprint", true)
			and descriptor.Distance > stopDistance + 5
		then
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
			{
				StopDistance = stopDistance,
				AutoJump = runtime.State:Get(
					"Farming.AutoJump",
					true
				),
				RepathInterval = runtime.State:Get(
					"Farming.RepathInterval",
					1.25
				),
				StuckTimeout = runtime.State:Get(
					"Farming.StuckTimeout",
					0.9
				),
			}
		)

		if
			not moved
			and movementError == "movement_controller_unavailable"
			and not movementWarnings[runtime]
		then
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
		if
			slot == "Ultimate"
			and not runtime.State:Get("Farming.UseUltimate", true)
		then
			return false
		end

		if slot == "Ultimate" and runtime.Energy.IsFull() ~= true then
			return false
		end

		local attempts = lastSlotAttempts[runtime] or {}
		lastSlotAttempts[runtime] = attempts
		local retryInterval =
			runtime.State:Get("Farming.SkillRetryInterval", 0.6)

		if
			attempts[slot]
			and os.clock() - attempts[slot] < retryInterval
		then
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
		elseif
			slot == "Primary"
			and adapter
			and type(adapter.UsePrimary) == "function"
		then
			pcall(adapter.UsePrimary)
		else
			pcall(runtime.Actions.UseSkill, slot)
		end

		return true
	end

	local function useFarmAttack(runtime, target, descriptor)
		if
			not runtime.State:Get("Farming.AutoAttack", true)
			or descriptor.Distance
				> runtime.State:Get("Farming.AttackRange", 45)
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
			runtime.Actions.AimAtTarget(
				target,
				runtime.State:Get("Combat.AimDuration", 0.2)
			)
		end

		local mode =
			runtime.State:Get("Farming.RotationMode", "Full Rotation")

		if mode == "Primary Only" then
			return attemptSlot(runtime, adapter, "Primary")
		elseif mode == "Selected Slot" then
			return attemptSlot(
				runtime,
				adapter,
				runtime.State:Get("Farming.AttackSlot", "Primary")
			)
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
			return health.Ratio
		end

		local humanoid = runtime.Game.GetHumanoid()

		if humanoid and humanoid.MaxHealth > 0 then
			return math.clamp(
				humanoid.Health / humanoid.MaxHealth,
				0,
				1
			)
		end

		return 1
	end

	function Engine.GetSurvivalState(runtime)
		local health = runtime.Health.GetState()

		if health then
			return {
				HealthRatio = health.Ratio,
				ProtectionRatio =
					health.ProtectionRatio or health.Ratio,
				Barrier = health.Barrier or 0,
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
		return {
			AutoJump = runtime.State:Get("Farming.AutoJump", true),
			RepathInterval = runtime.State:Get(
				"Farming.RepathInterval",
				1.25
			),
			StuckTimeout = runtime.State:Get(
				"Farming.StuckTimeout",
				0.9
			),
		}
	end

	local function dodgeThreat(runtime, adapter, threat, healthRatio)
		local damage = recentDamage[runtime]
		local damagedRecently =
			runtime.State:Get("Farming.DodgeAfterDamage", true)
			and damage
			and os.clock() - damage.At
				<= runtime.State:Get(
					"Farming.DamageReactionWindow",
					1.25
				)

		if
			not runtime.State:Get("Farming.AutoDodge", true)
			or (
				(not threat or threat.Count <= 0)
				and not damagedRecently
			)
			or (
				(not threat or threat.AttackingCount <= 0)
				and healthRatio
					> runtime.State:Get(
						"Farming.DodgeHealthThreshold",
						70
					) / 100
				and not damagedRecently
			)
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

	local function useEmergencyHeal(runtime, healthRatio)
		if
			not runtime.State:Get("Farming.AutoHealItem", false)
			or healthRatio
				> runtime.State:Get(
					"Farming.HealItemHealthThreshold",
					40
				) / 100
		then
			return false
		end

		local itemName =
			tostring(runtime.State:Get("Farming.HealItemName", ""))

		if itemName == "" then
			return false
		end

		local retryInterval =
			runtime.State:Get("Farming.HealItemRetryInterval", 5)
		local lastAttempt = lastHealAttempts[runtime] or 0

		if os.clock() - lastAttempt < retryInterval then
			return false
		end

		lastHealAttempts[runtime] = os.clock()
		pcall(runtime.Actions.UseQuickItem, itemName)
		return true
	end

	local function handleDefense(runtime)
		local threat = runtime.MobsAPI.GetThreatState(
			runtime.State:Get("Farming.ThreatRadius", 25)
		)
		local survival = Engine.GetSurvivalState(runtime)
		local adapter = runtime.ClassRegistry.GetCurrentAdapter()
		useEmergencyHeal(runtime, survival.HealthRatio)
		dodgeThreat(
			runtime,
			adapter,
			threat,
			survival.ProtectionRatio
		)

		if
			runtime.State:Get("Farming.EmergencyRetreat", true)
			and threat
			and threat.Nearest
			and survival.ProtectionRatio
				<= runtime.State:Get(
					"Farming.RetreatHealthThreshold",
					30
				) / 100
		then
			runtime.Navigator.RetreatFrom(
				threat.Nearest.Position,
				runtime.State:Get("Farming.RetreatDistance", 35),
				getNavigationOptions(runtime)
			)
			return true
		end

		return false
	end

	function Engine.Start(runtime, targetProvider)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Farming.Enabled", false)
			do
				updateSpeedBoost(runtime)
				updateDamageListener(runtime)
				local incapacitated =
					runtime.Status.IsIncapacitated()

				if incapacitated then
					runtime.Navigator.Stop()
					Engine.StopSprint(runtime)
				else
					local target, descriptor =
						Engine.GetTarget(runtime)

					if target and descriptor then
						if not handleDefense(runtime) then
							approachTarget(runtime, descriptor)
							useFarmAttack(
								runtime,
								target,
								descriptor
							)
						end
					else
						Engine.Stop(runtime)
					end
				end

				task.wait(
					runtime.State:Get("Farming.UpdateInterval", 0.2)
				)
			end

			Engine.Stop(runtime)
			Engine.ClearSpeedBoost(runtime)
			disconnectDamageListener(runtime)
			runtime.Actions.ClearTargetProvider(targetProvider)
			activeLoops[runtime] = nil
			movementWarnings[runtime] = nil
			rotationCursors[runtime] = nil
			lastSlotAttempts[runtime] = nil
			lastDodgeAttempts[runtime] = nil
			lastHealAttempts[runtime] = nil
			speedBoostWarnings[runtime] = nil
		end)
	end

	return Engine
end
