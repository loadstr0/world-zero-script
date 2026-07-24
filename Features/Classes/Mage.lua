return function()
	local MageFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, target, targetCount)
		local targetDistance = runtime.Mage.GetTargetDistance(target)

		if
			runtime.State:Get("Class.Mage.AutoUltimate", true)
			and targetCount >= runtime.State:Get("Class.Mage.UltimateMinimumTargets", 2)
			and targetDistance
			and targetDistance <= runtime.State:Get("Class.Mage.UltimateMaximumRange", 60)
			and runtime.Mage.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			runtime.State:Get("Class.Mage.UseArcaneWave", true)
			and targetCount >= runtime.State:Get("Class.Mage.WaveMinimumTargets", 2)
			and targetDistance
			and targetDistance <= runtime.State:Get("Class.Mage.WaveMaximumRange", 35)
			and runtime.Mage.CanUse("Skill2")
		then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Mage.UseArcaneBlast", true)
			and runtime.Mage.CanUse("Skill1")
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
			while not runtime.Stopped and runtime.State:Get("Class.Mage.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 45)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Mage.AutoUnsheath", true) then
						ready = runtime.Mage.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Mage.Use(
							chooseRotationSlot(runtime, target, targetCount or 1)
						)
					end
				end

				task.wait(runtime.State:Get("Class.Mage.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function MageFeature.Register(runtime, tab)
		runtime.State:Set("Class.Mage.AutoAura", false)
		runtime.State:Set("Class.Mage.AutoUnsheath", true)
		runtime.State:Set("Class.Mage.UseArcaneBlast", true)
		runtime.State:Set("Class.Mage.UseArcaneWave", true)
		runtime.State:Set("Class.Mage.WaveMinimumTargets", 2)
		runtime.State:Set("Class.Mage.WaveMaximumRange", 35)
		runtime.State:Set("Class.Mage.AutoUltimate", true)
		runtime.State:Set("Class.Mage.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Mage.UltimateMaximumRange", 60)
		runtime.State:Set("Class.Mage.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Mage automation")
		runtime.UI:CreateToggle(tab, "MageAutoAura", {
			Name = "Server-safe Mage aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Mage.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "MageAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Mage.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageAutoUnsheath", {
			Name = "Auto unsheath Staff",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Mage.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Arcane rotation")
		runtime.UI:CreateToggle(tab, "MageUseArcaneBlast", {
			Name = "Use direct and splash Arcane Blast",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Mage.UseArcaneBlast", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageUseArcaneWave", {
			Name = "Use up-to-12-event Arcane Wave",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Mage.UseArcaneWave", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageWaveMinimumTargets", {
			Name = "Minimum enemies for Arcane Wave",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Mage.WaveMinimumTargets", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageWaveMaximumRange", {
			Name = "Maximum target distance for Arcane Wave",
			Range = { 10, 50 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 35,
			Callback = function(value)
				runtime.State:Set("Class.Mage.WaveMaximumRange", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Arcane Ascension")
		runtime.UI:CreateToggle(tab, "MageAutoUltimate", {
			Name = "Auto Arcane Ascension at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Mage.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageUltimateMinimumTargets", {
			Name = "Minimum enemies for Arcane Ascension",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Mage.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageUltimateMaximumRange", {
			Name = "Maximum target distance for Ascension",
			Range = { 20, 60 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 60,
			Callback = function(value)
				runtime.State:Set("Class.Mage.UltimateMaximumRange", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Mage behavior",
			"Arcane Orbs can be cast while moving. Arcane Blast deals direct damage plus a 15-stud splash hit. Arcane Wave creates four forward bursts and accepts up to 12 validated damage callbacks. Arcane Ascension targets enemies from up to 60 studs, waits 2 seconds, then detonates a 20-stud explosion."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show energy and target distance",
			Callback = function()
				local energyState, energyError = runtime.Mage.GetEnergyState()
				local target =
					runtime.Actions.GetNearestTarget(runtime.State:Get("Combat.TargetRange", 45))
				local targetDistance = runtime.Mage.GetTargetDistance(target)
				local distanceText = targetDistance
						and tostring(math.floor(targetDistance)) .. " studs"
					or "no target"
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Mage status",
					"Energy: " .. energyText .. "\nNearest target: " .. distanceText,
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Arcane Blast",
			Callback = function()
				runtime.Mage.UseArcaneBlast()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Arcane Wave",
			Callback = function()
				runtime.Mage.UseArcaneWave()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Mage Dodge",
			Callback = function()
				runtime.Mage.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Arcane Ascension when ready",
			Callback = function()
				local used, useError = runtime.Mage.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Arcane Ascension", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return MageFeature
end
