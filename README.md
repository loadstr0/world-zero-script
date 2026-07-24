# World Zero Script

Modular Rayfield project modeled after the Eldorado Lua bridge and loader architecture.

## Entry points

- `Bootstrap.lua` is the single-file public execution entry point.
- `ExampleBridge.lua` supplies runtime settings and starts `Loader.lua`.
- `Loader.lua` fetches modules in dependency order, initializes each with a shared context, and calls `Main.Start(ctx)`.
- `world_zero_bridge.example.json` is the file-based alternative for executors with workspace file access.

## Module contract

Every implementation module returns a factory:

```lua
return function(ctx)
	local Module = {}
	return Module
end
```

Dependencies are obtained with `ctx:Require("ModuleName")`. Shared Roblox services are exposed through `ctx.Services`.

## Layout

```text
World Zero Script/
|-- Loader.lua
|-- ExampleBridge.lua
|-- Core/
|   |-- Config.lua
|   |-- Executor.lua
|   |-- Janitor.lua
|   |-- Logger.lua
|   `-- State.lua
|-- Game/
|   |-- Actions.lua
|   `-- Context.lua
|-- UI/
|   `-- Rayfield.lua
|-- Features/
|   |-- Combat.lua
|   |-- Farming.lua
|   |-- Loot.lua
|   |-- Missions.lua
|   |-- Player.lua
|   |-- Settings.lua
|   `-- Teleports.lua
`-- Main.lua
```

Feature modules currently register their Rayfield tabs but deliberately contain no guessed game calls. They will be filled in as requested World Zero source is supplied.

`Game/Actions.lua` is the guarded adapter for the live `ReplicatedStorage.Client.Actions` module. Feature modules should use this adapter instead of requiring the game module directly.

Executor-specific globals are centralized in `Core/Executor.lua`. Other modules should use its normalized capability fields rather than directly assuming `syn.*` or one executor's aliases exist.

## Current controls

The verified `Client.Actions` source supports these initial Rayfield controls:

- Target-range and aim-duration sliders
- One-shot nearest-target aim
- Optional aim before primary attacks
- Manual and automatic primary attacks
- Configurable attack-check interval
- Sprint toggle
- Mount and sheath buttons
- Quick-item name input and use button

Additional skill controls require `Shared.Skills` and the current class skillset source.

## Publish and execute

Publish this folder as the root of a public GitHub repository. Before committing, replace `YOUR_NAME/YOUR_REPO` in `Bootstrap.lua`.

Execute it with:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/Bootstrap.lua"))()
```

The repository must be public for this unauthenticated raw URL. Local research files and decompiled references are excluded by `.gitignore`.
