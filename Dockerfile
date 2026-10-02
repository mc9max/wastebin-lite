# syntax=docker/dockerfile:1
# =============================================================================
# Railway Template: Wastebin Lite  (v1)
# Upstream: https://github.com/matze/wastebin  (Rust/Axum, single static binary)
# Image:    quxfoo/wastebin:3.7.1  (scratch base, ships as non-root user 'app')
# =============================================================================
# Why this wrapper:
#   * quxfoo/wastebin ships as USER 'app' (uid 10001). Railway mounts its
#     persistent volumes ROOT-owned, so a non-root process cannot create or
#     write /data/state.db -> sqlite migration fails with EACCES -> crash loop.
#     We run as root so the SQLite DB writes to the root-owned volume cleanly.
#   * The scratch base has no shell, so Railway's EXTERNAL healthcheck
#     (healthcheckPath="/" in railway.toml) is the one that runs — we do not
#     add an in-container HEALTHCHECK (there is no wget/curl to call).
FROM quxfoo/wastebin:3.7.1

USER root

# Wastebin only reads WASTEBIN_ADDRESS_PORT (host:port). Railway's reverse
# proxy and external healthcheck both target the EXPOSEd port.
ENV WASTEBIN_ADDRESS_PORT="0.0.0.0:8088"
# Point the SQLite DB at the /data volume (railway.toml [[volumes]]).
# Without this it defaults to the container's writable layer and every
# restart wipes all pastes — this is the persistence-critical setting.
ENV WASTEBIN_DATABASE_PATH="/data/state.db"
# scratch base: sqlite migrations need a writable temp dir.
ENV TMPDIR="/tmp"

WORKDIR /app
EXPOSE 8088
CMD ["/app/wastebin"]
