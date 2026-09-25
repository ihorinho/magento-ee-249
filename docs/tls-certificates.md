# TLS certificates

nginx terminates TLS for `https://magento.test` and reads two files that are
**not in git** (`.gitignore`), because they are private keys:

| Path | Purpose |
| --- | --- |
| `docker/nginx/certs/magento.test.pem` | leaf certificate |
| `docker/nginx/certs/magento.test-key.pem` | leaf private key |
| `docker/nginx/ca/magento-local-ca.pem` | local CA that signed the leaf |
| `docker/nginx/ca/magento-local-ca-key.pem` | local CA private key |

If they are missing, nginx exits on boot:

```
[emerg] cannot load certificate "/etc/nginx/certs/magento.test.pem":
BIO_new_file() failed (... No such file or directory ...)
```

## Generate them

```bash
./docker/nginx/generate-certs.sh
docker compose up -d nginx
```

The script is idempotent: it reuses an existing CA and only re-issues the leaf,
so a browser that already trusts the CA keeps trusting it. The leaf is valid for
825 days (the maximum Chrome and Safari accept) with SANs for `magento.test`,
`*.magento.test`, `localhost`, `127.0.0.1` and `::1`.

Override the defaults via environment variables:

```bash
DOMAIN=shop.test DAYS=365 ./docker/nginx/generate-certs.sh
```

Note that `DOMAIN` must match `server_name` and the `ssl_certificate` paths in
`docker/nginx/default.conf`.

## Trust the CA

Until the CA is trusted, browsers show a warning and `curl` needs
`--cacert docker/nginx/ca/magento-local-ca.pem`.

On Debian/Ubuntu, for system-wide trust (covers curl, PHP, CLI tools):

```bash
sudo cp docker/nginx/ca/magento-local-ca.pem \
        /usr/local/share/ca-certificates/magento-local-ca.crt
sudo update-ca-certificates
```

Firefox and Chrome keep their own stores, so import
`docker/nginx/ca/magento-local-ca.pem` there as well:

- Firefox: Settings → Privacy & Security → Certificates → View Certificates →
  Authorities → Import, and tick "Trust this CA to identify websites".
- Chrome: Settings → Privacy and security → Security → Manage certificates →
  Authorities → Import.

## Host entry

`magento.test` must resolve locally:

```bash
grep magento.test /etc/hosts || echo "127.0.0.1 magento.test" | sudo tee -a /etc/hosts
```

## Verify

```bash
docker compose exec nginx nginx -t
curl -sS --cacert docker/nginx/ca/magento-local-ca.pem \
     -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://magento.test/
```

`200 0` means the certificate chain validates.
