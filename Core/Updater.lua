return function(ctx)
	local Updater = {}

	local Executor = ctx:Require("Executor")
	local HttpService = ctx.Services.HttpService
	local env = getgenv()

	local API_URL = "https://api.github.com/repos/loadstr0/world-zero-script/commits/main"

	local function requestBody(url)
		local separator = string.find(url, "?", 1, true) and "&" or "?"
		local requestUrl = url
			.. separator
			.. "cache="
			.. tostring(os.time())
			.. tostring(math.random(1000, 9999))

		if Executor.Request then
			local ok, response = pcall(Executor.Request, {
				Url = requestUrl,
				Method = "GET",
				Headers = {
					["Accept"] = "application/vnd.github+json",
					["Cache-Control"] = "no-cache",
					["User-Agent"] = "WorldZeroScript",
				},
			})

			if not ok then
				return nil, "request_failed:" .. tostring(response)
			end

			if type(response) == "table" then
				local status = tonumber(response.StatusCode or response.Status or 200)
				local body = response.Body or response.body

				if status and (status < 200 or status >= 300) then
					return nil, "github_http_" .. tostring(status)
				end

				if type(body) == "string" and body ~= "" then
					return body
				end
			elseif type(response) == "string" and response ~= "" then
				return response
			end

			return nil, "empty_github_response"
		end

		local ok, body = pcall(function()
			return game:HttpGet(requestUrl)
		end)

		if not ok then
			return nil, "http_get_failed:" .. tostring(body)
		end

		return body
	end

	function Updater.GetRemoteCommit()
		local body, requestError = requestBody(API_URL)

		if not body then
			return nil, requestError
		end

		local ok, data = pcall(function()
			return HttpService:JSONDecode(body)
		end)

		if not ok or type(data) ~= "table" or type(data.sha) ~= "string" then
			return nil, "invalid_github_response"
		end

		local message = nil

		if type(data.commit) == "table" then
			message = data.commit.message
		end

		return data.sha, nil, message
	end

	function Updater.ShortCommit(commit)
		if type(commit) ~= "string" then
			return "unknown"
		end

		return string.sub(commit, 1, 7)
	end

	function Updater.Initialize()
		local remoteCommit, remoteError, message = Updater.GetRemoteCommit()

		if not remoteCommit then
			return nil, remoteError
		end

		if type(env.WorldZeroLoadedCommit) ~= "string" then
			env.WorldZeroLoadedCommit = remoteCommit
		end

		return {
			LoadedCommit = env.WorldZeroLoadedCommit,
			RemoteCommit = remoteCommit,
			UpdateAvailable = env.WorldZeroLoadedCommit ~= remoteCommit,
			Message = message,
		}
	end

	function Updater.Check()
		return Updater.Initialize()
	end

	function Updater.Reload(targetCommit)
		if env.WorldZeroReloading == true then
			return false, "reload_already_running"
		end

		env.WorldZeroReloading = true

		task.defer(function()
			local previousCommit = env.WorldZeroLoadedCommit
			local remoteCommit = targetCommit

			if type(remoteCommit) ~= "string" then
				remoteCommit = Updater.GetRemoteCommit()
			end

			local separator = string.find(ctx.Base, "?", 1, true) and "&" or "?"
			local bootstrapUrl = ctx.Base .. "Bootstrap.lua" .. separator .. "cache=" .. tostring(os.time())
			local okSource, source = pcall(function()
				return game:HttpGet(bootstrapUrl)
			end)

			if not okSource then
				env.WorldZeroReloading = false
				warn("[WorldZeroUpdater] Bootstrap download failed:", source)
				return
			end

			local chunk, compileError = loadstring(source)

			if not chunk then
				env.WorldZeroReloading = false
				warn("[WorldZeroUpdater] Bootstrap compile failed:", compileError)
				return
			end

			if type(remoteCommit) == "string" then
				env.WorldZeroLoadedCommit = remoteCommit
			end

			local okRun, runError = pcall(chunk)

			if not okRun then
				env.WorldZeroLoadedCommit = previousCommit
				env.WorldZeroReloading = false
				warn("[WorldZeroUpdater] Reload failed:", runError)
				return
			end

			env.WorldZeroReloading = false
		end)

		return true
	end

	return Updater
end
