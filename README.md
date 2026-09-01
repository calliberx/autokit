# AutoKit

Your own WhatsApp automation server — n8n in queue mode plus a personal
Evolution API instance, on a VPS you control.

> **Status: verified end-to-end on 2026-08-31.** A clean install was brought up
> from scratch, a WhatsApp number was paired by QR, and a message was delivered
> through the full path: webhook → n8n → queue → worker → Evolution → WhatsApp.
> See [Known gaps](#known-gaps) for what is still untested.

## Requirements

- Ubuntu 22.04 or 24.04 VPS, 4GB RAM, 10GB free disk

  Measured idle usage of the whole stack is roughly 800MB. The 4GB figure is
  headroom for community-node installs and concurrent executions, not the
  floor — but it has not been tested below 4GB.
- Docker + Docker Compose v2
- A domain pointing at the server (optional — without one AutoKit runs on `http://IP:PORT`)
- A phone number for WhatsApp that is **not** your main personal number

## Install

```bash
git clone git@github.com:calliberx/autokit.git
cd autokit
./setup.sh
```

`setup.sh` asks whether you have a domain, checks the server can actually run
the stack, generates every password and key, writes the `.env` files and
starts the services. It does not ask for any API keys.

## After install

1. Open n8n and create your owner account.
2. **Settings → Community nodes** → install `n8n-nodes-evolution-api-english`.
   All three templates depend on it.
3. **Workflows → Import from file** → import from `templates/`.
4. Create an Evolution instance and scan the QR code to pair WhatsApp.

## Templates

Three templates ship with AutoKit. They are an operational backbone plus a
working WhatsApp entry point — not a library of finished business automations.

| File | What it does | Needs |
|---|---|---|
| `01-backup-workflows.json` | Nightly backup of every n8n workflow to a private GitHub repo, with a WhatsApp alert on success or failure | n8n API + GitHub PAT + Evolution credentials |
| `02-whatsapp-notification.json` | `POST {phone, message}` to a webhook, sends a WhatsApp message | Evolution credential, header auth |
| `03-whatsapp-agent-trigger.json` | Receives every inbound WhatsApp message and routes it by type (text / audio / image / PDF) | Evolution credential; OpenAI optional |

Each has a sticky note in the canvas listing exactly what to fill in. Nothing
is pre-wired to a live account — every instance name, phone number and repo is
a placeholder.

## Operations

```bash
docker compose ps          # service status
docker compose logs -f     # follow logs
./scripts/backup.sh        # back up volumes + config
./scripts/restore.sh <dir> # restore from a backup
./scripts/update.sh        # rolling update (backs up first)
```

Read [docs/VERSIONS.md](docs/VERSIONS.md) before changing any image tag. The
Evolution tag is the one that breaks WhatsApp.

## Security notes

- With a domain, n8n and Evolution bind to `127.0.0.1` and are reachable only
  through Traefik over HTTPS. Without a domain they bind to `0.0.0.0` in plain
  HTTP — acceptable for testing, not for client data.
- The Evolution API key is the only thing between the internet and your
  WhatsApp session. Treat it like a password.
- `setup.sh` writes `CREDENTIALS_*.txt`. Copy it off the server and delete it.

## Known gaps

- Verified on Docker for macOS (colima), **not yet on a clean Ubuntu VPS.** The
  domain path (Traefik + Let's Encrypt) is proven only by the production
  CalliberX server, not by a from-scratch install.
- Templates `01` and `03` are imported and load correctly but have **not been
  executed** — both need external credentials (GitHub PAT, OpenAI) to run.
  Template `02` is fully verified end to end.
- `03-whatsapp-agent-trigger.json` ships with its `Call 'Agent Manager'` node
  **disabled** — it referenced a workflow that is not part of AutoKit. Point it
  at your own agent workflow and enable it.
- No troubleshooting guide yet; it gets written from real delivery friction,
  not from imagination.

## Licence and disclaimer

AutoKit uses an unofficial WhatsApp connection through Evolution API. It is not
Meta's official WhatsApp Business API. WhatsApp can suspend numbers for
spam-like behaviour — use a dedicated number, warm it up, and only message
people who opted in.

Built by [CalliberX](https://calliberx.com).
