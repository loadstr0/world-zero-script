# Source Requests

## Received

- `ReplicatedStorage.Client.Actions`
- `ReplicatedStorage.Shared.Skills`
- `ReplicatedStorage.Shared.Combat.Skillsets.Swordmaster`
- `ReplicatedStorage.Shared.Combat`

The supplied sources confirm that `UseSkill(slot)` resolves metadata through `Shared.Skills`, then dispatches to the current class module under `Shared.Combat.Skillsets`. Swordmaster has a six-step primary combo, Crescent Strike, Leap Slash, Dodge, Sheath, and a charged 20-hit Ultimate. `Shared.Combat` reconstructs skill hitboxes and rate-limits skill identifiers on the server.

## Next priority

Please extract the full source for these modules next, in this order:

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
