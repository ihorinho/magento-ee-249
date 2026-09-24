# Database backup

Backups are made with `mariadb-dump` inside the `db` container and saved to `src/var/backups/`. Git ignores that folder because all of `src/var/` is ignored.

`bin/magento setup:backup` is turned off by default and deprecated by Adobe, so use the commands below instead.

## Create a backup

Run from the project root:

```bash
mkdir -p src/var/backups
docker compose exec -T db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"' \
  | gzip > src/var/backups/magento-$(date +%F-%H%M).sql.gz
```

- The password and database name come from the container's own environment variables, so they're not in your shell history.
- `-T` is required. Without it, Docker adds terminal control characters that corrupt the dump.
- `--single-transaction` takes a consistent snapshot without locking tables, so you don't need maintenance mode.
- `--routines --triggers` also saves stored procedures and triggers. Magento uses triggers for indexers set to "Update by Schedule".

Check the backup:

```bash
F=src/var/backups/magento-<date>.sql.gz
gzip -t "$F" && zcat "$F" | tail -1          # should print "-- Dump completed on ..."
zcat "$F" | grep -c '^CREATE TABLE'          # number of tables
```

## Restore a backup

Restoring overwrites the tables in the current database.

```bash
docker compose exec php bin/magento maintenance:enable

gunzip -c src/var/backups/magento-<date>.sql.gz \
  | docker compose exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'

docker compose exec php bin/magento cache:flush
docker compose exec php bin/magento maintenance:disable
```

The Valkey cache and sessions aren't in the dump. `cache:flush` clears the cache, so Magento doesn't serve data from before the restore. To also log everyone out, clear the sessions:

```bash
docker compose exec valkey valkey-cli -n 2 flushdb
```

### Clean restore

This drops the database first, so tables that were added after the backup are removed too:

```bash
docker compose exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE \`$MARIADB_DATABASE\`; CREATE DATABASE \`$MARIADB_DATABASE\`;"'
```

Then run the restore commands above.
