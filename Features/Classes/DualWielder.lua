return function()
	local DualWielderFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.DualWielder.AutoUltimate", true) then
			local canUseUltimate = runtime.DualWielder.CanUse("Ultimate")

			if canUseUltimate then
				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.DualWielder.MaintainTempo", true)
			and not runtime.DualWielder.IsTempoActive()
		then
			local canUseTempo = runtime.DualWielder.CanUse("Skill1")

			if canUseTempo then
				return "Skill1"
			end
		end

		if runtime.State:Get("Class.DualWielder.BuildSpeedFirst", true) then
			local speedState = runtime.DualWielder.GetSpeedState()

			if speedState.Stacks < speedState.MaximumStacks then
				return "Primary"
			end
		end

		if runtime.State:Get("Class.DualWielder.UseCrossSlash", true) then
			local canUseCrossSlash = runtime.DualWielder.CanUse("Skill3")

			if canUseCrossSlash then
				return "Skill3"
			end
		end

		if runtime.State:Get("Class.DualWielder.UseLeapStrikes", true) then
			local canUseLeapStrikes = runtime.DualWielder.CanUse("Skill2")

			if canUseLeapStrikes then
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
			while
				not runtime.Stopped
				and runtime.State:Get("Class.DualWielder.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 20)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if
						ready
						and runtime.State:Get("Class.DualWielder.AutoUnsheath", true)
					then
						ready = runtime.DualWielder.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.DualWielder.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Class.DualWielder.AttackInterval", 0.1))
			end

			activeLoops[runtime] = nil
		end)
	end

	function DualWielderFeature.Register(runtime, tab)
		runtime.State:Set("Class.DualWielder.AutoAura", false)
		runtime.State:Set("Class.DualWielder.AutoUnsheath", true)
		runtime.State:Set("Class.DualWielder.MaintainTempo", true)
		runtime.State:Set("Class.DualWielder.BuildSpeedFirst", true)
		runtime.State:Set("Class.DualWielder.UseLeapStrikes", true)
		runtime.State:Set("Class.DualWielder.UseCrossSlash", true)
		runtime.State:Set("Class.DualWielder.AutoUltimate", true)
		runtime.State:Set("Class.DualWielder.AttackInterval", 0.1)

		runtime.UI:CreateSection(tab, "Dual Wielder automation")
		runtime.UI:CreateToggle(tab, "DualWielderAutoAura", {
			Name = "Server-safe Dual Wielder aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "DualWielderAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.1,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DualWielderAutoUnsheath", {
			Name = "Auto unsheath both Longswords",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Speed and recovery")
		runtime.UI:CreateToggle(tab, "DualWielderMaintainTempo", {
			Name = "Maintain maximum-speed Tempo",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.MaintainTempo", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DualWielderBuildSpeedFirst", {
			Name = "Build 10 speed stacks before skills",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.BuildSpeedFirst", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DualWielderUseLeapStrikes", {
			Name = "Use Leap Strikes",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.UseLeapStrikes", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DualWielderUseCrossSlash", {
			Name = "Use twin Cross Slash crescents",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.UseCrossSlash", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DualWielderAutoUltimate", {
			Name = "Auto Ultimate at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.DualWielder.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Dual Wielder behavior",
			"Successful hits build up to 10 speed stacks for 1.5x animation speed; the stacks reset after 3 seconds without a hit. Tempo immediately grants maximum speed for 6 seconds. Every kill during Tempo refreshes the status for 4 seconds and heals 5% of maximum health. The full-energy Ultimate can produce nine cone hits, sixteen falling swords, and four slam hits."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show speed, Tempo, and energy",
			Callback = function()
				local speedState = runtime.DualWielder.GetSpeedState()
				local energyState, energyError = runtime.DualWielder.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Dual Wielder status",
					"Speed stacks: "
						.. tostring(speedState.Stacks)
						.. "/"
						.. tostring(speedState.MaximumStacks)
						.. " ("
						.. string.format("%.2fx", speedState.Multiplier)
						.. ")"
						.. "\nTempo: "
						.. (speedState.Tempo and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					6,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Activate Tempo",
			Callback = function()
				runtime.DualWielder.UseAttackBuff()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Leap Strikes",
			Callback = function()
				runtime.DualWielder.UseLeapStrikes()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Cross Slash",
			Callback = function()
				runtime.DualWielder.UseCrossSlash()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Dual Wielder Dodge",
			Callback = function()
				runtime.DualWielder.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap active weapon perks",
			Callback = function()
				runtime.DualWielder.SwapPerk()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Ultimate when ready",
			Callback = function()
				local used, useError = runtime.DualWielder.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Dual Wielder Ultimate", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return DualWielderFeature
end
