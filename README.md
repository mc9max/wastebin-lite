# Wastebin Lite on Railway

A 20 MB single-binary pastebin, self-hosted on one small container. Wastebin is a fast Rust/Axum paste service with zero framework overhead and none of the Node.js weight — encrypted pastes, burn-after-reading, expirations, markdown rendering, QR codes, nine themes, and 170+ syntax-highlighted languages out of the box.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/new/template/wastebin-lite)

## Features

- **Tiny & fast** — single ~20 MB static binary (Rust/Axum), ~20 MB RAM at rest, no Node runtime
- **Persistent** — SQLite on a Railway volume (`/data`), pastes survive redeploys and restarts
- **Encrypted pastes** — ChaCha20-Poly1305 + argon2 password protection, for secrets and keys
- **Burn after reading** — paste self-deletes after a one-time confirmation reveal
- **Expirations** — no-expiry, 10 min, 1 h, 1 d, 1 M, 1 y (customizable per deploy)
- **1 MB max body by default** — raise it for long logs; 170+ languages syntax-highlighted
- **Markdown render** — `/md/{id}` with GitHub tables, task lists, and admonitions
- **Raw view** — `/raw/{id}` for pipes, `curl`, and scripts
- **QR code** — `/qr/{id}` shares a paste to a phone in one tap
- **9 themes** — ayu, base16ocean, catppuccin, coldark, gruvbox, monokai, onehalf, rosepine, solarized
- **Owner tokens** — every paste URL carries a signed delete token so you can kill your own pastes
- **Keyboard-first UI** — `r` raw · `n` index · `y` copy URL · `c` copy content · `q` QR · `w` wrap · `m` markdown toggle · `?` keybindings
- **API-first** — create and fetch pastes with pure `curl`, no browser needed

## Architecture

One service, one container, one volume:

| Piece | Value |
| :--- | :--- |
| Container | `quxfoo/wastebin:3.7.1` (scratch base) + root wrapper (this repo) |
| Port | 8088 (Railway reverse proxy + external healthcheck target `/`) |
| Volume | `/data` → SQLite `state.db`, survives restarts |
| Secrets | per-install `WASTEBIN_SIGNING_KEY` (≥ 64 bytes) + `WASTEBIN_PASSWORD_SALT` |

The wrapper runs as **root** because Railway mounts its persistent volumes root-owned; `quxfoo/wastebin` ships as a non-root user and would otherwise crash-loop with `EACCES` writing `state.db`. The scratch base has no shell, so the healthcheck is Railway's external probe of `/` — there is no in-container `HEALTHCHECK` to write. The Dockerfile also pins `WASTEBIN_DATABASE_PATH=/data/state.db`; without it Wastebin writes the DB to the container's writable layer and every redeploy silently wipes all pastes.

## Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `WASTEBIN_BASE_URL` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Public base URL for the paste links shown in the UI / API. |
| `WASTEBIN_TITLE` | `Wastebin Lite` | Site title in the browser tab. |
| `WASTEBIN_THEME` | `catppuccin` | Default theme (see the 9 themes above). |
| `WASTEBIN_MAX_BODY_SIZE` | `1048576` | Max paste size in bytes (1 MiB). Raise for long logs. |
| `WASTEBIN_PASTE_EXPIRATIONS` | `0,10m,1h,1d,1M,1y` | Expiry options in the UI (`0` = no expiry). |
| `WASTEBIN_SIGNING_KEY` | `${{secret(64)}}` | **Required, ≥ 64 bytes** — the server refuses to boot with a shorter key. Signs owner/delete tokens. Auto-generated per install; changing it invalidates previously-issued owner tokens. |
| `WASTEBIN_PASSWORD_SALT` | `${{secret(16)}}` | Argon2 salt for encrypted pastes. Auto-generated per install; changing it makes existing encrypted pastes unreadable. |

The two secrets are generated fresh for every new Railway deploy and are never stored in the repository.

## Getting Started

### 1. Deploy

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/new/template/wastebin-lite)

