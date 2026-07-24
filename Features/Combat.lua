return function()
	local Combat = {
		Id = "Combat",
	}

	local autoPrimaryLoopRunning = false

	local function startAutoPrimaryLoop(runtime)
		if autoPrimaryLoopRunning then
			return
		end

		autoPrimaryLoopRunning = true

		task.spawn(function()
			while not runtime.Stopped and runtime.State:Get("Combat.AutoPrimary", false) do
				local range = runtime.State:Get("Combat.TargetRange", 15)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					if runtime.State:Get("Combat.AutoAim", true) then
						local duration = runtime.State:Get("Combat.AimDuration", 0.2)
						runtime.Actions.AimAtNearestTarget(duration, range)
					end

					runtime.Actions.UseSkill("Primary")
				end

				task.wait(runtime.State:Get("Combat.AttackInterval", 0.15))
			end

			autoPrimaryLoopRunning = false
		end)
	end

	function Combat.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Combat)
		local actions = runtime.Actions.Describe()
		local status = actions.Available
				and ("Available; initialized: " .. tostring(actions.Initialized))
			or ("Unavailable: " .. tostring(actions.Error))

		runtime.UI:CreateSection(tab, "Integration status")
		runtime.UI:CreateParagraph(
			tab,
			"Client.Actions",
			status
				.. "\nVerified exports include skill use, cooldown queries, target selection, aiming, sprinting, mounting, and quick items."
		)
		runtime.State:Set("Combat.TargetRange", 15)
		runtime.State:Set("Combat.AimDuration", 0.2)
		runtime.State:Set("Combat.AttackInterval", 0.15)
		runtime.State:Set("Combat.AutoAim", true)
		runtime.State:Set("Combat.AutoPrimary", false)

		runtime.UI:CreateSection(tab, "Targeting")
		runtime.UI:CreateSlider(tab, "CombatTargetRange", {
			Name = "Target range",
			Range = { 5, 30 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 15,
			Callback = function(value)
				runtime.State:Set("Combat.TargetRange", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAimDuration", {
			Name = "Aim duration",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.2,
			Callback = function(value)
				runtime.State:Set("Combat.AimDuration", value)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Aim at nearest target",
			Callback = function()
				runtime.Actions.AimAtNearestTarget(
					runtime.State:Get("Combat.AimDuration", 0.2),
					runtime.State:Get("Combat.TargetRange", 15)
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAutoAim", {
			Name = "Auto aim before primary",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AutoAim", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Primary attack")
		runtime.UI:CreateButton(tab, {
			Name = "Use primary attack",
			Callback = function()
				runtime.Actions.UseSkill("Primary")
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Combat.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAutoPrimary", {
			Name = "Auto primary",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Combat.AutoPrimary", value)

				if value then
					startAutoPrimaryLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSection(tab, "Additional skills")
		runtime.UI:CreateParagraph(
			tab,
			"Source required",
			"Shared.Skills and the current class skillset are needed before secondary skill controls can be named and wired safely."
		)
	end

	return Combat
end
