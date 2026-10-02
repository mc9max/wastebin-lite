# Wastebin Lite on Railway

A 20 MB single-binary pastebin, self-hosted on one small container. Wastebin is a fast Rust/Axum paste service with zero templates, zero framework overhead, and none of the Node.js weight — encrypted pastes, burn-after-reading, expirations, markdown rendering, QR codes, nine themes, and 170+ syntax-highlighted languages out of the box.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/wastebin-lite)

## Features

- **Tiny & fast** — single ~20 MB static binary (Rust/Axum), ~20 MB RAM at rest, no Node runtime
- **Persistent** — SQLite on a Railway volume (`/data`), pastes survive redeploys and restarts
- **Encrypted pastes** — ChaCha20-Poly1305 + argon2 password protection, for secrets and keys
- **Burn after reading** — paste self-deletes after the first view
- **Expirations** — no-expiry, 10 min, 1 h, 1 d, 1 M, 1 y (customizable per deploy)
- **1 MB max body by default** — raise it for long logs; 170+ languages syntax-highlighted
- **Markdown render** — `/md/{id}` with GitHub tables, task lists, and admonitions
- **Raw view** — `/raw/{id}` for pipes, `curl`, and scripts
- **QR code** — share a paste to a phone in one tap
- **9 themes** — ayu, base16ocean, catppuccin, coldark, gruvbox, monokai, onehalf, rosepine, solarized
- **Owner tokens** — every paste URL includes a deletion token so you can kill your own pastes
- **Keyboard-first UI** — `r` raw · `n` index · `y` copy URL · `c` copy content · `q` QR · `w` wrap · `m` markdown toggle · `?` keybindings
- **API-first** — create and fetch pastes with pure `curl`, no browser needed

## Architecture

One service, one container, one volume:

| Piece | Value |
| :--- | :--- |
| Container | `quxfoo/wastebin:3.7.1` (scratch base) + root wrapper (this repo) |
| Port | 8088 (Railway reverse proxy + external healthcheck target `/`) |
| Volume | `/data` → SQLite `state.db`, 1 GB, zstd-friendly, survives restarts |
| Signing key | per-install secret (owner/delete tokens) — must be ≥ 64 bytes |
| Paste salt | per-install secret (argon2 for encrypted pastes) |

The wrapper runs as **root** because Railway mounts its persistent volumes root-owned; `quxfoo/wastebin` ships as a non-root user and would crash-loop with `EACCES` writing `state.db`. The scratch base has no shell, so the healthcheck is Railway's external probe of `/` — no in-container `HEALTHCHECK` to write.

## Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `WASTEBIN_BASE_URL` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Public base URL for the paste links shown in the UI / API. |
| `WASTEBIN_TITLE` | `Wastebin Lite` | Site title in the browser tab. |
| `WASTEBIN_THEME` | `catppuccin` | Default theme (see the 9 themes above). |
| `WASTEBIN_MAX_BODY_SIZE` | `1048576` | Max paste size in bytes (1 MiB). Raise for long logs. |
| `WASTEBIN_PASTE_EXPIRATIONS` | `0,10m,1h,1d,1M,1y` | Expiry options in the UI (`0` = no expiry). |
| `WASTEBIN_SIGNING_KEY` | `${{secret(64)}}` | **Required, ≥ 64 bytes.** Signs owner/delete tokens. Auto-generated per install. |
| `WASTEBIN_PASSWORD_SALT` | `${{secret(16)}}` | Argon2 salt for encrypted pastes. Auto-generated per install. |

The two secrets are generated fresh for every new Railway deploy and never stored in the repository — change `WASTEBIN_SIGNING_KEY` on an existing install and previously-issued owner tokens stop working, change `WASTEBIN_PASSWORD_SALT` and encrypted pastes become unreadable.

## Getting Started

### 1. Deploy

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/wastebin-lite)

The template creates one service with a 1 GB `/data` volume. On first deploy it sets `WASTEBIN_SIGNING_KEY` and `WASTEBIN_PASSWORD_SALT` to fresh random values and wires `WASTEBIN_BASE_URL` to your public domain — no manual configuration needed.

### 2. Paste from the browser

Open `https://your-domain`, type or paste content, choose an expiry and (optionally) a content type, hit Enter. The UI is keyboard-driven: `r` raw, `n` index, `y` copy URL, `c` copy, `q` QR, `w` wrap, `m` markdown toggle, `?` all keybindings.

### 3. Paste from the API

```bash
# Plain paste (1-day expiry, .log extension so /md and /raw render it as text)
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"CPU 90%\nI/O 3%\nUptime 42d","extension":"log","title":"beszel-alert","expires":86400,"burn_after_reading":false}' \
  https://your-domain/
# -> {"path":"/Ibv9Fa.log","owner":"<delete-token>"}

# Raw content
curl https://your-domain/raw/Ibv9Fa.log

# Encrypted paste (password-protected)
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"secret-key-material","password":"mypass"}' \
  https://your-domain/
# Read it back with the password header:
curl -H "wastebin-password: mypass" https://your-domain/raw/<id>
```

### 4. Pipe anything in

```bash
journalctl -u systemd --since "1 hour ago" | curl -s --data-binary @- \
  -H "Content-Type: text/plain" https://your-domain/
```

## API Endpoints

| Method | Path | Description |
| :--- | :--- | :--- |
| `POST` | `/` | Create a paste. JSON `{text, title, extension, expires, password?, burn_after_reading?}` or raw body. |
| `GET` | `/{id}` | HTML view. Append the owner token to delete. |
| `GET` | `/raw/{id}` | Unprocessed paste body. |
| `GET` | `/md/{id}` | Rendered markdown (tables, task lists, admonitions). |
| `GET` | `/{id}.ext` | Paste served with a content-type based on extension. |
| `GET` | `/q/{id}` | QR code for the paste URL. |
| `DELETE` | `/{id}/owner/<token>` | Delete the paste with its owner token. |

## Dependencies for Wastebin Lite

- **Railway Hobby or above** — 1 GB RAM is plenty (~20 MB used at rest).
- **`/data` volume** — the template attaches a 1 GB volume automatically.
- **No external services** — no database, no cache, no queue. SQLite is embedded.

## Troubleshooting

- **Container crash-loops on a fresh install** — confirm `WASTEBIN_SIGNING_KEY` is ≥ 64 bytes (the server refuses to start on a shorter key); the template's `${{secret(64)}}` value satisfies this.
- **Encrypted pastes not readable after a redeploy** — `WASTEBIN_PASSWORD_SALT` changed between deploys. Regenerate the paste or set a fixed salt.
- **Owner tokens 403** — `WASTEBIN_SIGNING_KEY` changed after the tokens were issued. Old tokens are invalid by design.
- **Paste too large** — bump `WASTEBIN_MAX_BODY_SIZE` (bytes) and redeploy.
- **Port 8088 not serving** — `WASTEBIN_ADDRESS_PORT` must be `0.0.0.0:8088` (baked into the Dockerfile); the external healthcheck targets `/`.

## License

Upstream [Wastebin](https://github.com/matze/wastebin) is MIT-licensed. This template's Dockerfile and config are provided as-is.
