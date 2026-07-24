return function()
	local Missions = {
		Id = "Missions",
		Title = "Missions",
		Icon = "scroll-text",
	}

	function Missions.Register(runtime)
		local tab = runtime.UI:CreateTab(Missions.Id, Missions.Title, Missions.Icon)
		runtime.UI:CreateSection(tab, "Mission flow")
		runtime.UI:CreateParagraph(
			tab,
			"Source required",
			"Mission selection, queueing, objectives, and repeat logic await the relevant module source."
		)
	end

	return Missions
end

