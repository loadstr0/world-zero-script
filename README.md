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
|-- Tools/
|   `-- SourceExporter.lua
|-- Core/
|   |-- Config.lua
|   |-- Executor.lua
|   |-- Janitor.lua
|   |-- Logger.lua
|   `-- State.lua
|-- Game/
|   |-- Actions.lua
|   |-- ClassRegistry.lua
|   |-- Combat.lua
|   |-- Chests.lua
|   |-- Context.lua
|   |-- Drops.lua
|   |-- Energy.lua
|   |-- Health.lua
|   |-- Inventory.lua
|   |-- Gear.lua
|   |-- Missions.lua
|   |-- Mobs.lua
|   |-- Navigator.lua
|   |-- Profile.lua
|   |-- Quests.lua
|   |-- Status.lua
|   |-- Skills.lua
|   |-- Teleport.lua
|   |-- Towers.lua
|   |-- Walkspeed.lua
|   `-- Classes/
|       |-- Assassin.lua
|       |-- Archer.lua
|       |-- Berserker.lua
|       |-- Defender.lua
|       |-- Demon.lua
|       |-- Dragoon.lua
|       |-- DualWielder.lua
|       |-- Greatsword.lua
|       |-- Guardian.lua
|       |-- Hunter.lua
|       |-- IcefireMage.lua
|       |-- Leviathan.lua
|       |-- Mage.lua
|       |-- MageOfLight.lua
|       |-- MageOfShadows.lua
|       |-- Necromancer.lua
|       |-- Paladin.lua
|       |-- Starbreaker.lua
|       |-- Stormcaller.lua
|       |-- Summoner.lua
|       |-- Swordmaster.lua
|       `-- Warlord.lua
|-- UI/
|   |-- Navigation.lua
|   `-- Rayfield.lua
|-- Features/
|   |-- Automation/
|   |   |-- FarmingEngine.lua
|   |   |-- GearEngine.lua
|   |   `-- InventoryEngine.lua
|   |-- Classes/
|   |   |-- Assassin.lua
|   |   |-- Archer.lua
|   |   |-- Berserker.lua
|   |   |-- Defender.lua
|   |   |-- Demon.lua
|   |   |-- Dragoon.lua
|   |   |-- DualWielder.lua
|   |   |-- Greatsword.lua
|   |   |-- Guardian.lua
|   |   |-- Hunter.lua
|   |   |-- IcefireMage.lua
|   |   |-- Leviathan.lua
|   |   |-- Mage.lua
|   |   |-- MageOfLight.lua
|   |   |-- MageOfShadows.lua
|   |   |-- Necromancer.lua
|   |   |-- Paladin.lua
|   |   |-- Starbreaker.lua
|   |   |-- Stormcaller.lua
|   |   |-- Summoner.lua
|   |   |-- Swordmaster.lua
|   |   `-- Warlord.lua
|   |-- Combat.lua
|   |-- Farming.lua
|   |-- Gear.lua
|   |-- Home.lua
|   |-- Loot.lua
|   |-- Missions.lua
|   |-- Player.lua
|   |-- Settings.lua
|   `-- Teleports.lua
`-- Main.lua
```

Feature modules register Rayfield controls only when the corresponding World Zero behavior has been verified from supplied source.

`Game/Actions.lua` is the guarded adapter for the live `ReplicatedStorage.Client.Actions` module. Feature modules should use this adapter instead of requiring the game module directly.

Executor-specific globals are centralized in `Core/Executor.lua`. Other modules should use its normalized capability fields rather than directly assuming `syn.*` or one executor's aliases exist.

`Core/Updater.lua` checks the public GitHub `main` commit and can reload the modular runtime when a new commit is detected.

## Current controls

The verified `Client.Actions` source supports these initial Rayfield controls:

