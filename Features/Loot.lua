return function()
	local Loot = {
		Id = "Loot",
	}

	function Loot.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		runtime.UI:CreateSection(tab, "Loot")
		runtime.UI:CreateParagraph(
			tab,
			"Drop collection",
			"Drop filters, collection range, and chest behavior will be grouped in this section."
		)
	end

	return Loot
end
