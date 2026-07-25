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
		runtime.State:Set("Combat.AuraMapSweep", true)
		runtime.State:Set("Combat.AuraClusterRadius", 24)
		runtime.State:Set("Combat.AuraRetryInterval", 0.1)
		runtime.State:Set("Combat.AuraRetargetDelay", 0.15)
		runtime.State:Set("Combat.AuraFlightSpeed", 120)
		runtime.State:Set("Combat.BlatantMode", true)
		runtime.State:Set("Combat.MobFunnel", true)
		runtime.State:Set("Combat.FunnelMinimumTargets", 3)
		runtime.State:Set("Combat.FunnelAggroRange", 16)
		runtime.State:Set("Combat.FunnelTimeout", 6)
		runtime.State:Set("Combat.AirOrbit", true)
		runtime.State:Set("Combat.OrbitRadius", 8)
		runtime.State:Set("Combat.OrbitHeight", 6)
		runtime.State:Set("Combat.OrbitSpeed", 2.5)
		runtime.State:Set("Combat.PredictiveDodge", true)
		runtime.State:Set("Combat.PredictiveDodgeLead", 0.12)
		runtime.State:Set("Combat.PredictiveDodgeFallback", 0.25)
		runtime.State:Set("Combat.PrioritizeDungeonChests", true)

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

		runtime.UI:CreateToggle(tab, "CombatAuraMapSweep", {
			Name = "Map-wide cluster sweep",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AuraMapSweep", value)
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

		runtime.UI:CreateSlider(tab, "CombatAuraFlightSpeed", {
			Name = "Aura travel speed",
			Range = { 90, 180 },
			Increment = 10,
			Suffix = " studs/s",
			CurrentValue = 120,
			Callback = function(value)
				runtime.State:Set("Combat.AuraFlightSpeed", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatAuraRetargetDelay", {
			Name = "Delay after each kill",
			Range = { 0.05, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.15,
			Callback = function(value)
				runtime.State:Set("Combat.AuraRetargetDelay", value)
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
			"Finds clusters across the full map, flies to each one, and continuously uses normal class skills, AoE attacks, primary attacks, and pet abilities. It does not fabricate server damage at impossible distances."
		)

		runtime.UI:CreateSection(tab, "Blatant Farming")
		runtime.UI:CreateToggle(tab, "CombatBlatantMode", {
			Name = "Blatant OP farming mode",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.BlatantMode", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatMobFunnel", {
			Name = "Aggro sweep before each wave",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.MobFunnel", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatFunnelTimeout", {
			Name = "Maximum aggro sweep time",
			Range = { 2, 12 },
			Increment = 1,
			Suffix = "s",
			CurrentValue = 6,
			Callback = function(value)
				runtime.State:Set("Combat.FunnelTimeout", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatAirOrbit", {
			Name = "Airborne combat orbit",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.AirOrbit", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatOrbitRadius", {
			Name = "Orbit radius",
			Range = { 5, 14 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 8,
			Callback = function(value)
				runtime.State:Set("Combat.OrbitRadius", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "CombatOrbitHeight", {
			Name = "Orbit height",
			Range = { 3, 12 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 6,
			Callback = function(value)
				runtime.State:Set("Combat.OrbitHeight", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatPredictiveDodge", {
			Name = "Learned last-moment dodging",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.PredictiveDodge", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "CombatPrioritizeDungeonChests", {
			Name = "Always claim dungeon reward chests",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Combat.PrioritizeDungeonChests", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Blatant behavior",
			"Sweeps the current dungeon wave to pull aggro, attacks the densest stack while orbiting above ground effects, learns attack timing from real hits, and panic-flies away below the survival threshold."
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
