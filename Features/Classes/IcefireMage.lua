return function()
	local IcefireMageFeature = {}
	local activeLoops = {}

	local function canUseCloseSkill(runtime, slot, targetDistance, rangeKey, defaultRange)
		return targetDistance
			and targetDistance <= runtime.State:Get(rangeKey, defaultRange)
			and runtime.IcefireMage.CanUse(slot)
	end

	local function chooseRotationSlot(runtime, target, targetCount)
		local targetDistance = runtime.IcefireMage.GetTargetDistance(target)

		if
			runtime.State:Get("Class.IcefireMage.AutoUltimate", true)
			and targetCount
				>= runtime.State:Get("Class.IcefireMage.UltimateMinimumTargets", 2)
			and targetDistance
			and targetDistance
				<= runtime.State:Get("Class.IcefireMage.UltimateMaximumRange", 30)
			and runtime.IcefireMage.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		local prioritizeSuperFrost =
			runtime.State:Get("Class.IcefireMage.PrioritizeSuperFrost", true)

		if
			prioritizeSuperFrost
			and runtime.State:Get("Class.IcefireMage.UseIcicleField", true)
			and canUseCloseSkill(
				runtime,
				"Skill1",
				targetDistance,
				"Class.IcefireMage.IcicleMaximumRange",
				20
			)
		then
			return "Skill1"
		end

		if
			runtime.State:Get("Class.IcefireMage.UseLightningStrike", true)
			and canUseCloseSkill(
				runtime,
				"Skill3",
				targetDistance,
				"Class.IcefireMage.LightningMaximumRange",
				25
			)
		then
			return "Skill3"
		end

		if
			runtime.State:Get("Class.IcefireMage.UseFireball", true)
			and runtime.IcefireMage.CanUse("Skill2")
		then
			return "Skill2"
		end

		if
			not prioritizeSuperFrost
			and runtime.State:Get("Class.IcefireMage.UseIcicleField", true)
			and canUseCloseSkill(
				runtime,
				"Skill1",
				targetDistance,
				"Class.IcefireMage.IcicleMaximumRange",
				20
			)
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
			while
				not runtime.Stopped
				and runtime.State:Get("Class.IcefireMage.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 45)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if
						ready
						and runtime.State:Get("Class.IcefireMage.AutoUnsheath", true)
					then
						ready = runtime.IcefireMage.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.IcefireMage.Use(
							chooseRotationSlot(runtime, target, targetCount or 1)
						)
					end
				end

				task.wait(runtime.State:Get("Class.IcefireMage.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function IcefireMageFeature.Register(runtime, tab)
		runtime.State:Set("Class.IcefireMage.AutoAura", false)
		runtime.State:Set("Class.IcefireMage.AutoUnsheath", true)
		runtime.State:Set("Class.IcefireMage.PrioritizeSuperFrost", true)
		runtime.State:Set("Class.IcefireMage.UseIcicleField", true)
		runtime.State:Set("Class.IcefireMage.IcicleMaximumRange", 20)
		runtime.State:Set("Class.IcefireMage.UseFireball", true)
		runtime.State:Set("Class.IcefireMage.UseLightningStrike", true)
		runtime.State:Set("Class.IcefireMage.LightningMaximumRange", 25)
		runtime.State:Set("Class.IcefireMage.AutoUltimate", true)
		runtime.State:Set("Class.IcefireMage.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.IcefireMage.UltimateMaximumRange", 30)
		runtime.State:Set("Class.IcefireMage.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Icefire Mage automation")
		runtime.UI:CreateToggle(tab, "IcefireMageAutoAura", {
			Name = "Server-safe Icefire Mage aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "IcefireMageAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "IcefireMageAutoUnsheath", {
			Name = "Auto unsheath Staff",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Elemental rotation")
		runtime.UI:CreateToggle(tab, "IcefireMagePrioritizeSuperFrost", {
			Name = "Prioritize Super Frost at close range",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.PrioritizeSuperFrost", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "IcefireMageUseIcicleField", {
			Name = "Use Super Frost Icicle Field",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.UseIcicleField", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "IcefireMageIcicleMaximumRange", {
			Name = "Maximum target distance for Icicle Field",
			Range = { 5, 30 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 20,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.IcicleMaximumRange", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "IcefireMageUseFireball", {
			Name = "Use Burn Fireball",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.UseFireball", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "IcefireMageUseLightningStrike", {
			Name = "Use Shock Lightning Strike",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.UseLightningStrike", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "IcefireMageLightningMaximumRange", {
			Name = "Maximum target distance for Lightning",
			Range = { 8, 35 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 25,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.LightningMaximumRange", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Meteor Crash")
		runtime.UI:CreateToggle(tab, "IcefireMageAutoUltimate", {
			Name = "Auto Meteor Crash at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "IcefireMageUltimateMinimumTargets", {
			Name = "Minimum enemies for Meteor Crash",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "IcefireMageUltimateMaximumRange", {
			Name = "Maximum target distance for Meteor Crash",
			Range = { 10, 40 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 30,
			Callback = function(value)
				runtime.State:Set("Class.IcefireMage.UltimateMaximumRange", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Icefire Mage behavior",
			"Ice Needle inflicts Frost, Icicle Field inflicts Super Frost, Fireball inflicts Burn with direct and 15-stud blast damage, and Lightning Strike inflicts Shock. Meteor Crash opens with a 20-stud Frost hit, drops nine 14-stud meteors, then finishes with a 20-stud giant meteor for up to 11 damage events."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show energy and target distance",
			Callback = function()
				local energyState, energyError = runtime.IcefireMage.GetEnergyState()
				local target =
					runtime.Actions.GetNearestTarget(runtime.State:Get("Combat.TargetRange", 45))
				local targetDistance = runtime.IcefireMage.GetTargetDistance(target)
				local distanceText = targetDistance
						and tostring(math.floor(targetDistance)) .. " studs"
					or "no target"
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Icefire Mage status",
					"Energy: " .. energyText .. "\nNearest target: " .. distanceText,
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Icicle Field",
			Callback = function()
				runtime.IcefireMage.UseIcicleField()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Fireball",
			Callback = function()
				runtime.IcefireMage.UseFireball()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Lightning Strike",
			Callback = function()
				runtime.IcefireMage.UseLightningStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Icefire Mage Dodge",
			Callback = function()
				runtime.IcefireMage.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Meteor Crash when ready",
			Callback = function()
				local used, useError = runtime.IcefireMage.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Meteor Crash", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return IcefireMageFeature
end
