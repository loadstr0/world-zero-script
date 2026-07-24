return function()
	local BerserkerFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.Berserker.AutoUltimate", true) then
			local canUseUltimate = runtime.Berserker.CanUse("Ultimate")

			if canUseUltimate then
				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.Berserker.RageBurstOnly", false)
			and not runtime.Berserker.IsRaging()
		then
			return "Primary"
		end

		if runtime.State:Get("Class.Berserker.UseFissure", true) then
			local canUseFissure = runtime.Berserker.CanUse("Skill3")

			if canUseFissure then
				return "Skill3"
			end
		end

		if runtime.State:Get("Class.Berserker.UseGigaSpin", true) then
			local canUseSpin = runtime.Berserker.CanUse("Skill2")

			if canUseSpin then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Berserker.UseAggroSlam", false) then
			local canUseSlam = runtime.Berserker.CanUse("Skill1")

			if canUseSlam then
				return "Skill1"
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
			while not runtime.Stopped and runtime.State:Get("Class.Berserker.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 20)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Berserker.AutoUnsheath", true) then
						ready = runtime.Berserker.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Berserker.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Class.Berserker.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function BerserkerFeature.Register(runtime, tab)
		runtime.State:Set("Class.Berserker.AutoAura", false)
		runtime.State:Set("Class.Berserker.AutoUnsheath", true)
		runtime.State:Set("Class.Berserker.UseAggroSlam", false)
		runtime.State:Set("Class.Berserker.UseGigaSpin", true)
		runtime.State:Set("Class.Berserker.UseFissure", true)
		runtime.State:Set("Class.Berserker.AutoUltimate", true)
		runtime.State:Set("Class.Berserker.RageBurstOnly", false)
		runtime.State:Set("Class.Berserker.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Berserker automation")
		runtime.UI:CreateToggle(tab, "BerserkerAutoAura", {
			Name = "Server-safe Berserker aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "BerserkerAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerAutoUnsheath", {
			Name = "Auto unsheath Greataxe",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerUseAggroSlam", {
			Name = "Use Aggro Slam (attracts enemy focus)",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.UseAggroSlam", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerUseGigaSpin", {
			Name = "Use 8-hit Giga Spin",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.UseGigaSpin", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerUseFissure", {
			Name = "Use Fissure in rotation",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.UseFissure", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerAutoUltimate", {
			Name = "Auto Rage at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "BerserkerRageBurstOnly", {
			Name = "Save class skills for Rage burst",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Berserker.RageBurstOnly", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Berserker behavior",
			"Rage lasts 15 seconds, grants 70% defense and 25% primary damage, and upgrades skills with burn and flame effects. Giga Spin checks eight 15-stud hits. Aggro Slam attacks in a 16-stud area and attracts mob focus from up to 65 studs."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Rage and energy status",
			Callback = function()
				local energyState, energyError = runtime.Berserker.GetEnergyState()
				local energyText = energyState
						and (
							tostring(math.floor(energyState.Ratio * 100))
							.. "% energy"
						)
					or tostring(energyError)

				runtime.UI:Notify(
					"Berserker status",
					"Rage: "
						.. (runtime.Berserker.IsRaging() and "active" or "inactive")
						.. "\n"
						.. energyText,
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Aggro Slam",
			Callback = function()
				runtime.Berserker.UseAggroSlam()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Giga Spin",
			Callback = function()
				runtime.Berserker.UseGigaSpin()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Fissure",
			Callback = function()
				runtime.Berserker.UseFissure()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Berserker Dodge",
			Callback = function()
				runtime.Berserker.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap active weapon perks",
			Callback = function()
				runtime.Berserker.SwapPerk()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Activate Rage when ready",
			Callback = function()
				local used, useError = runtime.Berserker.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Berserker Rage", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return BerserkerFeature
end
