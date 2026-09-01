# Deploying on the tailnet

Section 2 picks Tailscale because it solves HTTPS certificates and cross-device
access in one move. Section 13 flags why it cannot wait: `getUserMedia` returns
undefined on plain HTTP from anything but `localhost`, so **the microphone will
never work from a phone until TLS is in place**, and it fails silently.

Tailscale is installed on this machine (1.102.3) but stopped and not
authenticated. These steps need your login, so they are written out rather than
run.

## 1. Bring the machine onto the tailnet

```bash
sudo tailscale up
```

## 2. Enable HTTPS for the tailnet

Once, in the admin console: **DNS → HTTPS Certificates → Enable**. Then confirm
the machine's name:

```bash
tailscale status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['Self']['DNSName'])"
```

## 3. Serve the app over TLS

`tailscale serve` terminates TLS and proxies to the local port, so the app keeps
listening on plain HTTP on loopback and never handles certificates itself.
WebSocket upgrades pass through.

```bash
tailscale serve --bg --https=443 http://127.0.0.1:8000
```

Start the app bound to loopback only:

```bash
./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
```

Then open `https://<machine>.<tailnet>.ts.net` from any device on the tailnet.
The client picks `wss://` automatically when the page is served over HTTPS.

Do **not** run `tailscale funnel` unless you intend to publish to the public
internet. Section 1's whole premise is that audio never leaves the machine, and
funnel breaks it.

## Capacity

`ASR_MAX_SESSIONS` caps concurrent sessions (default 3). Measured degradation is
in [FINDINGS.md](FINDINGS.md#7-phase-3-concurrency-partials-hold-up-commits-do-not);
partial latency holds to 4 streams, but commits per stream fall by a third.
Sessions past the cap are refused with an `at_capacity` error rather than queued.

## Retention

Archived audio is ~115 MB per session-hour.

```bash
curl -X POST "http://127.0.0.1:8000/maintenance/retention?days=30"
```

Deletes sessions older than `days`, their segments, and their WAV files. Wire it
to a launchd timer or a cron job; nothing calls it automatically.
