const { watchLog } = require("../src/watcher.js");
const path = require('path');

watchLog(path.join(__dirname, 'tmp/test.log'), ["ERROR", "500"], (kw, line) => {
  const ts = new Date().toISOString();
  console.log(`\x1b[31m[${ts}] MATCH: ${kw}\x1b[0m`);
  console.log(`  → ${line}`);
});
