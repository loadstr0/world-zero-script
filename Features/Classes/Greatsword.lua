return function()
	local GreatswordFeature = {}

	function GreatswordFeature.Register(runtime, tab)
		runtime.UI:CreateSection(tab, "Greatsword source status")
		runtime.UI:CreateParagraph(
			tab,
			"Automation unavailable",
			"The supplied Greatsword module is a three-swing prototype. Its Hit keyframe only prints HIT; it never calls Shared.Combat, AttackWithSkill, or a damage remote. It also defines no class skills, sheath action, dodge, or Ultimate. Automatic attacks are intentionally disabled so the UI does not present a non-damaging loop as a working aura."
		)
	end

	return GreatswordFeature
end
