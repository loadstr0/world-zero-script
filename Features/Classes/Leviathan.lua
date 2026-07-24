return function()
	local LeviathanFeature = {}
	local activeLoops = {}

	local function canBuildBubbleChain(runtime)
		return runtime.State:Get("Class.Leviathan.FollowBubbleChain", true)
			and runtime.State:Get("Class.Leviathan.UseRiptide", true)
			and runtime.State:Get("Class.Leviathan.UseHydrosurge", true)
			and runtime.State:Get("Class.Leviathan.UseMaelstrom", true)
	end

	local function fullChainReady(runtime)
		return runtime.Leviathan.CanUse("Skill1")
			and runtime.Leviathan.CanUse("Skill2")
			and runtime.Leviathan.CanUse("Skill3")
	end

	local function activeChainSlot(runtime)
		if not runtime.State:Get("Class.Leviathan.FollowBubbleChain", true) then
			return nil
		end

		local chainState = runtime.Leviathan.GetChainState()
		local slot
		local enabled

		if chainState == 2 then
			slot = "Skill2"
			enabled = runtime.State:Get("Class.Leviathan.UseHydrosurge", true)
		elseif chainState == 3 then
			slot = "Skill3"
			enabled = runtime.State:Get("Class.Leviathan.UseMaelstrom", true)
		else
			return nil
		end

		if enabled and runtime.Leviathan.CanUse(slot) then
			return slot
		end

		if runtime.State:Get("Class.Leviathan.ProtectBubbleChain", true) then
			return "Primary"
		end

		return nil
	end

	local function chooseRotationSlot(runtime, targetCount)
		local chainSlot = activeChainSlot(runtime)
		local wantsUltimate = runtime.State:Get("Class.Leviathan.AutoUltimate", true)
			and targetCount
				>= runtime.State:Get("Class.Leviathan.UltimateMinimumTargets", 2)
			and runtime.Leviathan.CanUse("Ultimate")

		if
			chainSlot
			and runtime.State:Get("Class.Leviathan.CompleteChainBeforeUltimate", true)
		then
			return chainSlot
		end

		if
			wantsUltimate
			and runtime.State:Get("Class.Leviathan.BuildSeaBubbleBeforeUltimate", true)
			and not runtime.Leviathan.IsSeaBubbleActive()
			and canBuildBubbleChain(runtime)
		then
			if fullChainReady(runtime) then
				return "Skill1"
			end

			return "Primary"
		end

		if wantsUltimate then
			return "Ultimate"
		end

		if chainSlot then
			return chainSlot
		end

		if
			runtime.State:Get("Class.Leviathan.UseRiptide", true)
			and runtime.Leviathan.CanUse("Skill1")
		then
			if
				runtime.State:Get("Class.Leviathan.RequireFullChainReady", true)
				and canBuildBubbleChain(runtime)
				and not fullChainReady(runtime)
			then
				return "Primary"
			end

			return "Skill1"
		end

		if
			runtime.State:Get("Class.Leviathan.UseHydrosurge", true)
			and runtime.Leviathan.CanUse("Skill2")
		then
			return "Skill2"
		end

		if
			not runtime.State:Get("Class.Leviathan.ChainOnlyMaelstrom", true)
			and runtime.State:Get("Class.Leviathan.UseMaelstrom", true)
			and runtime.Leviathan.CanUse("Skill3")
		then
			return "Skill3"
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
				and runtime.State:Get("Class.Leviathan.AutoAura", false)
			do
				local range = runtime.State:Get("Combat.TargetRange", 40)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Leviathan.AutoUnsheath", true) then
						ready = runtime.Leviathan.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Leviathan.Use(
							chooseRotationSlot(runtime, targetCount or 1)
						)
					end
				end

				task.wait(runtime.State:Get("Class.Leviathan.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function LeviathanFeature.Register(runtime, tab)
		runtime.State:Set("Class.Leviathan.AutoAura", false)
		runtime.State:Set("Class.Leviathan.AutoUnsheath", true)
		runtime.State:Set("Class.Leviathan.FollowBubbleChain", true)
		runtime.State:Set("Class.Leviathan.ProtectBubbleChain", true)
		runtime.State:Set("Class.Leviathan.CompleteChainBeforeUltimate", true)
		runtime.State:Set("Class.Leviathan.RequireFullChainReady", true)
		runtime.State:Set("Class.Leviathan.BuildSeaBubbleBeforeUltimate", true)
		runtime.State:Set("Class.Leviathan.UseRiptide", true)
		runtime.State:Set("Class.Leviathan.UseHydrosurge", true)
		runtime.State:Set("Class.Leviathan.UseMaelstrom", true)
		runtime.State:Set("Class.Leviathan.ChainOnlyMaelstrom", true)
		runtime.State:Set("Class.Leviathan.AutoUltimate", true)
		runtime.State:Set("Class.Leviathan.UltimateMinimumTargets", 2)
		runtime.State:Set("Class.Leviathan.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Leviathan automation")
		runtime.UI:CreateToggle(tab, "LeviathanAutoAura", {
			Name = "Server-safe Leviathan aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "LeviathanAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanAutoUnsheath", {
			Name = "Auto unsheath weapon",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Bubble chain")
		runtime.UI:CreateToggle(tab, "LeviathanFollowBubbleChain", {
			Name = "Follow Water Cyclone bubble chain",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.FollowBubbleChain", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanProtectBubbleChain", {
			Name = "Protect chain while required skill cools down",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.ProtectBubbleChain", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanCompleteChainBeforeUltimate", {
			Name = "Complete active Sea Bubble chain before Ultimate",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.CompleteChainBeforeUltimate", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanRequireFullChainReady", {
			Name = "Start chain only when all three skills are ready",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.RequireFullChainReady", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanBuildSeaBubbleBeforeUltimate", {
			Name = "Build Sea Bubble before full-energy Ultimate",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.BuildSeaBubbleBeforeUltimate", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanUseRiptide", {
			Name = "Use five-bubble Water Cyclone",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.UseRiptide", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanUseHydrosurge", {
			Name = "Use bubble-popping Hydrosurge",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.UseHydrosurge", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanUseMaelstrom", {
			Name = "Use six-second Maelstrom",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.UseMaelstrom", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LeviathanChainOnlyMaelstrom", {
			Name = "Save Maelstrom to finish Sea Bubble chain",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.ChainOnlyMaelstrom", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Leviathan's Wrath")
		runtime.UI:CreateToggle(tab, "LeviathanAutoUltimate", {
			Name = "Auto Leviathan's Wrath at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LeviathanUltimateMinimumTargets", {
			Name = "Minimum enemies for Leviathan's Wrath",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Class.Leviathan.UltimateMinimumTargets", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Leviathan behavior",
			"Water Cyclone leaves five bubbles that pop after 5 seconds for 45% Attack. Hydrosurge sweeps 40 studs and turns each popped bubble into three 40%-Attack serpents with 18-stud hits, including recursive bubble chains. Completing Maelstrom grants Sea Bubble for 8 seconds; credited kills heal Leviathan and nearby allies for 5% maximum health. Leviathan's Wrath grants 7 seconds of invincibility, performs eight dash hits, and summons up to 24 serpents."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show bubble chain and energy",
			Callback = function()
				local energyState, energyError = runtime.Leviathan.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Leviathan status",
					"Next chain action: "
						.. runtime.Leviathan.GetChainLabel()
						.. "\nSea Bubble: "
						.. (runtime.Leviathan.IsSeaBubbleActive() and "active" or "inactive")
						.. "\nInvincible: "
						.. (runtime.Leviathan.IsInvincible() and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					6,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Water Cyclone",
			Callback = function()
				runtime.Leviathan.UseRiptide()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Hydrosurge",
			Callback = function()
				runtime.Leviathan.UseHydrosurge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Maelstrom Spin",
			Callback = function()
				runtime.Leviathan.UseMaelstrom()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Leviathan Dodge",
			Callback = function()
				runtime.Leviathan.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Leviathan's Wrath when ready",
			Callback = function()
				local used, useError = runtime.Leviathan.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Leviathan's Wrath", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return LeviathanFeature
end
