'use strict';

const { watchLog }     = require('./src/watcher');
const { sendMail }     = require('./src/mailer');
const { createBatcher } = require('./src/batcher');

/**
 * Start monitoring a log file and send email alerts on keyword matches.
 *
 * @param {object}   config
 * @param {string}   config.file              - Path to the log file to watch
 * @param {string[]} config.keywords          - Keywords that trigger an alert
 * @param {string[]} config.to                - Recipient email addresses
 *
 * @param {object}   config.smtp              - SMTP credentials
 * @param {string}   config.smtp.host         - e.g. "smtp.gmail.com"
 * @param {number}   config.smtp.port         - 465 (SSL) | 587 (STARTTLS) | 25
 * @param {string}   config.smtp.user         - SMTP username
 * @param {string}   config.smtp.pass         - SMTP password / app-password
 * @param {string}   config.smtp.from         - Sender address (defaults to smtp.user)
 *
 * @param {number}   [config.batchWindowMs=10000]   - ms to collect hits before sending (default 10 s)
 * @param {number}   [config.cooldownMs=300000]      - ms to suppress alerts after sending (default 5 min)
 * @param {number}   [config.pollIntervalMs=1000]    - file polling interval in ms (default 1 s)
 *
 * @returns {{ stop: Function }}
 */
function sentinel(config) {
  const {
    file,
    keywords,
    to,
    smtp,
    batchWindowMs  = 10_000,
    cooldownMs     = 300_000,
    pollIntervalMs = 1_000,
  } = config;

  if (!file)              throw new Error('config.file is required');
  if (!keywords?.length)  throw new Error('config.keywords must be a non-empty array');
  if (!to?.length)        throw new Error('config.to must be a non-empty array of email addresses');
  if (!smtp?.host)        throw new Error('config.smtp.host is required');
  if (!smtp?.user)        throw new Error('config.smtp.user is required');
  if (!smtp?.pass)        throw new Error('config.smtp.pass is required');

  const from = smtp.from || smtp.user;

  // Create the batcher — it collects matches and fires one email per window
  const batcher = createBatcher(async (matches) => {
    const subject = `[log-sentinel] ${matches.length} alert(s) in ${file}`;

    const body = [
      `log-sentinel detected keyword matches in: ${file}`,
      `Time: ${new Date().toISOString()}`,
      ``,
      ...matches.map(
        (m, i) => `#${i + 1} keyword="${m.keyword}"\n    ${m.line}`
      ),
      ``,
      `-- log-sentinel`,
    ].join('\n');

    await sendMail({
      host:    smtp.host,
      port:    smtp.port || 587,
      user:    smtp.user,
      pass:    smtp.pass,
      from,
      to,
      subject,
      body,
    });

    console.log(`[log-sentinel] Alert email sent to: ${to.join(', ')}`);
  }, batchWindowMs, cooldownMs);

  // Start the file watcher
  const watcher = watchLog(file, keywords, (keyword, line, filePath) => {
    console.log(`[log-sentinel] Match — keyword="${keyword}" line="${line}"`);
    batcher.add({ keyword, line, file: filePath });
  }, pollIntervalMs);

  return { stop: watcher.stop };
}

module.exports = { sentinel };
