return function(ctx)
	local QuestRoutes = {}

	local Players = ctx.Services.Players
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local session = nil

	local function getRoot()
		local player = Players.LocalPlayer
		local character = player and player.Character
		return character
			and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
			or nil
	end

	local function isBlocked(root, targetPosition)
		local offset = targetPosition - root.Position

		if offset.Magnitude <= 8 then
			return false
		end

		local filter = { root.Parent }

		for _, containerName in ipairs({ "Mobs", "Characters", "Pets" }) do
			local container = Workspace:FindFirstChild(containerName)

			if container then
				table.insert(filter, container)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		params.IgnoreWater = true

		local result = Workspace:Raycast(root.Position, offset, params)
		return result ~= nil and (result.Position - targetPosition).Magnitude > 6
	end

	function QuestRoutes.GetCombatRoute(questState, descriptor)
		local root = getRoot()
		local targetPosition = descriptor and descriptor.Position

		if
			not questState
			or questState.ObjectiveType ~= "KillMob"
			or not root
			or typeof(targetPosition) ~= "Vector3"
		then
			return nil
		end

		local distance = (root.Position - targetPosition).Magnitude

		if distance <= 32 or not isBlocked(root, targetPosition) then
			return nil
		end

		local character = root.Parent

		if
			not session
			or session.QuestID ~= questState.ID
			or session.Character ~= character
		then
			session = {
				QuestID = questState.ID,
				Character = character,
				EnteredArea = false,
			}
		end

		local location = questState.Location
		local locationPosition = location and location.Position

		if typeof(locationPosition) == "Vector3" and not session.EnteredArea then
			local locationDistance = (root.Position - locationPosition).Magnitude

			if locationDistance > 25 then
				return {
					Kind = "QuestAreaEntrance",
					Name = questState.Reference or questState.Name,
					Position = locationPosition,
					StopDistance = 18,
					FlightGroundSafety = false,
					FlightCruiseHeight = 6,
					FlightNoclip = true,
				}
			end

			session.EnteredArea = true
		end

		return {
			Kind = "QuestInteriorApproach",
			Name = descriptor.Name or questState.Name,
			Position = targetPosition,
			StopDistance = 28,
			FlightGroundSafety = false,
			FlightCruiseHeight = 6,
			FlightNoclip = true,
		}
	end

	return QuestRoutes
end
