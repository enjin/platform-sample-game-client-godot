# Enjin Platform Sample Game (Godot)

A small top-down farming game that shows how **Enjin blockchain features fit
into a real game loop**. You log into a managed wallet, earn on-chain tokens by
playing, see them in an in-game backpack, and burn or send them to another
wallet — all driven by ordinary gameplay rather than a separate "wallet app".

It's built in Godot 4 and talks to the
[Enjin Platform sample game server](https://github.com/enjin/platform-sample-game-server)
over plain HTTP. The server owns a managed daemon wallet and submits the
on-chain transactions, so the game itself only makes simple REST calls.

## What it demonstrates

- **Managed-wallet login** — register/login with an email + password; the
  server returns a session token tied to a wallet the player never has to
  manage directly.
- **Minting from gameplay** — tilling soil occasionally turns up a collectible
  (a gold coin or a gem). Picking it up mints that token to your wallet
  on-chain, so a normal game action produces a real blockchain asset.
- **Reading the wallet** — the backpack lists the tokens your wallet actually
  holds, fetched live from the chain.
- **Melting & transferring** — burn a token, or send it to any other wallet
  address, straight from the backpack.
- **A collection of token types** — the game's collectibles (`gem_green`,
  `gold_coin`, `gold_coin_blue`) belong to one on-chain collection; you stamp
  your server's collection id onto them once so the wallet view lines up.

Everything blockchain-related is optional: with no server running, the game is
fully playable and the wallet features simply no-op.

## Prerequisites

- **Godot 4.4+** (standard build; no .NET / Mono required).
- The **Enjin Platform sample game server**
  ([`enjin/platform-sample-game-server`](https://github.com/enjin/platform-sample-game-server))
  running on `http://localhost:3000` (its default).

## Quick start

### 1. Start the game server

Follow the setup instructions in the server repository. On first run it creates
a managed daemon wallet and a Collection on-chain, persists them, and exposes
the collection id at `GET /api/setup/collection-id`.

### 2. Open the project in Godot

```bash
godot4 --editor .
```

(Or "Import" the folder from Godot's Project Manager.)

### 3. Stamp your collection id onto the token assets

The three collectible definitions (`resources/items/gem_green.tres`,
`gold_coin.tres`, `gold_coin_blue.tres`) need your server's collection id before
your wallet's tokens will match them in the backpack. With the server running:

1. **Project → Tools → Stamp Collection ID onto EnjinItem Assets**.
2. Confirm the server URL (default `http://localhost:3000`).
3. The tool writes the id onto each token `.tres`.

### 4. Play

Run the project (**F5**). The flow is: loader → main menu (register/login) →
farm.

| Input | Action |
|-------|--------|
| WASD / arrows | Move |
| Mouse + left click | Use the equipped item on the targeted tile / interact |
| Q / E or mouse wheel | Cycle the equipped item |
| Click a hotbar slot | Equip that slot |
| B (or the backpack icon, top-right) | Open the blockchain backpack |
| Click the market stall / warehouse | Open the market / warehouse panel |
| Menu button (top-right) | Settings (resolution, fullscreen, volume, login, quit) |
| Weather icons (under the clock) | Toggle sun / rain / thunder |
| F5 / F9 | Save / load (`user://save.sav`) |
| Esc | Close the open panel |

## The blockchain features, in play

1. **Log in.** Use the register/login form on the main menu (or the **Menu →
   Settings** panel in-game). The server registers-or-logs-in and hands back a
   session token; the game stores it and fetches your wallet.
2. **Earn a token.** Equip the hoe and till soil. Tilling has a chance to reveal
   a coin or gem in the world — click it (or walk over it) to pick it up, which
   mints that token to your managed wallet.
3. **Check your wallet.** Press **B** (or the backpack icon, top-right). The
   backpack reads your wallet's token balances from the chain and lists them.
4. **Melt or transfer.** From the backpack, burn a token (melt) or paste a
   recipient wallet address and send it (transfer).

On-chain mint/melt/transfer wait for finalization server-side and can take
**10–20+ seconds**; the backpack's status line tells you while it refreshes.

The rest of the loop is ordinary farming: water planted crops with the can
(crops only grow while watered), harvest with the basket, then **sell produce
and buy seeds at the market stall** or **stash/retrieve items at the
warehouse**. Walk into the house door to go inside.

## How the integration is wired (for developers)

If you're here to see how a game calls Enjin, these are the files to read:

| File | Role |
|------|------|
| `scripts/enjin/api/enjin_api_service.gd` | Thin REST client — one method per server endpoint |
| `scripts/enjin/core/enjin_manager.gd` | Session/auth state, wallet cache, mint/melt/transfer, the till-time token reveal |
| `scripts/enjin/data/` | Plain data models for wallet/token responses |
| `scenes/ui/backpack_ui.tscn` + `scripts/enjin/ui/` | The backpack: wallet token list with melt/transfer controls |
| `scenes/enjin/enjin_token.tscn` | The world pickup that triggers a mint |
| `resources/items/{gem_green,gold_coin,gold_coin_blue}.tres` | The token definitions (collection id stamped by the editor tool) |
| `addons/enjin_editor/` | The "Stamp Collection ID" editor tool |

### Server API the game uses

| Method | Path                        | Auth   | Purpose |
|--------|-----------------------------|--------|---------|
| GET    | `/api/auth/health-check`    | none   | Liveness ping |
| POST   | `/api/auth/register`        | none   | Register-or-login; returns `{ token, email, wallet }` |
| POST   | `/api/token/mint`           | bearer | `{ tokenId, amount }` |
| POST   | `/api/token/melt`           | bearer | `{ tokenId, amount }` |
| POST   | `/api/token/transfer`       | bearer | `{ tokenId, amount, recipient }` |
| GET    | `/api/wallet/get-tokens`    | bearer | `{ account, tokenAccounts[] }` |
| GET    | `/api/setup/collection-id`  | none   | Used by the editor tool |

## Verify the integration end-to-end

Two harnesses exercise the server without playing the game:

- `scenes/debug_enjin.tscn` — a button per REST endpoint.
- `smoke/game_server/game_server_smoke.tscn` — a scripted run through
  health → login → mint → melt → transfer with wallet dumps. Copy
  `smoke_config.example.tres` → `smoke_config.tres` (gitignored) and fill in
  credentials, or pass env vars. Headless / CI:

```bash
SMOKE_EMAIL=player@example.com SMOKE_PASSWORD=secret \
godot4 --headless --path . smoke/game_server/game_server_smoke.tscn -- --quit-after-smoke
echo $?   # 0 = all steps passed
```

## Exporting

`export_presets.cfg` ships macOS / Windows / Linux presets (GL Compatibility
renderer, safe everywhere). Install export templates once via **Editor → Manage
Export Templates**, then e.g.:

```bash
godot4 --headless --path . --export-release "Linux" build/linux/platform-sample-game.x86_64
```

`build/` and `export_credentials.cfg` are gitignored, and the populated smoke
config is excluded from exports.
