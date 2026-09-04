# How to run the server

This document applies to the legacy Python server in `server/`. The native
macOS app does not need it. The app has no server and no network setup.

Section 2 of [PLAN.md](PLAN.md) selected Tailscale for access from other
devices. This document does not use Tailscale. It gives three options that need
only macOS, SSH and one optional proxy.

## Read this first

The server has **no authentication of any kind**. A person who can reach the
port can do all of this:

- Open a session and record audio.
- Read each stored transcript.
- Delete the archived audio.

**Bind the server to the loopback interface.** Each option below starts the
server with `--host 127.0.0.1`. The options add access on top of that bind.
They do not change it.

**Do not open a port on your router. Do not put the server on the public
internet.** Section 1 of the plan states that audio never leaves the machine.

Section 13 of the plan gives the second constraint. On plain HTTP,
`getUserMedia` returns undefined for each host except `localhost`, and it gives
no error message. **The microphone does not work from a phone until TLS is in
place.** The capture page shows a message when this happens.

## Option 1: on the same Mac

This is the default. It needs no certificate and no proxy.

1. Start the server:

   ```bash
   ./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
   ```

2. Open <http://127.0.0.1:8000> in a browser on the same Mac.

The browser reads `127.0.0.1` as a secure origin, thus the microphone works.
Nothing listens on the network.

## Option 2: from another computer, through SSH

Use this option for a second Mac, a PC or a Linux machine. SSH gives the
encryption and the password check that the server does not have.

1. On the Mac that runs the server, enable Remote Login. Open System Settings,
   then **General**, then **Sharing**, then **Remote Login**.

2. On the same Mac, start the server:

   ```bash
   ./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
   ```

3. On the other computer, open the tunnel:

   ```bash
   ssh -N -L 8000:127.0.0.1:8000 <user>@<mac>.local
   ```

4. On the other computer, open <http://127.0.0.1:8000>.

The browser on the other computer reads `127.0.0.1`. It therefore treats the
page as a secure origin, and the microphone works. The WebSocket goes through
the same tunnel.

If `<mac>.local` does not resolve, use the IP address of the Mac. To find that
address, run `ipconfig getifaddr en0`.

## Option 3: from a phone, through a TLS proxy

A phone cannot open an SSH tunnel easily. The phone therefore needs HTTPS, and
the server needs a password. Caddy gives both. To install Caddy, run
`brew install caddy`.

**A phone accepts only a certificate from a certificate authority that the
phone knows.** This is the difficult part of this option. Read step 4 before
you start.

1. Make a password hash:

   ```bash
   caddy hash-password
   ```

   Caddy asks for a password and prints a bcrypt hash. Copy the hash.

2. Write a file with the name `Caddyfile`:

   ```
   https://<mac-ip>:8443 {
       tls internal
       basic_auth {
           transcriber <the hash from step 1>
       }
       reverse_proxy 127.0.0.1:8000
   }
   ```

   Replace `<mac-ip>` with the IP address of the Mac. Caddy passes the
   WebSocket upgrade through with no more configuration. Caddy before version
   2.8 spells the directive `basicauth`, with no underscore.

3. Start the server, then start Caddy:

   ```bash
   ./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
   caddy run --config Caddyfile
   ```

4. Install the root certificate of Caddy on the phone. `tls internal` makes a
   local certificate authority. The root certificate is here:

   ```
   ~/Library/Application Support/Caddy/pki/authorities/local/root.crt
   ```

   Send that file to the phone. On iOS, open the file and install the profile.
   Then open Settings › General › About › Certificate Trust Settings and enable
   full trust for it. On Android, install the file under Settings › Security ›
   Encryption & credentials › Install a certificate › CA certificate.

5. Open `https://<mac-ip>:8443` on the phone. Give the user name `transcriber`
   and your password.

**Do not skip the root certificate and accept the browser warning instead.**
The result is different on each browser and each version. This is not a
dependable path.

If you own a domain, you can use a certificate from a public certificate
authority. Caddy can get one with a DNS-01 challenge, and the phone then
accepts it with no profile. That path needs a DNS provider plugin for Caddy and
is outside this document.

uvicorn can also serve TLS itself with `--ssl-certfile` and `--ssl-keyfile`.
That gives you the certificate but no password. The server has no
authentication, thus use the proxy instead.

## Capacity

`ASR_MAX_SESSIONS` limits the number of concurrent sessions. The default is 3.
The server refuses a session above the limit with an `at_capacity` error. It
does not put the session in a queue.

[FINDINGS.md](FINDINGS.md#7-phase-3-concurrency-partials-hold-up-commits-do-not)
records the measured degradation. Partial latency holds to 4 streams, but the
number of commits per stream falls by one third.

## Retention

One hour of one session archives approximately 115 MB of audio.

```bash
curl -X POST "http://127.0.0.1:8000/maintenance/retention?days=30"
```

This request deletes each session that is older than `days`, its segments and
its WAV files. Nothing calls this endpoint automatically. Add it to a launchd
timer or to a cron job.
