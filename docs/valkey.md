# Valkey

Valkey runs as the `valkey` service in `docker-compose.yml`, and its port 6379 is published to the host.

| DB | Used for          | `env.php` section                |
|----|-------------------|----------------------------------|
| 0  | Default cache     | `cache.frontend.default`         |
| 1  | Full page cache   | `cache.frontend.page_cache`      |
| 2  | Sessions          | `session`                        |

The cache stores data compressed and serialized with igbinary, so the PHP image needs the `igbinary` extension (see `docker/php/Dockerfile`).

## Magento 2.4.9 problems

- `setup:config:set --session-save=valkey ...` writes a config that doesn't work. There is no `valkey` session handler at runtime (`app/etc/di.xml` only registers `db` and `redis`), so Magento quietly falls back to files. Sessions must use `'save' => 'redis'` with a `'redis'` block pointing at host `valkey`.
- `--session-save-valkey-host` is ignored, and the CLI writes `127.0.0.1`. The host must be `valkey`.
- If you re-run `setup:config:set` with session options, check the `session` section of `env.php` afterwards.
- The cache backend is different: `'backend' => 'valkey'` really works.

## Inspecting with `valkey-cli`

```bash
docker compose exec valkey valkey-cli
```

```bash
# Is it alive? How many keys per DB?
docker compose exec valkey valkey-cli ping
docker compose exec valkey valkey-cli info keyspace

# Browse keys (use --scan, never KEYS * on a big DB)
docker compose exec valkey valkey-cli -n 0 --scan --pattern '69d_*' | head
docker compose exec valkey valkey-cli -n 2 --scan --pattern 'sess_*'

# Look at one entry (Magento cache and session entries are hashes)
docker compose exec valkey valkey-cli -n 2 hgetall sess_<id>
docker compose exec valkey valkey-cli -n 0 type <key>
docker compose exec valkey valkey-cli -n 0 ttl <key>

# Watch every command Magento sends, live (good for checking which DB a request hits)
docker compose exec valkey valkey-cli monitor

# Health, memory, hit rate
docker compose exec valkey valkey-cli info memory
docker compose exec valkey valkey-cli info stats | grep -E 'keyspace_hits|keyspace_misses'
docker compose exec valkey valkey-cli --stat          # rolling one-line stats
docker compose exec valkey valkey-cli --bigkeys       # largest keys per type
docker compose exec valkey valkey-cli --latency       # round-trip latency
docker compose exec valkey valkey-cli slowlog get 10
```

Cache data shows up as binary because it is compressed and serialized with igbinary. Session data is readable.

## GUI tools

Connect them to `localhost:6379`, with no password:

- **Redis Insight** (free, from Redis): works with Valkey, has a key browser, memory analysis and a profiler.
- **Another Redis Desktop Manager** (open source): lightweight.
- **In the browser**: add a web UI service to `docker-compose.yml`, then open http://localhost:8081:

  ```yaml
  redis-commander:
    image: ghcr.io/joeferner/redis-commander
    environment:
      REDIS_HOSTS: cache:valkey:6379:0,fpc:valkey:6379:1,sessions:valkey:6379:2
    ports: ["8081:8081"]
    networks: [magento]
  ```

## Checking it end to end from Magento

```bash
# 1. Is the config right?
grep -n -A4 "'backend' =>\|'save' =>" src/app/etc/env.php

# 2. Does the cache fill DB 0 after a flush?
docker compose exec php bin/magento cache:flush
docker compose exec valkey valkey-cli -n 0 dbsize     # should drop to about 0
curl -sk https://magento.test/ >/dev/null
docker compose exec valkey valkey-cli -n 0 dbsize     # should grow

# 3. Is the full page cache hit? Load the same page twice and watch hits go up
docker compose exec valkey valkey-cli info stats | grep keyspace_hits

# 4. Are sessions stored in Valkey? Log into admin, then:
docker compose exec valkey valkey-cli -n 2 --scan --pattern 'sess_*'
ls src/var/session/      # no new files should appear here
```

Check 4 matters most. When the session handler fails, there is no error and sessions are written as files instead. If new files ever appear in `src/var/session/`, the session config has fallen back to files.
