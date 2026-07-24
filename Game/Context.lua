return function(ctx)
	local GameContext = {}

	local Players = ctx.Services.Players
	local ReplicatedStorage = ctx.Services.ReplicatedStorage

	function GameContext.GetLocalPlayer()
		return Players.LocalPlayer
	end

	function GameContext.GetCharacter()
		local player = GameContext.GetLocalPlayer()
		return player and player.Character or nil
	end

	function GameContext.GetHumanoid()
		local character = GameContext.GetCharacter()
		return character and character:FindFirstChildOfClass("Humanoid") or nil
	end

	function GameContext.GetRootPart()
		local character = GameContext.GetCharacter()
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	function GameContext.FindReplicated(path)
		local current = ReplicatedStorage

		for segment in string.gmatch(path or "", "[^%.]+") do
			current = current and current:FindFirstChild(segment)

			if not current then
				return nil
			end
		end

		return current
	end

	function GameContext.Describe()
		local player = GameContext.GetLocalPlayer()

		return {
			PlaceId = game.PlaceId,
			GameId = game.GameId,
			JobId = game.JobId,
			PlayerName = player and player.Name or "unknown",
			UserId = player and player.UserId or 0,
		}
	end

	return GameContext
end

