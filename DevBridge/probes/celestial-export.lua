local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

assert(type(decompile) == "function", "decompile_unavailable")
assert(type(writefile) == "function", "writefile_unavailable")
assert(type(makefolder) == "function", "makefolder_unavailable")

local outputRoot = "WorldZeroDevBridge/celestial-sources"
local roots = {
	ReplicatedStorage:FindFirstChild("MissionScripts")
		and ReplicatedStorage.MissionScripts:FindFirstChild("39"),
	ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Towers"),
}
local exported = {}

local function ensureFolder(path)
	local current = ""

	for segment in string.gmatch(path, "[^/]+") do
		current = current == "" and segment or (current .. "/" .. segment)
		pcall(makefolder, current)
	end
end

local function safeName(value)
	return string.gsub(tostring(value), '[<>:"/\\|%?%*%c]', "_")
end

local function export(instance)
	if
		not instance
		or not (
			instance:IsA("ModuleScript")
			or instance:IsA("LocalScript")
			or instance:IsA("Script")
		)
	then
		return
	end

	local ok, source = pcall(decompile, instance)
	local record = {
		Path = instance:GetFullName(),
		Class = instance.ClassName,
		Ok = ok and type(source) == "string" and source ~= "",
	}

	if record.Ok then
		local path = outputRoot .. "/"

		for segment in string.gmatch(instance:GetFullName(), "[^%.]+") do
			path = path .. safeName(segment) .. "/"
		end

		path = string.sub(path, 1, -2) .. ".lua"
		local parent = string.match(path, "^(.*)/[^/]+$")
		ensureFolder(parent)
		writefile(
			path,
			"-- Live Celestial Tower export\n-- "
				.. instance:GetFullName()
				.. "\n\n"
				.. source
		)
		record.File = path
	else
		record.Error = tostring(source)
	end

	table.insert(exported, record)
end

for _, root in ipairs(roots) do
	if root then
		export(root)

		for _, descendant in ipairs(root:GetDescendants()) do
			export(descendant)
		end
	end
end

ensureFolder(outputRoot)
writefile(outputRoot .. "/manifest.json", HttpService:JSONEncode(exported))
print("celestial_export", {
	Count = #exported,
	Output = outputRoot,
	Exports = exported,
})

return {
	Count = #exported,
	Output = outputRoot,
}
