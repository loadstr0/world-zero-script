return function()
	local StarbreakerFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, target, targetCount)
		local state = runtime.Starbreaker.GetStarforgeState()
		local targetDistance = runtime.Starbreaker.GetTargetDistance(target)

		if
			runtime.State:Get("Class.Starbreaker.AutoSupernova", true)
			and state.SupernovaReady
			and targetDistance
			and targetDistance <= 21
			and runtime.Starbreaker.CanUse("Skill1")
		then
			return "Skill1"
		end

		if
			runtime.State:Get("Class.Starbreaker.AutoFusion", true)
			and targetCount
				>= runtime.State:Get("Class.Starbreaker.FusionMinimumTargets", 2)
			and runtime.Starbreaker.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			state.FusionActive
			and runtime.State:Get(
				"Class.Starbreaker.PrioritizeFusionPrimary",
				false
			)
			and targetDistance
			and targetDistance <= 15
			and runtime.Starbreaker.CanUse("Primary")
		then
			return "Primary"
		end

		if
			state.Active
			and runtime.State:Get(
				"Class.Starbreaker.PrioritizeDoubleFlare",
				true
			)
			and runtime.State:Get("Class.Starbreaker.UseFlare", true)
			and runtime.Starbreaker.CanUse("Skill2")
		then
			return "Skill2"
		end

		local preserveCharge = state.FusionActive
			and runtime.State:Get(
				"Class.Starbreaker.PreserveChargeDuringFusion",
				true
			)

		if
			not preserveCharge
			and runtime.State:Get("Class.Starbreaker.AutoStarforge", true)
			and targetCount
				>= runtime.State:Get(
					"Class.Starbreaker.StarforgeMinimumTargets",
					2
				)
			and runtime.Starbreaker.CanActivateStarforge()
		then
			return "Skill3"
		end

		if
			runtime.State:Get("Class.Starbreaker.UseNova", true)
			and targetCount
				>= runtime.State:Get("Class.Starbreaker.NovaMinimumTargets", 1)
			and targetDistance
			and targetDistance <= 21
			and runtime.Starbreaker.CanUse("Skill1")
		then
			return "Skill1"
		end

		if
			runtime.State:Get("Class.Starbreaker.UseFlare", true)
			and runtime.Starbreaker.CanUse("Skill2")
		then
			return "Skill2"
		end

		local primaryRange = state.FusionActive and 15 or 16

		if
			targetDistance
			and targetDistance <= primaryRange
			and runtime.Starbreaker.CanUse("Primary")
		then
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
				and runtime.State:Get("Class.Starbreaker.AutoAura", false)
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
								"Class.Starbreaker.AutoUnsheath",
								true
							)
						then
							ready = runtime.Starbreaker.EnsureUnsheathed()
						end

						if ready then
							if runtime.State:Get("Combat.AutoAim", true) then
								local duration =
									runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							if slot == "Skill3" then
								runtime.Starbreaker.UseStarforge()
							else
								runtime.Starbreaker.Use(slot)
							end
						end
					end
				end

				task.wait(
					runtime.State:Get("Class.Starbreaker.AttackInterval", 0.15)
				)
			end

			activeLoops[runtime] = nil
		end)
	end

	function StarbreakerFeature.Register(runtime, tab)
		runtime.State:Set("Class.Starbreaker.AutoAura", false)
		runtime.State:Set("Class.Starbreaker.AutoUnsheath", true)
		runtime.State:Set("Class.Starbreaker.UseNova", true)
		runtime.State:Set("Class.Starbreaker.AutoSupernova", true)
		runtime.State:Set("Class.Starbreaker.NovaMinimumTargets", 1)
		runtime.State:Set("Class.Starbreaker.UseFlare", true)
		runtime.State:Set("Class.Starbreaker.PrioritizeDoubleFlare", true)
		runtime.State:Set("Class.Starbreaker.AutoStarforge", true)
		runtime.State:Set("Class.Starbreaker.StarforgeMinimumTargets", 2)
		runtime.State:Set("Class.Starbreaker.PreserveChargeDuringFusion", true)
		runtime.State:Set("Class.Starbreaker.AutoFusion", true)
		runtime.State:Set("Class.Starbreaker.FusionMinimumTargets", 2)
		runtime.State:Set("Class.Starbreaker.PrioritizeFusionPrimary", false)
		runtime.State:Set("Class.Starbreaker.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Starbreaker automation")
		runtime.UI:CreateToggle(tab, "StarbreakerAutoAura", {
			Name = "Server-safe Starbreaker combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "StarbreakerAttackInterval", {
			Name = "Starbreaker rotation check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerAutoUnsheath", {
			Name = "Auto unsheath both Greatswords",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Nova and Supernova")
		runtime.UI:CreateToggle(tab, "StarbreakerUseNova", {
			Name = "Use three-strike Nova",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.UseNova", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerAutoSupernova", {
			Name = "Immediately use earned Supernova follow-up",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AutoSupernova", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "StarbreakerNovaMinimumTargets", {
			Name = "Minimum enemies for Nova",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.NovaMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Nova chain",
			"Nova performs three 10-stud strikes. Landing the third enables a stronger fourth Supernova cast for four seconds and resets Skill1 so it can be used immediately. The three normal hits award 10 Starforge charge each; the fourth awards 20."
		)

		runtime.UI:CreateSection(tab, "Flare and Starforge")
		runtime.UI:CreateToggle(tab, "StarbreakerUseFlare", {
			Name = "Use eight-second seeking Flare",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.UseFlare", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerPrioritizeDoubleFlare", {
			Name = "Prioritize double Flare during Starforge",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set(
					"Class.Starbreaker.PrioritizeDoubleFlare",
					value
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerAutoStarforge", {
			Name = "Auto activate Starforge at 100 charge",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AutoStarforge", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "StarbreakerStarforgeMinimumTargets", {
			Name = "Minimum enemies for Starforge",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.Starbreaker.StarforgeMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Starforge behavior",
			"Starforge requires exactly 100 charge, grants 60% damage resistance for 15 seconds, empowers Stellar Slash with star waves, and doubles Flare. Its summoned field pulses 10 times 1.4 seconds apart in a 20-stud radius and reapplies a three-second slowdown on every pulse."
		)

		runtime.UI:CreateSection(tab, "Fusion Fall")
		runtime.UI:CreateToggle(tab, "StarbreakerAutoFusion", {
			Name = "Auto Fusion Fall at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Starbreaker.AutoFusion", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "StarbreakerFusionMinimumTargets", {
			Name = "Minimum enemies for Fusion Fall",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.Starbreaker.FusionMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerPreserveChargeDuringFusion", {
			Name = "Preserve full Starforge meter during Fusion",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set(
					"Class.Starbreaker.PreserveChargeDuringFusion",
					value
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "StarbreakerPrioritizeFusionPrimary", {
			Name = "Prioritize Fusion heavy-slam Primary",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Class.Starbreaker.PrioritizeFusionPrimary",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Fusion behavior",
			"Fusion Fall combines both swords for 21 seconds and changes Primary into a heavy explosive slam. One second after activation it grants a free 20-second Starforge without consuming the stored meter, allowing a charged Starforge to be preserved and activated after Fusion ends."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Starbreaker resource status",
			Callback = function()
				local state = runtime.Starbreaker.GetStarforgeState()
				local energyState, energyError =
					runtime.Starbreaker.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Starbreaker status",
					"Starforge charge: "
						.. tostring(math.floor(state.Charge))
						.. "/"
						.. tostring(state.MaximumCharge)
						.. "\nStarforge: "
						.. (state.Active and "active" or "inactive")
						.. "\nSupernova follow-up: "
						.. (state.SupernovaReady and "ready" or "not ready")
						.. "\nFusion: "
						.. (state.FusionActive and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Nova or Supernova",
			Callback = function()
				runtime.Starbreaker.UseNova()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Flare",
			Callback = function()
				runtime.Starbreaker.UseFlare()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Activate charged Starforge",
			Callback = function()
				local used, useError = runtime.Starbreaker.UseStarforge()

				if used == nil and useError then
					runtime.UI:Notify("Starforge", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap primary and offhand perk",
			Callback = function()
				runtime.Starbreaker.UsePerkSwap()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Starbreaker Dodge",
			Callback = function()
				runtime.Starbreaker.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Activate Fusion Fall when ready",
			Callback = function()
				local used, useError = runtime.Starbreaker.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Fusion Fall", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return StarbreakerFeature
end