The template creates one service with a `/data` volume. On first deploy it sets `WASTEBIN_SIGNING_KEY` and `WASTEBIN_PASSWORD_SALT` to fresh random values and wires `WASTEBIN_BASE_URL` to your public domain — no manual configuration needed.

### 2. Paste from the browser

Open `https://your-domain`, type or paste content, choose an expiry and (optionally) an extension and password, hit Enter. The UI is keyboard-driven: `r` raw, `n` index, `y` copy URL, `c` copy content, `q` QR, `w` wrap, `m` markdown toggle, `?` all keybindings.

### 3. Paste from the API

```bash
# Plain paste (1 MiB max, .log extension, 1-day expiry)
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"CPU 90%\nI/O 3%\nUptime 42d","extension":"log","title":"beszel-alert","expires":86400,"burn_after_reading":false}' \
  https://your-domain/
# -> {"path":"/Ibv9Fa.log","owner":"<signed-token>"}

# Raw content
curl https://your-domain/raw/Ibv9Fa.log

# Encrypted paste (password-protected)
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"secret-key-material","password":"mypass"}' \
  https://your-domain/
# Read it back with the password header:
curl -H "wastebin-password: mypass" https://your-domain/raw/<id>

# Burn after reading
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"self-destructing","burn_after_reading":true}' https://your-domain/
# The normal URL redirects to /burn/<id> (a one-time confirm interstitial);
# confirming reveals the paste exactly once, then the paste is gone (404).
```

Pipe anything in:

```bash
journalctl -u systemd --since "1 hour ago" | curl -s --data-binary @- \
  -H "Content-Type: text/plain" https://your-domain/
```

## API Endpoints

| Method | Path | Description |
| :--- | :--- | :--- |
| `POST` | `/` | Create a paste. JSON `{text, extension?, title?, expires?, password?, burn_after_reading?, owner?}` or a raw request body. Returns `{path, owner}`. |
| `GET` | `/{id}` | HTML view. If the paste is burn-protected, redirects to `/burn/{id}`. |
| `GET` | `/raw/{id}` | Unprocessed paste body. |
| `GET` | `/md/{id}` | Rendered markdown (tables, task lists, admonitions). |
| `GET` | `/qr/{id}` | QR code for the paste URL. |
| `GET` | `/burn/{id}` | One-time confirmation page for burn pastes. `POST confirm_burn=1` reveals and burns. |
| `GET` | `/{id}?owner=<token>` | Owner handshake — sets the delete authorization cookie. |
| `DELETE` | `/{id}` | Delete the paste (requires the `/{id}?owner=<token>` cookie above). |
| `POST` | `/delete/{id}` | Form-based delete (browser flow). |
| `GET` | `/theme` | Switch theme (`?pref=dark|light|auto`). |

## Dependencies for Wastebin Lite

- **Railway Hobby or above** — 1 GB RAM is plenty (~20 MB used at rest).
- **`/data` volume** — the template attaches it automatically.
- **No external services** — no database, no cache, no queue. SQLite is embedded.

## Troubleshooting

- **Container crash-loops on a fresh install** — confirm `WASTEBIN_SIGNING_KEY` is ≥ 64 bytes (the server refuses to start on a shorter key); the template's `${{secret(64)}}` value satisfies this.
- **Pastes vanish after a redeploy** — `WASTEBIN_DATABASE_PATH` must point at the volume (`/data/state.db`, baked into the Dockerfile) and the `/data` volume must be attached to the service.
- **Encrypted pastes unreadable after a redeploy** — `WASTEBIN_PASSWORD_SALT` changed between deploys; regenerate the paste or pin a stable salt value.
- **Owner token 403 / paste not deleted** — the token contains base64 `+` and `/`; when passing it as a query parameter URL-encode it, and always perform the `GET /{id}?owner=<token>` handshake before the `DELETE`.
- **Paste too large** — bump `WASTEBIN_MAX_BODY_SIZE` (bytes) and redeploy.
- **Port / health** — the container listens on `0.0.0.0:8088` (baked in); the external healthcheck targets `/`.

## License

Upstream [Wastebin](https://github.com/matze/wastebin) is MIT-licensed. This template's Dockerfile and config are provided as-is.
