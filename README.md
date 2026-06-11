# Platform Sample Game Client (Godot)

Godot 4 port of the [Enjin Platform sample game client](https://github.com/enjin/platform-sample-game-client-unity)
(Unity's HappyHarvest farming demo + Enjin blockchain integration).
Talks to the same C# game server (`platform-sample-game-server`) over plain HTTP.

> **Status:** All roadmap phases complete. The full farming loop, day/night
> cycle, weather, audio, blockchain backpack, and smoke test are ported.

## Prerequisites

- Godot **4.4+** (standard build; no .NET / Mono required). Developed on 4.6.
- The C# game server from
  [`enjin/platform-sample-game-server`](https://github.com/enjin/platform-sample-game-server)
  running on `http://localhost:3000` (default). The game runs fine without it —
  blockchain features (login, token drops minting, backpack) simply no-op.

## Quick start

### 1. Start the game server

Follow the setup instructions in the game server repository. On first run it
creates a managed daemon wallet and a Collection on-chain, persisted to
`state.json` and exposed at `GET /api/setup/collection-id`.

### 2. Open the Godot project

```bash
godot4 --editor .
```

(Or "Import" the folder from Godot's Project Manager.)

### 3. Stamp the Collection ID onto the EnjinItem assets

The three item resources (`resources/items/gem_green.tres`, `gold_coin.tres`,
`gold_coin_blue.tres`) must carry your server's collection id before wallet
tokens match. With the server running:

1. **Project → Tools → Stamp Collection ID onto EnjinItem Assets**.
2. Confirm the server URL (default `http://localhost:3000`).
3. The plugin writes the id onto every `EnjinItem` `.tres` file.

### 4. Play the game

Run the project (F5). Flow: loader → main menu (optional register/login)
→ farm.

| Input | Action |
|-------|--------|
| WASD / arrows | Move |
| Mouse + left click | Use equipped item on the targeted cell / interact |
| Q / E or mouse wheel | Cycle equipped item |
| Click a HUD slot | Equip that slot |
| B (or HUD button) | Open the blockchain backpack |
| F5 / F9 | Save / load (`user://save.sav`) |
| Esc | (reserved) menu |

**The loop:** till soil with the hoe (tilling occasionally reveals a token —
click or walk over it to mint it to your wallet), water with the can, plant
seeds, wait for growth (crops only grow while watered), harvest with the
basket. Walk into the house door to go inside.

### 5. Verify the integration (optional)

- `scenes/debug_enjin.tscn` — button harness for every REST endpoint.
- `smoke/game_server/game_server_smoke.tscn` — scripted end-to-end REST flow
  (health → login → mint → melt → transfer, with wallet dumps). Copy
  `smoke_config.example.tres` → `smoke_config.tres` (gitignored) and fill in
  credentials, or use env vars. Headless/CI:

```bash
SMOKE_EMAIL=player@example.com SMOKE_PASSWORD=secret \
godot4 --headless --path . smoke/game_server/game_server_smoke.tscn -- --quit-after-smoke
echo $?   # 0 = all 9 steps passed
```

## Project layout

```
project.godot                 Project config, autoloads, InputMap
addons/enjin_editor/          Editor plugin (Stamp Collection ID tool)
art/, audio/, fonts/          Assets imported from the Unity project
scenes/
  loader.tscn                 Boot scene -> main menu
  main_menu.tscn              Logo, Start, register/login form
  farm_outdoor.tscn           Main gameplay scene
  house_interior.tscn         Interior scene
  maps/                       GENERATED tilemap scenes (see tools/)
  player/player.tscn          CharacterBody2D + animations + camera
  enjin/enjin_token.tscn      World token pickup (click/walk to mint)
  world/                      Rain + thunder weather elements
  ui/backpack_ui.tscn         Wallet token list with melt/transfer
  debug_enjin.tscn            Phase 1 endpoint harness
scripts/
  enjin/                      API service, EnjinManager, models, token UI
  game/                       GameManager, player, terrain, items, save,
                              day cycle, weather, sound
  ui/                         Main menu + HUD
resources/
  items|products|crops/       Item/crop .tres (generated from Unity data)
  tilesets/world_tileset.tres GENERATED TileSet
  player_frames.tres          GENERATED SpriteFrames (Unity rig bake)
  day_night/                  Day tint gradients
smoke/game_server/            Standalone REST smoke test scene
ui/game_hud.tscn              Inventory slots, coins, clock, backpack button
tools/unity_import/           One-off Unity -> Godot conversion pipeline
```

## Server contract reference

| Method | Path                          | Auth   | Purpose |
|--------|-------------------------------|--------|---------|
| GET    | `/api/auth/health-check`      | none   | Liveness ping |
| POST   | `/api/auth/register`          | none   | Register-or-login; returns `{ token, email, wallet }` |
| POST   | `/api/token/mint`             | bearer | `{tokenId, amount}` |
| POST   | `/api/token/melt`             | bearer | `{tokenId, amount}` |
| POST   | `/api/token/transfer`         | bearer | `{tokenId, amount, recipient}` |
| GET    | `/api/wallet/get-tokens`      | bearer | `{ account, tokenAccounts[] }` |
| GET    | `/api/setup/collection-id`    | none   | Used by the editor plugin |

Mint/melt/transfer wait for on-chain finalization server-side and can take
10–20+ seconds; the backpack status line says so while it refreshes.

## Asset pipeline (tools/unity_import)

The world was converted from the Unity project mechanically; the scripts are
kept so the conversion can be re-run if the Unity content changes:

1. `extract_unity_maps.py` — parses Unity scenes + sprite metas; copies
   art/audio; emits tilemap/prop/physics manifests under `out/`.
2. `dump_items.py` — dumps item/product/crop ScriptableObjects to JSON.
3. `build_tilemaps.gd` — builds `world_tileset.tres` (incl. collision from
   Unity physics shapes + soil custom data) and the `scenes/maps/*.tscn`.
4. `build_items.gd` — builds the item/crop `.tres` resources.
5. `build_sprite_frames.gd` — assembles `player_frames.tres` from frames baked
   in Unity (`Assets/Editor/BakeCharacterFrames.cs` in the Unity project).
6. `verify_*.gd` — headless test harnesses per subsystem (shell, player,
   items, farming, save, world, enjin UI). Run e.g.
   `godot4 --headless --path . -s tools/unity_import/verify_farming.gd`.

Run order: extractor → `--headless --import` → builders.

## Known divergences from the Unity client

- **Lighting:** Unity blends five additive URP Light2D gradients; here a
  single `CanvasModulate` samples one gradient. No rim lights or rotating
  building shadows (`LightInterpolator` not ported). Street/house lamps get
  procedural `PointLight2D`s with flicker at night.
- **Tilled/watered soil** uses the RuleTile's centre tile only (no edge
  matching) — tile visuals at bed borders are slightly simpler.
- **Tool hand visuals** (animated hoe/watercan prefabs in the player's hand)
  are not ported; the character's own use animations still play.
- **Animals, market and warehouse NPCs** are not ported (the Unity build also
  shipped market/warehouse UI disabled).
- Water tiles are static (Unity's animated water tile is baked to one frame).

## Exporting

`export_presets.cfg` ships macOS / Windows / Linux presets (GL Compatibility
renderer, safe everywhere). Install export templates once via
**Editor → Manage Export Templates**, then:

```bash
godot4 --headless --path . --export-release "Linux" build/linux/platform-sample-game.x86_64
```

`build/` and `export_credentials.cfg` are gitignored; the populated smoke
config is excluded from exports.

## Roadmap

- [x] **Phase 0** — Project bootstrap
- [x] **Phase 1** — Enjin integration core (models, API service, EnjinManager, debug harness)
- [x] **Phase 2** — Editor plugin (Stamp Collection ID)
- [x] **Phase 3** — Game shell (Loader, MainMenu, scene transitions)
- [x] **Phase 4** — Tilemaps, player, farming gameplay
- [x] **Phase 5** — Day/night cycle, weather, audio, effects
- [x] **Phase 6** — Backpack UI + till-time token reveal
- [x] **Phase 7** — GameServerSmoke standalone test scene
- [x] **Phase 8** — Export presets + README

> Note: the Unity sample reveals tokens on **tilling** (`Hoe.cs`), not on
> harvest; this port matches the source behavior.

See `../platform-sample-game-client-unity/README.md` for the original client.
