return function()
	local Missions = {
		Id = "Missions",
	}

	function Missions.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		runtime.UI:CreateSection(tab, "Missions")
		runtime.UI:CreateParagraph(
			tab,
			"Mission flow",
			"Mission selection, queueing, objectives, and repeat behavior will be grouped in this section."
		)
	end

	return Missions
end
