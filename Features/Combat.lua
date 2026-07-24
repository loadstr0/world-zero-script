return function()
	local Combat = {
		Id = "Combat",
	}

	local autoPrimaryLoopRunning = false

	local function chooseRotationSlot(runtime)
		if runtime.State:Get("Combat.SwordmasterSkill1", false) then
			local canUse = runtime.Swordmaster.CanUse("Skill1")

			if canUse then
				return "Skill1"
			end
		end

		if runtime.State:Get("Combat.SwordmasterSkill2", false) then
			local canUse = runtime.Swordmaster.CanUse("Skill2")

			if canUse then
				return "Skill2"
			end
		end

		return "Primary"
	end

	local function startAutoPrimaryLoop(runtime)
		if autoPrimaryLoopRunning then
			return
		end

		autoPrimaryLoopRunning = true

		task.spawn(function()
			while not runtime.Stopped and runtime.State:Get("Combat.AutoPrimary", false) do
				local range = runtime.State:Get("Combat.TargetRange", 15)
				local target = runtime.Actions.GetNearestTarget(range)

				if target and runtime.Actions.IsBusy() ~= true then
					local minimumTargets = runtime.State:Get("Combat.MinimumTargets", 1)
					local targetCount = runtime.CombatAPI.CountTargetsInRadius(range)
					local ready = targetCount == nil or targetCount >= minimumTargets

					if ready and runtime.State:Get("Combat.AutoUnsheath", true) then
						ready = runtime.Swordmaster.EnsureUnsheathed()
					end

					if ready then
						if runtime.State:Get("Combat.AutoAim", true) then
							local duration = runtime.State:Get("Combat.AimDuration", 0.2)
							runtime.Actions.AimAtNearestTarget(duration, range)
						end

						runtime.Swordmaster.Use(chooseRotationSlot(runtime))
					end
				end

				task.wait(runtime.State:Get("Combat.AttackInterval", 0.15))
			end

			autoPrimaryLoopRunning = false
		end)
	end

	function Combat.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Combat)
		local actions = runtime.Actions.Describe()
		local combatAPI = runtime.CombatAPI.Describe()
		local skillCatalog = runtime.Skills.Describe()
		local selectedSkillSlot = "Primary"
		local skillLabels = {}
		local labelToSlot = {}
		local status = actions.Available
				and ("Available; initialized: " .. tostring(actions.Initialized))
			or ("Unavailable: " .. tostring(actions.Error))

		for _, skill in ipairs(skillCatalog.Options or {}) do
			local label = tostring(skill.Name) .. " (" .. tostring(skill.Slot) .. ")"
			table.insert(skillLabels, label)
			labelToSlot[label] = skill.Slot
		end

		if #skillLabels == 0 then
			skillLabels = { "Primary" }
			labelToSlot.Primary = "Primary"
		end

		runtime.UI:CreateSection(tab, "Integration status")
		runtime.UI:CreateParagraph(
			tab,
			"Client.Actions",
			status
				.. "\nVerified exports include skill use, cooldown queries, target selection, aiming, sprinting, mounting, and quick items."
		)
		runtime.UI:CreateParagraph(
			tab,
			"Current class",
			skillCatalog.ClassName
					and (tostring(skillCatalog.ClassName) .. "\nLoaded skill slots: " .. tostring(#(skillCatalog.Options or {})))
				or ("Unavailable: " .. tostring(skillCatalog.Error))
		)
		runtime.State:Set("Combat.TargetRange", 15)
		runtime.State:Set("Combat.AimDuration", 0.2)
		runtime.State:Set("Combat.AttackInterval", 0.15)
		runtime.State:Set("Combat.AutoAim", true)
		runtime.State:Set("Combat.AutoPrimary", false)
		runtime.State:Set("Combat.AutoUnsheath", true)
		runtime.State:Set("Combat.SwordmasterSkill1", false)
		runtime.State:Set("Combat.SwordmasterSkill2", false)
		runtime.State:Set("Combat.MinimumTargets", 1)

		runtime.UI:CreateSection(tab, "Targeting")
		runtime.UI:CreateSlider(tab, "CombatTargetRange", {
			Name = "Target range",
			Range = { 5, 50 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 15,
			Callback = function(value)
				runtime.State:Set("Combat.TargetRange", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAimDuration", {
			Name = "Aim duration",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.2,
			Callback = function(value)
				runtime.State:Set("Combat.AimDuration", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatMinimumTargets", {
			Name = "Minimum nearby targets",
			Range = { 1, 10 },
			Increment = 1,
			CurrentValue = 1,
			Callback = function(value)
				runtime.State:Set("Combat.MinimumTargets", value)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Scan valid targets now",
			Callback = function()
				local count, scanError = runtime.CombatAPI.CountTargetsInRadius(
					runtime.State:Get("Combat.TargetRange", 15)
				)

				if count == nil then
					runtime.UI:Notify("Combat scan", "Scan failed: " .. tostring(scanError), 5, 0)
					return
				end

				runtime.UI:Notify(
					"Combat scan",
					tostring(count) .. " server-valid target(s) are inside the selected radius.",
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Aim at nearest target",
			Callback = function()
				runtime.Actions.AimAtNearestTarget(
					runtime.State:Get("Combat.AimDuration", 0.2),
					runtime.State:Get("Combat.TargetRange", 15)
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAutoAim", {
			Name = "Auto aim before primary",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AutoAim", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Primary attack")
		runtime.UI:CreateButton(tab, {
			Name = "Use primary attack",
			Callback = function()
				runtime.Actions.UseSkill("Primary")
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAttackInterval", {
			Name = "Attack check interval",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Combat.AttackInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAutoPrimary", {
			Name = "Server-safe Swordmaster aura",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Combat.AutoPrimary", value)

				if value then
					startAutoPrimaryLoop(runtime)
				end
			end,
		})

		runtime.UI:CreateSection(tab, "Swordmaster rotation")
		runtime.UI:CreateToggle(tab, "CombatAutoUnsheath", {
			Name = "Auto unsheath before attacking",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AutoUnsheath", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatSwordmasterSkill1", {
			Name = "Use Crescent Strike in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Combat.SwordmasterSkill1", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatSwordmasterSkill2", {
			Name = "Use Leap Slash in rotation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Combat.SwordmasterSkill2", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified behavior",
			"Primary chains six swings and resets after 0.75s. Primary range is 10 studs; Crescent Strike can acquire a mob up to 50 studs away."
		)

		runtime.UI:CreateParagraph(
			tab,
			"Server validation",
			combatAPI.Available
					and "Shared.Combat is available. The server reconstructs hitboxes and rate-limits skill identifiers, so this aura uses normal Client.Actions skill execution."
				or ("Shared.Combat unavailable: " .. tostring(combatAPI.Error))
		)

		runtime.UI:CreateButton(tab, {
			Name = "Use Crescent Strike",
			Callback = function()
				runtime.Swordmaster.UseCrescentStrike()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Leap Slash",
			Callback = function()
				runtime.Swordmaster.UseLeapSlash()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Dodge",
			Callback = function()
				runtime.Swordmaster.UseDodge()
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use Ultimate when charged",
			Callback = function()
				runtime.Swordmaster.UseUltimate()
			end,
		})

		runtime.UI:CreateSection(tab, "Class skills")
		runtime.UI:CreateDropdown(tab, "CombatSelectedSkill", {
			Name = "Selected skill",
			Options = skillLabels,
			CurrentOption = { skillLabels[1] },
			MultipleOptions = false,
			Callback = function(options)
				local label = options and options[1]
				selectedSkillSlot = labelToSlot[label] or "Primary"
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use selected skill",
			Callback = function()
				runtime.Actions.UseSkill(selectedSkillSlot)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Skill mapping",
			"Names and slots come from Shared.Skills. Execution still passes through the current class skillset module."
		)
	end

	return Combat
end
