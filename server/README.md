# hush-server

Optional, self-hosted sync for Hush. Hush encrypts everything on the device with your sync
passphrase before it's sent, so the server only ever stores data it can't read. Without a
server, Hush works exactly as before and never touches the network.

* One small Go binary with an embedded database (bbolt). Uses about 10 MB of RAM.
* Image: `ghcr.io/jacobwingstrom/hush-server:latest` (amd64 and arm64).
* All state is in the `/data` volume. Back it up with Proxmox Backup Server or similar.

## Run it

Copy [`deploy/compose.yml`](deploy/compose.yml) (Tailscale, works anywhere) or
[`deploy/compose.lan.yml`](deploy/compose.lan.yml) (home network only) into a folder on a VM or
LXC with Docker, then:

```sh
docker compose up -d
docker compose logs hush        # copy the "Pairing token"
```

In Hush: **Settings > Sync**, enter the address and token, then create a passphrase.
The same compose file and steps are inside the app under **Settings > Sync > Set up the server**.

### Tailscale version

1. In the Tailscale admin console, turn on **MagicDNS** and **HTTPS Certificates** (DNS page).
2. Create an auth key (**Settings > Keys**) and paste it into `TS_AUTHKEY` in the compose file.
   It's only used the first time; the node stays logged in through the `tailscale-state` volume.
3. `docker compose up -d`. The server appears as `https://hush.<your-tailnet>.ts.net`.

It uses Tailscale's userspace networking, so it works in an unprivileged Proxmox LXC with no
`/dev/net/tun` passthrough.

### Update

```sh
docker compose pull && docker compose up -d
```

## Settings

| Variable | Default | |
| --- | --- | --- |
| `HUSH_TOKEN` | generated | Pairing token. If unset, a random one is saved in `/data/token`. |
| `HUSH_MAX_BLOB_MB` | `512` | Largest single attachment. |
| `HUSH_ADDR` | `:8080` | Listen address. |
| `HUSH_DATA` | `/data` | Data folder. |
| `HUSH_LOG` | | `quiet` turns off request logging. |

Commands: `/hush-server token` prints the token, and `/hush-server healthcheck` is used by the
Docker health check.

## Protocol

See [docs/sync-protocol.md](../docs/sync-protocol.md). It covers everything an Android or desktop
client needs.

## Develop

```sh
cd server
go test ./...
HUSH_DATA=./data go run .
```
