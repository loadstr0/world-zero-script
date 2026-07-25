return function(ctx)
	local Gear = {
		Id = "Gear",
	}

	local Engine = ctx:Require("GearEngine")

	local function formatDescriptor(descriptor)
		if not descriptor then
			return "none"
		end

		local perkNames = {}

		for _, perk in ipairs(descriptor.Perks or {}) do
			table.insert(
				perkNames,
				perk.DisplayName .. " " .. tostring(math.floor((tonumber(perk.Value) or 0) * 100)) .. "%"
			)
		end

		return descriptor.Name
			.. " | "
			.. descriptor.Stat
			.. " "
			.. tostring(math.floor(descriptor.CurrentScore))
			.. " → "
			.. tostring(math.floor(descriptor.MaximumScore))
			.. " | +"
			.. tostring(descriptor.Upgrade)
			.. "/"
			.. tostring(descriptor.UpgradeLimit)
			.. (descriptor.TradeEligible and " | trade reserve eligible" or "")
			.. " | farm score "
			.. tostring(
				math.floor(
					tonumber(descriptor.EffectiveMaximumScore)
						or tonumber(descriptor.MaximumScore)
						or 0
				)
			)
			.. (#perkNames > 0 and (" | " .. table.concat(perkNames, ", ")) or "")
	end

	function Gear.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Gear)
		local sourceStatus = runtime.GearAPI.Describe()

		runtime.State:Set("Gear.Enabled", false)
		runtime.State:Set("Gear.AutoWeapons", true)
		runtime.State:Set("Gear.AutoOffhand", true)
		runtime.State:Set("Gear.AutoArmor", true)
		runtime.State:Set("Gear.ReserveBestTradable", true)
		runtime.State:Set("Gear.AutoUpgrade", false)
		runtime.State:Set("Gear.AutoEquip", true)
		runtime.State:Set("Gear.EquipOnlyMaxed", false)
		runtime.State:Set("Gear.UpgradeMode", "Gold attempts")
		runtime.State:Set("Gear.GoldReserve", 0)
		runtime.State:Set("Gear.CrystalReserve", 0)
		runtime.State:Set("Gear.MinimumImprovement", 0)
		runtime.State:Set("Gear.MaxAttemptsPerItem", 50)
		runtime.State:Set("Gear.UpdateInterval", 2)

		runtime.Janitor:Add(function()
			Engine.Stop(runtime)
		end)

		runtime.UI:CreateSection(tab, "Smart loadout")
		runtime.UI:CreateParagraph(
			tab,
			"Maximum-potential scoring",
			sourceStatus.Available
					and "Weapons and armor are cloned at their real UpgradeLimit, then ranked by a balanced farming score. It includes raw Attack/Defense plus the item's real perk values: damage, critical stacking, sustain, ultimate charge, boss modifiers, HP, dodge, damage reduction, status resistance, and utility. Class and slot compatibility are still verified before any request."
				or ("Gear integration unavailable: " .. tostring(sourceStatus.Error))
		)

		runtime.Controls.GearEnabled = runtime.UI:CreateToggle(tab, "GearAutomationEnabled", {
			Name = "Enable smart gear automation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Gear.Enabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateToggle(tab, "GearAutoWeapons", {
			Name = "Manage best weapons",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Gear.AutoWeapons", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GearAutoOffhand", {
			Name = "Manage compatible offhand",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Gear.AutoOffhand", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GearAutoArmor", {
			Name = "Manage best armor",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Gear.AutoArmor", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GearReserveBestTradable", {
			Name = "Reserve strongest tradeable gear for main",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Gear.ReserveBestTradable", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GearMinimumImprovement", {
			Name = "Required potential improvement",
			Range = { 0, 25 },
			Increment = 1,
			Suffix = "%",
			CurrentValue = 0,
			Callback = function(value)
				runtime.State:Set("Gear.MinimumImprovement", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Upgrade and equip")
		runtime.UI:CreateToggle(tab, "GearAutoUpgrade", {
			Name = "Upgrade only the best candidate",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Gear.AutoUpgrade", value)
			end,
		})

		runtime.UI:CreateDropdown(tab, "GearUpgradeMode", {
			Name = "Upgrade payment mode",
			Options = {
				"Gold attempts",
				"Guaranteed crystals",
			},
			CurrentOption = { "Gold attempts" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Gear.UpgradeMode", options and options[1] or "Gold attempts")
			end,
		})

		runtime.UI:CreateToggle(tab, "GearAutoEquip", {
			Name = "Equip confirmed improvements",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Gear.AutoEquip", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "GearEquipOnlyMaxed", {
			Name = "Wait until candidate is fully upgraded",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Gear.EquipOnlyMaxed", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Spending safety",
			"Automatic upgrading is off by default. Gold mode retries the game's normal chance-based upgrade and can spend repeatedly. Guaranteed mode uses 20 crystals per remaining upgrade level. Reserves and a per-item attempt cap are always enforced."
		)

		runtime.UI:CreateSlider(tab, "GearGoldReserve", {
			Name = "Keep at least this much gold",
			Range = { 0, 5000000 },
			Increment = 10000,
			Suffix = " gold",
			CurrentValue = 0,
			Callback = function(value)
				runtime.State:Set("Gear.GoldReserve", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GearCrystalReserve", {
			Name = "Keep at least this many crystals",
			Range = { 0, 5000 },
			Increment = 20,
			Suffix = " crystals",
			CurrentValue = 0,
			Callback = function(value)
				runtime.State:Set("Gear.CrystalReserve", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GearMaxAttemptsPerItem", {
			Name = "Maximum gold attempts per item",
			Range = { 1, 200 },
			Increment = 1,
			Suffix = " attempts",
			CurrentValue = 50,
			Callback = function(value)
				runtime.State:Set("Gear.MaxAttemptsPerItem", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "GearUpdateInterval", {
			Name = "Inventory rescan interval",
			Range = { 0.5, 10 },
			Increment = 0.5,
			Suffix = "s",
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Gear.UpdateInterval", value)
			end,
		})

		runtime.UI:CreateSection(tab, "Loadout report")
		runtime.UI:CreateButton(tab, {
			Name = "Scan maximum-potential loadout",
			Callback = function()
				local scan = Engine.Scan(runtime)
				local lines = {}

				for _, slotName in ipairs(runtime.GearAPI.GetSlotNames()) do
					local slot = scan[slotName]
					table.insert(
						lines,
						slotName
							.. "\nCurrent: "
							.. formatDescriptor(slot and slot.Current)
							.. "\nBest: "
							.. formatDescriptor(slot and slot.Best)
							.. "\nReserved for main: "
							.. formatDescriptor(slot and slot.Reserved)
							.. "\nPotential gain: "
							.. (
								slot and slot.Improvement == math.huge and "new slot"
								or (tostring(math.floor(tonumber(slot and slot.Improvement or 0) * 10) / 10) .. "%")
							)
					)
				end

				runtime.UI:Notify("Smart gear scan", table.concat(lines, "\n\n"), 12, 0)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Run one safe gear action",
			Callback = function()
				local ok, actionError = Engine.Step(runtime)
				local status = Engine.GetStatus(runtime)

				runtime.UI:Notify(
					"Gear action",
					"Result: "
						.. tostring(ok)
						.. "\nAction: "
						.. tostring(status and status.Action or "none")
						.. "\nSlot: "
						.. tostring(status and status.Slot or "none")
						.. "\nItem: "
						.. tostring(status and status.Item or "none")
						.. "\nDetail: "
						.. tostring(actionError or (status and status.Error)),
					8,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Reset session upgrade-attempt limits",
			Callback = function()
				Engine.ResetAttempts(runtime)
				runtime.UI:Notify("Gear automation", "Session attempt counters reset.", 4, 0)
			end,
		})
	end

	return Gear
end
