return function()
	local Teleports = {
		Id = "Teleports",
	}

	function Teleports.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Travel)
		runtime.UI:CreateSection(tab, "World travel")
		runtime.UI:CreateParagraph(
			tab,
			"Destinations",
			"World, hub, and mission destinations will be listed here from verified teleport data."
		)
	end

	return Teleports
end
