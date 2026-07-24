return function()
	local NecromancerFeature = {}
	local activeLoops = {}

	local function chooseRotationSlot(runtime, target, targetCount)
		local targetDistance = runtime.Necromancer.GetTargetDistance(target)

		if
			runtime.State:Get("Class.Necromancer.AutoUltimate", true)
			and targetCount
				>= runtime.State:Get("Class.Necromancer.UltimateMinimumTargets", 2)
			and targetDistance
			and targetDistance
				<= runtime.State:Get("Class.Necromancer.UltimateMaximumRange", 30)
			and runtime.Necromancer.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			runtime.State:Get("Class.Necromancer.UseSpiritCavern", true)
			and targetCount
				>= runtime.State:Get("Class.Necromancer.CavernMinimumTargets", 2)
			and targetDistance
			and targetDistance
				<= runtime.State:Get("Class.Necromancer.CavernMaximumRange", 28)
			and runtime.Necromancer.CanUse("Skill3")
		then
			return "Skill3"
		end

		local soulState = runtime.Necromancer.GetSoulState()

		if
			runtime.State:Get("Class.Necromancer.UseSpiritBurst", true)
			and targetDistance
			and targetDistance <= soulState.BurstRadius
			and runtime.Necromancer.CanUseSpiritBurst(
				runtime.State:Get("Class.Necromancer.BurstMinimumCharges", 4)
			)
		then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Necromancer.UseTombstones", true)
			and targetCount
				>= runtime.State:Get("Class.Necromancer.TombstoneMinimumTargets", 1)
			and targetDistance
			and targetDistance
				<= runtime.State:Get("Class.Necromancer.TombstoneMaximumRange", 28)
			and runtime.Necromancer.CanUse("Skill1")
		then
			return "Skill1"
		end

		if
			targetDistance
			and targetDistance
				<= runtime.State:Get("Class.Necromancer.PrimaryMaximumRange", 14)
			and runtime.Necromancer.CanUse("Primary")
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
				and runtime.State:Get("Class.Necromancer.AutoAura", false)
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
								"Class.Necromancer.AutoUnsheath",
								true
							)
						then
							ready = runtime.Necromancer.EnsureUnsheathed()
						end

						if ready then
							if runtime.State:Get("Combat.AutoAim", true) then
								local duration =
									runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							if slot == "Skill2" then
								runtime.Necromancer.UseSpiritBurst(
									runtime.State:Get(
										"Class.Necromancer.BurstMinimumCharges",
										4
									)
								)
							else
								runtime.Necromancer.Use(slot)
							end
						end
					end
				end

				task.wait(runtime.State:Get("Class.Necromancer.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function NecromancerFeature.Register(runtime, tab)
		runtime.State:Set("Class.Necromancer.AutoAura", false)
		runtime.State:Set("Class.Necromancer.AutoUnsheath", true)
		runtime.State:Set("Class.Necromancer.PrimaryMaximumRange", 14)
		runtime.State:Set("Class.Necromancer.UseTombstones", true)
		runtime.State:Set("Class.Necromancer.TombstoneMinimumTargets", 1)
		runtime.State:Set("Class.Necromancer.TombstoneMaximumRange", 28)
		runtime.State:Set("Class.Necromancer.UseSpiritBurst", true)
		runtime.State:Set("Class.Necromancer.BurstMinimumCharges", 4)
		runtime.State:Set("Class.Necromancer.UseSpiritCavern", true)
		runtime.State:Set("Class.Necromancer.CavernMinimumTargets", 2)
		runtime.State:Set("Class.Necromancer.CavernMaximumRange", 28)
		runtime.State:Set("Class.Necromancer.AutoUltimate", true)
		runtime.State:Set("Class.Necromancer.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Necromancer.UltimateMaximumRange", 30)
		runtime.State:Set("Class.Necromancer.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Necromancer automation")
		runtime.UI:CreateToggle(tab, "NecromancerAutoAura", {
			Name = "Server-safe Necromancer combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerAttackInterval", {
			Name = "Necromancer rotation check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "NecromancerAutoUnsheath", {
			Name = "Auto unsheath Scythe",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerPrimaryMaximumRange", {
			Name = "Maximum target distance for Deadly Gash",
			Range = { 5, 20 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 14,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.PrimaryMaximumRange", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Soul charge and Spirit Burst")
		runtime.UI:CreateToggle(tab, "NecromancerUseSpiritBurst", {
			Name = "Auto soul-powered Spirit Burst",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.UseSpiritBurst", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerBurstMinimumCharges", {
			Name = "Minimum completed charges before Burst",
			Range = { 0, 4 },
			Increment = 1,
			CurrentValue = 4,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.BurstMinimumCharges", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Soul charge behavior",
			"Enemies you helped defeat release one soul. Every three souls add one Spirit Burst charge, up to four charge tiers. Burst consumes all completed charge groups but preserves the zero-to-two soul remainder. Its radius grows from 13 studs at zero charge to 21 studs at four charges."
		)

		runtime.UI:CreateSection(tab, "Multi-hit skills")
		runtime.UI:CreateToggle(tab, "NecromancerUseSpiritCavern", {
			Name = "Auto six-pulse Spirit Cavern",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.UseSpiritCavern", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerCavernMinimumTargets", {
			Name = "Minimum enemies for Spirit Cavern",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.CavernMinimumTargets", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerCavernMaximumRange", {
			Name = "Maximum target distance for Cavern",
			Range = { 10, 35 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 28,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.CavernMaximumRange", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "NecromancerUseTombstones", {
			Name = "Auto five-hit Tombstone Rise",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.UseTombstones", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerTombstoneMinimumTargets", {
			Name = "Minimum enemies for Tombstone Rise",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set(
					"Class.Necromancer.TombstoneMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerTombstoneMaximumRange", {
			Name = "Maximum target distance for Tombstones",
			Range = { 10, 35 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 28,
			Callback = function(value)
				runtime.State:Set(
					"Class.Necromancer.TombstoneMaximumRange",
					value
				)
			end,
		})

		runtime.UI:CreateSection(tab, "Undead Army")
		runtime.UI:CreateToggle(tab, "NecromancerAutoUltimate", {
			Name = "Auto summon Undead Army at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Necromancer.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerUltimateMinimumTargets", {
			Name = "Minimum enemies for Undead Army",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set(
					"Class.Necromancer.UltimateMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "NecromancerUltimateMaximumRange", {
			Name = "Maximum target distance for Army impact",
			Range = { 10, 45 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 30,
			Callback = function(value)
				runtime.State:Set(
					"Class.Necromancer.UltimateMaximumRange",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Necromancer behavior",
			"Tombstone Rise creates five forward damage waves. Spirit Cavern creates six 20-stud pulses 1.1 seconds apart and applies Hexed, which deals damage over time and reduces enemy attack by 35%. Undead Army starts with a 30-stud scythe impact, then the server spawns 10 level-scaled allied Death Knights; their attacks inflict Fear."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show souls and Undead Army status",
			Callback = function()
				local souls = runtime.Necromancer.GetSoulState()
				local energyState, energyError = runtime.Necromancer.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Necromancer status",
					"Stored souls: "
						.. tostring(souls.Raw)
						.. "\nBurst charges: "
						.. tostring(souls.Charges)
						.. "/"
						.. tostring(souls.MaximumCharges)
						.. "\nRemainder toward next charge: "
						.. tostring(souls.Remainder)
						.. "/"
						.. tostring(souls.SoulsPerCharge)
						.. "\nCurrent Burst radius: "
						.. tostring(souls.BurstRadius)
						.. " studs"
						.. "\nEnergy: "
						.. energyText
						.. "\nActive summon count: requires Shared.Mobs",
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Tombstone Rise",
			Callback = function()
				runtime.Necromancer.UseTombstoneRise()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Release Spirit Burst using threshold",
			Callback = function()
				local used, useError = runtime.Necromancer.UseSpiritBurst(
					runtime.State:Get("Class.Necromancer.BurstMinimumCharges", 4)
				)

				if used == nil and useError then
					runtime.UI:Notify("Spirit Burst", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Spirit Cavern",
			Callback = function()
				runtime.Necromancer.UseSpiritCavern()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Necromancer Dodge",
			Callback = function()
				runtime.Necromancer.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Summon Undead Army when ready",
			Callback = function()
				local used, useError = runtime.Necromancer.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Undead Army", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return NecromancerFeature
end
