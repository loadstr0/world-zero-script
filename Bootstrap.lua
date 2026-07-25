-- Single-file public entry point.
-- Public entry point for loadstr0/world-zero-script.

local env = getgenv()
local defaultBase = "https://raw.githubusercontent.com/loadstr0/world-zero-script/main/"
local previousCommit = env.WorldZeroLoadedCommit
local previousPinnedBase = type(previousCommit) == "string"
		and previousCommit ~= ""
		and (
			"https://raw.githubusercontent.com/loadstr0/world-zero-script/"
			.. previousCommit
			.. "/"
		)
	or nil
local configuredBase = env.WorldZeroBase
local officialPinnedBase = type(configuredBase) == "string"
	and string.match(
		configuredBase,
		"^https://raw%.githubusercontent%.com/loadstr0/world%-zero%-script/[%da-fA-F]+/$"
	) ~= nil
local base = (
		env.WorldZeroPinLatestCommit ~= false
		and (configuredBase == previousPinnedBase or officialPinnedBase)
	)
		and defaultBase
	or (configuredBase or defaultBase)

if env.WorldZeroReloading ~= true then
	env.WorldZeroLoadedCommit = nil
end

local function resolveLatestCommit()
	if env.WorldZeroPinLatestCommit == false or base ~= defaultBase then
		return
	end

	local requestFunction = typeof(request) == "function" and request
		or typeof(http_request) == "function" and http_request
		or type(syn) == "table" and typeof(syn.request) == "function" and syn.request
		or nil
	local apiUrl = "https://api.github.com/repos/loadstr0/world-zero-script/commits/main?cache="
		.. tostring(os.time())
		.. tostring(math.random(1000, 9999))
	local ok, response = pcall(function()
		if requestFunction then
			return requestFunction({
				Url = apiUrl,
				Method = "GET",
				Headers = {
					["Accept"] = "application/vnd.github+json",
					["Cache-Control"] = "no-cache",
					["User-Agent"] = "WorldZeroScript",
				},
			})
		end

		return game:HttpGet(apiUrl)
	end)

	if not ok then
		return
	end

	local body = type(response) == "table" and (response.Body or response.body) or response

	if type(body) ~= "string" or body == "" then
		return
	end

	local decodedOk, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), body)
	local commit = decodedOk and type(data) == "table" and data.sha or nil

	if type(commit) == "string" and string.match(commit, "^[%da-fA-F]+$") then
		base = "https://raw.githubusercontent.com/loadstr0/world-zero-script/" .. commit .. "/"
		env.WorldZeroLoadedCommit = commit
	end
end

resolveLatestCommit()

if string.sub(base, -1) ~= "/" then
	base = base .. "/"
end

env.WorldZeroBase = base
env.WorldZeroBridge = env.WorldZeroBridge
	or {
		Window = {
			Name = "World Zero",
			LoadingTitle = "World Zero",
			LoadingSubtitle = "Modular Rayfield build",
			Theme = "Default",
			ToggleUIKeybind = "Z",
		},
		ConfigurationSaving = {
			Enabled = true,
			FolderName = "WorldZero",
			FileName = "WorldZeroV1",
		},
		Debug = true,
	}

local loaderUrl = base .. "Loader.lua"

if env.WorldZeroCacheBust ~= false then
	loaderUrl = loaderUrl .. "?cache=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
end

local source = game:HttpGet(loaderUrl)
local loader, compileError = loadstring(source)

if not loader then
	error("[WorldZeroBootstrap] Loader compilation failed: " .. tostring(compileError), 0)
end

loader()
