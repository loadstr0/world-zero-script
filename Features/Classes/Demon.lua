return function()
	local DemonFeature = {}
	local activeLoops = {}

	local function canUseDarkBinding(runtime)
		if not runtime.State:Get("Class.Demon.UseDarkBinding", false) then
			return false
		end

		local canUse = runtime.Demon.CanUse("Skill1")

		if not canUse then
			return false
		end

		return runtime.Demon.IsDarkBindingSafe(
			runtime.State:Get("Class.Demon.DarkBindingMinHealth", 50)
		)
	end

	local function healthRatio(runtime)
		local state = runtime.Demon.GetHealthState()
		return state and state.Ratio or 1
	end

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.Demon.AutoUltimate", true) then
			local canUseUltimate = runtime.Demon.CanUse("Ultimate")

			if canUseUltimate then
				if canUseDarkBinding(runtime) then
					return "Skill1"
				end

				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.Demon.PrioritizeLifeSteal", true)
			and healthRatio(runtime)
				<= runtime.State:Get("Class.Demon.LifeStealHealthThreshold", 60) / 100
		then
			local canUseLifeSteal = runtime.Demon.CanUse("Skill3")

			if canUseLifeSteal then
				return "Skill3"
			end
		end

		if
			canUseDarkBinding(runtime)
			and (
				not runtime.State:Get("Class.Demon.DarkBindingPrinceOnly", true)
				or runtime.Demon.IsDemonPrince()
			)
		then
			return "Skill1"
		end

		if runtime.State:Get("Class.Demon.UseScytheThrow", true) then
			local canUseThrow = runtime.Demon.CanUse("Skill2")

			if canUseThrow then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Demon.UseLifeSteal", true) then
			local canUseLifeSteal = runtime.Demon.CanUse("Skill3")

			if canUseLifeSteal then
				return "Skill3"
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
			while not runtime.Stopped and runtime.State:Get("Class.Demon.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 60)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Demon.AutoUnsheath", true) then
						ready = runtime.Demon.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						local slot = chooseRotationSlot(runtime)

						if slot == "Skill1" then
							runtime.Demon.UseDarkBinding(
								runtime.State:Get("Class.Demon.DarkBindingMinHealth", 50)
							)
						else
							runtime.Demon.Use(slot)
						end
					end
				end

				task.wait(runtime.State:Get("Class.Demon.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function DemonFeature.Register(runtime, tab)
		runtime.State:Set("Class.Demon.AutoAura", false)
		runtime.State:Set("Class.Demon.AutoUnsheath", true)
		runtime.State:Set("Class.Demon.UseDarkBinding", false)
		runtime.State:Set("Class.Demon.DarkBindingMinHealth", 50)
		runtime.State:Set("Class.Demon.DarkBindingPrinceOnly", true)
		runtime.State:Set("Class.Demon.UseScytheThrow", true)
		runtime.State:Set("Class.Demon.UseLifeSteal", true)
		runtime.State:Set("Class.Demon.PrioritizeLifeSteal", true)
		runtime.State:Set("Class.Demon.LifeStealHealthThreshold", 60)
		runtime.State:Set("Class.Demon.AutoUltimate", true)
		runtime.State:Set("Class.Demon.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Demon automation")
		runtime.UI:CreateToggle(tab, "DemonAutoAura", {
			Name = "Server-safe Demon aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Demon.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "DemonAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Demon.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonAutoUnsheath", {
			Name = "Auto unsheath Scythe",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonUseScytheThrow", {
			Name = "Use 8-target Scythe Throw",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.UseScytheThrow", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonUseLifeSteal", {
			Name = "Use Life Steal curse",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.UseLifeSteal", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonPrioritizeLifeSteal", {
			Name = "Prioritize Life Steal at low health",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.PrioritizeLifeSteal", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "DemonLifeStealHealthThreshold", {
			Name = "Life Steal priority threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 60,
			Callback = function(value)
				runtime.State:Set("Class.Demon.LifeStealHealthThreshold", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Dark Binding")
		runtime.UI:CreateToggle(tab, "DemonUseDarkBinding", {
			Name = "Use +25% damage Dark Binding",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Demon.UseDarkBinding", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "DemonDarkBindingMinHealth", {
			Name = "Minimum health before sacrifice",
			Range = { 30, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 50,
			Callback = function(value)
				runtime.State:Set("Class.Demon.DarkBindingMinHealth", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonDarkBindingPrinceOnly", {
			Name = "Save Dark Binding for Demon Prince",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.DarkBindingPrinceOnly", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DemonAutoUltimate", {
			Name = "Auto Demon Prince at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Demon.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Demon behavior",
			"Demon Prince lasts 20 seconds, adds 35% attack damage, spawns tracking orbs, and performs ten 33.3-stud damage-and-slow pulses. Scythe Throw can chain through eight targets. Life Steal curses up to three targets normally or ten during Demon Prince. Dark Binding adds 25% damage for 8 seconds but costs 30% maximum health."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Demon status",
			Callback = function()
				local healthState, healthError = runtime.Demon.GetHealthState()
				local energyState, energyError = runtime.Demon.GetEnergyState()
				local healthText = healthState
						and tostring(math.floor(healthState.Ratio * 100)) .. "%"
					or tostring(healthError)
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Demon status",
					"Health: "
						.. healthText
						.. "\nEnergy: "
						.. energyText
						.. "\nDemon Prince: "
						.. (runtime.Demon.IsDemonPrince() and "active" or "inactive")
						.. "\nOrbs: "
						.. tostring(runtime.Demon.GetOrbCount()),
					6,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Dark Binding safely",
			Callback = function()
				local used, useError = runtime.Demon.UseDarkBinding(
					runtime.State:Get("Class.Demon.DarkBindingMinHealth", 50)
				)

				if used == nil and useError then
					runtime.UI:Notify("Dark Binding", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Scythe Throw",
			Callback = function()
				runtime.Demon.UseScytheThrow()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Life Steal",
			Callback = function()
				runtime.Demon.UseLifeSteal()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Demon Dodge",
			Callback = function()
				runtime.Demon.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Transform into Demon Prince",
			Callback = function()
				local used, useError = runtime.Demon.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Demon Prince", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return DemonFeature
end
