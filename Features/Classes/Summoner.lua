return function()
	local SummonerFeature = {}
	local activeLoops = {}
	local summonedBatches = {}

	local function getDetonationReady(runtime, targetCount)
		local summonedAt = summonedBatches[runtime]

		if
			not runtime.State:Get("Class.Summoner.AutoRiftExplosion", false)
			or not summonedAt
			or targetCount
				< runtime.State:Get(
					"Class.Summoner.ExplosionMinimumTargets",
					1
				)
		then
			return false
		end

		local delaySeconds =
			runtime.State:Get("Class.Summoner.ExplosionDelay", 3)

		return os.clock() - summonedAt >= delaySeconds
			and runtime.Summoner.CanUse("Skill2")
	end

	local function chooseRotationSlot(runtime, target, targetCount)
		local distance = runtime.Summoner.GetTargetDistance(target)
		local soulState = runtime.Summoner.GetSoulState()

		if
			runtime.State:Get("Class.Summoner.AutoUltimate", true)
			and targetCount
				>= runtime.State:Get(
					"Class.Summoner.UltimateMinimumTargets",
					2
				)
			and runtime.Summoner.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if getDetonationReady(runtime, targetCount) then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Summoner.AutoSummon", true)
			and runtime.Summoner.CanSummon(
				runtime.State:Get("Class.Summoner.SummonMinimumReady", 5)
			)
		then
			return "Skill1"
		end

		if
			runtime.State:Get("Class.Summoner.UseSoulHarvest", true)
			and not soulState.AtMaximum
			and targetCount
				>= runtime.State:Get(
					"Class.Summoner.HarvestMinimumTargets",
					2
				)
			and distance
			and distance <= 40
			and runtime.Summoner.CanUse("Skill3")
		then
			return "Skill3"
		end

		if
			distance
			and distance <= 70
			and runtime.Summoner.CanUse("Primary")
		then
			return "Primary"
		end

		return nil
	end

	local function useRotationSlot(runtime, slot)
		if slot == "Skill1" then
			local _, useError = runtime.Summoner.UseSummon(
				runtime.State:Get("Class.Summoner.SummonMinimumReady", 5)
			)

			if not useError then
				summonedBatches[runtime] = os.clock()
			end

			return
		end

		if slot == "Skill2" then
			local _, useError = runtime.Summoner.UseRiftExplosion()

			if not useError then
				summonedBatches[runtime] = nil
			end

			return
		end

		runtime.Summoner.Use(slot)
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Class.Summoner.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 70)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)

					if targetCount == nil then
						targetCount = 1
					end

					if targetCount >= runtime.State:Get("Combat.MinimumTargets", 1) then
						local slot = chooseRotationSlot(runtime, target, targetCount)
						local ready = slot ~= nil

						if
							ready
							and runtime.State:Get(
								"Class.Summoner.AutoUnsheath",
								true
							)
						then
							ready = runtime.Summoner.EnsureUnsheathed()
						end

						if ready then
							if runtime.State:Get("Combat.AutoAim", true) then
								local duration =
									runtime.State:Get("Combat.AimDuration", 0.2)
								runtime.Actions.AimAtNearestTarget(duration, range)
							end

							useRotationSlot(runtime, slot)
						end
					end
				end

				task.wait(
					runtime.State:Get("Class.Summoner.AttackInterval", 0.2)
				)
			end

			activeLoops[runtime] = nil
			summonedBatches[runtime] = nil
		end)
	end

	function SummonerFeature.Register(runtime, tab)
		runtime.State:Set("Class.Summoner.AutoAura", false)
		runtime.State:Set("Class.Summoner.AutoUnsheath", true)
		runtime.State:Set("Class.Summoner.AutoSummon", true)
		runtime.State:Set("Class.Summoner.SummonMinimumReady", 5)
		runtime.State:Set("Class.Summoner.AutoRiftExplosion", false)
		runtime.State:Set("Class.Summoner.ExplosionDelay", 3)
		runtime.State:Set("Class.Summoner.ExplosionMinimumTargets", 1)
		runtime.State:Set("Class.Summoner.UseSoulHarvest", true)
		runtime.State:Set("Class.Summoner.HarvestMinimumTargets", 2)
		runtime.State:Set("Class.Summoner.AutoUltimate", true)
		runtime.State:Set("Class.Summoner.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Summoner.AttackInterval", 0.2)

		runtime.UI:CreateSection(tab, "Summoner automation")
		runtime.UI:CreateToggle(tab, "SummonerAutoAura", {
			Name = "Server-safe Summoner combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerAttackInterval", {
			Name = "Summoner rotation check interval",
			Range = { 0.2, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.2,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "SummonerAutoUnsheath", {
			Name = "Auto unsheath Staff",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Soul bank and Lesser summons")
		runtime.UI:CreateToggle(tab, "SummonerAutoSummon", {
			Name = "Auto spend stored summon charges",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AutoSummon", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerSummonMinimumReady", {
			Name = "Minimum ready Lesser summons",
			Range = { 1, 5 },
			Increment = 1,
			CurrentValue = 5,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.SummonMinimumReady", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Soul economy",
			"Every 100 Souls creates one ready Lesser summon, up to five. Skill1 spends the entire ready bank at once. Rift Rifle hits have a 25% chance to grant 40 Souls, and defeated enemies you helped damage release one to three pickups worth 20 Souls each. New Souls are discarded while all five summon charges are ready, so the rotation spends a full bank before harvesting more."
		)

		runtime.UI:CreateSection(tab, "Soul Harvest")
		runtime.UI:CreateToggle(tab, "SummonerUseSoulHarvest", {
			Name = "Auto Soul Harvest while bank has space",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.UseSoulHarvest", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerHarvestMinimumTargets", {
			Name = "Minimum enemies for Soul Harvest",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.HarvestMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Harvest output",
			"Soul Harvest targets within 40 studs, starts with a forward hit, then pulses four times in a 20-stud radius. Every pulse can harvest up to six enemies for 15 Souls each, with one cast capped at 300 Souls. The collected total arrives through the Soul orb created after four seconds."
		)

		runtime.UI:CreateSection(tab, "Rift Explosion burst")
		runtime.UI:CreateToggle(tab, "SummonerAutoRiftExplosion", {
			Name = "OP: detonate newly summoned Lesser army",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AutoRiftExplosion", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerExplosionDelay", {
			Name = "Delay before Rift Explosion",
			Range = { 0.5, 10 },
			Increment = 0.5,
			Suffix = "s",
			CurrentValue = 3,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.ExplosionDelay", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerExplosionMinimumTargets", {
			Name = "Minimum enemies for Rift Explosion",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.ExplosionMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified detonation behavior",
			"Rift Explosion forces every owned Lesser Soul Being to use its explosion attack. It deliberately ignores the Greater Soul Being from Super Summon. Automatic detonation only tracks Lesser armies created by this running interface; use the manual button for summons that existed before the interface loaded."
		)

		runtime.UI:CreateSection(tab, "Super Summon")
		runtime.UI:CreateToggle(tab, "SummonerAutoUltimate", {
			Name = "Auto Super Summon at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "SummonerUltimateMinimumTargets", {
			Name = "Minimum enemies for Super Summon",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Summoner.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Greater summon",
			"Super Summon requires full energy and creates one Greater Soul Being at effective mission level plus 10. The Greater summon is separate from the five-charge Soul bank and is not consumed by Rift Explosion."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Summoner resource status",
			Callback = function()
				local souls = runtime.Summoner.GetSoulState()
				local energy, energyError = runtime.Summoner.GetEnergyState()
				local energyText = energy
						and tostring(math.floor(energy.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Summoner status",
					"Loose Souls: "
						.. tostring(souls.Souls)
						.. "/"
						.. tostring(souls.SoulsPerCharge)
						.. "\nReady Lesser summons: "
						.. tostring(souls.ReadyCount)
						.. "/"
						.. tostring(souls.MaximumReadyCount)
						.. "\nTotal banked Soul value: "
						.. tostring(souls.TotalBankedSouls)
						.. "\nEnergy: "
						.. energyText
						.. "\nLive summon count: requires Shared.Mobs",
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Summon ready Lesser army",
			Callback = function()
				local used, useError = runtime.Summoner.UseSummon(
					runtime.State:Get("Class.Summoner.SummonMinimumReady", 5)
				)

				if not useError then
					summonedBatches[runtime] = os.clock()
				elseif used == nil then
					runtime.UI:Notify("Summon", tostring(useError), 4, 0)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Detonate all Lesser summons",
			Callback = function()
				local _, useError = runtime.Summoner.UseRiftExplosion()

				if not useError then
					summonedBatches[runtime] = nil
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Soul Harvest",
			Callback = function()
				runtime.Summoner.UseSoulHarvest()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Summoner Dodge",
			Callback = function()
				runtime.Summoner.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Create Greater Soul Being when ready",
			Callback = function()
				local used, useError = runtime.Summoner.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Super Summon", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return SummonerFeature
end
