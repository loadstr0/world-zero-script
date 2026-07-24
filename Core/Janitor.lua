return function()
	local Janitor = {}
	Janitor.__index = Janitor

	function Janitor.new()
		return setmetatable({
			Items = {},
			Cleaned = false,
		}, Janitor)
	end

	function Janitor:Add(item, cleanupMethod)
		if self.Cleaned then
			return item
		end

		table.insert(self.Items, {
			Item = item,
			Method = cleanupMethod,
		})

		return item
	end

	function Janitor:Cleanup()
		if self.Cleaned then
			return
		end

		self.Cleaned = true

		for index = #self.Items, 1, -1 do
			local entry = self.Items[index]
			local item = entry.Item
			local method = entry.Method

			pcall(function()
				if type(item) == "function" then
					item()
				elseif type(method) == "function" then
					method(item)
				elseif type(method) == "string" and item and type(item[method]) == "function" then
					item[method](item)
				elseif typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				elseif item and type(item.Destroy) == "function" then
					item:Destroy()
				end
			end)
		end

		table.clear(self.Items)
	end

	return Janitor
end

