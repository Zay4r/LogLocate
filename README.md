# LogLocate

**Find keywords through large text files instantly.**

LogLocate is a high-performance log indexer and alerter. It watches log files in real-time, builds searchable indexes, and sends alerts when critical patterns are detected.

---

## 🚀 Quick Start

### Installation

```bash
# Option 1: Remote install (recommended)
curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/main/install.sh | sudo bash

# Option 2: Local install
sudo bash install.sh
```

### Basic Usage

```bash
# Start watching a log file
sudo log-locate add /var/log/app.log

# Search for a keyword
log-locate search /var/log/app.log "ERROR"

# See all watched files
log-locate status

# Stop watching a file
sudo log-locate remove /var/log/app.log
```

---

## 📖 Complete User Guide

### What is LogLocate?

LogLocate solves the problem of searching large log files. Instead of scanning entire files every time, it:

1. **Watches** log files as they grow
2. **Indexes** matching keywords for instant search
3. **Alerts** you when critical patterns appear

### Installation Requirements

- Linux system with `bash`, `tail`, `awk`, `grep`, `dd`, `curl`
- Root/sudo access for setup
- `systemd` for service management

### Commands

#### 1. **Add a Log File** (Start Watching)

```bash
sudo log-locate add <file-path> [--patterns "PATTERN1 PATTERN2"]
```

**Examples:**

```bash
# Watch with default patterns (ERROR, WARN, FATAL)
sudo log-locate add /var/log/app.log

# Watch with custom patterns
sudo log-locate add /var/log/app.log --patterns "ERROR CRITICAL user_id=*"

# Watch with wildcard patterns (prefix matching)
sudo log-locate add /var/log/app.log --patterns "request_id=* user_id=* error_code=*"
```

**What happens:**
- Creates an index file at `/var/log/app.log.idx`
- Starts a systemd service to monitor the file
- Begins indexing matching keywords immediately

---

#### 2. **Search the Index**

```bash
log-locate search <file-path> <keyword>
```

**Examples:**

```bash
# Exact keyword match
log-locate search /var/log/app.log "ERROR"

# Wildcard prefix search
log-locate search /var/log/app.log "user_id=*"

# Search for specific values
log-locate search /var/log/app.log "user_id=12345"
```

**Output shows:**
- Line number
- Timestamp from the log
- Matched keyword
- Search time in milliseconds

---

#### 3. **Range Search (Find Logs in Time Window)**

```bash
log-locate range <file-path> <from-timestamp> <to-timestamp>
```

**Examples:**

```bash
# Search logs between two timestamps
log-locate range /var/log/app.log 2026-05-28T10:00:00Z 2026-05-28T10:30:00Z

# Morning shift logs
log-locate range /var/log/app.log 2026-05-28T08:00:00Z 2026-05-28T12:00:00Z
```

**Timestamp format:** ISO 8601 (e.g., `2026-05-28T10:15:30Z`)

---

#### 4. **View Watched Files**

```bash
log-locate status
```

**Shows:**
- All files being monitored
- Service status (active/inactive)
- Number of indexed entries per file

---

#### 5. **Stop Watching a File**

```bash
sudo log-locate remove <file-path>
```

**Examples:**

```bash
# Stop watching a log file
sudo log-locate remove /var/log/app.log
```

