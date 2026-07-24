return function()
	local AssassinFeature = {}
	local activeLoops = {}

	local function getTargetDistance(runtime, target)
		local root = runtime.Game.GetRootPart()

		if not root or typeof(target) ~= "Instance" then
			return nil
		end

		local targetPart

		if target:IsA("BasePart") then
			targetPart = target
		else
			targetPart = target.PrimaryPart
				or target:FindFirstChild("HumanoidRootPart")
				or target:FindFirstChild("Collider")
		end

		if not targetPart then
			return nil
		end

		return (targetPart.Position - root.Position).Magnitude
	end

	local function chooseRotationSlot(runtime, target)
		if runtime.State:Get("Class.Assassin.AutoUltimate", true) then
			local canUseUltimate = runtime.Assassin.CanUse("Ultimate")

			if canUseUltimate then
				return "Ultimate"
			end
		end

		if
			runtime.State:Get("Class.Assassin.AutoShadowCloak", true)
			and not runtime.Assassin.IsShadowMode()
		then
			local canUseCloak = runtime.Assassin.CanUse("Skill1")

			if canUseCloak then
				return "Skill1"
			end
		end

		local targetDistance = getTargetDistance(runtime, target)

		if
			targetDistance
			and targetDistance > 14
			and runtime.State:Get("Class.Assassin.UseShadowLeap", true)
		then
			local canUseLeap = runtime.Assassin.CanUse("Skill2")

			if canUseLeap then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Assassin.UseShadowStrike", true) then
			local canUseStrike = runtime.Assassin.CanUse("Skill3")

			if canUseStrike then
				return "Skill3"
			end
		end

		if runtime.State:Get("Class.Assassin.UseShadowLeap", true) then
			local canUseLeap = runtime.Assassin.CanUse("Skill2")

			if canUseLeap then
				return "Skill2"
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
			while not runtime.Stopped and runtime.State:Get("Class.Assassin.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 60)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Class.Assassin.AutoUnsheath", true) then
						ready = runtime.Assassin.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Assassin.Use(chooseRotationSlot(runtime, target))
					end
				end

				task.wait(runtime.State:Get("Class.Assassin.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function AssassinFeature.Register(runtime, tab)
		runtime.State:Set("Class.Assassin.AutoAura", false)
		runtime.State:Set("Class.Assassin.AutoUnsheath", true)
		runtime.State:Set("Class.Assassin.AutoShadowCloak", true)
		runtime.State:Set("Class.Assassin.UseShadowLeap", true)
		runtime.State:Set("Class.Assassin.UseShadowStrike", true)
		runtime.State:Set("Class.Assassin.AutoUltimate", true)
		runtime.State:Set("Class.Assassin.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Assassin automation")
		runtime.UI:CreateToggle(tab, "AssassinAutoAura", {
			Name = "Server-safe Assassin aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "AssassinAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AssassinAutoUnsheath", {
			Name = "Auto unsheath both longswords",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AssassinAutoShadowCloak", {
			Name = "Maintain Shadow Cloak for criticals",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.AutoShadowCloak", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AssassinUseShadowLeap", {
			Name = "Use Shadow Leap gap closer",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.UseShadowLeap", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AssassinUseShadowStrike", {
			Name = "Use Shadow Strike in rotation",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.UseShadowStrike", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AssassinAutoUltimate", {
			Name = "Auto Realm of Shadows at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Assassin.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Assassin behavior",
			"Shadow Cloak lasts 5 seconds, raises movement speed by 60%, and guarantees critical blows. Shadow Leap targets up to 60 studs and teleports behind the enemy. Shadow Strike attacks twice in a 15-stud area. Realm of Shadows requires full energy and grants Shadow Mode for 15 seconds."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show Shadow Mode and energy",
			Callback = function()
				local energyState, energyError = runtime.Assassin.GetEnergyState()
				local energyText = energyState
						and (
							tostring(math.floor(energyState.Ratio * 100))
							.. "% energy"
						)
					or tostring(energyError)

				runtime.UI:Notify(
					"Assassin status",
					"Shadow Mode: "
						.. (runtime.Assassin.IsShadowMode() and "active" or "inactive")
						.. "\n"
						.. energyText,
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Shadow Cloak",
			Callback = function()
				runtime.Assassin.UseShadowCloak()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Shadow Leap",
			Callback = function()
				runtime.Assassin.UseShadowLeap()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Shadow Strike",
			Callback = function()
				runtime.Assassin.UseShadowStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Assassin Dodge",
			Callback = function()
				runtime.Assassin.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Swap active weapon perks",
			Callback = function()
				runtime.Assassin.SwapPerk()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Realm of Shadows when ready",
			Callback = function()
				local used, useError = runtime.Assassin.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Realm of Shadows", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return AssassinFeature
end
