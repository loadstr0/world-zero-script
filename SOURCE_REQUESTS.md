# Source Requests

## Received

- `ReplicatedStorage.Client.Actions`
- `ReplicatedStorage.Shared.Skills`
- `ReplicatedStorage.Shared.Combat.Skillsets.Swordmaster`
- `ReplicatedStorage.Shared.Combat.Skillsets.Archer`
- `ReplicatedStorage.Shared.Combat.Skillsets.Assassin`
- `ReplicatedStorage.Shared.Combat.Skillsets.Berserker`
- `ReplicatedStorage.Shared.Combat.Skillsets.Defender`
- `ReplicatedStorage.Shared.Combat.Skillsets.Demon`
- `ReplicatedStorage.Shared.Combat.Skillsets.Dragoon`
- `ReplicatedStorage.Shared.Combat.Skillsets.DualWielder`
- `ReplicatedStorage.Shared.Combat.Skillsets.Greatsword`
- `ReplicatedStorage.Shared.Combat.Skillsets.Guardian`
- `ReplicatedStorage.Shared.Combat.Skillsets.Hunter`
- `ReplicatedStorage.Shared.Combat.Skillsets.IcefireMage`
- `ReplicatedStorage.Shared.Combat.Skillsets.Leviathan`
- `ReplicatedStorage.Shared.Combat.Skillsets.Mage`
- `ReplicatedStorage.Shared.Combat.Skillsets.MageOfLight`
- `ReplicatedStorage.Shared.Combat.Skillsets.MageOfShadows`
- `ReplicatedStorage.Shared.Combat.Skillsets.Necromancer`
- `ReplicatedStorage.Shared.Combat.Skillsets.Paladin`
- `ReplicatedStorage.Shared.Combat.Skillsets.Starbreaker`
- `ReplicatedStorage.Shared.Combat.Skillsets.General`
- `ReplicatedStorage.Shared.Combat`
- `ReplicatedStorage.Shared.Profile`

The supplied sources confirm that `UseSkill(slot)` resolves metadata through `Shared.Skills`, then dispatches to the current class module under `Shared.Combat.Skillsets`. Swordmaster, Archer, Assassin, Berserker, Defender, Demon, Dragoon, Dual Wielder, Guardian, Hunter, Icefire Mage, Leviathan, Mage, Mage of Light, Mage of Shadows, Necromancer, Paladin, and Starbreaker have verified automation panels. Greatsword has a verified source-status panel, but its supplied module is an unfinished non-damaging prototype. `General` only supplies the shared Sprint slot. `Shared.Combat` reconstructs skill hitboxes and rate-limits skill identifiers on the server. `Shared.Profile` mirrors `Profile.Class.Value` to the player's `Class` attribute whenever the equipped class changes.

## Next priority

For class-aware UI coverage, send the currently equipped class first, followed by the remaining skillsets:

- `Stormcaller`, `Summoner`, `Warlord`

Each path is `ReplicatedStorage.Shared.Combat.Skillsets.<ClassName>`.

For mob filtering and automation, the next non-class sources are:

1. `ReplicatedStorage.Shared.Mobs`
2. `ReplicatedStorage.Shared.Gamebeast.Infra.Shared.Modules.GetRemote`
3. `ReplicatedStorage.Shared.Drops`
4. `ReplicatedStorage.Shared.Missions`
5. `ReplicatedStorage.Shared.Missions.MissionData`
6. `ReplicatedStorage.Shared.Teleport`
7. `ReplicatedStorage.Shared.Teleport.WorldData`

After those, the next useful client modules are:

- `ReplicatedStorage.Client.Gui.GuiScripts.MissionObjective`
- `ReplicatedStorage.Client.Gui.GuiScripts.MissionQueue`
- `ReplicatedStorage.Client.Gui.GuiScripts.MissionSelect`
- `ReplicatedStorage.Client.Gui.GuiScripts.QuestTracker`
- `ReplicatedStorage.Client.Gui.GuiScripts.HubTeleport`
- `ReplicatedStorage.Client.Gui.GuiScripts.WorldTeleport`
- `ReplicatedStorage.Client.Gui.GuiScripts.LootReceived`

If your extractor also supports instance-tree scans, capture the names and classes of:

- Direct children of `ReplicatedStorage` that are RemoteEvents or RemoteFunctions
- The live workspace folders containing mobs/enemies
- The live workspace folders containing drops, chests, and mission objectives

Do not invoke the admin command modules. They are useful as naming clues only and may be server-authorized.
