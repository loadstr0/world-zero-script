return function()
	local Farming = {
		Id = "Farming",
	}

	local activeLoops = {}
	local activeTargets = {}
	local movementWarnings = {}

	local function getOptions(runtime, rangeOverride)
		local configuredRange =
			runtime.State:Get("Farming.TargetRange", 120)

		return {
			Mode = runtime.State:Get("Farming.TargetMode", "Nearest"),
			Range = math.min(
				tonumber(rangeOverride) or configuredRange,
				configuredRange
			),
			BossOnly = runtime.State:Get("Farming.BossOnly", false),
			EliteOnly = runtime.State:Get("Farming.EliteOnly", false),
			NameFilter = runtime.State:Get("Farming.NameFilter", ""),
			IncludeOwned = false,
		}
	end

	local function getTarget(runtime, rangeOverride)
		local target, descriptor =
			runtime.MobsAPI.SelectTarget(getOptions(runtime, rangeOverride))

		if target then
			activeTargets[runtime] = target
		end

		return target, descriptor
	end

	local function stopWalking(runtime)
		local humanoid = runtime.Game.GetHumanoid()
		local root = runtime.Game.GetRootPart()

		if humanoid and root then
			humanoid:MoveTo(root.Position)
		end
	end

	local function approachTarget(runtime, descriptor)
		if not runtime.State:Get("Farming.AutoApproach", true) then
			return false
		end

		local humanoid = runtime.Game.GetHumanoid()
		local root = runtime.Game.GetRootPart()

		if not humanoid or not root then
			if not movementWarnings[runtime] then
				movementWarnings[runtime] = true
				runtime.UI:Notify(
					"Auto approach",
					"This character has no client Humanoid movement controller. Targeting and attacks remain active.",
					5,
					0
				)
			end

			return false
		end

		local stopDistance =
			runtime.State:Get("Farming.StopDistance", 10)

		if descriptor.Distance <= stopDistance then
			humanoid:MoveTo(root.Position)
			return false
		end

		local offset = root.Position - descriptor.Position
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local direction = flatOffset.Magnitude > 0
				and flatOffset.Unit
			or Vector3.new(0, 0, 1)
		local destination =
			descriptor.Position + direction * stopDistance

		humanoid:MoveTo(destination)
		return true
	end

	local function useFarmAttack(runtime, target, descriptor)
		if
			not runtime.State:Get("Farming.AutoAttack", true)
			or descriptor.Distance
				> runtime.State:Get("Farming.AttackRange", 20)
			or runtime.Actions.IsBusy() == true
		then
			return
		end

		local adapter = runtime.ClassRegistry.GetCurrentAdapter()

		if adapter and type(adapter.EnsureUnsheathed) == "function" then
			local ready = adapter.EnsureUnsheathed()

			if not ready then
				return
			end
		end

		if runtime.State:Get("Combat.AutoAim", true) then
			runtime.Actions.AimAtTarget(
				target,
				runtime.State:Get("Combat.AimDuration", 0.2)
			)
		end

		local slot = runtime.State:Get("Farming.AttackSlot", "Primary")

		if adapter and type(adapter.Use) == "function" then
			adapter.Use(slot)
		elseif
			slot == "Primary"
			and adapter
			and type(adapter.UsePrimary) == "function"
		then
			adapter.UsePrimary()
		else
			runtime.Actions.UseSkill(slot)
		end
	end

	local function startLoop(runtime)
		if activeLoops[runtime] then
			return
		end

		activeLoops[runtime] = true

		task.spawn(function()
			while
				not runtime.Stopped
				and runtime.State:Get("Farming.Enabled", false)
			do
				local target, descriptor = getTarget(runtime)

				if target and descriptor then
					approachTarget(runtime, descriptor)
					useFarmAttack(runtime, target, descriptor)
				else
					activeTargets[runtime] = nil
					stopWalking(runtime)
				end

				task.wait(
					runtime.State:Get("Farming.UpdateInterval", 0.2)
				)
			end

			stopWalking(runtime)
			runtime.Actions.ClearTargetProvider()
			activeTargets[runtime] = nil
			activeLoops[runtime] = nil
			movementWarnings[runtime] = nil
		end)
	end

	function Farming.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		local mobStatus = runtime.MobsAPI.Describe()
		local targetProvider = function(range)
			return getTarget(runtime, range)
		end

		runtime.State:Set("Farming.Enabled", false)
		runtime.State:Set("Farming.TargetMode", "Nearest")
		runtime.State:Set("Farming.TargetRange", 120)
		runtime.State:Set("Farming.BossOnly", false)
		runtime.State:Set("Farming.EliteOnly", false)
		runtime.State:Set("Farming.NameFilter", "")
		runtime.State:Set("Farming.AutoApproach", true)
		runtime.State:Set("Farming.StopDistance", 10)
		runtime.State:Set("Farming.AutoAttack", true)
		runtime.State:Set("Farming.AttackSlot", "Primary")
		runtime.State:Set("Farming.AttackRange", 20)
		runtime.State:Set("Farming.UpdateInterval", 0.2)

		runtime.Janitor:Add(function()
			runtime.Actions.ClearTargetProvider(targetProvider)
		end)

		runtime.UI:CreateSection(tab, "Auto Farm")
		runtime.UI:CreateToggle(tab, "FarmingEnabled", {
			Name = "Enable filtered Auto Farm",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Farming.Enabled", value)

				if value then
					runtime.Actions.SetTargetProvider(targetProvider)
					startLoop(runtime)
				else
					runtime.Actions.ClearTargetProvider(targetProvider)
				end
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
			"Auto Farm can attack with one selected slot itself. When a class combat aura is also enabled in the Combat tab, that full class rotation inherits these same filtered targets."
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
				runtime.State:Set(
					"Farming.TargetMode",
					options and options[1] or "Nearest"
				)
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

		runtime.UI:CreateSection(tab, "Movement and attacks")
		runtime.UI:CreateToggle(tab, "FarmingAutoApproach", {
			Name = "Walk toward selected target",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoApproach", value)

				if not value then
					stopWalking(runtime)
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

		runtime.UI:CreateToggle(tab, "FarmingAutoAttack", {
			Name = "Attack selected target",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Farming.AutoAttack", value)
			end,
		})

		runtime.UI:CreateDropdown(tab, "FarmingAttackSlot", {
			Name = "Farm attack slot",
			Options = {
				"Primary",
				"Skill1",
				"Skill2",
				"Skill3",
				"Ultimate",
			},
			CurrentOption = { "Primary" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set(
					"Farming.AttackSlot",
					options and options[1] or "Primary"
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "FarmingAttackRange", {
			Name = "Maximum distance to attack",
			Range = { 5, 80 },
			Increment = 1,
			Suffix = " studs",
			CurrentValue = 20,
			Callback = function(value)
				runtime.State:Set("Farming.AttackRange", value)
			end,
		})

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
			Name = "Show current farm target",
			Callback = function()
				local target, descriptor = getTarget(runtime)

				if not target or not descriptor then
					runtime.UI:Notify(
						"Farm target",
						"No mob matches the current filters.",
						4,
						0
					)
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
				local matching, matchingError =
					runtime.MobsAPI.GetMatching(getOptions(runtime))

				runtime.UI:Notify(
					"Mob scan",
					matching
							and (
								tostring(#matching)
								.. " valid mob(s) match the current filters."
							)
						or ("Scan failed: " .. tostring(matchingError)),
					5,
					0
				)
			end,
		})
	end

	return Farming
end