- Filtered Auto Farm with boss, elite, name, health, level, and distance targeting
- Map-wide target discovery with sticky-target health progress, stalled-target skipping, and retry blacklisting
- Full equipped-class rotation across every available special attack, Primary, and charged Ultimate
- Dual Wielder boss-only Blade Dance policy with live `EnergyProperties` readiness
- Pathfinding, terrain-safe ascent/cruise/descent flight, or instant CFrame navigation with optional flight noclip and collision restoration
- Adaptive ranged kiting using live player/mob speed and equipped-class Primary range
- Barrier-aware Auto Dodge with post-damage follow-up Dodge and persistent airborne low-health recovery
- Exact catalog-driven responses for Darkness, freezes, Shock, Knockdown, Stunned, Poison, damage-over-time, vulnerability, healing, and Death Mark
- Freeze Tag teammate rescue using the verified 15-stud thaw condition
- Dynamic world, real hub, special destination, and currently active event travel from live `WorldData`
- Mission selection, matchmaking, stage-aware traversal/checkpoint routing, Celestial Tower arena/portal progression, failed-run auto-retry with late-loader recovery, free-reward claiming, and replay/return automation
- Main-quest-first automation with exact kill-mob targeting, map-wide fallback, cross-world travel, exact quest-dungeon launch, dungeon return, quest-area fallback routing, and reward claiming
- Central `queue_on_teleport` continuation for world, hub, event, dungeon, and mission-finish travel
- Coordinated dropped-item/currency collection with post-kill loot windows so collection does not steal movement from a living target by default
- Maximum-upgrade-potential gear scoring, protected upgrade/equip automation, and spending reserves
- Capacity-aware inventory supervision with separately armed, maximum-potential smart selling that retains the strongest gear per subtype and preserves locked, favorited, modified, equipped, and best-potential items
- Respawn waiting, anti-idle, movement ownership, and error-recovery loops for long sessions
- One-click safe farming start/stop across farming, main quests, loot, chests, and smart gear
- Projected regeneration-aware quick-item healing
- Optional automation-only WalkspeedManager multiplier with capped slow compensation
- Optional approach, stopping distance, attack range, and selected-slot mode
- Shared filtered targets for every class aura
- Exact live Summoner counts and proximity-based Lesser-army detonation
- Target-range and aim-duration sliders
- One-shot nearest-target aim
- Optional aim before primary attacks
- Manual primary attacks for every detected class
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Server-validated target scanning and minimum-target gating
- Server-safe Swordmaster aura through normal skill execution
- Archer ranged aura with configurable skills and automatic charged Ultimate
- Assassin shadow-critical aura with gap closing and automatic full-energy Ultimate
- Berserker Rage burst aura with upgraded fire skills and full-energy activation
- Defender eight-hit rotation with conditional party-healing Shield automation
- Demon Prince burst aura with health-guarded Dark Binding and Life Steal recovery
- Dragoon live Dragon Chain completion and 18-dragon full-energy burst
- Dual Wielder maximum-speed Tempo, kill-healing, and 29-event Ultimate rotation
- Guardian Aggro Defense, enemy draw, and four-pulse Sword Prison control
- Hunter Familiar management, Venom Trap control, and healing Divine Arrow
- Icefire Mage range-guarded elemental rotation and 11-event Meteor Crash
- Leviathan recursive bubble chains, Sea Bubble healing, and invincible burst
- Mage group-aware Arcane Wave and full-energy Arcane Ascension
- Mage of Light health-safe Infused Orbs, healing, Barrier, and Grace
- Mage of Shadows autonomous orb hunters, six-pulse Chains, and Shadow Form burst
- Necromancer soul-aware Spirit Burst, six-pulse Cavern, and ten-summon Undead Army
- Paladin health-aware blocking, party Retribution, maintained Light, and healing Ring
- Starbreaker automatic Supernova chains, double Flare, Starforge fields, and Fusion
- Stormcaller protected Supercharge, Chain Lightning, Storm Surge, and Thunder God
- Summoner Soul banking, Lesser-army detonation, Soul Harvest, and Super Summon
- Warlord triple Piledriver, counter Block, Chains of War, and Yggdrasil
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate buttons
- Configurable attack-check interval
- Sprint toggle
- Mount and sheath buttons
- Quick-item name input and use button

