# Dedicated server image. Expects `game/scripts/export.sh server` to have produced build/server/.
# Designed to run with a read-only root filesystem: Godot's user:// data and logs go to /tmp.
FROM debian:trixie-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --uid 10010 --home /srv/game game
WORKDIR /srv/game
COPY build/server/ ./
USER game
ENV XDG_DATA_HOME=/tmp/xdg/data \
    XDG_CONFIG_HOME=/tmp/xdg/config \
    XDG_CACHE_HOME=/tmp/xdg/cache
EXPOSE 7777
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/7777"]
ENTRYPOINT ["./the-game-server.x86_64", "--headless", "--"]
# The ticket key is shared with the accounts API; the server refuses to start without it.
CMD ["--server", "--port=7777", "--ticket-key-file=/run/secrets/ticket/ticket-key"]
