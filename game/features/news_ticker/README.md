# News ticker

A two-sided flat screen hangs over the centre of the casino gaming floor (0, 3, 0)
and scrolls the latest top headlines from [TheNewsAPI](https://www.thenewsapi.com/)
under a red BREAKING NEWS banner.

- Only the dedicated server (`Network.Mode.SERVER`) fetches (`/v1/news/top`, every 15
  minutes, retry after 60 s on failure) and replicates `headlines` through `Sync`, so
  web clients avoid CORS and never see the token. Clients, offline play and the login
  screen never call the API; offline they show the welcome line.
- The server caches the last headlines and fetch time in `user://news_cache.json`, so a
  restart within 15 minutes reuses them instead of calling the API again.
- The token comes from the server's `THENEWSAPI_TOKEN` environment variable. It is
  deliberately not committed. Without it the screen shows a welcome line.
