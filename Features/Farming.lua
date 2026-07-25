return function(ctx)
	local Farming = {
		Id = "Farming",
	}

	local Engine = ctx:Require("FarmingEngine")

	function Farming.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		local mobStatus = runtime.MobsAPI.Describe()
		local healthStatus = runtime.Health.Describe()
		local statusStatus = runtime.Status.Describe()
		local walkspeedStatus = runtime.Walkspeed.Describe()
		local targetProvider = function(range)
			return Engine.GetActiveTarget(runtime, range)
		end

		runtime.AutomationTargetProvider = targetProvider

		runtime.State:Set("Farming.Enabled", false)
		runtime.State:Set("Farming.TargetMode", "Nearest")
		runtime.State:Set("Farming.TargetRange", 120)
		runtime.State:Set("Farming.MapWideTargets", false)
		runtime.State:Set("Farming.BossOnly", false)
		runtime.State:Set("Farming.EliteOnly", false)
		runtime.State:Set("Farming.NameFilter", "")
		runtime.State:Set("Farming.AutoApproach", true)
		runtime.State:Set("Farming.MovementMode", "Pathfinding")
		runtime.State:Set("Farming.CFrameFlightSpeed", 90)
		runtime.State:Set("Farming.CFrameZeroVelocity", true)
		runtime.State:Set("Farming.FlightNoclip", true)
		runtime.State:Set("Farming.StickyTargets", true)
		runtime.State:Set("Farming.SkipStalledTargets", true)
		runtime.State:Set("Farming.NoDamageTimeout", 15)
		runtime.State:Set("Farming.StalledTargetRetryDelay", 20)
		runtime.State:Set("Farming.StopDistance", 10)
		runtime.State:Set("Farming.TargetHeightOffset", 0)
		runtime.State:Set("Farming.AdaptiveKiting", true)
		runtime.State:Set("Farming.KiteDistance", 28)
		runtime.State:Set("Farming.AutoSprint", true)
		runtime.State:Set("Farming.SpeedBoostEnabled", false)
		runtime.State:Set("Farming.SpeedBoostMultiplier", 1.5)
		runtime.State:Set("Farming.SpeedBoostCounterSlows", true)
		runtime.State:Set("Farming.AutoJump", true)
		runtime.State:Set("Farming.RepathInterval", 1.25)
		runtime.State:Set("Farming.TargetMoveThreshold", 10)
		runtime.State:Set("Farming.StuckTimeout", 1.4)
		runtime.State:Set("Farming.AutoAttack", true)
		runtime.State:Set("Farming.RotationMode", "Full Rotation")
		runtime.State:Set("Farming.AttackSlot", "Primary")
		runtime.State:Set("Farming.UseUltimate", true)
		runtime.State:Set("Farming.SkillRetryInterval", 0.6)
		runtime.State:Set("Farming.AttackRange", 45)
		runtime.State:Set("Farming.AutoDodge", true)
		runtime.State:Set("Farming.AutoThawFreezeTag", true)
		runtime.State:Set("Farming.FreezeTagRescueRange", 120)
		runtime.State:Set("Farming.DebuffSurvival", true)
		runtime.State:Set("Farming.DebuffSafetyThreshold", 60)
		runtime.State:Set("Farming.DodgeAfterDamage", true)
		runtime.State:Set("Farming.DamageReactionWindow", 1.25)
		runtime.State:Set("Farming.ThreatRadius", 25)
		runtime.State:Set("Farming.DodgeHealthThreshold", 70)
		runtime.State:Set("Farming.EmergencyRetreat", true)
		runtime.State:Set("Farming.RetreatHealthThreshold", 30)
		runtime.State:Set("Farming.RetreatDistance", 35)
		runtime.State:Set("Farming.AutoHealItem", false)
		runtime.State:Set("Farming.HealItemName", "")
		runtime.State:Set("Farming.HealItemHealthThreshold", 40)
		runtime.State:Set("Farming.HealItemRetryInterval", 5)
		runtime.State:Set("Farming.UpdateInterval", 0.2)

		runtime.Janitor:Add(function()
			runtime.Actions.ClearTargetProvider(targetProvider)
		end)

		runtime.UI:CreateSection(tab, "Auto Farm")
		runtime.Controls.FarmingEnabled = runtime.UI:CreateToggle(tab, "FarmingEnabled", {
			Name = "Enable filtered Auto Farm",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.Enabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified mob integration",
			mobStatus.Available
					and "Shared.Mobs is active. Auto Farm excludes dead, hidden, invincible, unattackable, and player-owned summons. Boss tags, elite state, ownership, level, and live health come from the game's client mob registry."
				or ("Shared.Mobs unavailable: " .. tostring(mobStatus.Error))
		)

		runtime.UI:CreateParagraph(
			tab,
			"Class rotations",
			"Full Rotation is the default. Auto Farm reads the currently equipped class, cycles every available special attack, uses Ultimate when energy is full, and keeps Primary attacks in the rotation. The separate class aura is optional."
		)

		runtime.UI:CreateParagraph(
			tab,
			"Damage avoidance",
			"Status handling now follows the supplied catalog: Darkness pauses skills but keeps moving; Frozen, Shock, Knockdown, and Stunned stop movement and skills; damage-over-time and defense debuffs raise the safety threshold; Poison suppresses wasted heal-item attempts."
		)

		runtime.UI:CreateParagraph(
			tab,
			"Survival sources",
			"Health: "
				.. tostring(healthStatus.Available)
				.. " | Status: "
				.. tostring(statusStatus.Available)
				.. " | Walkspeed: "
				.. tostring(walkspeedStatus.Available)
		)

		runtime.UI:CreateSection(tab, "Target selection")
		runtime.UI:CreateDropdown(tab, "FarmingTargetMode", {
			Name = "Target priority",
			Options = {
				"Nearest",
				"Boss Priority",
				"Lowest Health",
				"Highest Level",
			},
			CurrentOption = { "Nearest" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Farming.TargetMode", options and options[1] or "Nearest")
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingTargetRange", {
			Name = "Farm search range",
			Range = { 10, 500 },
			Increment = 5,
			Suffix = " studs",
			CurrentValue = 120,
			Callback = function(value)
				runtime.State:Set("Farming.TargetRange", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingMapWideTargets", {
			Name = "Search every loaded mob regardless of distance",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.MapWideTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingBossOnly", {
			Name = "Bosses only",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.BossOnly", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingEliteOnly", {
			Name = "Elites only",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.EliteOnly", value)
			end,
		})

		runtime.UI:CreateInput(tab, "FarmingNameFilter", {
			Name = "Mob-name filter",
			CurrentValue = "",
			PlaceholderText = "Comma-separated names; blank allows all",
			RemoveTextAfterFocusLost = false,
			Callback = function(value)
				runtime.State:Set("Farming.NameFilter", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Movement mode")
		runtime.UI:CreateToggle(tab, "FarmingAutoApproach", {
			Name = "Move toward automation target",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoApproach", value)

				if not value then
					Engine.Stop(runtime)
				end
			end,
		})

		runtime.UI:CreateDropdown(tab, "FarmingMovementMode", {
			Name = "Navigation method",
			Options = {
				"Pathfinding",
				"Smooth Flight",
				"Instant CFrame",
			},
			CurrentOption = { "Pathfinding" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Farming.MovementMode", options and options[1] or "Pathfinding")
				runtime.Navigator.Stop()
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingCFrameFlightSpeed", {
			Name = "Smooth-flight speed",
			Range = { 20, 500 },
			Increment = 10,
			Suffix = " studs/s",
			CurrentValue = 90,
			Callback = function(value)
				runtime.State:Set("Farming.CFrameFlightSpeed", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingCFrameZeroVelocity", {
			Name = "Cancel momentum after CFrame movement",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.CFrameZeroVelocity", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingFlightNoclip", {
			Name = "Disable character collision while flying",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.FlightNoclip", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Blatant navigation",
			"Smooth Flight continuously moves through the air at the selected speed and retargets moving destinations. Instant CFrame moves to the requested stopping distance in one update. Both bypass pathfinding and can be corrected by the server."
		)

		runtime.UI:CreateSection(tab, "Pathfinding controls")

		runtime.UI:CreateToggle(tab, "FarmingAutoJump", {
			Name = "Jump over path obstacles",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoJump", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingAutoSprint", {
			Name = "Sprint on long approaches",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoSprint", value)

				if not value then
					Engine.StopSprint(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingStopDistance", {
			Name = "Approach stopping distance",
			Range = { 3, 40 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 10,
			Callback = function(value)
				runtime.State:Set("Farming.StopDistance", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingTargetHeightOffset", {
			Name = "Combat hover height",
			Range = { 0, 40 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 0,
			Callback = function(value)
				runtime.State:Set("Farming.TargetHeightOffset", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Hover positioning",
			"Height 0 approaches normally. A higher value keeps the character above the target and works best with ranged classes or a matching attack range."
		)

		runtime.UI:CreateToggle(tab, "FarmingAdaptiveKiting", {
			Name = "Adaptive ranged kiting",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AdaptiveKiting", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingKiteDistance", {
			Name = "Preferred ranged distance",
			Range = { 10, 45 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 28,
			Callback = function(value)
				runtime.State:Set("Farming.KiteDistance", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingRepathInterval", {
			Name = "Moving-target path refresh",
			Range = { 0.5, 3 },
			Increment = 0.25,
			Suffix = "s",
			CurrentValue = 1.25,
			Callback = function(value)
				runtime.State:Set("Farming.RepathInterval", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingStuckTimeout", {
			Name = "Stuck jump recovery delay",
			Range = { 0.5, 3 },
			Increment = 0.1,
			Suffix = "s",
			CurrentValue = 1.4,
			Callback = function(value)
				runtime.State:Set("Farming.StuckTimeout", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingTargetMoveThreshold", {
			Name = "Target movement before path refresh",
			Range = { 3, 30 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 10,
			Callback = function(value)
				runtime.State:Set("Farming.TargetMoveThreshold", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingSpeedBoostEnabled", {
			Name = "Enable automation speed boost",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.SpeedBoostEnabled", value)

				if not value then
					Engine.ClearSpeedBoost(runtime)
				end
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingSpeedBoostMultiplier", {
			Name = "Automation movement multiplier",
			Range = { 1, 3 },
			Increment = 0.1,
			Suffix = "x",
			CurrentValue = 1.5,
			Callback = function(value)
				runtime.State:Set("Farming.SpeedBoostMultiplier", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingSpeedBoostCounterSlows", {
			Name = "Compensate status slows",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.SpeedBoostCounterSlows", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Movement multiplier",
			"This uses the same client WalkspeedManager API as status effects and can counter non-zero slows up to the 3x cap. Frozen, Shock, and other zero-speed roots remain blocked. The server can still correct movement, so it is optional."
		)

		runtime.UI:CreateSection(tab, "Attack rotation")
		runtime.UI:CreateToggle(tab, "FarmingStickyTargets", {
			Name = "Keep each target until it becomes invalid",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.StickyTargets", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingSkipStalledTargets", {
			Name = "Skip targets that take no damage",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.SkipStalledTargets", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingNoDamageTimeout", {
			Name = "No-damage target timeout",
			Range = { 5, 45 },
			Increment = 1,
			Suffix = "s",
			CurrentValue = 15,
			Callback = function(value)
				runtime.State:Set("Farming.NoDamageTimeout", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingAutoAttack", {
			Name = "Attack selected target",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoAttack", value)
			end,
		})

		runtime.UI:CreateDropdown(tab, "FarmingRotationMode", {
			Name = "Attack rotation",
			Options = {
				"Full Rotation",
				"Primary Only",
				"Selected Slot",
			},
			CurrentOption = { "Full Rotation" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Farming.RotationMode", options and options[1] or "Full Rotation")
			end,
		})

		runtime.UI:CreateDropdown(tab, "FarmingAttackSlot", {
			Name = "Selected-slot attack",
			Options = {
				"Primary",
				"Skill1",
				"Skill2",
				"Skill3",
				"Skill4",
				"Ultimate",
			},
			CurrentOption = { "Primary" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Farming.AttackSlot", options and options[1] or "Primary")
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingUseUltimate", {
			Name = "Use Ultimate at full energy",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.UseUltimate", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingSkillRetryInterval", {
			Name = "Per-skill retry spacing",
			Range = { 0.2, 2 },
			Increment = 0.1,
			Suffix = "s",
			CurrentValue = 0.6,
			Callback = function(value)
				runtime.State:Set("Farming.SkillRetryInterval", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingAttackRange", {
			Name = "Maximum distance to attack",
			Range = { 5, 80 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 45,
			Callback = function(value)
				runtime.State:Set("Farming.AttackRange", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Damage avoidance")
		runtime.UI:CreateToggle(tab, "FarmingAutoThawFreezeTag", {
			Name = "Thaw Freeze Tag teammates",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoThawFreezeTag", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingFreezeTagRescueRange", {
			Name = "Freeze Tag rescue range",
			Range = { 20, 300 },
			Increment = 10,
			Suffix = " studs",
			CurrentValue = 120,
			Callback = function(value)
				runtime.State:Set("Farming.FreezeTagRescueRange", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified freeze behavior",
			"Freeze Tag thaws after a non-frozen player remains within 15 studs for one second, so automation can rescue teammates. Normal Frozen and Frozen Heartbreak only lock movement; their supplied handlers expose no client break-free action."
		)

		runtime.UI:CreateToggle(tab, "FarmingAutoDodge", {
			Name = "Auto Dodge incoming attacks",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoDodge", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingDebuffSurvival", {
			Name = "Debuff-aware survival mode",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.DebuffSurvival", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingDebuffSafetyThreshold", {
			Name = "DoT/vulnerability safety threshold",
			Range = { 20, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 60,
			Callback = function(value)
				runtime.State:Set("Farming.DebuffSafetyThreshold", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingDodgeAfterDamage", {
			Name = "Dodge follow-up attacks after damage",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.DodgeAfterDamage", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingDamageReactionWindow", {
			Name = "Post-damage Dodge window",
			Range = { 0.25, 3 },
			Increment = 0.25,
			Suffix = "s",
			CurrentValue = 1.25,
			Callback = function(value)
				runtime.State:Set("Farming.DamageReactionWindow", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingThreatRadius", {
			Name = "Threat detection radius",
			Range = { 5, 60 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 25,
			Callback = function(value)
				runtime.State:Set("Farming.ThreatRadius", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingDodgeHealthThreshold", {
			Name = "Extra Dodge below health",
			Range = { 10, 100 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 70,
			Callback = function(value)
				runtime.State:Set("Farming.DodgeHealthThreshold", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingEmergencyRetreat", {
			Name = "Emergency low-health retreat",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.EmergencyRetreat", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingRetreatHealthThreshold", {
			Name = "Retreat below health",
			Range = { 5, 80 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 30,
			Callback = function(value)
				runtime.State:Set("Farming.RetreatHealthThreshold", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingRetreatDistance", {
			Name = "Emergency retreat distance",
			Range = { 10, 80 },
			Increment = 5,
			Suffix = " studs",
			CurrentValue = 35,
			Callback = function(value)
				runtime.State:Set("Farming.RetreatDistance", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "FarmingAutoHealItem", {
			Name = "Use a quick heal item",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.AutoHealItem", value)
			end,
		})

		runtime.UI:CreateInput(tab, "FarmingHealItemName", {
			Name = "Quick heal item name",
			CurrentValue = "",
			PlaceholderText = "Exact quick-item name",
			RemoveTextAfterFocusLost = false,
			Callback = function(value)
				runtime.State:Set("Farming.HealItemName", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingHealItemHealthThreshold", {
			Name = "Use heal item below health",
			Range = { 5, 90 },
			Increment = 5,
			Suffix = "%",
			CurrentValue = 40,
			Callback = function(value)
				runtime.State:Set("Farming.HealItemHealthThreshold", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingHealItemRetryInterval", {
			Name = "Heal-item retry spacing",
			Range = { 1, 20 },
			Increment = 1,
			Suffix = "s",
			CurrentValue = 5,
			Callback = function(value)
				runtime.State:Set("Farming.HealItemRetryInterval", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Diagnostics and timing")
		runtime.UI:CreateSlider(tab, "FarmingUpdateInterval", {
			Name = "Farm update interval",
			Range = { 0.1, 1 },
			Increment = 0.05,
			Suffix = "s",
			CurrentValue = 0.2,
			Callback = function(value)
				runtime.State:Set("Farming.UpdateInterval", value)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show automation status",
			Callback = function()
				local threat, threatError =
					runtime.MobsAPI.GetThreatState(runtime.State:Get("Farming.ThreatRadius", 25))
				local navigation = runtime.Navigator.GetState()
				local className = runtime.ClassRegistry.GetCurrentClass() or "Unknown"
				local survival = Engine.GetSurvivalState(runtime)
				local statuses, statusesError = runtime.Status.GetSummary()
				local walkspeed, walkspeedError = runtime.Walkspeed.Get()
				local outOfCombat = runtime.Health.IsOutOfCombat()
				local lastDamage = runtime.Health.GetLastDamage()
				local statusAnalysis = statuses and statuses.Analysis or {}

				runtime.UI:Notify(
					"Automation status",
					"Class: "
						.. tostring(className)
						.. "\nRotation: "
						.. tostring(runtime.State:Get("Farming.RotationMode", "Full Rotation"))
						.. "\nHealth: "
						.. tostring(math.floor(survival.HealthRatio * 100))
						.. "%"
						.. "\nBarrier: "
						.. tostring(math.floor(survival.Barrier))
						.. " | protected: "
						.. tostring(math.floor(survival.ProtectionRatio * 100))
						.. "%"
						.. "\nWalkspeed: "
						.. tostring(walkspeed and math.floor(walkspeed * 10) / 10 or walkspeedError)
						.. "\nStatuses: "
						.. tostring(statuses and statuses.Text or statusesError)
						.. "\nStatus risk: DoT "
						.. tostring(math.floor((statusAnalysis.DamagePerSecond or 0) * 100))
						.. "%/s"
						.. " | move blocked "
						.. tostring(statusAnalysis.MovementBlocked or false)
						.. " | skills blocked "
						.. tostring(statusAnalysis.SkillsBlocked or false)
						.. "\nHealing blocked: "
						.. tostring(statusAnalysis.HealingBlocked or false)
						.. " | vulnerable: "
						.. tostring(statusAnalysis.HasDefenseDebuff or false)
						.. " | fatal: "
						.. tostring(statusAnalysis.HasFatalStatus or false)
						.. "\nOut of combat: "
						.. tostring(outOfCombat)
						.. "\nLast damage: "
						.. tostring(lastDamage and lastDamage.Amount or 0)
						.. " from "
						.. tostring(lastDamage and lastDamage.Attacker or "none")
						.. "\nThreats: "
						.. tostring(threat and threat.Count or 0)
						.. " (attacking: "
						.. tostring(threat and threat.AttackingCount or 0)
						.. ")"
						.. "\nNavigation: "
						.. tostring(navigation.Status)
						.. (threat and "" or ("\nThreat scan: " .. tostring(threatError))),
					8,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show current farm target",
			Callback = function()
				local target, descriptor = Engine.GetTarget(runtime)

				if not target or not descriptor then
					runtime.UI:Notify("Farm target", "No mob matches the current filters.", 4, 0)
					return
				end

				runtime.UI:Notify(
					"Farm target",
					tostring(descriptor.NameTag)
						.. "\nType: "
						.. tostring(descriptor.Type)
						.. "\nDistance: "
						.. tostring(math.floor(descriptor.Distance))
						.. " studs"
						.. "\nHealth: "
						.. tostring(math.floor(descriptor.Health.Ratio * 100))
						.. "%"
						.. "\nLevel: "
						.. tostring(descriptor.Level)
						.. "\nBoss: "
						.. tostring(descriptor.BossTag or "no")
						.. "\nElite: "
						.. tostring(descriptor.IsElite),
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Scan matching mobs",
			Callback = function()
				local matching, matchingError = runtime.MobsAPI.GetMatching(Engine.GetOptions(runtime))

				runtime.UI:Notify(
					"Mob scan",
					matching and (tostring(#matching) .. " valid mob(s) match the current filters.")
						or ("Scan failed: " .. tostring(matchingError)),
					5,
					0
				)
			end,
		})
	end

	return Farming
end
