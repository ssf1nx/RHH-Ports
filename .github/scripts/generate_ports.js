const fs = require('fs').promises;
const path = require('path');
const readline = require('readline');

const screenshotExtensions = ['.png', '.jpg', '.jpeg'];
const optionalFiles = ['gameinfo.xml', 'README.md'];
const GITHUB_REPO_BASE = 'https://github.com/JeodC/RHH-Ports/tree/main/ports/released';
const GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/JeodC/RHH-Ports/main/ports/released';

const ports = [];

async function processDir(currentDir) {
    const entries = await fs.readdir(currentDir, { withFileTypes: true });

    for (const entry of entries) {
        if (!entry.isDirectory()) continue;

        const subDir = path.join(currentDir, entry.name);
        const subEntries = await fs.readdir(subDir, { withFileTypes: true });
        const fileNames = subEntries.filter(f => f.isFile()).map(f => f.name.toLowerCase());

        const portJsonFile = fileNames.find(f => f === 'port.json');
        const screenshotFile = subEntries.find(
            e =>
                e.isFile() &&
                e.name.toLowerCase().startsWith('screenshot') &&
                screenshotExtensions.includes(path.extname(e.name).toLowerCase())
        );

        // If port.json and screenshot exist, generate port
        if (portJsonFile && screenshotFile) {
            // Warn about missing optional files
            const missingOptional = optionalFiles.filter(f => !fileNames.includes(f.toLowerCase()));
            if (missingOptional.length) {
                const folderName = path.relative(baseDir, subDir).split(path.sep).join('/');
                const missingColored = missingOptional.map(f => `\x1b[94m${f}\x1b[0m`).join(', ');
                console.log(`\x1b[33mWarning:\x1b[0m Missing ${missingColored} in ${folderName}`);
            }

            // Compute latest modification recursively
            let latestMtime = 0;
            async function getLatest(dir) {
                const allEntries = await fs.readdir(dir, { withFileTypes: true });
                for (const e of allEntries) {
                    const fullPath = path.join(dir, e.name);
                    const stat = await fs.stat(fullPath);
                    if (stat.mtimeMs > latestMtime) latestMtime = stat.mtimeMs;
                    if (e.isDirectory()) await getLatest(fullPath);
                }
            }
            await getLatest(subDir);

            const portRaw = await fs.readFile(path.join(subDir, 'port.json'), 'utf-8');
            const data = JSON.parse(portRaw);

            const relativeDir = path.relative(baseDir, subDir).split(path.sep).join('/');
            const downloadDir = path.relative(baseDir, path.dirname(subDir)).split(path.sep).join('/');

            data.source = {
                date_updated: new Date(latestMtime || Date.now()).toISOString().split('T')[0],
                url: `ports/released/${relativeDir}`,
                download_url: `${GITHUB_REPO_BASE}/${downloadDir}`,
                screenshot_url: `${GITHUB_RAW_BASE}/${relativeDir}/${screenshotFile.name}`
            };

            ports.push(data);
        }

        // Recurse into subfolders
        await processDir(subDir);
    }
}

async function main() {
    try {
        global.baseDir = path.resolve('./ports/released');
        const outputFile = path.resolve('./docs/ports.json');

        await processDir(baseDir);

        ports.sort((a, b) => {
            const aTitle = a.attr?.title || a.name || '';
            const bTitle = b.attr?.title || b.name || '';
            return aTitle.toLowerCase().localeCompare(bTitle.toLowerCase());
        });

        await fs.writeFile(outputFile, JSON.stringify(ports, null, 4), 'utf-8');
        console.log(`\x1b[32mGenerated ports.json with ${ports.length} ports.\x1b[0m`);
    } catch (err) {
        console.error('Error:', err);
    } finally {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });
        rl.question('Press Enter to exit...', () => {
            rl.close();
            process.exit(0);
        });
    }
}

main();