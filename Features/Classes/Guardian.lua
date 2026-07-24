return function()
	local GuardianFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, targetCount)
		if
			runtime.State:Get("Class.Guardian.AutoUltimate", true)
			and targetCount >= runtime.State:Get("Class.Guardian.UltimateMinimumTargets", 3)
		then
			local canUseUltimate = runtime.Guardian.CanUse("Ultimate")

			if canUseUltimate then
				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.Guardian.MaintainAggroDefense", true)
			and not runtime.Guardian.IsAggroDefenseActive()
			and targetCount >= runtime.State:Get("Class.Guardian.AggroMinimumTargets", 2)
		then
			local canUseAggroDraw = runtime.Guardian.CanUse("Skill1")

			if canUseAggroDraw then
				return "Skill1"
			end
		end

		if runtime.State:Get("Class.Guardian.UseSlashFury", true) then
			local canUseSlashFury = runtime.Guardian.CanUse("Skill3")

			if canUseSlashFury then
				return "Skill3"
			end
		end

		if runtime.State:Get("Class.Guardian.UseRockSpikes", true) then
			local canUseRockSpikes = runtime.Guardian.CanUse("Skill2")

			if canUseRockSpikes then
				return "Skill2"
			end
		end

		return "Primary"
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while not runtime.Stopped and runtime.State:Get("Class.Guardian.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 30)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Guardian.AutoUnsheath", true) then
						ready = runtime.Guardian.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Guardian.Use(chooseRotationSlot(runtime, targetCount or 1))
					end
				end

				task.wait(runtime.State:Get("Class.Guardian.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function GuardianFeature.Register(runtime, tab)
		runtime.State:Set("Class.Guardian.AutoAura", false)
		runtime.State:Set("Class.Guardian.AutoUnsheath", true)
		runtime.State:Set("Class.Guardian.MaintainAggroDefense", true)
		runtime.State:Set("Class.Guardian.AggroMinimumTargets", 2)
		runtime.State:Set("Class.Guardian.UseRockSpikes", true)
		runtime.State:Set("Class.Guardian.UseSlashFury", true)
		runtime.State:Set("Class.Guardian.AutoUltimate", true)
		runtime.State:Set("Class.Guardian.UltimateMinimumTargets", 3)
		runtime.State:Set("Class.Guardian.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Guardian automation")
		runtime.UI:CreateToggle(tab, "GuardianAutoAura", {
			Name = "Server-safe Guardian aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "GuardianAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GuardianAutoUnsheath", {
			Name = "Auto unsheath Greataxe",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Defense and crowd control")
		runtime.UI:CreateToggle(tab, "GuardianMaintainAggroDefense", {
			Name = "Maintain Aggro Defense",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.MaintainAggroDefense", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GuardianAggroMinimumTargets", {
			Name = "Minimum enemies for Aggro Draw",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.AggroMinimumTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GuardianUseRockSpikes", {
			Name = "Use Rock Spikes",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.UseRockSpikes", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GuardianUseSlashFury", {
			Name = "Use four-crescent Slash Fury",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.UseSlashFury", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GuardianAutoUltimate", {
			Name = "Auto Sword Prison at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GuardianUltimateMinimumTargets", {
			Name = "Minimum enemies for Sword Prison",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 3,
			Callback = function(value)
				runtime.State:Set("Class.Guardian.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Guardian behavior",
			"Aggro Draw applies Aggro Defense for 8 seconds and attracts valid enemies from up to 50 studs. Slash Fury launches four crescents and permits up to nine damage callbacks with 13-stud impact checks. Sword Prison emits four control pulses two seconds apart; each pulse applies a five-second stop to targets within 40 studs."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show defense and energy status",
			Callback = function()
				local energyState, energyError = runtime.Guardian.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Guardian status",
					"Aggro Defense: "
						.. (runtime.Guardian.IsAggroDefenseActive() and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Aggro Draw",
			Callback = function()
				runtime.Guardian.UseAggroDraw()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Rock Spikes",
			Callback = function()
				runtime.Guardian.UseRockSpikes()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Slash Fury",
			Callback = function()
				runtime.Guardian.UseSlashFury()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Guardian Dodge",
			Callback = function()
				runtime.Guardian.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Sword Prison when ready",
			Callback = function()
				local used, useError = runtime.Guardian.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Sword Prison", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return GuardianFeature
end