**What happens:**
- Stops the systemd service
- Keeps the index file for history (doesn't delete it)

---

#### 6. **Help**

```bash
log-locate help
log-locate --help
log-locate -h
```

---

## 📋 Pattern Matching Guide

LogLocate supports two types of pattern matching:

### 1. Exact Match
```bash
log-locate add /var/log/app.log --patterns "ERROR FATAL CRITICAL"
```
Matches only: `ERROR`, `FATAL`, `CRITICAL`

### 2. Wildcard/Prefix Match
```bash
log-locate add /var/log/app.log --patterns "user_id=* request_id=* error_code=*"
```
Matches anything starting with the prefix:
- `user_id=12345` ✓
- `user_id=99999` ✓
- `request_id=abc123` ✓
- `error_code=500` ✓

---

## ⚙️ Configuration

### Global Config
Located at: `/etc/log-locate/config`

```bash
# Default patterns for all files
PATTERNS="ERROR WARN FATAL"

# Patterns that trigger alerts
ALERT_PATTERNS="ERROR FATAL 500"

# Notification method: telegram, email, or both
NOTIFY="telegram"

# Telegram settings (for alerts)
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"

# Email settings (for alerts)
SMTP_HOST="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USER="your_email@gmail.com"
SMTP_PASS="your_password"
ALERT_FROM="sender@example.com"
ALERT_TO="recipient@example.com"

# Alert batching (seconds before sending)
BATCH_SECONDS="10"

# Cooldown between alerts (seconds)
COOLDOWN_SECONDS="300"
```

### Per-File Config
For custom patterns per log file:

```bash
/etc/log-locate/<filename>.conf
```

Example: `/etc/log-locate/app.log.conf`

```bash
# Override patterns for just this file
PATTERNS="CUSTOM PATTERN1 PATTERN2"
ALERT_PATTERNS="CRITICAL"
```

---

## 🔔 Alerts

LogLocate can send alerts via **Telegram** or **Email** when alert patterns are detected.

### Enable Telegram Alerts

1. Create a bot on Telegram via [@BotFather](https://t.me/botfather)
2. Get your chat ID from [@userinfobot](https://t.me/userinfobot)
3. Edit `/etc/log-locate/config`:

```bash
NOTIFY="telegram"
TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
TELEGRAM_CHAT_ID="987654321"
ALERT_PATTERNS="ERROR FATAL CRITICAL"
```

### Enable Email Alerts

```bash
NOTIFY="email"
SMTP_HOST="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USER="your_email@gmail.com"
SMTP_PASS="your_app_password"
ALERT_FROM="your_email@gmail.com"
ALERT_TO="admin@example.com"
ALERT_PATTERNS="ERROR FATAL"
```

---

## 📁 File Locations

| Path | Purpose |
|------|---------|
| `/usr/local/bin/log-locate` | Main CLI tool |
| `/usr/local/bin/log-locate-daemon` | Background indexer service |
| `/etc/systemd/system/log-locate@.service` | Systemd service template |
| `/etc/log-locate/config` | Global configuration |
| `/etc/log-locate/*.conf` | Per-file configurations |
| `/var/log/app.log.idx` | Index file (created per log) |

---

## 🔍 Index File Format

The `.idx` files are tab-separated and human-readable:

```
TOKEN	LINE_NUMBER	TIMESTAMP
ERROR	15	2026-05-28T10:15:30Z
ERROR	42	2026-05-28T10:20:15Z
database	15	2026-05-28T10:15:30Z
```

You can search them manually:
```bash
grep "ERROR" /var/log/app.log.idx
```

---

## 🎯 Real-World Examples

### Example 1: Monitor Web Server
```bash
# Watch Apache access logs with custom patterns
sudo log-locate add /var/log/apache2/access.log --patterns "500 403 404 4[0-9][0-9]"

# Search for errors
log-locate search /var/log/apache2/access.log "500"
```

### Example 2: Monitor Application Logs
```bash
# Watch app logs with user tracking
sudo log-locate add /var/log/myapp/production.log --patterns "ERROR WARN user_id=* request_id=*"

# Find specific user's errors
log-locate search /var/log/myapp/production.log "user_id=12345"

# Find all errors in a time range
log-locate range /var/log/myapp/production.log 2026-05-28T09:00:00Z 2026-05-28T10:00:00Z
```

### Example 3: View Monitoring Status
```bash
log-locate status

# Output:
# log-locate — watched files
# ──────────────────────────────────────────────────────────────
#   active    /var/log/app.log
#            Index: 1542 entries
#   active    /var/log/nginx/access.log
#            Index: 3891 entries
# ──────────────────────────────────────────────────────────────
```

---

## 🚨 Troubleshooting

### "Index not found" error

```bash
log-locate search /var/log/app.log "ERROR"
# Error: [log-locate] Index not found: /var/log/app.log.idx
```

**Solution:** Start watching the file first:
```bash
sudo log-locate add /var/log/app.log
```

---

### Service won't start

Check the systemd service:
```bash
# View service status
systemctl status log-locate@*.service

# View service logs
journalctl -u "log-locate@*" -f
```

---

### Alerts not sending

1. Check configuration:
```bash
cat /etc/log-locate/config
```

2. Test Telegram token:
```bash
curl -X GET "https://api.telegram.org/botYOUR_TOKEN/getMe"
```

3. Verify email credentials:
```bash
# Try sending a test email
echo "Test" | curl smtp://smtp.gmail.com:587 \
  --user "your_email@gmail.com:your_password" \
  --mail-from "your_email@gmail.com" \
  --mail-rcpt "recipient@example.com"
```

---

## 📊 Performance Tips

1. **Use specific patterns** - Reduces index size
   ```bash
   # Good: specific patterns
   sudo log-locate add /var/log/app.log --patterns "ERROR FATAL"
   
   # Avoid: too broad
   sudo log-locate add /var/log/app.log --patterns "* *"
   ```

2. **Archive old indexes** - Keep disk usage down
   ```bash
   # Compress old index
   gzip /var/log/app.log.idx.2026-05-01
   ```

3. **Monitor service** - Ensure daemon is running
   ```bash
   log-locate status
   ```

---

## 🔧 Advanced Usage

### View Daemon Logs
```bash
# Real-time logs for a specific service
journalctl -u log-locate@var-log-app.log.service -f

# Last 50 lines
journalctl -u log-locate@var-log-app.log.service -n 50
```

### Manual Index Creation
```bash
# Index existing log (no alerts)
log-locate-daemon /var/log/app.log
```

### Remove All Watched Files
```bash
# Careful! This removes all monitoring
systemctl stop 'log-locate@*.service'
systemctl disable 'log-locate@*.service'
```

---

## 📝 Log File Format

LogLocate expects timestamps in ISO 8601 format at the start of each line:

```
2026-05-28T10:15:30.123Z [ERROR] Database connection failed
2026-05-28T10:15:31.456Z [WARN] Cache miss detected
```

**If your logs don't have timestamps**, LogLocate uses the current time instead.

---

## 📄 License

MIT License - See LICENSE file

---

## 🤝 Support

For issues or feature requests, visit: [GitHub Issues](https://github.com/Zay4r/LogLocate/issues)

---

## ✨ Features

- ✅ **Instant Search** - Binary search on pre-built index
- ✅ **Real-Time Indexing** - Watches files as they grow
- ✅ **Pattern Matching** - Exact match and wildcard patterns
- ✅ **Time Range Search** - Find logs between timestamps
- ✅ **Alerts** - Telegram & Email notifications
- ✅ **Systemd Integration** - Automatic startup and management
- ✅ **Log Rotation Support** - Follows files across rotations
- ✅ **Lightweight** - Minimal dependencies, bash-only

---

**Happy log hunting! 🎯**
