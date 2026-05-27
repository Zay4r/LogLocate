#!/usr/bin/env node
'use strict';

const { sentinel } = require('../index');

// ─── Minimal arg parser (no dependencies) ───────────────────────────────────
function parseArgs(argv) {
  const args = {};
  let i = 2; // skip "node" and script path
  while (i < argv.length) {
    const key = argv[i];
    if (key.startsWith('--')) {
      const name = key.slice(2);
      const val  = argv[i + 1];
      if (val && !val.startsWith('--')) {
        args[name] = val;
        i += 2;
      } else {
        args[name] = true;
        i += 1;
      }
    } else {
      i++;
    }
  }
  return args;
}

function printHelp() {
  console.log(`
Usage: log-sentinel [options]

Required:
  --file        <path>        Log file to watch (e.g. /var/log/app.log)
  --keywords    <k1,k2,...>   Comma-separated keywords to watch for
  --to          <e1,e2,...>   Comma-separated recipient email addresses
  --smtp-host   <host>        SMTP server host (e.g. smtp.gmail.com)
  --smtp-user   <user>        SMTP login username
  --smtp-pass   <pass>        SMTP password or app-password

Optional:
  --smtp-port   <port>        SMTP port: 465 (SSL) | 587 (STARTTLS, default) | 25
  --smtp-from   <address>     Sender address (defaults to --smtp-user)
  --batch-ms    <ms>          Collect matches for N ms before sending (default: 10000)
  --cooldown-ms <ms>          Suppress alerts for N ms after sending (default: 300000)
  --poll-ms     <ms>          File polling interval in ms (default: 1000)
  --help                      Show this help

Examples:
  # Gmail (use an App Password, not your real password)
  log-sentinel \\
    --file /var/log/app.log \\
    --keywords "ERROR,500,FATAL" \\
    --to "alice@example.com,bob@example.com" \\
    --smtp-host smtp.gmail.com \\
    --smtp-port 587 \\
    --smtp-user you@gmail.com \\
    --smtp-pass "abcd efgh ijkl mnop"

  # Outlook / Office 365
  log-sentinel \\
    --file /var/log/app.log \\
    --keywords "Exception,Timeout" \\
    --to "team@company.com" \\
    --smtp-host smtp.office365.com \\
    --smtp-port 587 \\
    --smtp-user you@company.com \\
    --smtp-pass "yourpassword"
`);
}

// ─── Main ────────────────────────────────────────────────────────────────────
const args = parseArgs(process.argv);

if (args.help || process.argv.length < 3) {
  printHelp();
  process.exit(0);
}

// Validate required args
const required = ['file', 'keywords', 'to', 'smtp-host', 'smtp-user', 'smtp-pass'];
const missing  = required.filter(k => !args[k]);
if (missing.length) {
  console.error(`[log-sentinel] Missing required options: ${missing.map(k => '--' + k).join(', ')}`);
  printHelp();
  process.exit(1);
}

const config = {
  file:          args['file'],
  keywords:      args['keywords'].split(',').map(k => k.trim()).filter(Boolean),
  to:            args['to'].split(',').map(e => e.trim()).filter(Boolean),
  smtp: {
    host: args['smtp-host'],
    port: parseInt(args['smtp-port'] || '587', 10),
    user: args['smtp-user'],
    pass: args['smtp-pass'],
    from: args['smtp-from'],
  },
  batchWindowMs:  args['batch-ms']    ? parseInt(args['batch-ms'], 10)    : undefined,
  cooldownMs:     args['cooldown-ms'] ? parseInt(args['cooldown-ms'], 10) : undefined,
  pollIntervalMs: args['poll-ms']     ? parseInt(args['poll-ms'], 10)     : undefined,
};

try {
  const watcher = sentinel(config);
  console.log('[log-sentinel] Running. Press Ctrl+C to stop.');

  process.on('SIGINT',  () => { watcher.stop(); process.exit(0); });
  process.on('SIGTERM', () => { watcher.stop(); process.exit(0); });
} catch (err) {
  console.error('[log-sentinel] Error:', err.message);
  process.exit(1);
}
