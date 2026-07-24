return function()
	local DragoonFeature = {}
	local activeLoops = {}

	local function chainSlot(runtime)
		if not runtime.State:Get("Class.Dragoon.FollowDragonChain", true) then
			return nil
		end

		local chainState = runtime.Dragoon.GetChainState()
		local slot
		local enabled

		if chainState == 1 then
			slot = "Skill1"
			enabled = runtime.State:Get("Class.Dragoon.UseInfinityStrike", true)
		elseif chainState == 2 then
			slot = "Skill2"
			enabled = runtime.State:Get("Class.Dragoon.UseDragonWrath", true)
		elseif chainState == 3 then
			slot = "Skill3"
			enabled = runtime.State:Get("Class.Dragoon.UseDragonSlam", true)
		else
			return nil
		end

		if enabled and runtime.Dragoon.CanUse(slot) then
			return slot
		end

		if runtime.State:Get("Class.Dragoon.ProtectDragonChain", true) then
			return "Primary"
		end

		return nil
	end

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Class.Dragoon.AutoUltimate", true) then
			local canUseUltimate = runtime.Dragoon.CanUse("Ultimate")

			if canUseUltimate then
				return "Ultimate"
			end
		end

		local requiredChainSlot = chainSlot(runtime)

		if requiredChainSlot then
			return requiredChainSlot
		end

		if runtime.State:Get("Class.Dragoon.UseInfinityStrike", true) then
			local canUseInfinity = runtime.Dragoon.CanUse("Skill1")

			if canUseInfinity then
				return "Skill1"
			end
		end

		if runtime.State:Get("Class.Dragoon.UseDragonWrath", true) then
			local canUseWrath = runtime.Dragoon.CanUse("Skill2")

			if canUseWrath then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Dragoon.UseDragonSlam", true) then
			local canUseSlam = runtime.Dragoon.CanUse("Skill3")

			if canUseSlam then
				return "Skill3"
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
			while not runtime.Stopped and runtime.State:Get("Class.Dragoon.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 30)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Dragoon.AutoUnsheath", true) then
						ready = runtime.Dragoon.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Dragoon.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Class.Dragoon.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function DragoonFeature.Register(runtime, tab)
		runtime.State:Set("Class.Dragoon.AutoAura", false)
		runtime.State:Set("Class.Dragoon.AutoUnsheath", true)
		runtime.State:Set("Class.Dragoon.FollowDragonChain", true)
		runtime.State:Set("Class.Dragoon.ProtectDragonChain", true)
		runtime.State:Set("Class.Dragoon.UseInfinityStrike", true)
		runtime.State:Set("Class.Dragoon.UseDragonWrath", true)
		runtime.State:Set("Class.Dragoon.UseDragonSlam", true)
		runtime.State:Set("Class.Dragoon.AutoUltimate", true)
		runtime.State:Set("Class.Dragoon.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Dragoon automation")
		runtime.UI:CreateToggle(tab, "DragoonAutoAura", {
			Name = "Server-safe Dragoon aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "DragoonAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonAutoUnsheath", {
			Name = "Auto unsheath Spear",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Dragon Chain")
		runtime.UI:CreateToggle(tab, "DragoonFollowDragonChain", {
			Name = "Follow the live Dragon Chain step",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.FollowDragonChain", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonProtectDragonChain", {
			Name = "Protect chain while required skill cools down",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.ProtectDragonChain", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonUseInfinityStrike", {
			Name = "Use Infinity Strike (10 cross hits)",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.UseInfinityStrike", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonUseDragonWrath", {
			Name = "Use 5-hit Dragon Wrath",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.UseDragonWrath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonUseDragonSlam", {
			Name = "Use Dragon Slam",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.UseDragonSlam", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DragoonAutoUltimate", {
			Name = "Auto Dragon Dance at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Dragoon.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Dragoon behavior",
			"Critical hits mark enemies for 10 seconds, increasing skill damage against them by 20%. The live chain order is Infinity Strike, Dragon Wrath, then Dragon Slam; completion grants Dragon Mode for 8 seconds. Dragon Dance launches 18 dragons and grants Dragon Mode for 16 seconds."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Dragon Chain status",
			Callback = function()
				local energyState, energyError = runtime.Dragoon.GetEnergyState()
				local energyText = energyState
						and tostring(math.floor(energyState.Ratio * 100)) .. "%"
					or tostring(energyError)

				runtime.UI:Notify(
					"Dragoon status",
					"Next chain action: "
						.. runtime.Dragoon.GetChainLabel()
						.. "\nDragon Mode: "
						.. (runtime.Dragoon.IsDragonMode() and "active" or "inactive")
						.. "\nEnergy: "
						.. energyText,
					6,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Infinity Strike",
			Callback = function()
				runtime.Dragoon.UseInfinityStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Dragon Wrath",
			Callback = function()
				runtime.Dragoon.UseDragonWrath()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Dragon Slam",
			Callback = function()
				runtime.Dragoon.UseDragonSlam()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Dragoon Dodge",
			Callback = function()
				runtime.Dragoon.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Dragon Dance when ready",
			Callback = function()
				local used, useError = runtime.Dragoon.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Dragon Dance", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return DragoonFeature
end
