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
- `ReplicatedStorage.Shared.Combat.Skillsets.Stormcaller`
- `ReplicatedStorage.Shared.Combat.Skillsets.Summoner`
- `ReplicatedStorage.Shared.Combat.Skillsets.Warlord`
- `ReplicatedStorage.Shared.Combat.Skillsets.General`
- `ReplicatedStorage.Shared.Combat`
- `ReplicatedStorage.Shared.Profile`
- `ReplicatedStorage.Shared.Mobs`
- `ReplicatedStorage.Shared.Health`
- `ReplicatedStorage.Shared.Status`
- `ReplicatedStorage.Shared.Status.Statuses`
- `ReplicatedStorage.Shared.WalkspeedManager`

The supplied sources confirm that `UseSkill(slot)` resolves metadata through `Shared.Skills`, then dispatches to the current class module under `Shared.Combat.Skillsets`. Swordmaster, Archer, Assassin, Berserker, Defender, Demon, Dragoon, Dual Wielder, Guardian, Hunter, Icefire Mage, Leviathan, Mage, Mage of Light, Mage of Shadows, Necromancer, Paladin, Starbreaker, Stormcaller, Summoner, and Warlord have verified automation panels. Greatsword has a verified source-status panel, but its supplied module is an unfinished non-damaging prototype. `General` only supplies the shared Sprint slot. `Shared.Combat` reconstructs skill hitboxes and rate-limits skill identifiers on the server. `Shared.Profile` mirrors `Profile.Class.Value` to the player's `Class` attribute whenever the equipped class changes.

## Batch export received

`WorldZeroSourceDump/1784933652` exported 89 of 89 requested scripts with no failures. It includes every status handler plus settings, gear, missions, objectives, quests, teleports, chests, drops, inventory, item data, world events, and related client interfaces.

The batch confirms:

- Normal `Frozen` and `FrozenHeartbreak` only lock client movement and expose no break-free request.
- `FrozenFreezeTag` is removed server-side after a non-frozen player remains within 15 studs for one second.
- `Shared.Teleport` provides validated world, hub, mission, and matchmaking travel requests.
- `Shared.Missions` provides mission data, queue controls, one server-validated free reward, and replay/return party choices.
- Client drops are represented by pickup parts under `workspace.Coins` and redeem only after the character or pet reaches the verified pickup radius.
- Spawned mission/event chests use `Shared.Chests`; the game automatically requests opening once the character is within 10 studs.

## Next priority

Mission selection, matchmaking, automatic free-reward claiming, replay/return behavior, dynamic world travel, and Freeze Tag teammate rescue are now implemented.

The next source-backed options from this dump are:

- Auto pathfinding to dropped items and currency.
- Auto approach/open for spawned mission and world-event chests.
- Quest completion/reward claiming with objective navigation.
- Inventory cleanup and rule-based selling with locked/favorited item protection.

Do not invoke the admin command modules. They are useful as naming clues only and may be server-authorized.