Skill names and slots are available from `Shared.Skills`. Swordmaster, Archer, Assassin, Berserker, Defender, Demon, Dragoon, Dual Wielder, Guardian, Hunter, Icefire Mage, Leviathan, Mage, Mage of Light, Mage of Shadows, Necromancer, Paladin, Starbreaker, Stormcaller, Summoner, and Warlord execution details are verified through their respective `Shared.Combat.Skillsets` modules. This completes the supplied production class coverage.

The supplied Greatsword module is also source-verified, but it is an unfinished non-damaging prototype: its only hit callback prints `HIT`, and it defines no class skills or Ultimate. The class-aware panel reports that limitation and deliberately does not expose fake automation.

The Combat tab reads the live `Shared.Skills` catalog and identifies the equipped class through the replicated `LocalPlayer.Class` attribute verified in `Shared.Profile`. `Game/ClassRegistry.lua` selects only the matching verified class panel. A class change automatically rebuilds the interface, while skill execution remains routed through `Client.Actions`.

## Rayfield navigation

The visible interface is intentionally smaller than the module tree:

- Home
- Automation
- Gear
- Quests & Missions
- Loot
- Combat
- Travel
- Player
- Settings

`UI/Navigation.lua` owns tab names, icons, and keys. Feature implementation remains split across separate modules even when multiple features share one visible tab.

## Publish and execute

This folder is configured for the public repository `loadstr0/world-zero-script`.

Execute it with:

```lua
loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/loadstr0/world-zero-script/main/Bootstrap.lua?cache="
		.. tostring(os.time())
))()
```

The runtime prints labeled `INITIALIZATION START` and `INITIALIZATION END` boundaries around all feature-registration output.

The repository must be public for this unauthenticated raw URL. Local research files and decompiled references are excluded by `.gitignore`.

## Source exporter

`Tools/SourceExporter.lua` exports the next research batch without pasting every decompiled module into chat. It writes a timestamped `WorldZeroSourceDump` folder inside the executor workspace, preserving the replicated hierarchy and adding a JSON manifest, remote inventory, and likely live-world objective/drop locations.

Execute it separately from the main interface:

```lua
loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/loadstr0/world-zero-script/main/Tools/SourceExporter.lua?cache="
		.. tostring(os.time())
))()
```

The output folder path is printed and copied to the clipboard when supported. Copy the whole timestamped folder into this project's ignored `References/` folder before sharing it with Codex. Both `References/` and a root-level `WorldZeroSourceDump/` are ignored so raw game sources cannot be committed accidentally.

The default batch covers the status handlers, settings, gear, remote resolver, missions, objectives, quests, teleports, chests, drops, inventory, and the related client interfaces. To add paths without editing the exporter, set `getgenv().WorldZeroSourceExporter.ModulePaths` or `.TreePaths` before executing it; tree paths recursively include every script below that instance.

## Developer bridge

`DevBridge/WorldZeroBridge.cmd` is a local command-line application for sending isolated diagnostic Luau jobs through Project Real's filesystem IPC. It captures prints, warnings, returned values, errors, tracebacks, and client metadata, then archives JSON results inside `DevBridge/results/`.

Built-in probes include runtime status, quest-dungeon routing, Celestial Tower floor/controller inspection, inventory-model inspection, and a read-only smart-selling preview. See `DevBridge/README.md` for commands and safety details.

## Configuration and updates

Rayfield automatically saves all flagged controls. The Settings tab reports the active configuration folder/file and can reload saved values.
The first complete release uses the `WorldZero/WorldZeroV1` save name so older partial-build files do not produce missing-control warnings.

Every fresh execution downloads the latest GitHub modules. The Settings tab also supports manual update checks, configurable polling, and optional automatic runtime reload when `main` changes.
