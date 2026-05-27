'use strict';

const fs = require('fs');
const readline = require('readline');

/**
 * Watch a log file for new lines and trigger a callback when keywords are found.
 * Uses fs.watchFile (polling) so it works across all platforms and NFS mounts.
 *
 * @param {string}   filePath  - Absolute path to the log file
 * @param {string[]} keywords  - Keywords to scan each new line for
 * @param {Function} onMatch   - Called with (keyword, line, filePath) on a match
 * @param {number}   [interval=1000] - Polling interval in ms
 * @returns {{ stop: Function }} - Call stop() to unwatch
 */
function watchLog(filePath, keywords, onMatch, interval = 1000) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Log file not found: ${filePath}`);
  }

  // Start reading from the END of the file so we only catch NEW lines
  let lastSize = fs.statSync(filePath).size;

  function checkFile(curr, prev) {
    // File was truncated/rotated — reset position
    if (curr.size < prev.size) {
      console.log(`[log-sentinel] File rotated or truncated: ${filePath}`);
      lastSize = 0;
    }

    // No new data
    if (curr.size === lastSize) return;

    // Read only the new bytes appended since last check
    const stream = fs.createReadStream(filePath, {
      start: lastSize,
      end: curr.size - 1,
      encoding: 'utf8',
    });

    lastSize = curr.size;

    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

    rl.on('line', (line) => {
      if (!line.trim()) return;

      for (const keyword of keywords) {
        if (line.includes(keyword)) {
          onMatch(keyword, line, filePath);
          break; // One alert per line, even if multiple keywords match
        }
      }
    });
  }

  fs.watchFile(filePath, { persistent: true, interval }, checkFile);

  console.log(`[log-sentinel] Watching: ${filePath}`);
  console.log(`[log-sentinel] Keywords: ${keywords.join(', ')}`);

  return {
    stop() {
      fs.unwatchFile(filePath, checkFile);
      console.log(`[log-sentinel] Stopped watching: ${filePath}`);
    },
  };
}

module.exports = { watchLog };
