# log-sentinel

> Watch log files and send email alerts when keywords appear. **Zero dependencies** — pure Node.js built-ins only.

---

## Features

- **Zero dependencies** — uses only `fs`, `net`, `tls`, `readline` (Node built-ins)
- **Raw SMTP** — supports Gmail, Outlook/Office 365 via STARTTLS (port 587) or SSL (port 465)
- **Batch alerts** — collects multiple hits in a time window into one email (no inbox flooding)
- **Cooldown** — suppresses further alerts for a configurable period after each send
- **Log rotation aware** — detects file truncation and resets automatically
- **Multiple recipients** — send to as many emails as you need
- **CLI + programmatic API**

---

## Install

```bash
npm install -g log-sentinel   # global CLI
# or
npm install log-sentinel      # local / programmatic use
```

---

## CLI Usage

```bash
log-sentinel \
  --file /var/log/app.log \
  --keywords "ERROR,500,FATAL" \
  --to "alice@example.com,bob@example.com" \
  --smtp-host smtp.gmail.com \
  --smtp-port 587 \
  --smtp-user you@gmail.com \
  --smtp-pass "abcd efgh ijkl mnop"
```

### All Options

| Flag | Required | Default | Description |
|---|---|---|---|
| `--file` | ✅ | — | Log file path to watch |
| `--keywords` | ✅ | — | Comma-separated keywords |
| `--to` | ✅ | — | Comma-separated recipient emails |
| `--smtp-host` | ✅ | — | SMTP server (e.g. `smtp.gmail.com`) |
| `--smtp-user` | ✅ | — | SMTP username |
| `--smtp-pass` | ✅ | — | SMTP password / app-password |
| `--smtp-port` | ❌ | `587` | `465` (SSL) or `587` (STARTTLS) |
| `--smtp-from` | ❌ | `smtp-user` | Sender address |
| `--batch-ms` | ❌ | `10000` | Collect matches for N ms before emailing |
| `--cooldown-ms` | ❌ | `300000` | Suppress alerts for N ms after a send |
| `--poll-ms` | ❌ | `1000` | File polling interval in ms |

---

## Programmatic API

```js
const { sentinel } = require('log-sentinel');

const watcher = sentinel({
  file:     '/var/log/app.log',
  keywords: ['ERROR', '500', 'FATAL'],
  to:       ['alice@example.com', 'bob@example.com'],

  smtp: {
    host: 'smtp.gmail.com',
    port: 587,                    // 587 = STARTTLS, 465 = SSL
    user: 'you@gmail.com',
    pass: 'abcd efgh ijkl mnop',  // Gmail App Password
    from: 'alerts@yourapp.com',   // optional
  },

  batchWindowMs:  10_000,   // wait 10 s to collect hits before sending
  cooldownMs:     300_000,  // don't send again for 5 min after an alert
  pollIntervalMs: 1_000,    // check the file every 1 s
});

// Later, to stop watching:
watcher.stop();
```

---

## Gmail Setup

Gmail requires an **App Password** (not your real password):

1. Enable 2-Step Verification on your Google Account
2. Go to **Google Account → Security → App Passwords**
3. Create a new App Password (name it anything, e.g. "log-sentinel")
4. Use the generated 16-character password as `--smtp-pass`

SMTP settings for Gmail:
```
host: smtp.gmail.com
port: 587   (STARTTLS)  or  465 (SSL)
```

## Outlook / Office 365 Setup

```
host: smtp.office365.com
port: 587
```

Use your regular Office 365 email and password (or an app password if MFA is enabled).

---

## How it Works

```
Log file
   │  (new bytes appended)
   ▼
fs.watchFile  ──► readline  ──► keyword scan
                                    │
                              match found
                                    │
                                 Batcher
                          (collect for 10 s)
                                    │
                              Raw SMTP client
                          (net/tls built-ins)
                                    │
                             Email delivered
```

1. `fs.watchFile` polls the file on a configurable interval
2. When the file grows, only the **new bytes** are read (no re-reading the whole file)
3. Each new line is scanned for keywords
4. Matches are fed into a **batcher** that waits for a quiet window before sending
5. The raw SMTP client opens a TCP/TLS socket and speaks the SMTP protocol directly

---

## Project Structure

```
log-sentinel/
├── index.js          ← Public API (sentinel function)
├── bin/
│   └── cli.js        ← CLI entry point
├── src/
│   ├── watcher.js    ← File watcher (fs.watchFile + readline)
│   ├── mailer.js     ← Raw SMTP client (net + tls)
│   └── batcher.js    ← Alert debouncer / cooldown
└── package.json
```
