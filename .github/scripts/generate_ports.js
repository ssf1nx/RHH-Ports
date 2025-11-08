const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');
const ports = [];

// ---------------------------------------------------------------------
// Configuration
const SKIP_NAMES = ['.', '..', '.git', '.DS_Store', '.gitignore', '.gitkeep'];
const GITHUB_REPO_BASE = 'https://github.com/JeodC/RHH-Ports/tree/main/ports/released';
const GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/JeodC/RHH-Ports/main/ports/released';

// ---------------------------------------------------------------------
async function getPortStats(portDir, portName) {

  let latestMtime = 0;
  let totalSize = 0;
  const md5List = [];

  async function recurse(dir) {
    const entries = await fs.readdir(dir, { withFileTypes: true });

    for (const e of entries) {
      const fullPath = path.join(dir, e.name);
      const stat = await fs.stat(fullPath);

      // ---- mtime -------------------------------------------------------
      if (stat.mtimeMs > latestMtime) latestMtime = stat.mtimeMs;

      // ---- directories -------------------------------------------------
      if (e.isDirectory()) {
        await recurse(fullPath);
        continue;
      }

      // ---- skip list ------------------------
      if (SKIP_NAMES.includes(e.name)) continue;
      if (e.name.startsWith('._')) continue; // AppleDouble
      // large-file parts (".part.001" etc.)
      if (e.name.slice(-9, -3) === '.part.' && /^\d{3}$/.test(e.name.slice(-3))) continue;

      // ---- include *every* regular file --------------------------------
      const relPath = path.relative(portDir, fullPath).split(path.sep).join('/');
      const buffer = await fs.readFile(fullPath);
      const fileMd5 = crypto.createHash('md5').update(buffer).digest('hex');

      md5List.push({ name: relPath, md5: fileMd5 });
      totalSize += stat.size;
    }
  }

  await recurse(portDir);

  // ---- deterministic order (case-insensitive) -----------------------
  md5List.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));

  // ---- combined MD5 (MD5 of concatenated file-MD5s) -----------------
  const combinedStr = md5List.map(f => f.md5).join('');
  const combinedMd5 = crypto.createHash('md5').update(combinedStr).digest('hex');

  return { latestMtime, totalSize, md5: combinedMd5 };
}

// ---------------------------------------------------------------------
async function processDir(currentDir, baseDir) {
  const entries = await fs.readdir(currentDir, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const subDir = path.join(currentDir, entry.name);
    const subEntries = await fs.readdir(subDir, { withFileTypes: true });
    const fileNamesLower = subEntries.filter(f => f.isFile()).map(f => f.name.toLowerCase());

    // Required files
    const portJsonFile = subEntries.find(e => e.isFile() && e.name.toLowerCase() === 'port.json');
    const screenshotFile = subEntries.find(e => {
      const ext = path.extname(e.name).toLowerCase();
      return e.isFile() &&
             e.name.toLowerCase().startsWith('screenshot') &&
             ['.png', '.jpg', '.jpeg'].includes(ext);
    });

    if (!portJsonFile || !screenshotFile) {
      // Not a valid port
      await processDir(subDir, baseDir);
      continue;
    }

    // ---- optional-file warnings ------------
    const optional = ['readme.md', 'gameinfo.xml'];
    const missing = optional.filter(f => !fileNamesLower.includes(f.toLowerCase()));
    if (missing.length) {
      const folder = path.relative(baseDir, subDir).split(path.sep).join('/');
      const colored = missing.map(f => `\x1b[94m${f}\x1b[0m`).join(', ');
      console.log(`\x1b[33mWarning:\x1b[0m Missing ${colored} in ${folder}`);
    }

    // ---- stats -------------------------------------------------------
    const { latestMtime, totalSize, md5 } = await getPortStats(subDir, entry.name);

    // ---- read port.json ---------------------------------------------
    const portRaw = await fs.readFile(path.join(subDir, 'port.json'), 'utf-8');
    const data = JSON.parse(portRaw);

    // ---- build source object -------------------
    const relativeDir = path.relative(baseDir, subDir).split(path.sep).join('/');
    const downloadDir = path.relative(baseDir, path.dirname(subDir)).split(path.sep).join('/');

    data.source = {
      date_updated: new Date(latestMtime || Date.now()).toISOString().split('T')[0],
      download_url: `${GITHUB_REPO_BASE}/${downloadDir}`,
      screenshot_url: `${GITHUB_RAW_BASE}/${relativeDir}/${screenshotFile.name}`,
      size: totalSize,
      md5: md5
    };

    ports.push(data);

    // Recurse into sub-folders
    await processDir(subDir, baseDir);
  }
}

// ---------------------------------------------------------------------
async function main() {
  try {
    const baseDir = path.resolve('./ports/released');
    global.baseDir = baseDir;
    const outputFile = path.resolve('./docs/ports.json');
    await processDir(baseDir, baseDir);

    // sort by title
    ports.sort((a, b) => {
      const aTitle = (a.attr?.title || a.name || '').toLowerCase();
      const bTitle = (b.attr?.title || b.name || '').toLowerCase();
      return aTitle.localeCompare(bTitle);
    });

    await fs.writeFile(outputFile, JSON.stringify(ports, null, 4), 'utf-8');
    console.log(`\x1b[32mGenerated ports.json with ${ports.length} ports.\x1b[0m`);
  } catch (err) {
    console.error('Error:', err);
  } finally {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question('Press Enter to exit...', () => rl.close());
  }
}

main();