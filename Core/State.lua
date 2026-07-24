return function()
	local State = {}
	State.__index = State

	function State.new()
		return setmetatable({
			Values = {},
			Listeners = {},
		}, State)
	end

	function State:Get(key, default)
		local value = self.Values[key]

		if value == nil then
			return default
		end

		return value
	end

	function State:Set(key, value)
		local previous = self.Values[key]
		self.Values[key] = value

		if previous == value then
			return
		end

		for _, callback in ipairs(self.Listeners[key] or {}) do
			task.spawn(callback, value, previous)
		end
	end

	function State:Subscribe(key, callback)
		self.Listeners[key] = self.Listeners[key] or {}
		table.insert(self.Listeners[key], callback)

		local connected = true

		return function()
			if not connected then
				return
			end

			connected = false
			local listeners = self.Listeners[key]

			if not listeners then
				return
			end

			local index = table.find(listeners, callback)

			if index then
				table.remove(listeners, index)
			end
		end
	end

	return State
end
