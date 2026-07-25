local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.State and runtime.ClassRegistry, "World Zero runtime is not fully initialized")

local engine = runtime.Context:Require("FarmingEngine")
local adapter = runtime.ClassRegistry.GetCurrentAdapter()
local target, descriptor = engine.GetTarget(runtime, math.huge, true)
local energy, energyError = runtime.Energy.GetState()
local canUse, canUseReason = adapter and adapter.CanUse("Ultimate")
local sharedEnergy = WZDB.require("ReplicatedStorage.Shared.Energy")
local character = runtime.Game.GetCharacter()
local directProperties = sharedEnergy and character
	and sharedEnergy:GetEnergyProperties(character)
	or nil

local result = {
	Class = runtime.ClassRegistry.GetCurrentClass(),
	UseUltimate = runtime.State:Get("Farming.UseUltimate", true),
	RotationMode = runtime.State:Get("Farming.RotationMode", "Full Rotation"),
	SelectedSlot = runtime.State:Get("Farming.AttackSlot", "Primary"),
	Energy = energy,
	EnergyError = energyError,
	EnergyFull = runtime.Energy.IsFull(),
	DirectEnergyPropertiesType = typeof(directProperties),
	DirectEnergy = directProperties
		and directProperties:FindFirstChild("Energy")
		and directProperties.Energy.Value
		or nil,
	DirectMaximum = directProperties
		and directProperties:FindFirstChild("MaxEnergy")
		and directProperties.MaxEnergy.Value
		or nil,
	Busy = runtime.Actions.IsBusy(),
	Sheathed = runtime.Actions.IsSheathed(),
	OnCooldown = runtime.Actions.IsOnCooldown("Ultimate"),
	RemainingCooldown = runtime.Actions.GetRemainingCooldown("Ultimate"),
	AdapterCanUse = canUse,
	AdapterReason = canUseReason,
	Target = descriptor and {
		Name = descriptor.NameTag,
		ModelName = descriptor.ModelName,
		IsBoss = descriptor.IsBoss,
		BossTag = descriptor.BossTag,
		Distance = descriptor.Distance,
		Health = descriptor.Health,
	} or nil,
	Skills = runtime.Skills.List(),
}

print("dualwielder_ultimate", result)
return result
