# Fer & Fioles — Kingdom Warfare

An original Roblox kingdom battlefield with sword-only combat, stamina, delayed health regeneration, trees, mines, capturable flags and buildable outposts. No parry, block or kick actions.

The Medieval Warfare Reforged videos and the [wiki supplied by the user](https://official-medieval-warfare-reforged.fandom.com/wiki/Official_Medieval_Warfare_Reforged_Wikia) are currently blocked by this environment's network allowlist (HTTP 403). The mechanics below implement the requested systems; kingdom names, visuals and numerical settings are project defaults, **not verified reproductions of that game**. [Current schematics and tuning](docs/KINGDOM_WORLD.md) record the exact implementation and pending calibration.

## Open and play

1. Download [the ZIP](releases/FerEtFioles.zip?raw=1) or [the standalone place](releases/FerEtFioles.rbxlx?raw=1).
2. In Roblox Studio, use **File > Open from File** to open `FerEtFioles/build/FerEtFioles.rbxlx` from the ZIP, or the standalone place.
3. Press **Play** and choose a kingdom. Solo play supports gathering and capturing; use **Test > Server & Clients** with two or more players for enemy combat and contested flags.

All scripts and original primitive scenery are included. No paid models, external animation assets or live wiki requests are required.

## World loop

- Choose Redcliff, Korblox, Greywolf or Overseer and spawn at its keep. These four identities are retained project choices, pending reference verification.
- Strike enemies with alternating horizontal sword swings. The server checks stamina, cooldown, range, arc, line of sight, team and protection. Allies take no sword damage.
- Use **E** or **Harvest** beside a tree or ore node. Hits spend stamina; the final accepted strike awards wood or ore. Depleted nodes disappear and return on their timers.
- Stand at Westwatch, Eastwatch or Southwatch to capture its flag. Different kingdoms in the zone contest it and freeze progress. More allies do not accelerate capture.
- Spend **30 wood + 15 ore** to fortify a nearby owned, uncontested flag. Select an owned built outpost in the menu to respawn there. Lost or unbuilt outposts fall back to the kingdom base.
- Death returns you after **5 seconds**, with fresh health, stamina and potions. Inventory survives death. There are no automatic duel rounds in the default world mode.

The map has four keeps, a forest, quarry, three flag sites, **16 trees and 12 ore nodes**, built from 394 static primitives. The protected kingdom-selection area is isolated from the battlefield.

## Controls

| Input | Action |
| --- | --- |
| Standard Roblox controls | Move, look and jump |
| Left click / touch sword | One sword attack |
| Hold Shift / touch sprint | Sprint |
| Ctrl / camera button | Toggle shoulder camera lock |
| E / Harvest button | Chop a nearby tree or mine ore |
| M / Kingdoms button | Choose a kingdom, build and select outpost respawn |
| Z / X / C | Small / medium / large potion |
| Hold Tab | Player scoreboard |

Menus, text entry and spectating suspend combat input or camera lock as appropriate. Mobile has explicit interaction and combat buttons.

## Current tuning

All values live in [src/shared/Config.luau](src/shared/Config.luau), shared by the authoritative server and interface.

| Mechanic | Project default |
| --- | --- |
| Health / stamina | 100 / 100 |
| Sword damage / cost / cooldown | 25 HP / 10 stamina / 0.45 s |
| Sprint drain / stamina recovery | 1 per moving second / 5 per second after 1.5 s without spending |
| Health regeneration | 2 HP/s after 8 s without damage, attacks or gathering |
| Potions | +20 / +45 / +75 HP; stock 3 / 2 / 1 per life; shared 60 s cooldown |
| Gathering | 10 stamina; one strike per second |
| Trees | Four hits; eight wood on depletion; regrow after 45 s |
| Mines | Five hits; five ore on depletion; return after 60 s |
| Flags | 18-stud radius; 15 s uncontested capture |
| Kingdom switching | 60 s cooldown; 8 s out of combat; alive character required |

Wood, ore, kingdom membership, kills/deaths and all world ownership are **server-session state**. Rejoining resets player world inventory; a new server resets the world. The existing cosmetic/coin profile system remains separate; no world persistence or global kingdom economy is implied.

## Development and validation

```sh
make setup       # Checksum-verified Rojo 7.7.1 + Luau 0.742 (Linux x86-64)
make check       # Compile sources and execute rules + service lifecycle tests
make map         # Export and validate both original maps
make build       # Build build/FerEtFioles.rbxlx
make studio-test # Build the separate engine smoke-test place
make package     # Refresh places, source ZIP and releases/
make serve       # Start Rojo source synchronization
```

CLI checks cover combat, recovery, kingdom selection, shared resources, contested captures, construction, respawn races, profiles and the retained duel mode. Service tests execute real modules with explicit clock/character/network doubles; they do not simulate Roblox physics or networking. Map export validates supported, clear spawns, reachable resources and clear roads. Roblox Studio remains necessary to validate animations, mobile layout, real multiplayer and engine behavior; see the checklist in [the schematics](docs/KINGDOM_WORLD.md).

Set `Config.Game.Mode = "Lobby"` to use the retained invitation-based 1v1/2v2 mode instead. Its documentation is [LOBBY_CONTRACT.md](docs/LOBBY_CONTRACT.md). Each mode constructs only its own lifecycle service.
