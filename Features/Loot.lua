return function(ctx)
	local Loot = {
		Id = "Loot",
	}

	local Engine = ctx:Require("FarmingEngine")
	local InventoryEngine = ctx:Require("InventoryEngine")

	function Loot.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Loot)
		local dropStatus = runtime.DropsAPI.Describe()
		local chestStatus = runtime.ChestsAPI.Describe()
		local inventoryStatus = runtime.InventoryAPI.Describe()
		local selling = false

		runtime.State:Set("Loot.DropsEnabled", false)
		runtime.State:Set("Loot.ChestsEnabled", true)
		runtime.State:Set("Loot.CollectionRange", 120)
		runtime.State:Set("Loot.CombatPriorityRange", 35)
		runtime.State:Set("Loot.CollectDuringCombat", false)
		runtime.State:Set("Loot.AfterKillSweep", true)
		runtime.State:Set("Loot.AfterKillSweepDuration", 2.5)
		runtime.State:Set("Loot.SellingArmed", false)
		runtime.State:Set("Loot.SmartSellDominatedGear", true)
		runtime.State:Set("Loot.SmartSellKeepPerCategory", 2)
		runtime.State:Set("Loot.SellByTierEnabled", false)
		runtime.State:Set("Loot.SellMaxTier", 1)
		runtime.State:Set("Loot.SellMaxLevel", 10)
		runtime.State:Set("Loot.PreserveModified", true)
		runtime.State:Set("Loot.AutoSellEnabled", false)
		runtime.State:Set("Loot.AutoSellArmed", false)
		runtime.State:Set("Loot.AutoSellReserveSlots", 3)
		runtime.State:Set("Loot.AutoSellBatchSize", 5)
		runtime.State:Set("Loot.AutoSellInterval", 5)
		runtime.State:Set("Loot.AutoSellModifiedDominated", true)
		runtime.State:Set("Loot.AutoCloseRewardReveal", true)

		local lootReceivedController = nil

		local function closeRewardReveal()
			if type(lootReceivedController) ~= "table" then
				local replicatedStorage = game:GetService("ReplicatedStorage")
				local client = replicatedStorage:FindFirstChild("Client")
				local gui = client and client:FindFirstChild("Gui")
				local scripts = gui and gui:FindFirstChild("GuiScripts")
				local moduleScript = scripts and scripts:FindFirstChild("LootReceived")

				if not moduleScript or not moduleScript:IsA("ModuleScript") then
					return false
				end

				local ok, controller = pcall(require, moduleScript)

				if not ok or type(controller) ~= "table" then
					return false
				end

				lootReceivedController = controller
			end

			if type(lootReceivedController._Close) ~= "function" then
				return false
			end

			return pcall(lootReceivedController._Close, lootReceivedController)
		end

		task.spawn(function()
			while not runtime.Stopped do
				if runtime.State:Get("Loot.AutoCloseRewardReveal", true) then
					closeRewardReveal()
				end

				task.wait(0.15)
			end
		end)

		runtime.Janitor:Add(function()
			InventoryEngine.Stop(runtime)
		end)

		runtime.UI:CreateSection(tab, "Drop collection")
		runtime.Controls.LootDropsEnabled = runtime.UI:CreateToggle(tab, "LootDropsEnabled", {
			Name = "Collect dropped items and currency",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.DropsEnabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.Controls.LootChestsEnabled = runtime.UI:CreateToggle(tab, "LootChestsEnabled", {
			Name = "Approach spawned reward chests",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.ChestsEnabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootAutoCloseRewardReveal", {
			Name = "Close chest item reveal automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.AutoCloseRewardReveal", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootCollectionRange", {
			Name = "Loot search range",
			Range = { 20, 500 },
			Increment = 10,
			Suffix = " studs",
			CurrentValue = 120,
			Callback = function(value)
				runtime.State:Set("Loot.CollectionRange", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootCombatPriorityRange", {
			Name = "Collect during combat within",
			Range = { 5, 100 },
			Increment = 5,
			Suffix = " studs",
			CurrentValue = 35,
			Callback = function(value)
				runtime.State:Set("Loot.CombatPriorityRange", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootCollectDuringCombat", {
			Name = "Allow loot to interrupt a live target",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.CollectDuringCombat", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootAfterKillSweep", {
			Name = "Brief loot sweep after each defeated target",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.AfterKillSweep", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootAfterKillSweepDuration", {
			Name = "Post-combat loot window",
			Range = { 0.5, 6 },
			Increment = 0.5,
			Suffix = "s",
			CurrentValue = 2.5,
			Callback = function(value)
				runtime.State:Set("Loot.AfterKillSweepDuration", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified collection behavior",
			"The game creates pickup parts in workspace.Coins and collects them at about four studs. Spawned reward chests open through the game's own proximity check at about ten studs. This feature only walks into those verified ranges; it does not forge reward requests."
		)

		runtime.UI:CreateParagraph(
			tab,
			"Movement coordination",
			"Drops, chests, quests, combat, retreats, and teammate rescues share one navigator. By default, loot never steals movement from a living combat target; a short sweep opens only after the locked target is defeated."
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show nearby loot",
			Callback = function()
				local range = runtime.State:Get("Loot.CollectionRange", 120)
				local drops, dropError = runtime.DropsAPI.List(range)
				local chests, chestError = runtime.ChestsAPI.List(range)

				runtime.UI:Notify(
					"Nearby loot",
					"Drops: "
						.. tostring(drops and #drops or 0)
						.. (drops and "" or (" (" .. tostring(dropError) .. ")"))
						.. "\nChests: "
						.. tostring(chests and #chests or 0)
						.. (chests and "" or (" (" .. tostring(chestError) .. ")")),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Source status",
			"Drop folder present now: "
				.. tostring(dropStatus.Available)
				.. " | Visible chests now: "
				.. tostring(chestStatus.Count)
		)

		runtime.UI:CreateSection(tab, "Protected inventory cleanup")
		runtime.UI:CreateToggle(tab, "LootSellingArmed", {
			Name = "Arm manual inventory selling",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.SellingArmed", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootSmartSellDominatedGear", {
			Name = "Sell gear dominated by stronger gear",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.SmartSellDominatedGear", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootSmartSellKeepPerCategory", {
			Name = "Strongest items kept per gear category",
			Range = { 1, 5 },
			Increment = 1,
			Suffix = " items",
			CurrentValue = 2,
			Callback = function(value)
				runtime.State:Set("Loot.SmartSellKeepPerCategory", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootSellByTierEnabled", {
			Name = "Also use tier and level sell rules",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.SellByTierEnabled", value)
			end,
		})

		runtime.UI:CreateDropdown(tab, "LootSellMaxTier", {
			Name = "Highest tier to sell",
			Options = {
				"Tier 1",
				"Tier 2",
				"Tier 3",
			},
			CurrentOption = { "Tier 1" },
			MultipleOptions = false,
			Callback = function(options)
				local label = options and options[1] or "Tier 1"
				local tier = tonumber(string.match(label, "%d+")) or 1
				runtime.State:Set("Loot.SellMaxTier", tier)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootSellMaxLevel", {
			Name = "Highest item level to sell",
			Range = { 1, 150 },
			Increment = 1,
			Suffix = "",
			CurrentValue = 10,
			Callback = function(value)
				runtime.State:Set("Loot.SellMaxLevel", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootPreserveModified", {
			Name = "Preserve empowered, dyed, and modified items",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.PreserveModified", value)
			end,
		})

		local getSellCandidates = function()
			return InventoryEngine.GetCandidates(runtime)
		end

		runtime.UI:CreateButton(tab, {
			Name = "Preview protected sell selection",
			Callback = function()
				local candidates, candidateError, candidateSummary = getSellCandidates()

				if not candidates then
					runtime.UI:Notify("Sell preview", "Preview failed: " .. tostring(candidateError), 5, 0)
					return
				end

				local sample = {}

				for index = 1, math.min(5, #candidates) do
					local item = candidates[index]
					table.insert(
						sample,
						item.Name
							.. " ("
							.. tostring(item.CleanupMode or "rule")
							.. (item.DominatedBy and (", replaced by " .. tostring(item.DominatedBy)) or "")
							.. ")"
					)
				end

				runtime.UI:Notify(
					"Sell preview",
					tostring(#candidates)
						.. " safe cleanup item(s) match; "
						.. tostring(candidateSummary and candidateSummary.Smart or 0)
						.. " are dominated gear."
						.. (#sample > 0 and ("\n" .. table.concat(sample, "\n")) or ""),
					8,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Sell matching unprotected items now",
			Callback = function()
				if not runtime.State:Get("Loot.SellingArmed", false) then
					runtime.UI:Notify("Inventory selling", "Arm manual inventory selling first.", 4, 0)
					return
				end

				if selling then
					return
				end

				selling = true
				local candidates, candidateError = getSellCandidates()

				if not candidates or #candidates == 0 then
					selling = false
					runtime.UI:Notify(
						"Inventory selling",
						candidates and "No unprotected items match."
							or ("Selection failed: " .. tostring(candidateError)),
						5,
						0
					)
					return
				end

				local gold, soldOrError = runtime.InventoryAPI.Sell(
					candidates,
					runtime.State:Get("Loot.PreserveModified", true),
					runtime.GearAPI.GetProtectedItems({
						ReserveBestTradable = runtime.State:Get("Gear.ReserveBestTradable", true),
					})
				)
				selling = false

				runtime.UI:Notify(
					"Inventory selling",
					gold and (tostring(soldOrError) .. " item(s) sold for " .. tostring(gold) .. " gold.")
						or ("Sell failed: " .. tostring(soldOrError)),
					6,
					0
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Sell protection",
			inventoryStatus.Available
					and "Locked, favorited, equipped, current-best, and best-upgrade-potential items are always excluded and rechecked immediately before the server request. Modified-item protection is enabled by default. Smart cleanup compares maximum upgraded Attack or Defense inside the same weapon subtype or armor category."
				or ("Inventory selling unavailable: " .. tostring(inventoryStatus.Error))
		)

		runtime.UI:CreateSection(tab, "Inventory pressure")
		runtime.UI:CreateParagraph(
			tab,
			"Why this matters",
			"World Zero refuses item pickups when inventory slots are full. Cleanup starts while reserve slots still exist, so a newly dropped upgrade can enter the inventory first. It then becomes protected as the new best item and the weakest dominated predecessor becomes the first sell candidate."
		)

		runtime.UI:CreateToggle(tab, "LootAutoSellEnabled", {
			Name = "Clean inventory automatically near full",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.AutoSellEnabled", value)
				InventoryEngine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootAutoSellArmed", {
			Name = "Arm automatic protected selling",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.AutoSellArmed", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootAutoSellModifiedDominated", {
			Name = "Sell weaker perked gear when space is low",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Loot.AutoSellModifiedDominated", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootAutoSellReserveSlots", {
			Name = "Start cleanup at remaining slots",
			Range = { 0, 10 },
			Increment = 1,
			Suffix = " slots",
			CurrentValue = 3,
			Callback = function(value)
				runtime.State:Set("Loot.AutoSellReserveSlots", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "LootAutoSellBatchSize", {
			Name = "Maximum items per cleanup",
			Range = { 1, 15 },
			Increment = 1,
			Suffix = " items",
			CurrentValue = 5,
			Callback = function(value)
				runtime.State:Set("Loot.AutoSellBatchSize", value)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show inventory supervisor status",
			Callback = function()
				local capacity, capacityError = runtime.InventoryAPI.GetCapacity()
				local status = InventoryEngine.GetStatus(runtime)
				local capacityText = capacity
						and (
							tostring(capacity.Used)
							.. "/"
							.. tostring(capacity.Capacity)
							.. " slots used; "
							.. tostring(capacity.Remaining)
							.. " remaining."
						)
					or ("Capacity unavailable: " .. tostring(capacityError))

				runtime.UI:Notify(
					"Inventory supervisor",
					capacityText
						.. "\nLast action: "
						.. tostring(status and status.Action or "none")
						.. "\nSmart candidates: "
						.. tostring(status and status.SmartCandidates or 0)
						.. "\nDetail: "
						.. tostring(status and status.Error or "none"),
					7,
					0
				)
			end,
		})
	end

	return Loot
end
