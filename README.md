# Riftgate

A 2D platformer built in **Godot 4.6** featuring a full **Portal gun** mechanic — place linked blue and orange portals on surfaces and fling yourself through them with preserved momentum. *"Speedy thing goes in, speedy thing comes out."*


## Game Showcase

<iframe width="560" height="315" src="https://youtu.be/yJme9-4Xrk4" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

Game Showcase: https://youtu.be/yJme9-4Xrk4

---

## Activity Checklist

- [x] Week 2: Activity 1 - Gameplay Mechanics
- [x] Week 2: Activity 2 - Level Design
- [x] Week 3: Activity 1 - UI/UX & Audio
- [x] Week 3: Activity 2 - AI & Enemies
- [] Week 4: Activity 1 - 3D Basics & Optimization (No 3D)
- [x] Week 4: Activity 2 - Multiplayer (Basic Cloud Server)

---

## Gameplay Controls

- **Move:** `A` / `D`
- **Jump:** `W` / `Space`
- **Sprint:** `Shift` (ground only)
- **Blue Portal:** `Left Click`
- **Orange Portal:** `Right Click`
- **Reset Portals:** `R`
- **Remove Debug Menu:** `\``

The player can place two linked portals on any valid wall/floor/ceiling surface. Entering one teleports you out the other, preserving your speed and redirecting it along the exit portal's normal. Air friction is intentionally reduced after a portal fling so momentum carries properly.

---

## Core Systems

### Portal Mechanic

- **PortalEntity** — base class for any body that can travel through portals. Implements custom `move_and_collide` loop that detects portal surfaces and defers to the portal's teleport logic. Tracks a `launched_by_portal` flag to reduce air friction for 1.5 seconds after a fling.
- **Portal Gun** — raycasts from the player to the mouse cursor. On click, places a blue or orange portal on the hit surface (Walls layer). Both portals are automatically linked when both exist.
- **Portal** — when a `PortalEntity` overlaps, it teleports it to the linked portal. Exit velocity equals entry speed directed along the exit portal's outward normal. A brief cooldown prevents instant re-teleportation.

### Player Controller

Extends `PortalEntity` with full platformer movement:
- Ground acceleration, air acceleration, and a weaker "fling" air acceleration for portal launches
- Coyote time (0.12s) and jump buffering (0.1s) for responsive input
- Sprint multiplier on ground
- Health system with damage, knockback, death, and respawn
- AnimationTree-driven state machine (Idle, Walk, Sprint, Jump, Land, Knockback, Die)
- Invincibility frames with sprite blinking

### Enemies

- **NightBorne** — melee-only patrol AI with idle/roam/chase/attack states. Uses line-of-sight raycasts for player detection, edge and wall raycasts to stay on platforms, and a deaggro leash area. Only damaged by turret bullets.
- **Striker** — melee + ranged patrol AI with an additional dash state. The Strike animation has melee hitbox frames and a bullet-spawn frame. Only damaged by turret bullets.

### Hazards

- **Saw** — moves between two points (or stays stationary). Damages on contact with knockback.
- **Laser** — continuous damage ticks while the player overlaps.
- **Spike / SpikeGroup** — timed spike traps that cycle between hidden and active. Groups can activate in sync or staggered waves.
- **Turret** — auto-fires bullets on a timed animation loop. Turret bullets extend `PortalEntity` and can travel through portals, allowing the player to redirect them into enemies.

### Bullets Through Portals

Both turret and striker bullets extend `PortalEntity`, so they can be teleported through portals just like the player. After exiting a portal, their velocity is redirected along the exit normal — this allows the player to strategically place portals to redirect turret fire into enemies.

---

## Physics Layers

| Layer | Name    | Purpose                                          |
|-------|---------|--------------------------------------------------|
| 1     | Player  | Player character body                            |
| 2     | Walls   | Static environment collision (portal-placeable)  |
| 3     | Portals | Portal area detection                            |
| 4     | Hazards | Damage-dealing areas (saws, spikes, lasers, etc.)|
| 5     | Enemies | Enemy bodies                                     |

---

## Project Structure

```
go-dot-exercise-1/
├── Main.tscn
├── main.gd
├── character/
│   ├── CharacterModel.tscn
│   └── CharacterScript.gd
├── levels/
│   ├── Level1.tscn
│   └── Level2.tscn
├── enemies/
│   ├── enemy_entity.gd
│   ├── night_borne_enemy.gd
│   ├── striker_enemy.gd
│   ├── NightBorneEnemy.tscn
│   └── StrikerEnemy.tscn
├── hazards/
│   ├── laser.gd
│   ├── saw.gd
│   ├── spike.gd
│   ├── spike_group.gd
│   ├── turret.gd
│   └── Turret.tscn
├── portal/
│   ├── portal_entity.gd
│   ├── portal_gun.gd
│   ├── portal.gd
│   ├── PortalBlue.tscn
│   ├── PortalOrange.tscn
│   └── PortalGun.tscn
├── multiplayer-nakama/
│   ├── Client.tscn
│   ├── client.gd
│   ├── docker-compose.yml
│   ├── addons/
│   └── sync/
│       ├── player_sync.gd
│       ├── enemy_sync.gd
│       └── portal_sync.gd
├── huds/
│   └── HealthHUD.tscn
├── debugs/
│   └── debug_hud.gd
├── asssets/
│   ├── character/
│   ├── enemies/
│   ├── guns/
│   ├── portals/
│   ├── sounds/
│   └── tilesets/
├── bgms/
└── addons/
```

---

## Requirements

- Godot 4.6
- Docker (for local Nakama server)

---

## Running

1. Open the project in Godot 4.6
2. Press F5 or click Play
