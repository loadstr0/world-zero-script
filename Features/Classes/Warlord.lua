return function()
	local WarlordFeature = {}
	local activeLoops = {}
	local piledriverChains = {}

	local function getPiledriverChain(runtime)
		local chain = piledriverChains[runtime]

		if chain and os.clock() - chain.StartedAt >= 3.5 then
			piledriverChains[runtime] = nil
			chain = nil
		end

		return chain
	end

	local function recordPiledriver(runtime)
		local chain = getPiledriverChain(runtime)

		if not chain then
			chain = {
				Count = 0,
				StartedAt = os.clock(),
			}
			piledriverChains[runtime] = chain
		end

		chain.Count = chain.Count + 1

		if chain.Count >= 3 then
			piledriverChains[runtime] = nil
		end
	end

	local function wantsBlock(runtime, targetCount)
		if
			not runtime.State:Get("Class.Warlord.AutoBlock", true)
			or targetCount
				< runtime.State:Get("Class.Warlord.BlockMinimumTargets", 1)
		then
			return false, false
		end

		local health = runtime.Warlord.GetHealthState()
		local threshold =
			runtime.State:Get("Class.Warlord.BlockHealthThreshold", 60) / 100
		local emergency = health ~= nil and health.Ratio <= threshold
		local aggressive =
			runtime.State:Get("Class.Warlord.AggressiveBlock", false)

		return emergency or aggressive, emergency
	end

	local function chooseRotationSlot(runtime, target, targetCount)
		local distance = runtime.Warlord.GetTargetDistance(target)
		local activeChain = getPiledriverChain(runtime)

		if
			activeChain
			and runtime.State:Get("Class.Warlord.CompletePiledriverChain", true)
			and distance
			and distance <= 12
			and runtime.Warlord.CanUse("Skill1")
		then
			return "Skill1"
		end

		local blockWanted, emergencyBlock =
			wantsBlock(runtime, targetCount)

		if emergencyBlock and runtime.Warlord.CanBlock() then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Warlord.AutoUltimate", true)
			and targetCount
				>= runtime.State:Get(
					"Class.Warlord.UltimateMinimumTargets",
					3
				)
			and runtime.Warlord.CanUse("Ultimate")
		then
			return "Ultimate"
		end

		if
			runtime.State:Get("Class.Warlord.UseChainsOfWar", true)
			and targetCount
				>= runtime.State:Get(
					"Class.Warlord.ChainsMinimumTargets",
					2
				)
			and distance
			and distance <= 40
			and runtime.Warlord.CanUse("Skill3")
		then
			return "Skill3"
		end

		if blockWanted and runtime.Warlord.CanBlock() then
			return "Skill2"
		end

		if
			runtime.State:Get("Class.Warlord.UsePiledriver", true)
			and targetCount
				>= runtime.State:Get(
					"Class.Warlord.PiledriverMinimumTargets",
					1
				)
			and distance
			and distance <= 12
			and runtime.Warlord.CanUse("Skill1")
		then
			return "Skill1"
		end

		if
			distance
			and distance <= 16
			and runtime.Warlord.CanUse("Primary")
		then
			return "Primary"
		end

		return nil
	end

	local function useRotationSlot(runtime, slot)
		if slot == "Skill1" then
			local _, useError = runtime.Warlord.UsePiledriver()

			if not useError then
				recordPiledriver(runtime)
			end

			return
		end

		if slot == "Skill2" then
			runtime.Warlord.UseBlock()
			return
		end

		runtime.Warlord.Use(slot)
	end

	local function startRotationLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Class.Warlord.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 40)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)

					if targetCount == nil then
						targetCount = 1
					end

					if targetCount >= runtime.State:Get("Combat.MinimumTargets", 1) then
						local slot =
							chooseRotationSlot(runtime, target, targetCount)
						local ready = slot ~= nil

						if
							ready
							and runtime.State:Get(
								"Class.Warlord.AutoUnsheath",
								true
							)
						then
							ready = runtime.Warlord.EnsureUnsheathed()
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
					runtime.State:Get("Class.Warlord.AttackInterval", 0.15)
				)
			end

			activeLoops[runtime] = nil
			piledriverChains[runtime] = nil
		end)
	end

	function WarlordFeature.Register(runtime, tab)
		runtime.State:Set("Class.Warlord.AutoAura", false)
		runtime.State:Set("Class.Warlord.AutoUnsheath", true)
		runtime.State:Set("Class.Warlord.UsePiledriver", true)
		runtime.State:Set("Class.Warlord.CompletePiledriverChain", true)
		runtime.State:Set("Class.Warlord.PiledriverMinimumTargets", 1)
		runtime.State:Set("Class.Warlord.AutoBlock", true)
		runtime.State:Set("Class.Warlord.BlockHealthThreshold", 60)
		runtime.State:Set("Class.Warlord.BlockMinimumTargets", 1)
		runtime.State:Set("Class.Warlord.AggressiveBlock", false)
		runtime.State:Set("Class.Warlord.UseChainsOfWar", true)
		runtime.State:Set("Class.Warlord.ChainsMinimumTargets", 2)
		runtime.State:Set("Class.Warlord.AutoUltimate", true)
		runtime.State:Set("Class.Warlord.UltimateMinimumTargets", 3)
		runtime.State:Set("Class.Warlord.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Warlord automation")
		runtime.UI:CreateToggle(tab, "WarlordAutoAura", {
			Name = "Server-safe Warlord combat aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordAttackInterval", {
			Name = "Warlord rotation check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "WarlordAutoUnsheath", {
			Name = "Auto unsheath Greataxe and Shield",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Piledriver chain")
		runtime.UI:CreateToggle(tab, "WarlordUsePiledriver", {
			Name = "Use Piledriver",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.UsePiledriver", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "WarlordCompletePiledriverChain", {
			Name = "OP: force the complete three-hit chain",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set(
					"Class.Warlord.CompletePiledriverChain",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordPiledriverMinimumTargets", {
			Name = "Minimum enemies to start Piledriver",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set(
					"Class.Warlord.PiledriverMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Piledriver chain",
			"Piledriver can be activated three times inside a 3.5-second chain window before its five-second cooldown begins. Each 12-stud impact is stronger than the previous one, reaching 2x damage on the third cast. The OP option gives active chains priority so other rotation skills do not waste the window."
		)

		runtime.UI:CreateSection(tab, "Charged Block")
		runtime.UI:CreateToggle(tab, "WarlordAutoBlock", {
			Name = "Auto Charged Block",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AutoBlock", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordBlockHealthThreshold", {
			Name = "Emergency Block health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 60,
			Callback = function(value)
				runtime.State:Set(
					"Class.Warlord.BlockHealthThreshold",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordBlockMinimumTargets", {
			Name = "Minimum enemies for Charged Block",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.BlockMinimumTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "WarlordAggressiveBlock", {
			Name = "OP: near-continuous counter Block",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AggressiveBlock", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Block behavior",
			"Charged Block sets the server Blocking state for two seconds on a three-second cooldown. It negates 80% of incoming damage, and a successfully blocked hit triggers the Warlord counter pulse with Shock. Aggressive mode uses Block whenever enemies are present instead of waiting for the health threshold."
		)

		runtime.UI:CreateSection(tab, "Chains and Yggdrasil")
		runtime.UI:CreateToggle(tab, "WarlordUseChainsOfWar", {
			Name = "Use Chains of War",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.UseChainsOfWar", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordChainsMinimumTargets", {
			Name = "Minimum enemies for Chains of War",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.ChainsMinimumTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "WarlordAutoUltimate", {
			Name = "Auto Yggdrasil at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Warlord.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "WarlordUltimateMinimumTargets", {
			Name = "Minimum enemies for Yggdrasil",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 3,
			Callback = function(value)
				runtime.State:Set(
					"Class.Warlord.UltimateMinimumTargets",
					value
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified crowd-control behavior",
			"Chains of War hits a 40-stud area and lowers enemy defense by 50%. Yggdrasil covers an 80-stud acquisition area for 18 seconds and schedules five damage pulses 3.6 seconds apart. Its catalog behavior reels in and Shocks enemies; the server additionally applies a two-second Slowdown to movable bosses caught at activation."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Warlord defense status",
			Callback = function()
				local state = runtime.Warlord.GetState()
				local health, healthError =
					runtime.Warlord.GetHealthState()
				local energy, energyError =
					runtime.Warlord.GetEnergyState()
				local healthText = health
						and tostring(math.floor(health.Ratio * 100)) .. "%"
					or tostring(healthError)
				local energyText = energy
						and tostring(math.floor(energy.Ratio * 100)) .. "%"
					or tostring(energyError)
				local chain = getPiledriverChain(runtime)

				runtime.UI:Notify(
					"Warlord status",
					"Health: "
						.. healthText
						.. "\nBlocking: "
						.. (state.Blocking and "active" or "inactive")
						.. "\nPiledriver chain: "
						.. tostring(chain and chain.Count or 0)
						.. "/3"
						.. "\nEnergy: "
						.. energyText,
					6,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Continue Piledriver chain",
			Callback = function()
				local _, useError = runtime.Warlord.UsePiledriver()

				if not useError then
					recordPiledriver(runtime)
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Raise Charged Block",
			Callback = function()
				runtime.Warlord.UseBlock()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Cast Chains of War",
			Callback = function()
				runtime.Warlord.UseChainsOfWar()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap Greataxe and Shield perks",
			Callback = function()
				runtime.Warlord.UsePerkSwap()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Warlord Dodge",
			Callback = function()
				runtime.Warlord.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Summon Yggdrasil when ready",
			Callback = function()
				local used, useError = runtime.Warlord.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Yggdrasil", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return WarlordFeature
end
