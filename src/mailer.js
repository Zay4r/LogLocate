'use strict';

const net = require('net');
const tls = require('tls');
const { Buffer } = require('buffer');

/**
 * Minimal raw-SMTP client. Supports:
 *   - Port 465  → direct TLS (SSL)
 *   - Port 587  → plain then STARTTLS upgrade
 *   - Port 25   → plain SMTP (no TLS, for local relay)
 *
 * No third-party libraries used.
 */

function base64(str) {
  return Buffer.from(str, 'utf8').toString('base64');
}

/**
 * Send a single email over raw SMTP.
 *
 * @param {object} opts
 * @param {string}   opts.host       - SMTP host (e.g. smtp.gmail.com)
 * @param {number}   opts.port       - 465 | 587 | 25
 * @param {string}   opts.user       - SMTP login username
 * @param {string}   opts.pass       - SMTP login password / app-password
 * @param {string}   opts.from       - Sender address
 * @param {string[]} opts.to         - Array of recipient addresses
 * @param {string}   opts.subject    - Email subject
 * @param {string}   opts.body       - Plain-text email body
 * @returns {Promise<void>}
 */
function sendMail({ host, port, user, pass, from, to, subject, body }) {
  return new Promise((resolve, reject) => {
    const useSsl       = port === 465;
    const useStarttls  = port === 587;

    // Encode recipients for the DATA headers
    const toHeader = to.join(', ');

    // Build RFC-2822 message
    const date    = new Date().toUTCString();
    const message = [
      `Date: ${date}`,
      `From: ${from}`,
      `To: ${toHeader}`,
      `Subject: ${subject}`,
      `MIME-Version: 1.0`,
      `Content-Type: text/plain; charset=UTF-8`,
      ``,
      body,
    ].join('\r\n');

    let socket;
    let upgraded = false;   // whether STARTTLS upgrade has happened
    let buffer   = '';
    let step     = 0;       // conversation state machine index

    // SMTP conversation steps (written after each expected server response)
    const steps = [
      // 0 — greeting received → send EHLO
      () => send(`EHLO localhost`),
      // 1 — EHLO response → either STARTTLS or go straight to AUTH
      () => {
        if (useStarttls && !upgraded) {
          send('STARTTLS');
        } else {
          send('AUTH LOGIN');
        }
      },
      // 2 — STARTTLS/AUTH LOGIN response
      () => {
        if (useStarttls && !upgraded) {
          // Upgrade the socket to TLS in-place
          upgradeToTls();
        } else {
          send(base64(user));
        }
      },
      // 3 — username prompt (334) → send username, or re-EHLO after TLS upgrade
      () => send(base64(user)),
      // 4 — password prompt (334) → send password
      () => send(base64(pass)),
      // 5 — AUTH OK (235) → MAIL FROM
      () => send(`MAIL FROM:<${from}>`),
      // 6 — MAIL FROM OK → RCPT TO (loop all recipients)
      () => {
        const rcptCommands = to.map(addr => `RCPT TO:<${addr}>`);
        sendSequential(rcptCommands, () => {
          step = 7;
          send('DATA');
        });
      },
      // 7 — DATA prompt (354) → send message body
      () => send(`${message}\r\n.`),
      // 8 — message accepted (250) → QUIT
      () => send('QUIT'),
      // 9 — goodbye → close
      () => socket.destroy(),
    ];

    function send(cmd) {
      socket.write(cmd + '\r\n');
    }

    // Send an array of commands one-by-one without waiting for server ACK between them.
    // Used for multiple RCPT TO lines. Calls done() when finished.
    function sendSequential(cmds, done) {
      for (const cmd of cmds) send(cmd);
      done();
    }

    function advance() {
      if (step < steps.length) {
        const fn = steps[step++];
        fn();
      }
    }

    function upgradeToTls() {
      const plain = socket;
      socket = tls.connect({ socket: plain, host, servername: host }, () => {
        upgraded = true;
        buffer   = '';
        step     = 1; // re-run EHLO over the encrypted channel
        send(`EHLO localhost`);
      });
      socket.on('data', onData);
      socket.on('error', reject);
    }

    function onData(chunk) {
      buffer += chunk.toString();

      // SMTP responses can be multi-line; wait until we have a complete one.
      // A complete response line looks like: "NNN text\r\n" (no dash after code).
      const lines = buffer.split('\r\n');
      buffer = lines.pop(); // keep the incomplete tail

      for (const line of lines) {
        if (!line) continue;

        const code = parseInt(line.slice(0, 3), 10);
        const isLast = line[3] !== '-'; // dash = multi-line continuation

        if (!isLast) continue; // wait for the final line of a multi-line response

        if (code >= 400) {
          reject(new Error(`SMTP error ${code}: ${line}`));
          socket.destroy();
          return;
        }

        // Special case: after STARTTLS (220) the TLS handshake handles the advance
        if (code === 220 && step === 3 && useStarttls && !upgraded) {
          upgradeToTls();
          return;
        }

        advance();
      }
    }

    // --- Open the socket ---
    if (useSsl) {
      socket = tls.connect({ host, port, servername: host }, () => {});
    } else {
      socket = net.connect({ host, port });
    }

    socket.on('data', onData);
    socket.on('close', resolve);
    socket.on('error', reject);
    socket.setTimeout(15000, () => {
      reject(new Error('SMTP connection timed out'));
      socket.destroy();
    });
  });
}

module.exports = { sendMail };
