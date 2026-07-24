return function()
	local DefenderFeature = {}
	local activeLoops = {}

	local function shouldUseUltimate(runtime)
		if not runtime.State:Get("Class.Defender.AutoUltimate", true) then
			return false
		end

		local canUseUltimate = runtime.Defender.CanUse("Ultimate")

		if not canUseUltimate then
			return false
		end

		local radius = 50
		local minimumAllies = runtime.State:Get("Class.Defender.MinimumAllies", 0)
		local allyCount = runtime.Defender.CountNearbyAllies(radius)

		if allyCount < minimumAllies then
			return false
		end

		if runtime.State:Get("Class.Defender.EmergencyHealOnly", false) then
			return runtime.Defender.HasInjuredAlly(
				radius,
				runtime.State:Get("Class.Defender.HealThreshold", 40)
			)
		end

		return true
	end

	local function chooseRotationSlot(runtime)
		if shouldUseUltimate(runtime) then
			return "Ultimate"
		end

		if runtime.State:Get("Class.Defender.UseCycloneSwing", true) then
			local canUseSpin = runtime.Defender.CanUse("Skill2")

			if canUseSpin then
				return "Skill2"
			end
		end

		if runtime.State:Get("Class.Defender.UseGroundbreaker", true) then
			local canUseGroundbreaker = runtime.Defender.CanUse("Skill1")

			if canUseGroundbreaker then
				return "Skill1"
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
			while not runtime.Stopped and runtime.State:Get("Class.Defender.AutoAura", false) do
				local range = runtime.State:Get("Combat.TargetRange", 14)
				local target = runtime.Actions.GetNearestTarget(range)
				local emergencySupport = runtime.State:Get(
					"Class.Defender.EmergencyHealOnly",
					false
				) and shouldUseUltimate(runtime)

				if (target or emergencySupport) and runtime.Actions.IsBusy() ~= true then
					local ready = emergencySupport

					if target then
						local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
						local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
						ready = targetCount == nil or targetCount >= minimumTargets
					end

					if ready and runtime.State:Get("Class.Defender.AutoUnsheath", true) then
						ready = runtime.Defender.EnsureUnsheathed()
					end

					if ready then
						if target and runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Defender.Use(
							emergencySupport and "Ultimate"
								or chooseRotationSlot(runtime)
						)
					end
				end

				task.wait(runtime.State:Get("Class.Defender.AttackInterval", 0.15))
			end

			activeLoops[runtime] = nil
		end)
	end

	function DefenderFeature.Register(runtime, tab)
		runtime.State:Set("Class.Defender.AutoAura", false)
		runtime.State:Set("Class.Defender.AutoUnsheath", true)
		runtime.State:Set("Class.Defender.UseGroundbreaker", true)
		runtime.State:Set("Class.Defender.UseCycloneSwing", true)
		runtime.State:Set("Class.Defender.AutoUltimate", true)
		runtime.State:Set("Class.Defender.MinimumAllies", 0)
		runtime.State:Set("Class.Defender.EmergencyHealOnly", false)
		runtime.State:Set("Class.Defender.HealThreshold", 40)
		runtime.State:Set("Class.Defender.AttackInterval", 0.15)

		runtime.UI:CreateSection(tab, "Defender automation")
		runtime.UI:CreateToggle(tab, "DefenderAutoAura", {
			Name = "Server-safe Defender aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Defender.AutoAura", value)

				if value then
					startRotationLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "DefenderAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Class.Defender.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DefenderAutoUnsheath", {
			Name = "Auto unsheath Greataxe",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Defender.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DefenderUseGroundbreaker", {
			Name = "Use Groundbreaker in rotation",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Defender.UseGroundbreaker", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DefenderUseCycloneSwing", {
			Name = "Use 8-hit Cyclone Swing",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Defender.UseCycloneSwing", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Defender's Shield")
		runtime.UI:CreateToggle(tab, "DefenderAutoUltimate", {
			Name = "Auto Shield at full energy during aura",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Class.Defender.AutoUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "DefenderMinimumAllies", {
			Name = "Minimum nearby allies for Shield",
			Range = { 0, 10 },
			Increment = 1,
			CurrentValue = 0,
			Callback = function(value)
				runtime.State:Set("Class.Defender.MinimumAllies", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "DefenderEmergencyHealOnly", {
			Name = "Only spend Shield for an injured ally",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Class.Defender.EmergencyHealOnly", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "DefenderHealThreshold", {
			Name = "Injured ally health threshold",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 40,
			Callback = function(value)
				runtime.State:Set("Class.Defender.HealThreshold", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified Defender behavior",
			"Cyclone Swing checks eight hits in a 9-stud radius. Groundbreaker hits an 8-stud area. Defender's Shield requires full energy, damages enemies within 50 studs, and performs seven healing checks on nearby players."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show energy and nearby allies",
			Callback = function()
				local energyState, energyError = runtime.Defender.GetEnergyState()
				local energyText = energyState
						and (
							tostring(math.floor(energyState.Ratio * 100))
							.. "% energy"
						)
					or tostring(energyError)

				runtime.UI:Notify(
					"Defender status",
					energyText
						.. "\nNearby allies: "
						.. tostring(runtime.Defender.CountNearbyAllies(50)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Groundbreaker",
			Callback = function()
				runtime.Defender.UseGroundbreaker()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Cyclone Swing",
			Callback = function()
				runtime.Defender.UseCycloneSwing()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Defender Dodge",
			Callback = function()
				runtime.Defender.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Defender's Shield when ready",
			Callback = function()
				local used, useError = runtime.Defender.UseUltimate()

				if used == nil and useError then
					runtime.UI:Notify("Defender's Shield", tostring(useError), 4, 0)
				end
			end,
		})
	end

	return DefenderFeature
end
