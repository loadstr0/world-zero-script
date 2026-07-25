return function()
	local Combat = {
		Id = "Combat",
	}

	function Combat.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Combat)
		local actions = runtime.Actions.Describe()
		local combatAPI = runtime.CombatAPI.Describe()
		local skillCatalog = runtime.Skills.Describe()
		local classStatus = runtime.ClassRegistry.Describe()
		local currentClass = classStatus.ClassName or skillCatalog.ClassName or "Unknown"
		local classAdapter = runtime.ClassRegistry.GetCurrentAdapter()
		local classMetadata = classAdapter
				and type(classAdapter.Describe) == "function"
				and classAdapter.Describe()
			or {}
		local defaultTargetRange = tonumber(classMetadata.AutomationRange)
			or classMetadata.Primary
				and tonumber(classMetadata.Primary.Range)
			or 15
		local selectedSkillSlot = "Primary"
		local skillLabels = {}
		local labelToSlot = {}
		local status = actions.Available
				and ("Available; initialized: " .. tostring(actions.Initialized))
			or ("Unavailable: " .. tostring(actions.Error))
		local automationStatus = "awaiting class skillset source"

		if classStatus.Verified then
			automationStatus = classStatus.AutomationReady
					and "verified"
				or "source verified; combat implementation incomplete"
		end

		for _, skill in ipairs(skillCatalog.Options or {}) do
			local label = tostring(skill.Name) .. " (" .. tostring(skill.Slot) .. ")"
			table.insert(skillLabels, label)
			labelToSlot[label] = skill.Slot
		end

		if #skillLabels == 0 then
			skillLabels = { "Primary" }
			labelToSlot.Primary = "Primary"
		end

		runtime.State:Set("Combat.TargetRange", defaultTargetRange)
		runtime.State:Set("Combat.AimDuration", 0.2)
		runtime.State:Set("Combat.AutoAim", true)
		runtime.State:Set("Combat.MinimumTargets", 1)
		runtime.State:Set("Combat.AuraEnabled", true)
		runtime.State:Set("Combat.AuraClusterRadius", 24)
		runtime.State:Set("Combat.AuraRetryInterval", 0.1)

		runtime.UI:CreateSection(tab, "Integration status")
		runtime.UI:CreateParagraph(
			tab,
			"Client.Actions",
			status
				.. "\nVerified exports include skill use, cooldown queries, target selection, aiming, sprinting, mounting, and quick items."
		)
		runtime.UI:CreateParagraph(
			tab,
			"Equipped class",
			tostring(currentClass)
				.. "\nAutomation profile: "
				.. automationStatus
				.. "\nLoaded skill slots: "
				.. tostring(#(skillCatalog.Options or {}))
				.. "\nRecommended target range: "
				.. tostring(defaultTargetRange)
				.. " studs"
		)

		runtime.UI:CreateSection(tab, "Targeting")
		runtime.UI:CreateSlider(tab, "CombatTargetRange", {
			Name = "Target range",
			Range = { 5, 60 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = defaultTargetRange,
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
					runtime.State:Get("Combat.TargetRange", defaultTargetRange)
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
					runtime.State:Get("Combat.TargetRange", defaultTargetRange)
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAutoAim", {
			Name = "Auto aim before class attacks",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AutoAim", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Combat Aura")
		runtime.UI:CreateToggle(tab, "CombatAuraEnabled", {
			Name = "OP combat aura",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AuraEnabled", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAuraClusterRadius", {
			Name = "Aura cluster radius",
			Range = { 10, 60 },
			Increment = 2,
			Suffix = " studs",
			CurrentValue = 24,
			Callback = function(value)
				runtime.State:Set("Combat.AuraClusterRadius", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAuraRetryInterval", {
			Name = "Aura action spacing",
			Range = { 0.05, 0.5 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.1,
			Callback = function(value)
				runtime.State:Set("Combat.AuraRetryInterval", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Aura behavior",
			"Prioritizes the densest nearby enemy cluster and continuously uses normal class skills, AoE attacks, primary attacks, and pet abilities. It does not fabricate server damage."
		)

		runtime.UI:CreateSection(tab, "Primary attack")
		runtime.UI:CreateButton(tab, {
			Name = "Use primary attack",
			Callback = function()
				runtime.Actions.UseSkill("Primary")
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Server validation",
			combatAPI.Available
					and "Shared.Combat is available. The server reconstructs hitboxes and rate-limits skill identifiers; verified automation uses normal Client.Actions skill execution."
				or ("Shared.Combat unavailable: " .. tostring(combatAPI.Error))
		)

		local classFeature, classFeatureError = runtime.ClassRegistry.GetCurrentFeature()

		if classFeature and type(classFeature.Register) == "function" then
			classFeature.Register(runtime, tab)
		else
			runtime.UI:CreateSection(tab, tostring(currentClass) .. " automation")
			runtime.UI:CreateParagraph(
				tab,
				"Class source required",
				"Manual skills are available below. Automatic rotation will appear after this class skillset is supplied.\n"
					.. tostring(classFeatureError)
			)
		end

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
			"Names and slots come from Shared.Skills. The class-specific panel above is selected from the equipped class registry."
		)
	end

	return Combat
end
