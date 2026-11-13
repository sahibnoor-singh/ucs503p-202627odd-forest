// Runs every *.test.js with Node's built-in test runner. Lists the files itself
// so it works on Node 18+ and in Windows shells (no glob support needed).
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const files = fs.readdirSync(__dirname).filter((f) => f.endsWith('.test.js')).sort().map((f) => path.join(__dirname, f));
const result = spawnSync(process.execPath, ['--test', ...files], { stdio: 'inherit' });
process.exit(result.status === null ? 1 : result.status);
