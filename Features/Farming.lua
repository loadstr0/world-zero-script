return function()
	local Farming = {
		Id = "Farming",
	}

	function Farming.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		runtime.UI:CreateSection(tab, "Farming")
		runtime.UI:CreateParagraph(
			tab,
			"Farm configuration",
			"Target selection and movement will appear here after the mob and combat APIs are verified."
		)
	end

	return Farming
end
