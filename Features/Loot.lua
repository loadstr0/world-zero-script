return function()
	local Loot = {
		Id = "Loot",
		Title = "Loot",
		Icon = "package-open",
	}

	function Loot.Register(runtime)
		local tab = runtime.UI:CreateTab(Loot.Id, Loot.Title, Loot.Icon)
		runtime.UI:CreateSection(tab, "Drops")
		runtime.UI:CreateParagraph(
			tab,
			"Source required",
			"Drop discovery and collection controls will use verified workspace objects and module exports."
		)
	end

	return Loot
end

