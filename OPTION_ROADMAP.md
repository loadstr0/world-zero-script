# Option Roadmap

## Available now

- Class-aware skill selector
- Manual primary and selected-skill activation
- Nearest-target aim
- Experimental nearest-target Auto Primary
- Sprint, mount, sheath, and quick-item controls
- Persistent Rayfield configuration
- GitHub update checks and optional live auto-reload

## High-power combat options

### Kill Aura

Planned controls:

- Enable toggle
- Aura range
- Target mode: nearest or all
- Attack mode: primary, selected skill, or rotation
- Attack interval
- Boss-only and mob-name filters

Required source:

1. `ReplicatedStorage.Shared.Combat.Skillsets.Swordmaster`
2. `ReplicatedStorage.Shared.Combat`
3. `ReplicatedStorage.Shared.Mobs`

The existing Auto Primary loop is not considered a finished kill aura because Swordmaster's `Attack` behavior has not been verified.

### Skill Aura / Rotation

Potentially available after class skillset inspection:

- Automatic Skill1/Skill2/Ultimate rotation
- Cooldown-aware priority
- Minimum target count per skill
- Boss burst mode

### Other possible high-power options

- Auto farm with target and world filters
- Auto mission selection/repeat
- Auto loot and chest collection
- Boss targeting and phase-aware attacks
- Mob vacuum only if the game exposes client-authoritative movement
- Cooldown modification only if server validation permits it

Options that are enforced by the server will be marked unavailable instead of presented as working.
