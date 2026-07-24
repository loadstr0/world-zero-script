return function()
	local PaladinFeature = {}
	local activeLoops = {}

	local function getHealthRatio(runtime)
		local health = runtime.Paladin.GetHealthState()
		return health and health.Ratio or 1
	end

	local function hasSupportEmergency(runtime, thresholdKey, defaultThreshold)
		local threshold = runtime.State:Get(thresholdKey, defaultThreshold)

		if getHealthRatio(runtime) <= threshold / 100 then
			return true
		end

		return runtime.Paladin.HasInjuredAlly(40, threshold)
	end

	local function shouldUseRetribution(runtime, targetCount)
		if not runtime.State:Get("Class.Paladin.AutoRetribution", true) then
			return false
		end

		local supportNeeded = hasSupportEmergency(
			runtime,
			"Class.Paladin.RetributionHealthThreshold",
			70
		)

		if supportNeeded then
			return true
		end

		if runtime.State:Get("Class.Paladin.RetributionSupportOnly", false) then
			return false
		end

		return targetCount
			>= runtime.State:Get("Class.Paladin.RetributionMinimumTargets", 2)
	end

	local function shouldUseUltimate(runtime, targetCount)
		if not runtime.State:Get("Class.Paladin.AutoUltimate", true) then
			return false
		end

		local emergency = hasSupportEmergency(
			runtime,
			"Class.Paladin.UltimateEmergencyThreshold",
			40
		)

		if emergency then
			return true
		end

		if runtime.State:Get("Class.Paladin.SaveUltimateForEmergency", false) then
			return false
		end

		return targetCount
			>= runtime.State:Get("Class.Paladin.UltimateMinimumTargets", 2)
	end

	local function chooseRotationSlot(runtime, target, targetCount)
		if
			shouldUseUltimate(runtime, targetCount)
			and runtime.Paladin.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			shouldUseRetribution(runtime, targetCount)
			and runtime.Paladin.CanUse("Skill2")
		then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Paladin.AutoBlock", true)
			and getHealthRatio(runtime)
				<= runtime.State:Get("Class.Paladin.BlockHealthThreshold", 80) / 100
			and targetCount
				>= runtime.State:Get("Class.Paladin.BlockMinimumTargets", 1)
			and runtime.Paladin.CanUse("Skill1")
		then
			return "Skill1"
		end

		local targetDistance = runtime.Paladin.GetTargetDistance(target)

		if
			target
			and runtime.State:Get("Class.Paladin.MaintainLightSword", true)
			and not runtime.Paladin.IsLightSwordActive()
			and targetDistance
			and targetDistance <= 60
			and runtime.Paladin.CanUse("Skill3")
		then
			return "Skill3"
		end

		if
			targetDistance
			and targetDistance <= runtime.Paladin.GetPrimaryRange()
			and runtime.Paladin.CanUse("Primary")
		then
			return "Primary"
		end

		return nil
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Class.Paladin.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 40)
				local target = runtime.Actions.GetNearestTarget(range)
				local supportNeeded = hasSupportEmergency(
					runtime,
					"Class.Paladin.RetributionHealthThreshold",
					70
				) or hasSupportEmergency(
					runtime,
					"Class.Paladin.UltimateEmergencyThreshold",
					40
				)

				if
					(target or supportNeeded)
					and runtime.Actions.IsBusy() ~= true
				then
					local targetCount = 0

					if target then
						targetCount =
							runtime.CombatAPI.CountTargetsInRadius(range) or 1
					end

					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local combatReady =
						target ~= nil and targetCount >= minimumTargets

					if combatReady or supportNeeded then
						local slot =
							chooseRotationSlot(runtime, target, targetCount)
						local ready = slot ~= nil

						if
							ready
							and runtime.State:Get("Class.Paladin.AutoUnsheath", true)
						then
							ready = runtime.Paladin.EnsureUnsheathed()
						end

						if ready then
							if
								target
								and runtime.State:Get("Combat.AutoAim", true)
							then
								local duration =
									runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							runtime.Paladin.Use(slot)
						end
					end
				end

				task.wait(runtime.State:Get("Class.Paladin.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function PaladinFeature.Register(runtime, tab)
		runtime.State:Set("Class.Paladin.AutoAura", false)
		runtime.State:Set("Class.Paladin.AutoUnsheath", true)
		runtime.State:Set("Class.Paladin.MaintainLightSword", true)
		runtime.State:Set("Class.Paladin.AutoBlock", true)
		runtime.State:Set("Class.Paladin.BlockHealthThreshold", 80)
		runtime.State:Set("Class.Paladin.BlockMinimumTargets", 1)
		runtime.State:Set("Class.Paladin.AutoRetribution", true)
		runtime.State:Set("Class.Paladin.RetributionHealthThreshold", 70)
		runtime.State:Set("Class.Paladin.RetributionSupportOnly", false)
		runtime.State:Set("Class.Paladin.RetributionMinimumTargets", 2)
		runtime.State:Set("Class.Paladin.AutoUltimate", true)
		runtime.State:Set("Class.Paladin.SaveUltimateForEmergency", false)
		runtime.State:Set("Class.Paladin.UltimateEmergencyThreshold", 40)
		runtime.State:Set("Class.Paladin.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Paladin.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Paladin automation")
		runtime.UI:CreateToggle(tab, "PaladinAutoAura", {
			Name = "Server-safe Paladin combat and support",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinAttackInterval", {
			Name = "Paladin rotation check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "PaladinAutoUnsheath", {
			Name = "Auto unsheath Longsword and Shield",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Paladin Light")
		runtime.UI:CreateToggle(tab, "PaladinMaintainLightSword", {
			Name = "Maintain enhanced Paladin Light",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.MaintainLightSword", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Enhanced Primary",
			"Light Thrust attacks twice 23 studs forward and grants Paladin Light for nine seconds. While active, Noble Slash changes to its enhanced damage identifier, grows from 16 to 21 studs, and widens from a 25-degree to a 45-degree cone."
		)

		runtime.UI:CreateSection(tab, "Gilded Block")
		runtime.UI:CreateToggle(tab, "PaladinAutoBlock", {
			Name = "Auto Gilded Block at low health",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AutoBlock", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinBlockHealthThreshold", {
			Name = "Block health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 80,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.BlockHealthThreshold", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinBlockMinimumTargets", {
			Name = "Minimum enemies before blocking",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.BlockMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified block behavior",
			"Gilded Block opens a one-second server blocking window and negates 80% of incoming damage. Every successfully blocked hit heals 5% maximum health, triggers splash damage, and increases nearby enemy focus within 50 studs."
		)

		runtime.UI:CreateSection(tab, "Divine Retribution")
		runtime.UI:CreateToggle(tab, "PaladinAutoRetribution", {
			Name = "Auto Divine Retribution",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AutoRetribution", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "PaladinRetributionSupportOnly", {
			Name = "Only cast Retribution for injured players",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.RetributionSupportOnly",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinRetributionHealthThreshold", {
			Name = "Retribution health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 70,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.RetributionHealthThreshold",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinRetributionMinimumTargets", {
			Name = "Minimum enemies for aggressive Retribution",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.RetributionMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Retribution support",
			"Divine Retribution damages enemies, heals players within 40 studs for 45% of the Paladin's maximum health, and grants a 45% defense boost for nine seconds. Its server implementation also removes negative statuses from the Paladin."
		)

		runtime.UI:CreateSection(tab, "Ring of Justice")
		runtime.UI:CreateToggle(tab, "PaladinAutoUltimate", {
			Name = "Auto Ring of Justice at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Paladin.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "PaladinSaveUltimateForEmergency", {
			Name = "Save Ring for a health emergency",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.SaveUltimateForEmergency",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinUltimateEmergencyThreshold", {
			Name = "Ring emergency health threshold",
			Range = { 10, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 40,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.UltimateEmergencyThreshold",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "PaladinUltimateMinimumTargets", {
			Name = "Minimum enemies for combat Ring",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.Paladin.UltimateMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Ring behavior",
			"Ring of Justice runs for 15 seconds. Each of its 15 pulses damages enemies, heals nearby players for 5% maximum health, clears statuses, and resets Judgment. It grants Paladin Light for the full duration and performs eight enemy-attraction checks."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Paladin support status",
			Callback = function()
				local health, healthError = runtime.Paladin.GetHealthState()
				local energyState, energyError = runtime.Paladin.GetEnergyState()
				local healthText = health
						and tostring(math.floor(health.Ratio * 100)) .. "%"
					or tostring(healthError)
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Paladin status",
					"Health: "
						.. healthText
						.. "\nEnergy: "
						.. energyText
						.. "\nNearby allies: "
						.. tostring(runtime.Paladin.CountNearbyAllies(40))
						.. "\nPaladin Light: "
						.. (
							runtime.Paladin.IsLightSwordActive()
								and "active"
							or "inactive"
						)
						.. "\nDefense boost: "
						.. (
							runtime.Paladin.HasDefenseBoost()
								and "active"
							or "inactive"
						)
						.. "\nRing: "
						.. (
							runtime.Paladin.IsUltimateActive()
								and "active"
							or "inactive"
						),
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Gilded Block",
			Callback = function()
				runtime.Paladin.UseGildedBlock()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Divine Retribution",
			Callback = function()
				runtime.Paladin.UseDivineRetribution()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Light Thrust",
			Callback = function()
				runtime.Paladin.UseLightThrust()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap primary and offhand perk",
			Callback = function()
				runtime.Paladin.UsePerkSwap()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Paladin Dodge",
			Callback = function()
				runtime.Paladin.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Ring of Justice when ready",
			Callback = function()
				local used, useError = runtime.Paladin.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Ring of Justice", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return PaladinFeature
end
