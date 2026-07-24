return function()
	local Farming = {
		Id = "Farming",
		Title = "Farming",
		Icon = "sprout",
	}

	function Farming.Register(runtime)
		local tab = runtime.UI:CreateTab(Farming.Id, Farming.Title, Farming.Icon)
		runtime.UI:CreateSection(tab, "Automation")
		runtime.UI:CreateParagraph(
			tab,
			"Source required",
			"Target selection, movement, and attack controls will be added after their game APIs are verified."
		)
	end

	return Farming
end

