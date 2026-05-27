#!/usr/bin/env node
'use strict';

/**
 * Generates a large log file, then continuously appends new lines.
 * Usage: node generate-logs.js [--file /tmp/test.log] [--size-mb 1024] [--interval 500]
 */

const fs   = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {};
  let i = 2;
  while (i < argv.length) {
    const key = argv[i];
    if (key.startsWith('--')) {
      args[key.slice(2)] = argv[i + 1];
      i += 2;
    } else i++;
  }
  return args;
}

const args    = parseArgs(process.argv);
const file    = args['file'] || path.join(process.cwd(), 'logs', 'test.log');

// Create the directory if it doesn't exist
fs.mkdirSync(path.dirname(file), { recursive: true });
const sizeMb  = parseInt(args['size-mb']  || '1024', 10);
const interval= parseInt(args['interval'] || '500', 10);

const LEVELS   = ['INFO', 'INFO', 'INFO', 'WARN', 'ERROR', 'DEBUG'];
const MESSAGES = [
  'User login successful user_id=',
  'Request processed path=/api/v1/users latency=',
  'Database query executed table=orders rows=',
  'Cache miss key=session:',
  'ERROR: Connection refused host=db-primary port=5432',
  '500 Internal Server Error path=/api/checkout',
  'WARN: High memory usage percent=',
  'ERROR: Timeout after 30000ms service=payment-gateway',
  'Scheduled job completed job=cleanup_expired_sessions',
  'ERROR: Failed to parse JSON body request_id=',
];

function randomLine() {
  const level = LEVELS[Math.floor(Math.random() * LEVELS.length)];
  const msg   = MESSAGES[Math.floor(Math.random() * MESSAGES.length)];
  const suffix= Math.floor(Math.random() * 99999);
  const ts    = new Date().toISOString();
  return `${ts} [${level}] ${msg}${suffix}\n`;
}

// ── Phase 1: write the bulk file ──────────────────────────────────────────────
const targetBytes = sizeMb * 1024 * 1024;
console.log(`Generating ${sizeMb} MB log file at ${file} ...`);

const ws = fs.createWriteStream(file);
let written = 0;

function writeBatch() {
  let ok = true;
  while (written < targetBytes && ok) {
    const line = randomLine();
    ok = ws.write(line);
    written += Buffer.byteLength(line);
  }
  if (written < targetBytes) {
    ws.once('drain', writeBatch);
  } else {
    ws.end(() => {
      const mb = (written / 1024 / 1024).toFixed(1);
      console.log(`Done — wrote ${mb} MB (${written.toLocaleString()} bytes)`);
      console.log(`Now appending new lines every ${interval} ms ...`);
      appendLoop();
    });
  }
}

writeBatch();

// ── Phase 2: keep appending new lines so the watcher has something to detect ──
function appendLoop() {
  setInterval(() => {
    fs.appendFileSync(file, randomLine());
  }, interval);
}