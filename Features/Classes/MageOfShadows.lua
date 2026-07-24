return function()
	local MageOfShadowsFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, target, targetCount)
		local shadowForm = runtime.MageOfShadows.IsShadowFormActive()

		if
			runtime.State:Get("Class.MageOfShadows.AutoShadowForm", true)
			and targetCount
				>= runtime.State:Get("Class.MageOfShadows.ShadowFormMinimumTargets", 2)
			and runtime.MageOfShadows.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			runtime.State:Get("Class.MageOfShadows.AutoMerge", true)
			and runtime.MageOfShadows.CanMerge(
				runtime.State:Get("Class.MageOfShadows.MergeMinimumOrbs", 9)
			)
		then
			return "Skill2"
		end

		if
			shadowForm
			and runtime.State:Get(
				"Class.MageOfShadows.PrioritizePrimaryInShadowForm",
				false
			)
			and runtime.MageOfShadows.CanUse("Primary")
		then
			return "Primary"
		end

		local saveSkills =
			runtime.State:Get("Class.MageOfShadows.SaveSkillsForShadowForm", false)

		if not saveSkills or shadowForm then
			if
				runtime.State:Get("Class.MageOfShadows.UseShadowChains", true)
				and targetCount
					>= runtime.State:Get(
						"Class.MageOfShadows.ChainsMinimumTargets",
						2
					)
				and runtime.MageOfShadows.CanUse("Skill3")
			then
				return "Skill3"
			end

			local targetDistance = runtime.MageOfShadows.GetTargetDistance(target)

			if
				runtime.State:Get("Class.MageOfShadows.UseShadowExplosion", true)
				and targetDistance
				and targetDistance
					<= runtime.State:Get(
						"Class.MageOfShadows.ExplosionMaximumRange",
						20
					)
				and runtime.MageOfShadows.CanUse("Skill1")
			then
				return "Skill1"
			end
		end

		if runtime.MageOfShadows.CanUse("Primary") then
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
				and runtime.State:Get("Class.MageOfShadows.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 45)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)

					if targetCount == nil then
						targetCount = 1
					end

					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)

					if targetCount >= minimumTargets then
						local slot =
							chooseRotationSlot(runtime, target, targetCount)
						local ready = slot ~= nil

						if
							ready
							and runtime.State:Get(
								"Class.MageOfShadows.AutoUnsheath",
								true
							)
						then
							ready = runtime.MageOfShadows.EnsureUnsheathed()
						end

						if ready then
							if runtime.State:Get("Combat.AutoAim", true) then
								local duration =
									runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							if slot == "Skill2" then
								runtime.MageOfShadows.UseShadowMerge(
									runtime.State:Get(
										"Class.MageOfShadows.MergeMinimumOrbs",
										9
									)
								)
							else
								runtime.MageOfShadows.Use(slot)
							end
						end
					end
				end

				task.wait(
					runtime.State:Get("Class.MageOfShadows.AttackInterval", 0.15)
				)
			end

			activeLoops[runtime] = nil
		end)
	end

	function MageOfShadowsFeature.Register(runtime, tab)
		runtime.State:Set("Class.MageOfShadows.AutoAura", false)
		runtime.State:Set("Class.MageOfShadows.AutoUnsheath", true)
		runtime.State:Set("Class.MageOfShadows.AutoMerge", true)
		runtime.State:Set("Class.MageOfShadows.MergeMinimumOrbs", 9)
		runtime.State:Set("Class.MageOfShadows.UseShadowChains", true)
		runtime.State:Set("Class.MageOfShadows.ChainsMinimumTargets", 2)
		runtime.State:Set("Class.MageOfShadows.UseShadowExplosion", true)
		runtime.State:Set("Class.MageOfShadows.ExplosionMaximumRange", 20)
		runtime.State:Set("Class.MageOfShadows.AutoShadowForm", true)
		runtime.State:Set("Class.MageOfShadows.ShadowFormMinimumTargets", 2)
		runtime.State:Set("Class.MageOfShadows.SaveSkillsForShadowForm", false)
		runtime.State:Set(
			"Class.MageOfShadows.PrioritizePrimaryInShadowForm",
			false
		)
		runtime.State:Set("Class.MageOfShadows.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Mage of Shadows automation")
		runtime.UI:CreateToggle(tab, "MageOfShadowsAutoAura", {
			Name = "Server-safe Shadow combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfShadowsAttackInterval", {
			Name = "Shadow rotation check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfShadowsAutoUnsheath", {
			Name = "Auto unsheath Staff",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Orb control")
		runtime.UI:CreateToggle(tab, "MageOfShadowsAutoMerge", {
			Name = "Auto merge small orbs into hunters",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.AutoMerge", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfShadowsMergeMinimumOrbs", {
			Name = "Minimum small orbs before Shadow Merge",
			Range = { 3, 10 },
			Increment = 1,
			CurrentValue = 9,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.MergeMinimumOrbs", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfShadowsPrioritizePrimaryInForm", {
			Name = "Prioritize empowered Primary in Shadow Form",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.PrioritizePrimaryInShadowForm",
					value
				)
			end,
		})

		runtime.UI:CreateSection(tab, "Damage skills")
		runtime.UI:CreateToggle(tab, "MageOfShadowsUseChains", {
			Name = "Auto six-pulse Shadow Chains",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.UseShadowChains", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfShadowsChainsMinimumTargets", {
			Name = "Minimum enemies for Shadow Chains",
			Range = { 1, 5 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.ChainsMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfShadowsUseExplosion", {
			Name = "Auto close-range Shadow Explosion",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.UseShadowExplosion",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfShadowsExplosionMaximumRange", {
			Name = "Maximum target distance for Explosion",
			Range = { 5, 40 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 20,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.ExplosionMaximumRange",
					value
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfShadowsSaveSkillsForForm", {
			Name = "Save Chains and Explosion for Shadow Form",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.SaveSkillsForShadowForm",
					value
				)
			end,
		})

		runtime.UI:CreateSection(tab, "Shadow Form")
		runtime.UI:CreateToggle(tab, "MageOfShadowsAutoForm", {
			Name = "Auto Shadow Form at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfShadows.AutoShadowForm", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfShadowsFormMinimumTargets", {
			Name = "Minimum enemies for Shadow Form",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.MageOfShadows.ShadowFormMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Mage of Shadows behavior",
			"Shadow Seeker spends one of 10 regenerating small orbs and explodes in a 15-stud area. Shadow Merge consumes three small orbs per autonomous large orb, keeps at most three active, hunts within 30 studs, and lasts 24.5 seconds. Shadow Chains selects up to five enemies within 40 studs, slows them for six seconds, and deals six damage pulses. Shadow Form lasts 10 seconds, doubles orb generation to two per second, strengthens Primary, and grants 70% cooldown reduction."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Shadow combat status",
			Callback = function()
				local orbs = runtime.MageOfShadows.GetOrbState()
				local energyState, energyError =
					runtime.MageOfShadows.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Mage of Shadows status",
					"Small orbs: "
						.. tostring(orbs.Total)
						.. "/"
						.. tostring(orbs.Maximum)
						.. "\nAvailable merge groups: "
						.. tostring(orbs.MergeGroups)
						.. "\nShadow Form: "
						.. (
							runtime.MageOfShadows.IsShadowFormActive()
								and "active"
							or "inactive"
						)
						.. "\nFast cooldown: "
						.. (
							runtime.MageOfShadows.HasFastCooldown()
								and "active"
							or "inactive"
						)
						.. "\nEnergy: "
						.. energyText
						.. "\nActive large-orb count: game-private",
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Merge available Shadow Orbs",
			Callback = function()
				local used, useError = runtime.MageOfShadows.UseShadowMerge(3)

				if used == nil and useError then
					runtime.UI:Notify("Shadow Merge", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Shadow Explosion",
			Callback = function()
				runtime.MageOfShadows.UseShadowExplosion()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Shadow Chains",
			Callback = function()
				runtime.MageOfShadows.UseShadowChains()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Mage of Shadows Dodge",
			Callback = function()
				runtime.MageOfShadows.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Activate Shadow Form when ready",
			Callback = function()
				local used, useError = runtime.MageOfShadows.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Shadow Form", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return MageOfShadowsFeature
end
