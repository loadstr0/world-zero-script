return function()
	local ArcherFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.Archer.AutoUltimate", true) then
			local ultimateReady = runtime.Archer.IsUltimateReady()
			local canUseUltimate = runtime.Archer.CanUse("Ultimate")

			if ultimateReady and canUseUltimate then
				return "Ultimate"
			end
		end

		if runtime.State:Get("Class.Archer.UseSkill3", false) then
			local canUse = runtime.Archer.CanUse("Skill3")

			if canUse then
				return "Skill3"
			end
		end

		if runtime.State:Get("Class.Archer.UseSkill2", false) then
			local canUse = runtime.Archer.CanUse("Skill2")

			if canUse then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Archer.UseSkill1", false) then
			local canUse = runtime.Archer.CanUse("Skill1")

			if canUse then
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
			while not runtime.Stopped and runtime.State:Get("Class.Archer.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 60)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Archer.AutoUnsheath", true) then
						ready = runtime.Archer.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Archer.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Class.Archer.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function ArcherFeature.Register(runtime, tab)
		runtime.State:Set("Class.Archer.AutoAura", false)
		runtime.State:Set("Class.Archer.AutoUnsheath", true)
		runtime.State:Set("Class.Archer.UseSkill1", false)
		runtime.State:Set("Class.Archer.UseSkill2", false)
		runtime.State:Set("Class.Archer.UseSkill3", false)
		runtime.State:Set("Class.Archer.AutoUltimate", true)
		runtime.State:Set("Class.Archer.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Archer automation")
		runtime.UI:CreateToggle(tab, "ArcherAutoAura", {
			Name = "Server-safe Archer aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Archer.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "ArcherAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Archer.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "ArcherAutoUnsheath", {
			Name = "Auto unsheath bow",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Archer.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "ArcherUseSkill1", {
			Name = "Use Piercing Arrow in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Archer.UseSkill1", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "ArcherUseSkill2", {
			Name = "Use Spirit Bomb in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Archer.UseSkill2", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "ArcherUseSkill3", {
			Name = "Use Mortar Strike in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Archer.UseSkill3", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "ArcherAutoUltimate", {
			Name = "Auto Ultimate at 6 Great Spirit Arrows",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Archer.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Archer behavior",
			"Primary and class skills acquire targets up to 60 studs away. Piercing Arrow chains targets, Spirit Bomb slows in an 18-stud area, and Mortar Strike hits eight times over three seconds."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Great Spirit Arrow charge",
			Callback = function()
				local resourceState, resourceError = runtime.Archer.GetResourceState()

				if not resourceState then
					runtime.UI:Notify("Archer charge", tostring(resourceError), 5, 0)
					return
				end

				runtime.UI:Notify(
					"Archer charge",
					tostring(resourceState.GreatSpiritArrows)
						.. "/6 Great Spirit Arrows\nCurrent segment: "
						.. tostring(math.floor(resourceState.Energy))
						.. "%",
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Piercing Arrow",
			Callback = function()
				runtime.Archer.UsePiercingArrow()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Spirit Bomb",
			Callback = function()
				runtime.Archer.UseSpiritBomb()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Mortar Strike",
			Callback = function()
				runtime.Archer.UseMortarStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Archer Dodge",
			Callback = function()
				runtime.Archer.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Ultimate when charged",
			Callback = function()
				local used, useError = runtime.Archer.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Archer Ultimate", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return ArcherFeature
end
