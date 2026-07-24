return function()
	local SwordmasterFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.Swordmaster.UseSkill1", false) then
			local canUse = runtime.Swordmaster.CanUse("Skill1")

			if canUse then
				return "Skill1"
			end
		end

		if runtime.State:Get("Class.Swordmaster.UseSkill2", false) then
			local canUse = runtime.Swordmaster.CanUse("Skill2")

			if canUse then
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
				and runtime.State:Get("Class.Swordmaster.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 15)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Swordmaster.AutoUnsheath", true) then
						ready = runtime.Swordmaster.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Swordmaster.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Class.Swordmaster.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function SwordmasterFeature.Register(runtime, tab)
		runtime.State:Set("Class.Swordmaster.AutoAura", false)
		runtime.State:Set("Class.Swordmaster.AutoUnsheath", true)
		runtime.State:Set("Class.Swordmaster.UseSkill1", false)
		runtime.State:Set("Class.Swordmaster.UseSkill2", false)
		runtime.State:Set("Class.Swordmaster.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Swordmaster automation")
		runtime.UI:CreateToggle(tab, "SwordmasterAutoAura", {
			Name = "Server-safe Swordmaster aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Swordmaster.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "SwordmasterAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Swordmaster.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "SwordmasterAutoUnsheath", {
			Name = "Auto unsheath before attacking",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Swordmaster.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "SwordmasterUseSkill1", {
			Name = "Use Crescent Strike in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Swordmaster.UseSkill1", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "SwordmasterUseSkill2", {
			Name = "Use Leap Slash in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Swordmaster.UseSkill2", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Swordmaster behavior",
			"Primary chains six swings and resets after 0.75s. Primary range is 10 studs; Crescent Strike can acquire a mob up to 50 studs away."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Use Crescent Strike",
			Callback = function()
				runtime.Swordmaster.UseCrescentStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Leap Slash",
			Callback = function()
				runtime.Swordmaster.UseLeapSlash()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Dodge",
			Callback = function()
				runtime.Swordmaster.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Ultimate when charged",
			Callback = function()
				runtime.Swordmaster.UseUltimate()
			end,
		})
	end

	return SwordmasterFeature
end
