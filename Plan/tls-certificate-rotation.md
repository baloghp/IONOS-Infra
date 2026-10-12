# TLS Certificate Rotation (`*.ittd.app`)

Runbook for the IONOS wildcard certificate that Caddy serves on VPS-2 Frontend.

Related: `Plan/05-implementation-phases/02-frontend-gateway-tls-static-site.md`, `ansible/roles/caddy/`.

## Certificate inventory

IONOS holds **two** included SSL Starter Wildcard slots ("Inklusive Zertifikate") for `*.ittd.app`. They are independent orders, not duplicates of one certificate.

| IONOS row | Sectigo serial | Validity (UTC) | Role |
|-----------|----------------|----------------|------|
| `04/12/2026` ✓ | `D8B68A00…BCA85813` | 2026-06-06 → 2026-12-03 | **Live** — deployed as `bundle.pem` + `private.key` |
| `21/09/2026` ℹ | `E6DE0290…` (reissued 2026-03-29) | 2026-03-21 → 2026-09-20 | Spare — reissue requested 2026-09-07, certificate not yet issued |

IONOS displays expiry in local time, so a `notAfter` of `23:59:59 UTC` shows as the following day.

**Keep both slots.** Rotating into the *spare* slot leaves the live certificate valid and installed for the whole cutover, so a bad deploy is one file swap away from rollback. Reissuing the live order instead supersedes the certificate currently serving traffic.

Renewal notices arrive for whichever row is nearest expiry, including the spare. Check which row is live before acting.

## Control-node layout

`ansible/files/frontend/ssl/` — gitignored via `ansible/.gitignore`, never commit key material.

```text
ittd.app_ssl_certificate.cer               # live server cert       -> ssl/server.cer
_.ittd.app_private_key.key                 # live key (chmod 600)   -> ssl/private.key
_.ittd.app_ssl_certificate_INTERMEDIATE/   # intermediate1.cer, intermediate2.cer
renewal-pending/                           # next cert + key, staged before cutover
_.ittd.app.pfx                             # unused by Ansible
```

Filenames are bound to `caddy_ssl_server_cert_src` / `caddy_ssl_private_key_src` in `ansible/roles/caddy/defaults/main.yml`. Keep the names or update the defaults.

## Rotation

Trigger roughly three weeks before the live certificate's `notAfter` — next is **2026-12-03**.

1. In IONOS, reissue and download the **spare** slot: server certificate, private key, intermediate bundle.
2. Stage all of it in `renewal-pending/`, key as `chmod 600`.
3. Verify the pair matches *before* touching the live files:

```bash
cd ansible/files/frontend/ssl/renewal-pending
openssl x509 -in ittd.app_ssl_certificate.cer -noout -subject -dates -ext subjectAltName
diff <(openssl x509 -noout -modulus -in ittd.app_ssl_certificate.cer) \
     <(openssl rsa  -noout -modulus -in _.ittd.app_private_key.key) && echo "pair OK"
```

4. Promote the staged pair over the two live files, keeping a copy of the previous pair until step 5 passes.
5. Deploy and confirm the serial on the wire changed:

```bash
cd ansible
ansible-playbook playbooks/gateway.yml
openssl s_client -connect www.ittd.app:443 -servername www.ittd.app </dev/null 2>/dev/null \
  | openssl x509 -noout -dates -serial
```

The `caddy` role compares certificate and key moduli and fails the play before restarting Caddy, so a mismatched pair cannot reach production.

**Rollback:** restore the previous `.cer` / `.key` pair and re-run `playbooks/gateway.yml`.

## Intermediates

`Sectigo Public Server Authentication CA DV R36` (to 2036) chained to root `R46` (to 2038). Only replace them if IONOS ships a different chain — a routine rotation changes the server certificate and key only.

## Audit

All issuances are public in certificate transparency logs:

```bash
curl -s "https://crt.sh/?q=ittd.app&output=json" | python3 -m json.tool
```

Certificates before 2026-03 include Let's Encrypt entries from the superseded `Old_Config` auto-TLS gateway; those no longer renew.
