'use strict';

/**
 * Batches match events that arrive within a time window into a single email.
 * Prevents inbox flooding when many matching lines appear at once.
 *
 * @param {Function} sendFn        - (matches) => Promise<void>
 * @param {number}   windowMs      - Collect matches for this many ms before sending (default 10 s)
 * @param {number}   cooldownMs    - After sending, ignore new matches for this many ms (default 5 min)
 */
function createBatcher(sendFn, windowMs = 10_000, cooldownMs = 300_000) {
  let pending    = [];   // buffered matches waiting to be sent
  let timer      = null; // debounce timer
  let coolingDown = false;

  function flush() {
    if (pending.length === 0) return;

    const batch = [...pending];
    pending     = [];
    timer       = null;

    sendFn(batch).catch((err) => {
      console.error('[log-sentinel] Failed to send alert email:', err.message);
    });

    // Start cooldown
    coolingDown = true;
    setTimeout(() => {
      coolingDown = false;
    }, cooldownMs);
  }

  return {
    /**
     * Add a match to the current batch.
     * @param {{ keyword: string, line: string, file: string }} match
     */
    add(match) {
      if (coolingDown) return; // suppress during cooldown

      pending.push(match);

      // Reset the debounce window
      clearTimeout(timer);
      timer = setTimeout(flush, windowMs);
    },
  };
}

module.exports = { createBatcher };
