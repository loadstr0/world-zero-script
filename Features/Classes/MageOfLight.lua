return function()
	local MageOfLightFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, hasTarget, targetCount)
		local health = runtime.MageOfLight.GetHealthState()
		local healthRatio = health and health.Ratio or 1
		local emergencyThreshold =
			runtime.State:Get("Class.MageOfLight.GraceEmergencyThreshold", 40) / 100
		local graceEmergency = healthRatio <= emergencyThreshold

		if runtime.State:Get("Class.MageOfLight.AutoGrace", true) then
			local saveForEmergency =
				runtime.State:Get("Class.MageOfLight.SaveGraceForEmergency", false)
			local minimumTargets =
				runtime.State:Get("Class.MageOfLight.GraceMinimumTargets", 2)
			local wantsGrace = graceEmergency
				or (
					not saveForEmergency
					and hasTarget
					and targetCount >= minimumTargets
				)

			if wantsGrace and runtime.MageOfLight.CanUse("Ultimate") then
				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.MageOfLight.AutoHealingCircle", true)
			and healthRatio
				<= runtime.State:Get("Class.MageOfLight.HealingThreshold", 75) / 100
			and runtime.MageOfLight.CanUse("Skill1")
		then
			return "Skill1"
		end

		if runtime.State:Get("Class.MageOfLight.AutoBarrier", true) then
			local barrier = runtime.MageOfLight.GetBarrier()
			local barrierThreshold =
				runtime.State:Get("Class.MageOfLight.BarrierHealthThreshold", 90) / 100

			if
				barrier ~= nil
				and barrier <= 0
				and healthRatio <= barrierThreshold
				and runtime.MageOfLight.CanUse("Skill3")
			then
				return "Skill3"
			end
		end

		if hasTarget and runtime.State:Get("Class.MageOfLight.AutoInfuse", true) then
			local minimumOrbs =
				runtime.State:Get("Class.MageOfLight.InfuseMinimumOrbs", 10)
			local healthFloor =
				runtime.State:Get("Class.MageOfLight.InfuseHealthFloor", 50) / 100

			if runtime.MageOfLight.CanInfuse(minimumOrbs, healthFloor) then
				return "Skill2"
			end
		end

		if hasTarget and runtime.MageOfLight.CanUse("Primary") then
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
				and runtime.State:Get("Class.MageOfLight.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 45)
				local target = runtime.Actions.GetNearestTarget(range)

				if runtime.Actions.IsBusy() ~= true then
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)

					if targetCount == nil then
						targetCount = target and 1 or 0
					end

					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local combatReady = target ~= nil and targetCount >= minimumTargets
					local slot =
						chooseRotationSlot(runtime, combatReady, targetCount)

					if slot then
						local ready = true

						if runtime.State:Get("Class.MageOfLight.AutoUnsheath", true) then
							ready = runtime.MageOfLight.EnsureUnsheathed()
						end

						if ready then
							if combatReady and runtime.State:Get("Combat.AutoAim", true) then
								local duration = runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							if slot == "Skill2" then
								runtime.MageOfLight.UseInfusedLight(
									runtime.State:Get(
										"Class.MageOfLight.InfuseMinimumOrbs",
										10
									),
									runtime.State:Get(
										"Class.MageOfLight.InfuseHealthFloor",
										50
									) / 100
								)
							else
								runtime.MageOfLight.Use(slot)
							end
						end
					end
				end

				task.wait(runtime.State:Get("Class.MageOfLight.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function MageOfLightFeature.Register(runtime, tab)
		runtime.State:Set("Class.MageOfLight.AutoAura", false)
		runtime.State:Set("Class.MageOfLight.AutoUnsheath", true)
		runtime.State:Set("Class.MageOfLight.AerialCombat", true)
		runtime.State:Set("Class.MageOfLight.AerialCombatHeight", 60)
		runtime.State:Set("Class.MageOfLight.VerticalTargetBypass", true)
		runtime.State:Set("Class.MageOfLight.ServerSafeRange", 90)
		runtime.State:Set("Class.MageOfLight.AutoHealingCircle", true)
		runtime.State:Set("Class.MageOfLight.HealingThreshold", 75)
		runtime.State:Set("Class.MageOfLight.AutoBarrier", true)
		runtime.State:Set("Class.MageOfLight.BarrierHealthThreshold", 90)
		runtime.State:Set("Class.MageOfLight.AutoInfuse", true)
		runtime.State:Set("Class.MageOfLight.InfuseMinimumOrbs", 10)
		runtime.State:Set("Class.MageOfLight.InfuseHealthFloor", 50)
		runtime.State:Set("Class.MageOfLight.AutoGrace", true)
		runtime.State:Set("Class.MageOfLight.SaveGraceForEmergency", false)
		runtime.State:Set("Class.MageOfLight.GraceEmergencyThreshold", 40)
		runtime.State:Set("Class.MageOfLight.GraceMinimumTargets", 2)
		runtime.State:Set("Class.MageOfLight.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Mage of Light automation")
		runtime.UI:CreateToggle(tab, "MageOfLightAutoAura", {
			Name = "Server-safe Light combat and support",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightAttackInterval", {
			Name = "Support and attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfLightAutoUnsheath", {
			Name = "Auto unsheath Staff",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Aerial stance")
		runtime.UI:CreateToggle(tab, "MageOfLightAerialCombat", {
			Name = "Maintain high aerial combat position",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AerialCombat", value)
			end,
		})

		runtime.Controls.MageOfLightAerialCombatHeight = runtime.UI:CreateSlider(tab, "MageOfLightAerialCombatHeight", {
			Name = "Aerial combat height",
			Range = { 20, 80 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 60,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AerialCombatHeight", value)
			end,
		})

		runtime.Actions.SetInternalTargetOverride(
			true,
			"MageOfLight",
			runtime.State:Get("Class.MageOfLight.ServerSafeRange", 90)
		)
		runtime.Janitor:Add(function()
			runtime.Actions.SetInternalTargetOverride(false)
		end)

		runtime.UI:CreateToggle(tab, "MageOfLightVerticalTargetBypass", {
			Name = "Attack targets below the aerial stance",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.VerticalTargetBypass", value)
				runtime.Actions.SetInternalTargetOverride(
					value,
					"MageOfLight",
					runtime.State:Get("Class.MageOfLight.ServerSafeRange", 90)
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Air recovery",
			"Mage of Light keeps a 60-stud combat orbit by default. Its client selector stops at 45 studs and is only 30 studs tall, while the server accepts the normal Light Seeker impact from the tested 60-stud position. The reversible executor hook feeds the exact automation target into that normal attack and briefly bypasses only Light Seeker's client-side visibility check."
		)

		runtime.UI:CreateSection(tab, "Healing and Barrier")
		runtime.UI:CreateToggle(tab, "MageOfLightAutoHealingCircle", {
			Name = "Auto six-pulse Healing Circle",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoHealingCircle", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightHealingThreshold", {
			Name = "Healing Circle health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 75,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.HealingThreshold", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfLightAutoBarrier", {
			Name = "Auto Barrier when protection is empty",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoBarrier", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightBarrierHealthThreshold", {
			Name = "Barrier health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 90,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.BarrierHealthThreshold", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Infused Orbs")
		runtime.UI:CreateToggle(tab, "MageOfLightAutoInfuse", {
			Name = "Auto convert normal orbs to Infused",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoInfuse", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightInfuseMinimumOrbs", {
			Name = "Minimum normal orbs to Infuse",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 10,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.InfuseMinimumOrbs", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightInfuseHealthFloor", {
			Name = "Minimum projected health after Infuse",
			Range = { 10, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 50,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.InfuseHealthFloor", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Grace")
		runtime.UI:CreateToggle(tab, "MageOfLightAutoGrace", {
			Name = "Auto Grace at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.AutoGrace", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MageOfLightSaveGraceForEmergency", {
			Name = "Save Grace for health emergency",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.SaveGraceForEmergency", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightGraceEmergencyThreshold", {
			Name = "Grace emergency health threshold",
			Range = { 10, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 40,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.GraceEmergencyThreshold", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MageOfLightGraceMinimumTargets", {
			Name = "Minimum enemies for combat Grace",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.MageOfLight.GraceMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Mage of Light behavior",
			"One orb regenerates each second up to 10. Infused Light costs 4% maximum health per normal orb, up to 40%, and converts all held orbs to charged attacks. Healing Circle pulses six times in a 22.5-stud area. Grace supplies 10 charged orbs, cleanses nearby allies, grants Blessed for 10 seconds, then performs ten full-heal and Barrier pulses in a 30-stud area."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Light support status",
			Callback = function()
				local orbs = runtime.MageOfLight.GetOrbState()
				local health, healthError = runtime.MageOfLight.GetHealthState()
				local barrier, barrierError = runtime.MageOfLight.GetBarrier()
				local energyState, energyError = runtime.MageOfLight.GetEnergyState()
				local healthText = health
						and tostring(math.floor(health.Ratio * 100)) .. "%"
					or tostring(healthError)
				local barrierText = barrier
						and tostring(math.floor(barrier))
					or tostring(barrierError)
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Mage of Light status",
					"Orbs: "
						.. tostring(orbs.Total)
						.. "/10 ("
						.. tostring(orbs.Charged)
						.. " charged)"
						.. "\nInfuse cost: "
						.. tostring(math.floor(orbs.InfuseCostRatio * 100))
						.. "% health"
						.. "\nHealth: "
						.. healthText
						.. "\nBarrier: "
						.. barrierText
						.. "\nBlessed: "
						.. (runtime.MageOfLight.IsBlessed() and "active" or "inactive")
						.. "\nWings: "
						.. (runtime.MageOfLight.IsWingsActive() and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Healing Circle",
			Callback = function()
				runtime.MageOfLight.UseHealingCircle()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Infuse orbs using safety floor",
			Callback = function()
				local used, useError = runtime.MageOfLight.UseInfusedLight(
					runtime.State:Get("Class.MageOfLight.InfuseMinimumOrbs", 10),
					runtime.State:Get("Class.MageOfLight.InfuseHealthFloor", 50) / 100
				)

				if used == nil and useError then
					runtime.UI:Notify("Infused Light", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Barrier",
			Callback = function()
				runtime.MageOfLight.UseBarrier()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Mage of Light Dodge",
			Callback = function()
				runtime.MageOfLight.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Grace when ready",
			Callback = function()
				local used, useError = runtime.MageOfLight.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Grace", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return MageOfLightFeature
end
