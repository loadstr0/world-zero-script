-- World Zero Script/Loader.lua
--
-- Thin bootstrapper. Every implementation file is loaded as a module factory:
--     return function(ctx) ... return module end
--
-- The order below is the dependency order. Feature code stays out of this file.

local HttpService = game:GetService("HttpService")
local env = getgenv()

local MODULES = {
	{ Key = "Logger", Path = "Core/Logger" },
	{ Key = "Executor", Path = "Core/Executor" },
	{ Key = "Updater", Path = "Core/Updater" },
	{ Key = "Config", Path = "Core/Config" },
	{ Key = "Janitor", Path = "Core/Janitor" },
	{ Key = "State", Path = "Core/State" },
	{ Key = "GameContext", Path = "Game/Context" },
	{ Key = "Profile", Path = "Game/Profile" },
	{ Key = "Actions", Path = "Game/Actions" },
	{ Key = "CombatAPI", Path = "Game/Combat" },
	{ Key = "Energy", Path = "Game/Energy" },
	{ Key = "Health", Path = "Game/Health" },
	{ Key = "Status", Path = "Game/Status" },
	{ Key = "Skills", Path = "Game/Skills" },
	{ Key = "Assassin", Path = "Game/Classes/Assassin" },
	{ Key = "AssassinFeature", Path = "Features/Classes/Assassin" },
	{ Key = "Archer", Path = "Game/Classes/Archer" },
	{ Key = "ArcherFeature", Path = "Features/Classes/Archer" },
	{ Key = "Berserker", Path = "Game/Classes/Berserker" },
	{ Key = "BerserkerFeature", Path = "Features/Classes/Berserker" },
	{ Key = "Defender", Path = "Game/Classes/Defender" },
	{ Key = "DefenderFeature", Path = "Features/Classes/Defender" },
	{ Key = "Demon", Path = "Game/Classes/Demon" },
	{ Key = "DemonFeature", Path = "Features/Classes/Demon" },
	{ Key = "Dragoon", Path = "Game/Classes/Dragoon" },
	{ Key = "DragoonFeature", Path = "Features/Classes/Dragoon" },
	{ Key = "DualWielder", Path = "Game/Classes/DualWielder" },
	{ Key = "DualWielderFeature", Path = "Features/Classes/DualWielder" },
	{ Key = "Greatsword", Path = "Game/Classes/Greatsword" },
	{ Key = "GreatswordFeature", Path = "Features/Classes/Greatsword" },
	{ Key = "Guardian", Path = "Game/Classes/Guardian" },
	{ Key = "GuardianFeature", Path = "Features/Classes/Guardian" },
	{ Key = "Hunter", Path = "Game/Classes/Hunter" },
	{ Key = "HunterFeature", Path = "Features/Classes/Hunter" },
	{ Key = "IcefireMage", Path = "Game/Classes/IcefireMage" },
	{ Key = "IcefireMageFeature", Path = "Features/Classes/IcefireMage" },
	{ Key = "Leviathan", Path = "Game/Classes/Leviathan" },
	{ Key = "LeviathanFeature", Path = "Features/Classes/Leviathan" },
	{ Key = "Mage", Path = "Game/Classes/Mage" },
	{ Key = "MageFeature", Path = "Features/Classes/Mage" },
	{ Key = "MageOfLight", Path = "Game/Classes/MageOfLight" },
	{ Key = "MageOfLightFeature", Path = "Features/Classes/MageOfLight" },
	{ Key = "MageOfShadows", Path = "Game/Classes/MageOfShadows" },
	{ Key = "MageOfShadowsFeature", Path = "Features/Classes/MageOfShadows" },
	{ Key = "Necromancer", Path = "Game/Classes/Necromancer" },
	{ Key = "NecromancerFeature", Path = "Features/Classes/Necromancer" },
	{ Key = "Paladin", Path = "Game/Classes/Paladin" },
	{ Key = "PaladinFeature", Path = "Features/Classes/Paladin" },
	{ Key = "Starbreaker", Path = "Game/Classes/Starbreaker" },
	{ Key = "StarbreakerFeature", Path = "Features/Classes/Starbreaker" },
	{ Key = "Swordmaster", Path = "Game/Classes/Swordmaster" },
	{ Key = "SwordmasterFeature", Path = "Features/Classes/Swordmaster" },
	{ Key = "ClassRegistry", Path = "Game/ClassRegistry" },
	{ Key = "Navigation", Path = "UI/Navigation" },
	{ Key = "RayfieldUI", Path = "UI/Rayfield" },
	{ Key = "Home", Path = "Features/Home" },
	{ Key = "Farming", Path = "Features/Farming" },
	{ Key = "Combat", Path = "Features/Combat" },
	{ Key = "Missions", Path = "Features/Missions" },
	{ Key = "Loot", Path = "Features/Loot" },
	{ Key = "Teleports", Path = "Features/Teleports" },
	{ Key = "Player", Path = "Features/Player" },
	{ Key = "Settings", Path = "Features/Settings" },
	{ Key = "Main", Path = "Main" },
}

local BASE = env.WorldZeroBase
local BRIDGE_FILE = env.WorldZeroBridgeFile or "world_zero_bridge.json"

