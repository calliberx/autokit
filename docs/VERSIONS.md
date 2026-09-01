# Pinned versions

Every image in `docker-compose.yml` is pinned to an exact tag. This is
deliberate. `:latest` is how a working WhatsApp connection turns into a
support ticket overnight.

**How these were chosen:** each tag below is what actually runs on the
CalliberX production VPS, verified against the live containers on
2026-08-31 — not copied from upstream release notes.

| Service | Tag | Why it matters |
|---|---|---|
| `evoapicloud/evolution-api` | `v2.3.7` | **The one that breaks.** Evolution talks to WhatsApp over an unofficial protocol. A new tag can change pairing behaviour or stop connecting entirely. Note the org is `evoapicloud` — older guides say `atendai`, which is stale. |
| `n8nio/n8n` | `2.36.8` | Main and worker must always be on the **same** tag. Mismatched versions cause queue errors that look like random execution failures. |
| `n8nio/runners` | `2.36.8` | Follows the n8n tag. |
| `postgres` | `15` | Major version only. Never jump majors without a dump/restore. |
| `redis` | `7` | Queue only, no persistence concerns beyond the appendonly file. |
| `traefik` | `v3` | Stable within the v3 line. |

## Do not use 2.37.x

`2.37.5` is published only as separate `-amd64` and `-arm64` tags. There is no
multi-arch manifest, so `docker pull n8nio/n8n:2.37.5` fails outright. Stay on
the 2.36 line until upstream publishes a combined manifest.

## The 1.x → 2.x jump

Tags in the `1.x` line (including the `1.129.1` this file previously pinned)
**no longer exist on Docker Hub.** Anything still referencing them fails at
`docker compose up` with `not found`. n8n is on the 2.x line now.

## The Evolution phone version

`CONFIG_SESSION_PHONE_VERSION` (in `.env.evolution`) tells Evolution which
WhatsApp Web build to present as. When WhatsApp rejects new pairings, this
value is usually the fix — not the image tag. Update it before touching
anything else.

An Evolution container that starts cleanly, logs no errors, and still answers
**HTTP 500 on every endpoint** is a configuration fault, not a bad image —
compare its environment against a known-good instance before changing tags.

## Updating safely

```bash
./scripts/backup.sh          # always first
# edit the tag in docker-compose.yml
./scripts/update.sh
```

Verify after every update:

1. n8n UI loads and you can log in
2. A test workflow executes (confirms the worker is consuming the queue)
3. Evolution responds: `curl -H "apikey: $KEY" $EVOLUTION_URL/instance/fetchInstances`
4. The paired WhatsApp number still sends and receives

If step 3 or 4 fails, roll the tag back and restore:

```bash
./scripts/restore.sh backups/backup-<timestamp>
```
