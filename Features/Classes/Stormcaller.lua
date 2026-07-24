return function()
	local StormcallerFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, target, targetCount)
		local state = runtime.Stormcaller.GetState()
		local distance = runtime.Stormcaller.GetTargetDistance(target)

		if
			runtime.State:Get("Class.Stormcaller.AutoThunderGod", true)
			and targetCount >= runtime.State:Get("Class.Stormcaller.ThunderGodMinimumTargets", 2)
			and runtime.Stormcaller.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			runtime.State:Get("Class.Stormcaller.AutoSupercharge", true)
			and targetCount >= runtime.State:Get("Class.Stormcaller.SuperchargeMinimumTargets", 2)
		then
			local floor = runtime.State:Get("Class.Stormcaller.SuperchargeHealthFloor", 40) / 100

			if runtime.Stormcaller.CanSupercharge(floor) then
				return "Skill1"
			end
		end

		if
			state.ThunderGod
			and runtime.State:Get("Class.Stormcaller.PrioritizeThunderGodPrimary", false)
			and distance
			and distance <= 14
			and runtime.Stormcaller.CanUse("Primary")
		then
			return "Primary"
		end

		if
			runtime.State:Get("Class.Stormcaller.UseChainLightning", true)
			and targetCount >= runtime.State:Get("Class.Stormcaller.ChainMinimumTargets", 2)
			and distance
			and distance <= 35
			and runtime.Stormcaller.CanUse("Skill2")
		then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Stormcaller.UseStormSurge", true)
			and targetCount >= runtime.State:Get("Class.Stormcaller.SurgeMinimumTargets", 2)
			and distance
			and distance <= 45
			and runtime.Stormcaller.CanUse("Skill3")
		then
			return "Skill3"
		end

		local primaryRange = state.ThunderGod and 14 or 50

		if distance and distance <= primaryRange and runtime.Stormcaller.CanUse("Primary") then
			return "Primary"
		end

		return nil
	end

	local function useRotationSlot(runtime, slot)
		if slot == "Skill1" then
			return runtime.Stormcaller.UseSupercharge(
				runtime.State:Get("Class.Stormcaller.SuperchargeHealthFloor", 40) / 100
			)
		end

		return runtime.Stormcaller.Use(slot)
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Class.Stormcaller.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 50)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)

					if targetCount == nil then
						targetCount = 1
					end

					if targetCount >= runtime.State:Get("Combat.MinimumTargets", 1) then
						local slot = chooseRotationSlot(runtime, target, targetCount)
						local ready = slot ~= nil

						if ready and runtime.State:Get("Class.Stormcaller.AutoUnsheath", true) then
							ready = runtime.Stormcaller.EnsureUnsheathed()
						end

						if ready then
							if runtime.State:Get("Combat.AutoAim", true) then
								local duration = runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							useRotationSlot(runtime, slot)
						end
					end
				end

				task.wait(runtime.State:Get("Class.Stormcaller.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function StormcallerFeature.Register(runtime, tab)
		runtime.State:Set("Class.Stormcaller.AutoAura", false)
		runtime.State:Set("Class.Stormcaller.AutoUnsheath", true)
		runtime.State:Set("Class.Stormcaller.AutoSupercharge", true)
		runtime.State:Set("Class.Stormcaller.SuperchargeMinimumTargets", 2)
		runtime.State:Set("Class.Stormcaller.SuperchargeHealthFloor", 40)
		runtime.State:Set("Class.Stormcaller.UseChainLightning", true)
		runtime.State:Set("Class.Stormcaller.ChainMinimumTargets", 2)
		runtime.State:Set("Class.Stormcaller.UseStormSurge", true)
		runtime.State:Set("Class.Stormcaller.SurgeMinimumTargets", 2)
		runtime.State:Set("Class.Stormcaller.AutoThunderGod", true)
		runtime.State:Set("Class.Stormcaller.ThunderGodMinimumTargets", 2)
		runtime.State:Set("Class.Stormcaller.PrioritizeThunderGodPrimary", false)
		runtime.State:Set("Class.Stormcaller.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Stormcaller automation")
		runtime.UI:CreateToggle(tab, "StormcallerAutoAura", {
			Name = "Server-safe Stormcaller combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.AutoAura", value)
				if value then startRotationLoop(runtime) end
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerAttackInterval", {
			Name = "Stormcaller rotation check interval",
			Range = { 0.05, 1 }, Increment = 0.05, Suffix = "s", CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.AttackInterval", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "StormcallerAutoUnsheath", {
			Name = "Auto unsheath Staff", CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Supercharge health control")
		runtime.UI:CreateToggle(tab, "StormcallerAutoSupercharge", {
			Name = "Auto Supercharge when health floor is safe", CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.AutoSupercharge", value)
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerSuperchargeHealthFloor", {
			Name = "Minimum health left after Supercharge",
			Range = { 1, 80 }, Increment = 1, Suffix = "%", CurrentValue = 40,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.SuperchargeHealthFloor", value)
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerSuperchargeMinimumTargets", {
			Name = "Minimum enemies for Supercharge",
			Range = { 1, 8 }, Increment = 1, CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.SuperchargeMinimumTargets", value)
			end,
		})
		runtime.UI:CreateParagraph(
			tab,
			"Verified Supercharge tradeoff",
			"Supercharge spends 20% maximum health but cannot reduce you below 1 HP. For 6.9 seconds, every attack marks enemies for five seconds and each application heals 0.5% maximum health. The skill text says up to 20% can be refunded, but the verified server implementation caps the cumulative refund at 15%."
		)

		runtime.UI:CreateSection(tab, "Lightning rotation")
		runtime.UI:CreateToggle(tab, "StormcallerUseChainLightning", {
			Name = "Use Chain Lightning", CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.UseChainLightning", value)
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerChainMinimumTargets", {
			Name = "Minimum enemies for Chain Lightning",
			Range = { 1, 8 }, Increment = 1, CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.ChainMinimumTargets", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "StormcallerUseStormSurge", {
			Name = "Use two-stage Storm Surge", CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.UseStormSurge", value)
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerSurgeMinimumTargets", {
			Name = "Minimum enemies for Storm Surge",
			Range = { 1, 10 }, Increment = 1, CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.SurgeMinimumTargets", value)
			end,
		})
		runtime.UI:CreateParagraph(
			tab,
			"Verified lightning behavior",
			"Chain Lightning starts within 35 studs, can reach up to eight enemies, and may return through previous targets. Storm Surge creates an initial slowing pulse followed by the larger strike; its activation is 1.5x faster during Thunder God."
		)

		runtime.UI:CreateSection(tab, "Thunder God burst")
		runtime.UI:CreateToggle(tab, "StormcallerAutoThunderGod", {
			Name = "Auto Thunder God at full energy", CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.AutoThunderGod", value)
			end,
		})
		runtime.UI:CreateSlider(tab, "StormcallerThunderGodMinimumTargets", {
			Name = "Minimum enemies for Thunder God",
			Range = { 1, 10 }, Increment = 1, CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.ThunderGodMinimumTargets", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "StormcallerPrioritizeThunderGodPrimary", {
			Name = "OP: prioritize Thunder God sword spam", CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Stormcaller.PrioritizeThunderGodPrimary", value)
			end,
		})
		runtime.UI:CreateParagraph(
			tab,
			"Verified Thunder God behavior",
			"Thunder God lasts 20 seconds, grants 50% movement speed, and transforms the Staff into fast dual swords. Each sword hit has a 25% chance to discharge at another enemy within 35 studs, limited to one discharge opportunity every 1.5 seconds. The OP toggle prioritizes this enhanced Primary whenever the target is within its 14-stud cone."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Stormcaller status",
			Callback = function()
				local state = runtime.Stormcaller.GetState()
				local projected, healthError = runtime.Stormcaller.GetProjectedSuperchargeState()
				local energy, energyError = runtime.Stormcaller.GetEnergyState()
				local healthText = projected
						and tostring(math.floor(projected.CurrentRatio * 100)) .. "% -> "
							.. tostring(math.floor(projected.ProjectedRatio * 100)) .. "%"
					or tostring(healthError)
				local energyText = energy
						and tostring(math.floor(energy.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Stormcaller status",
					"Health now -> after Supercharge: " .. healthText
						.. "\nSupercharge: " .. (state.Supercharged and "active" or "inactive")
						.. "\nThunder God: " .. (state.ThunderGod and "active" or "inactive")
						.. "\nUltimate speed: " .. (state.UltimateSpeed and "active" or "inactive")
						.. "\nEnergy: " .. energyText,
					7,
					0
				)
			end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Activate health-safe Supercharge",
			Callback = function()
				local used, useError = runtime.Stormcaller.UseSupercharge(
					runtime.State:Get("Class.Stormcaller.SuperchargeHealthFloor", 40) / 100
				)
				if used == nil and useError then
					runtime.UI:Notify("Supercharge", tostring(useError), 4, 0)
				end
			end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Cast Chain Lightning",
			Callback = function() runtime.Stormcaller.UseChainLightning() end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Cast Storm Surge",
			Callback = function() runtime.Stormcaller.UseStormSurge() end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Use Discharge Dash",
			Callback = function() runtime.Stormcaller.UseDodge() end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Activate Thunder God when ready",
			Callback = function()
				local used, useError = runtime.Stormcaller.UseUltimate()
				if used == nil and useError then
					runtime.UI:Notify("Thunder God", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return StormcallerFeature
end
