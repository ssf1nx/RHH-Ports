const fs = require('fs').promises;
const fsSync = require('fs');
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');

const ports = [];

// -----------------------------------------------------------------------------
// Configuration
const GITHUB_REPO_BASE = 'https://github.com/JeodC/RHH-Ports';
const GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/JeodC/RHH-Ports/main/ports/released';
const PORTS_JSON_FILE = './docs/ports.json';

// -----------------------------------------------------------------------------
// Helpers

async function computePortMd5(portDir) {
    const allFiles = [];

    async function collectFiles(dir) {
        const entries = await fs.readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);

            if (entry.name.startsWith('.') || entry.name.startsWith('._') || ['.git', '.DS_Store'].includes(entry.name)) continue;

            if (entry.isDirectory()) {
                await collectFiles(fullPath);
            } else if (entry.isFile()) {
                allFiles.push(fullPath);
            }
        }
    }

    await collectFiles(portDir);
    allFiles.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));

    const hash = crypto.createHash('md5');
    let totalSize = 0;
    let latestMtime = 0;

    for (const filePath of allFiles) {
        const content = await fs.readFile(filePath);
        const stats = await fs.stat(filePath);

        totalSize += stats.size;
        if (stats.mtimeMs > latestMtime) latestMtime = stats.mtimeMs;

        hash.update(content);
    }

    return { md5: hash.digest('hex'), totalSize, latestMtime };
}

// -----------------------------------------------------------------------------
// Directory Processing

async function processDir(currentDir, baseDir) {
    const entries = await fs.readdir(currentDir, { withFileTypes: true });

    for (const entry of entries) {
        if (!entry.isDirectory()) continue;

        const subDir = path.join(currentDir, entry.name);
        const subEntries = await fs.readdir(subDir, { withFileTypes: true });
        const fileNamesLower = subEntries.filter(f => f.isFile()).map(f => f.name.toLowerCase());

        const portJsonFile = subEntries.find(e => e.isFile() && e.name.toLowerCase() === 'port.json');
        const screenshotFile = subEntries.find(e => {
            const ext = path.extname(e.name).toLowerCase();
            return e.isFile() &&
                   e.name.toLowerCase().startsWith('screenshot') &&
                   ['.png', '.jpg', '.jpeg'].includes(ext);
        });

        if (!portJsonFile || !screenshotFile) {
            await processDir(subDir, baseDir);
            continue;
        }

        const optional = ['readme.md', 'gameinfo.xml'];
        const missing = optional.filter(f => !fileNamesLower.includes(f.toLowerCase()));
        if (missing.length) {
            const folder = path.relative(baseDir, subDir).split(path.sep).join('/');
            const colored = missing.map(f => `\x1b[94m${f}\x1b[0m`).join(', ');
            console.log(`\x1b[33mWarning:\x1b[0m Missing ${colored} in ${folder}`);
        }

        const { md5, totalSize, latestMtime } = await computePortMd5(subDir);

        const portRaw = await fs.readFile(path.join(subDir, 'port.json'), 'utf-8');
        const data = JSON.parse(portRaw);

        const relativeDir = path.relative(baseDir, subDir).split(path.sep).join('/');
        const zipName = path.basename(subDir);

        data.source = {
            date_updated: new Date(latestMtime || Date.now()).toISOString().split('T')[0],
            download_url: `${GITHUB_REPO_BASE}/releases/download/ports-latest/${zipName}.zip`,
            screenshot_url: `${GITHUB_RAW_BASE}/${relativeDir}/${screenshotFile.name}`,
            size: totalSize,
            md5: md5
        };

        ports.push(data);
        await processDir(subDir, baseDir);
    }
}

// -----------------------------------------------------------------------------
// Main

async function main() {
    try {
        const baseDir = path.resolve('./ports/released');
        const outputFile = path.resolve(PORTS_JSON_FILE);
        await processDir(baseDir, baseDir);

        ports.sort((a, b) => {
            const aTitle = (a.attr?.title || a.name || '').toLowerCase();
            const bTitle = (b.attr?.title || b.name || '').toLowerCase();
            return aTitle.localeCompare(bTitle);
        });

        await fs.mkdir(path.dirname(outputFile), { recursive: true });
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