if type(BASE) ~= "string" or BASE == "" then
	error("[WorldZeroLoader] Set getgenv().WorldZeroBase to the raw URL containing this project.", 0)
end

if string.sub(BASE, -1) ~= "/" then
	BASE = BASE .. "/"
end

local function stopPreviousRuntime()
	local previous = env.WorldZeroRuntime

	if type(previous) ~= "table" then
		return
	end

	if previous.Modules and previous.Modules.Main and type(previous.Modules.Main.Stop) == "function" then
		pcall(previous.Modules.Main.Stop)
	end

	env.WorldZeroRuntime = nil
end

local function getRequest()
	if typeof(request) == "function" then
		return request
	end

	if typeof(http_request) == "function" then
		return http_request
	end

	if syn and typeof(syn.request) == "function" then
		return syn.request
	end

	if http and typeof(http.request) == "function" then
		return http.request
	end

	return nil
end

local function addCacheBust(url)
	if env.WorldZeroCacheBust == false then
		return url
	end

	local separator = string.find(url, "?", 1, true) and "&" or "?"
	return url .. separator .. "cache=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
end

local function httpGet(url)
	local finalUrl = addCacheBust(url)
	local req = getRequest()

	if req then
		local ok, response = pcall(function()
			return req({
				Url = finalUrl,
				Method = "GET",
				Headers = {
					["Cache-Control"] = "no-cache",
					["Pragma"] = "no-cache",
				},
			})
		end)

		if not ok then
			error("[WorldZeroLoader] request() failed: " .. tostring(response), 2)
		end

		if type(response) == "table" then
			local status = tonumber(response.StatusCode or response.Status or 200)
			local body = response.Body or response.body

			if status and (status < 200 or status >= 300) then
				error("[WorldZeroLoader] HTTP " .. tostring(status) .. " for " .. url, 2)
			end

			if type(body) == "string" and body ~= "" then
				return body
			end
		elseif type(response) == "string" and response ~= "" then
			return response
		end

		error("[WorldZeroLoader] Empty response for " .. url, 2)
	end

	local ok, body = pcall(function()
		return game:HttpGet(finalUrl)
	end)

	if not ok then
		error("[WorldZeroLoader] game:HttpGet failed: " .. tostring(body), 2)
	end

	if type(body) ~= "string" or body == "" then
		error("[WorldZeroLoader] Empty response for " .. url, 2)
	end

	return body
end

local function loadBridge()
	if type(env.WorldZeroBridge) == "table" then
		return env.WorldZeroBridge
	end

	if typeof(readfile) ~= "function" then
		return {}
	end

	if typeof(isfile) == "function" and not isfile(BRIDGE_FILE) then
		return {}
	end

	local okRead, encoded = pcall(readfile, BRIDGE_FILE)

	if not okRead or type(encoded) ~= "string" or encoded == "" then
		warn("[WorldZeroLoader] Could not read bridge file:", encoded)
		return {}
	end

	local okDecode, bridge = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)

	if not okDecode or type(bridge) ~= "table" then
		warn("[WorldZeroLoader] Could not decode bridge file:", bridge)
		return {}
	end

	env.WorldZeroBridge = bridge
	return bridge
end

stopPreviousRuntime()

local ctx = {
	Base = BASE,
	Bridge = loadBridge(),
	Modules = {},
	Services = {
		Players = game:GetService("Players"),
		ReplicatedStorage = game:GetService("ReplicatedStorage"),
		RunService = game:GetService("RunService"),
		UserInputService = game:GetService("UserInputService"),
		HttpService = HttpService,
		TeleportService = game:GetService("TeleportService"),
	},
}

function ctx:Require(key)
	local module = self.Modules[key]

	if module == nil then
		error("[WorldZeroLoader] Module is not loaded: " .. tostring(key), 2)
	end

	return module
end

local function loadRemote(spec)
	local url = BASE .. spec.Path .. ".lua"
	local source = httpGet(url)
	local chunk, compileError = loadstring(source)

	if not chunk then
		error("[WorldZeroLoader] Failed to compile " .. spec.Key .. ": " .. tostring(compileError), 0)
	end

	local okRun, result = pcall(chunk)

	if not okRun then
		error("[WorldZeroLoader] Failed to run " .. spec.Key .. ": " .. tostring(result), 0)
	end

	if type(result) == "function" then
		local okFactory, module = pcall(result, ctx)

		if not okFactory then
			error("[WorldZeroLoader] Failed to initialize " .. spec.Key .. ": " .. tostring(module), 0)
		end

		result = module
	end

	if result == nil then
		error("[WorldZeroLoader] Module returned nil: " .. spec.Key, 0)
	end

	return result
end

for _, spec in ipairs(MODULES) do
	ctx.Modules[spec.Key] = loadRemote(spec)
end

env.WorldZeroRuntime = ctx

local okStart, startError = pcall(function()
	ctx.Modules.Main.Start(ctx)
end)

if not okStart then
	pcall(ctx.Modules.Main.Stop)
	env.WorldZeroRuntime = nil
	error("[WorldZeroLoader] Startup failed: " .. tostring(startError), 0)
end
