return function(ctx)
	local StarterPass = {}

	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players
	local cachedModule = nil
	local claiming = false

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript =
			GameContext.FindReplicated("Shared.Starterpass")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_starterpass_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_starterpass_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	local function call(methodName, ...)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		local method = module[methodName]

		if type(method) ~= "function" then
			return nil, "starterpass_missing_" .. string.lower(methodName)
		end

		local packed = table.pack(pcall(method, module, ...))

		if not packed[1] then
			return nil, "starterpass_call_failed_"
				.. string.lower(methodName)
				.. ":"
				.. tostring(packed[2])
		end

		return table.unpack(packed, 2, packed.n)
	end

	local function getState()
		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		local exp, expError = call("GetPlayerExp", player)

		if tonumber(exp) == nil then
			return nil, expError or "starterpass_exp_unavailable"
		end

		local freeRank, paidRank = call("GetItemRanks", player)
		local premium = call("HasPremiumTrack", player)
		local expPerRank = tonumber(module.EXP_PER_RANK) or 500
		local highestTier = type(module.GetHighestTier) == "function"
				and tonumber(call("GetHighestTier"))
			or nil

		return {
			Available = true,
			Active = type(module.IsActive) ~= "function"
				or call("IsActive", player) == true,
			Experience = tonumber(exp) or 0,
			ExperiencePerRank = expPerRank,
			EarnedRank = math.floor((tonumber(exp) or 0) / expPerRank),
			FreeTrack = tonumber(freeRank) or 0,
			PaidTrack = tonumber(paidRank) or 0,
			HasPremium = premium == true,
			HighestTier = highestTier,
			Module = module,
			Player = player,
		}
	end

	local function nextTier(state, paid)
		local module = state and state.Module
		local current = paid and state.PaidTrack or state.FreeTrack

		if not module or type(module.FindNextItemTier) ~= "function" then
			return nil
		end

		local ok, tier = pcall(
			module.FindNextItemTier,
			module,
			current,
			paid == true
		)

		tier = ok and tonumber(tier) or nil

		if
			not tier
			or tier <= current
			or tier > state.EarnedRank
			or (state.HighestTier and tier > state.HighestTier)
		then
			return nil
		end

		return tier
	end

	function StarterPass.GetState()
		return getState()
	end

	function StarterPass.ClaimAvailable(maximum)
		if claiming then
			return nil, "starterpass_claim_in_progress"
		end

		claiming = true
		local claims = {}
		local lastError = nil
		local limit = math.clamp(tonumber(maximum) or 50, 1, 100)

		for _ = 1, limit do
			local state, stateError = getState()

			if not state then
				lastError = stateError
				break
			elseif not state.Active then
				lastError = "starterpass_inactive"
				break
			end

			local paid = false
			local tier = nextTier(state, false)

			if not tier and state.HasPremium then
				paid = true
				tier = nextTier(state, true)
			end

			if not tier then
				break
			end

			local previousTrack = paid and state.PaidTrack or state.FreeTrack
			local _, redeemError = call(
				"RedeemItem",
				state.Player,
				tier,
				paid
			)

			if redeemError then
				lastError = redeemError
				break
			end

			task.wait(0.4)
			local refreshed, refreshError = getState()
			local refreshedTrack = refreshed
				and (paid and refreshed.PaidTrack or refreshed.FreeTrack)
				or previousTrack

			if refreshedTrack <= previousTrack then
				lastError = refreshError or "starterpass_claim_not_acknowledged"
				break
			end

			table.insert(claims, {
				Tier = tier,
				Track = paid and "Premium" or "Free",
			})
		end

		claiming = false

		if #claims == 0 then
			return nil, lastError or "no_starterpass_rewards_available"
		end

		return claims, lastError
	end

	function StarterPass.ObserveAvailable(callback)
		local signal, signalError = call("GetItemsAvailableSignal")

		if not signal or type(signal.Connect) ~= "function" then
			return nil, signalError or "starterpass_items_signal_unavailable"
		end

		return signal:Connect(callback)
	end

	function StarterPass.Describe()
		local state, stateError = getState()

		if not state then
			return {
				Available = false,
				Error = stateError,
			}
		end

		return {
			Available = true,
			Active = state.Active,
			EarnedRank = state.EarnedRank,
			FreeTrack = state.FreeTrack,
			PaidTrack = state.PaidTrack,
			HasPremium = state.HasPremium,
			HighestTier = state.HighestTier,
		}
	end

	return StarterPass
end
