return function()
	local Teleports = {
		Id = "Teleports",
		Title = "Teleports",
		Icon = "map",
	}

	function Teleports.Register(runtime)
		local tab = runtime.UI:CreateTab(Teleports.Id, Teleports.Title, Teleports.Icon)
		runtime.UI:CreateSection(tab, "Destinations")
		runtime.UI:CreateParagraph(
			tab,
			"Source required",
			"World, hub, and mission destinations will be populated from verified teleport data."
		)
	end

	return Teleports
end

