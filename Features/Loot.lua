return function(ctx)
	local Loot = {
		Id = "Loot",
	}

	local Engine = ctx:Require("FarmingEngine")

	function Loot.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		local dropStatus = runtime.DropsAPI.Describe()
		local chestStatus = runtime.ChestsAPI.Describe()
		local inventoryStatus = runtime.InventoryAPI.Describe()
		local selling = false

		runtime.State:Set("Loot.DropsEnabled", false)
		runtime.State:Set("Loot.ChestsEnabled", false)
		runtime.State:Set("Loot.CollectionRange", 120)
		runtime.State:Set("Loot.CombatPriorityRange", 35)
		runtime.State:Set("Loot.SellingArmed", false)
		runtime.State:Set("Loot.SellMaxTier", 1)
		runtime.State:Set("Loot.SellMaxLevel", 10)
		runtime.State:Set("Loot.PreserveModified", true)

		runtime.UI:CreateSection(tab, "Drop collection")
		runtime.UI:CreateToggle(tab, "LootDropsEnabled", {
			Name = "Collect dropped items and currency",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.DropsEnabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateToggle(tab, "LootChestsEnabled", {
			Name = "Approach spawned reward chests",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Loot.ChestsEnabled", value)
				Engine.Reconcile(runtime)
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

		runtime.UI:CreateParagraph(
			tab,
			"Verified collection behavior",
			"The game creates pickup parts in workspace.Coins and collects them at about four studs. Spawned reward chests open through the game's own proximity check at about ten studs. This feature only walks into those verified ranges; it does not forge reward requests."
		)

		runtime.UI:CreateParagraph(
			tab,
			"Movement coordination",
			"Drops, chests, quests, combat, retreats, and teammate rescues share one navigator. Nearby loot can briefly interrupt combat; distant loot waits until there is no active target."
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
			return runtime.InventoryAPI.ListSellCandidates({
				MaxTier = runtime.State:Get("Loot.SellMaxTier", 1),
				MaxLevel = runtime.State:Get("Loot.SellMaxLevel", 10),
				PreserveModified = runtime.State:Get("Loot.PreserveModified", true),
			})
		end

		runtime.UI:CreateButton(tab, {
			Name = "Preview protected sell selection",
			Callback = function()
				local candidates, candidateError = getSellCandidates()

				if not candidates then
					runtime.UI:Notify("Sell preview", "Preview failed: " .. tostring(candidateError), 5, 0)
					return
				end

				local sample = {}

				for index = 1, math.min(5, #candidates) do
					local item = candidates[index]
					table.insert(
						sample,
						item.Name .. " (T" .. tostring(item.Tier) .. ", L" .. tostring(item.Level) .. ")"
					)
				end

				runtime.UI:Notify(
					"Sell preview",
					tostring(#candidates)
						.. " unprotected item(s) match."
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

				local gold, soldOrError =
					runtime.InventoryAPI.Sell(candidates, runtime.State:Get("Loot.PreserveModified", true))
				selling = false

				runtime.UI:Notify(
					"Inventory selling",
					gold
							and (tostring(soldOrError) .. " item(s) sold for " .. tostring(gold) .. " gold.")
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
					and "Locked and favorited items are always excluded and rechecked immediately before the server request. Modified-item protection is enabled by default. Selling is manual, armed separately, and can be previewed first."
				or ("Inventory selling unavailable: " .. tostring(inventoryStatus.Error))
		)
	end

	return Loot
end
