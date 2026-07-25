# Option Roadmap

## Available now

- Class-aware skill selector
- Live equipped-class detection and automatic UI rebuilding
- Registry-driven class panels; unsupported classes show only verified generic controls
- Manual primary and selected-skill activation
- Nearest-target aim
- Experimental nearest-target Auto Primary
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate controls
- Server-validated radius scan and minimum-target gating
- Server-safe Swordmaster combat aura through normal skill execution
- Archer ranged aura with Skill1/Skill2/Skill3 rotation and charged Ultimate
- Assassin Shadow Cloak, Shadow Leap, Shadow Strike, and full-energy Ultimate rotation
- Berserker Rage burst mode with Aggro Slam, eight-hit Giga Spin, and Fissure
- Defender conditional party-heal automation with eight-hit Cyclone and Groundbreaker
- Demon Prince burst mode with chained Scythe Throw and health-guarded Dark Binding
- Dragoon live Dragon Chain completion with marked-target bonus and Dragon Dance
- Dual Wielder maximum-speed Tempo, 5% kill-healing, and multi-stage Ultimate
- Greatsword source-aware disabled panel for its current non-damaging prototype
- Guardian Aggro Defense maintenance and four-pulse Sword Prison crowd control
- Hunter auto-summon/Frenzy, close-range Venom Trap, and emergency Divine Arrow
- Icefire Mage Super Frost priority with field-aware range guards and Meteor Crash
- Leviathan preflighted bubble chain, recursive serpent bursts, and Sea Bubble healing
- Mage group-gated Arcane Wave and range-guarded Arcane Ascension
- Mage of Light projected-health Infuse guard with automated healing, Barrier, and Grace
- Mage of Shadows nine-orb merging, autonomous hunters, Shadow Chains, and form burst modes
- Necromancer maximum-charge Spirit Burst, Hexed Cavern, and ten-summon Undead Army
- Paladin emergency support, maintained enhanced Primary, and 15-pulse Ring of Justice
- Starbreaker charge-aware Supernova, double Flare, Starforge, and Fusion sequencing
- Stormcaller health-safe Supercharge, eight-target lightning, Surge, and Thunder God
- Summoner five-charge Soul banking, anti-waste Harvest, and Greater summon automation
- Warlord emergency Block, triple Piledriver, defense break, and Yggdrasil automation
- Filtered Auto Farm with nearest, boss, health, level, elite, and name targeting
- Map-wide targeting, sticky targets, no-damage timeout, and temporary stalled-target blacklisting
- Automatic equipped-class rotation through every available special, Primary, and Ultimate
- Boss-only Blade Dance targeting with corrected live energy-folder readiness
- Pathfinding, terrain-clamped ascent/cruise/descent flight, and instant CFrame movement with flight noclip cleanup
- Speed-aware ranged kiting and optional automation movement multiplier
- Barrier-aware Auto Dodge, post-hit follow-up Dodge, persistent airborne low-health recovery, and quick-item healing
- Exact status handling: skill-only Darkness pause; full Frozen/Shock/Knockdown/Stunned pause
- DoT/vulnerability safety thresholds, Poison heal suppression, and regeneration projection
- Optional capped compensation for non-zero status slows
- Explicit Death Mark warning instead of a fake cleanse
- Shared target provider for filtered class auras and exact Summoner proximity checks
- Sprint, mount, sheath, and quick-item controls
- Persistent Rayfield configuration
- GitHub update checks and optional live auto-reload
- Main-quest-first automation with exact mob objectives, unbounded loaded-map scans, cross-world travel, exact quest dungeons, stage-aware traversal/checkpoints, quest-location fallback, and claiming
- Teleport continuation through centralized `queue_on_teleport`
- Post-kill dropped-item/currency collection and proximity-open reward-chest routing without stealing live combat targets by default
- Smart best-potential weapon/offhand/armor upgrades and equipping
- Capacity-aware smart selling that compares maximum-potential stats within each weapon subtype or armor, keeps configurable backups, and preserves equipped/best/modified gear
- Real hubs and active event destinations from live `WorldData`
- Anti-idle and respawn-safe long-session recovery
- One-click non-destructive full-farm start/stop

## High-power combat options

### Kill Aura / Auto Farm

Available controls:

- Enable toggle
- Aura range
- Target modes: nearest, boss priority, lowest health, or highest level
- Full class rotation, Primary-only, or selected-slot attack modes
- Automatic full-energy Ultimate usage
- Attack interval
- Boss-only, elite-only, and comma-separated mob-name filters
- Pathfinding approach, sprinting, obstacle jumps, stopping distance, and stuck recovery
- Primary-range and live-Walkspeed-aware kiting
- Incoming/post-damage Dodge, barrier/debuff-aware airborne recovery thresholds, and projected-healing-aware quick items

Swordmaster behavior, server hitbox validation, and `Shared.Mobs` client targeting are verified. The direct `AttackTarget` remote is explicitly flagged as autofarming, and invalid damage identifiers are recorded as Kill Aura before a delayed kick. Those trap paths remain deliberately unexposed; farming uses normal class skill execution.

### Skill Aura / Rotation

Available now:

- Automatic rotation through every special slot exposed by the equipped class
- Cooldown-aware round-robin scheduling so unavailable skills do not block later skills
- Automatic charged Ultimate usage with a verified full-energy check
- Automatic Assassin Ultimate usage with a verified full-energy check
- Configurable Mage of Shadows skill saving and empowered-Primary Shadow Form modes
- Soul-aware Necromancer rotation with maximum-charge Burst and automatic Undead Army
- Party-health-aware Paladin healing with aggressive or emergency-only Ring modes
- Starbreaker full-meter preservation through Fusion for back-to-back Starforge uptime
- Stormcaller Thunder God sword priority with 25% long-range discharge opportunities
- Summoner five-Lesser army detonation while preserving the Greater Soul Being
- Warlord full three-hit Piledriver priority and near-continuous counter Block

Filtered targets now feed the existing class auras, enabling boss-only class rotations without duplicating combat logic.

### Other source-dependent high-power options

- Auto farm world filters
- Boss targeting and phase-aware attacks
- Mob vacuum only if the game exposes client-authoritative movement
- Cooldown modification only if server validation permits it

Options that are enforced by the server will be marked unavailable instead of presented as working.
