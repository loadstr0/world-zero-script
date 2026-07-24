# Option Roadmap

## Available now

- Class-aware skill selector
- Manual primary and selected-skill activation
- Nearest-target aim
- Experimental nearest-target Auto Primary
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate controls
- Server-validated radius scan and minimum-target gating
- Server-safe Swordmaster combat aura through normal skill execution
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

1. `ReplicatedStorage.Shared.Mobs`

Swordmaster behavior and server hitbox validation are now verified. The direct `AttackTarget` remote is explicitly flagged as autofarming, and invalid damage identifiers are recorded as Kill Aura before a delayed kick. Those trap paths are deliberately not exposed. `Shared.Mobs` is still required for boss and mob-name filters.

### Skill Aura / Rotation

Available now:

- Automatic Skill1/Skill2 rotation
- Cooldown-aware priority

Still requires more source:

- Automatic Ultimate usage with a verified full-energy check
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
