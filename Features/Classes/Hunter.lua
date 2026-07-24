return function()
	local HunterFeature = {}
	local activeLoops = {}

	local function healthEmergency(runtime, familiarState)
		if not runtime.State:Get("Class.Hunter.EmergencyDivineArrow", true) then
			return false
		end

		local threshold =
			runtime.State:Get("Class.Hunter.EmergencyHealthThreshold", 35) / 100
		local playerHealth = runtime.Hunter.GetPlayerHealthState()

		if playerHealth and playerHealth.Ratio <= threshold then
			return true
		end

		return familiarState.Health ~= nil and familiarState.Health.Ratio <= threshold
	end

	local function chooseRotationSlot(runtime, target, targetCount)
		local familiarState = runtime.Hunter.GetFamiliarState()

		if runtime.State:Get("Class.Hunter.AutoUltimate", true) then
			local minimumTargets =
				runtime.State:Get("Class.Hunter.UltimateMinimumTargets", 2)
			local wantsUltimate = targetCount >= minimumTargets
				or healthEmergency(runtime, familiarState)

			if wantsUltimate and runtime.Hunter.CanUse("Ultimate") then
				return "Ultimate"
			end
		end

		if familiarState.Tamed then
			if
				not familiarState.Active
				and runtime.State:Get("Class.Hunter.AutoSummonFamiliar", true)
				and runtime.Hunter.CanUseFamiliar()
			then
				return "Skill2"
			end

			if
				familiarState.Active
				and not familiarState.Frenzy
				and runtime.State:Get("Class.Hunter.AutoFrenzy", true)
				and runtime.Hunter.CanUseFamiliar()
			then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Hunter.UseVenomTrap", true) then
			local targetDistance = runtime.Hunter.GetTargetDistance(target)
			local trapRange = runtime.State:Get("Class.Hunter.TrapUseRange", 10)

			if
				targetDistance
				and targetDistance <= trapRange
				and runtime.Hunter.CanUse("Skill3")
			then
				return "Skill3"
			end
		end

		if
			runtime.State:Get("Class.Hunter.UseBlazingShot", true)
			and runtime.Hunter.CanUse("Skill1")
		then
			return "Skill1"
		end

		return "Primary"
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while not runtime.Stopped and runtime.State:Get("Class.Hunter.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 60)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Hunter.AutoUnsheath", true) then
						ready = runtime.Hunter.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Hunter.Use(
							chooseRotationSlot(runtime, target, targetCount or 1)
						)
					end
				end

				task.wait(runtime.State:Get("Class.Hunter.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function HunterFeature.Register(runtime, tab)
		runtime.State:Set("Class.Hunter.AutoAura", false)
		runtime.State:Set("Class.Hunter.AutoUnsheath", true)
		runtime.State:Set("Class.Hunter.AutoSummonFamiliar", true)
		runtime.State:Set("Class.Hunter.AutoFrenzy", true)
		runtime.State:Set("Class.Hunter.UseBlazingShot", true)
		runtime.State:Set("Class.Hunter.UseVenomTrap", true)
		runtime.State:Set("Class.Hunter.TrapUseRange", 10)
		runtime.State:Set("Class.Hunter.AutoUltimate", true)
		runtime.State:Set("Class.Hunter.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Hunter.EmergencyDivineArrow", true)
		runtime.State:Set("Class.Hunter.EmergencyHealthThreshold", 35)
		runtime.State:Set("Class.Hunter.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Hunter automation")
		runtime.UI:CreateToggle(tab, "HunterAutoAura", {
			Name = "Server-safe Hunter aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "HunterAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "HunterAutoUnsheath", {
			Name = "Auto unsheath Bow",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "HunterUseBlazingShot", {
			Name = "Use four-pulse Blazing Shot",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.UseBlazingShot", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Familiar")
		runtime.UI:CreateToggle(tab, "HunterAutoSummonFamiliar", {
			Name = "Auto summon an already-tamed Familiar",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AutoSummonFamiliar", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "HunterAutoFrenzy", {
			Name = "Maintain eight-second Familiar Frenzy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AutoFrenzy", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Trap and Divine Arrow")
		runtime.UI:CreateToggle(tab, "HunterUseVenomTrap", {
			Name = "Use four-second Venom Trap root",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.UseVenomTrap", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "HunterTrapUseRange", {
			Name = "Maximum target distance for trap",
			Range = { 4, 20 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 10,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.TrapUseRange", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "HunterAutoUltimate", {
			Name = "Auto Divine Arrow at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "HunterUltimateMinimumTargets", {
			Name = "Minimum enemies for Divine Arrow",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "HunterEmergencyDivineArrow", {
			Name = "Emergency Divine Arrow for low health",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.EmergencyDivineArrow", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "HunterEmergencyHealthThreshold", {
			Name = "Player or Familiar health threshold",
			Range = { 10, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 35,
			Callback = function(value)
				runtime.State:Set("Class.Hunter.EmergencyHealthThreshold", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Hunter behavior",
			"Blazing Shot leaves four damaging burn pulses. A summoned Familiar has 10x health scaling and attacks within 40 studs; Frenzy lasts 8 seconds, raises its attack ratio from 0.10 to 0.15, and grants 30% critical chance. Venom Trap stops targets for 4 seconds. Divine Arrow deals ten one-second pulses in a 50-stud area while healing Hunter and Familiar and granting the Familiar 80% defense."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Hunter and Familiar status",
			Callback = function()
				local familiar = runtime.Hunter.GetFamiliarState()
				local playerHealth, playerHealthError = runtime.Hunter.GetPlayerHealthState()
				local energyState, energyError = runtime.Hunter.GetEnergyState()
				local familiarHealth = familiar.Health
						and tostring(math.floor(familiar.Health.Ratio * 100)) .. "%"
					or "unavailable"
				local playerHealthText = playerHealth
						and tostring(math.floor(playerHealth.Ratio * 100)) .. "%"
					or tostring(playerHealthError)
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Hunter status",
					"Familiar: "
						.. (familiar.Tamed and familiar.Name or "not tamed")
						.. "\nSummoned: "
						.. (familiar.Active and "yes" or "no")
						.. "\nFrenzy: "
						.. (familiar.Frenzy and "active" or "inactive")
						.. "\nFamiliar health: "
						.. familiarHealth
						.. "\nPlayer health: "
						.. playerHealthText
						.. "\nEnergy: "
						.. energyText,
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Blazing Shot",
			Callback = function()
				runtime.Hunter.UseBlazingShot()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Tame / summon / Frenzy Familiar",
			Callback = function()
				runtime.Hunter.UseFamiliar()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Place Venom Trap",
			Callback = function()
				runtime.Hunter.UseVenomTrap()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Standing-still Trick Shot",
			Callback = function()
				runtime.Hunter.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Divine Arrow when ready",
			Callback = function()
				local used, useError = runtime.Hunter.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Divine Arrow", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return HunterFeature
end
