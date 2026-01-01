async function loadPorts() {
    const container = document.getElementById('ports-container');
    const countDisplay = document.getElementById('port-count');
    const searchBar = document.getElementById('search-bar');
    const genreDropdown = document.getElementById('genre-filter');
    const availabilityDropdown = document.getElementById('availability-filter');
    const requirementsDropdown = document.getElementById('requirements-filter');
    const sortDropdown = document.getElementById('sort-select');
    const GITHUB_REPO_OWNER = 'JeodC';
    const GITHUB_REPO_NAME = 'RHH-Ports';

    try {
        // ------------------------------
        // Load ports.json
        // ------------------------------
        const res = await fetch('ports.json');
        if (!res.ok) throw new Error('Failed to load ports.json');
        const ports = await res.json();

        if (!ports.length) {
            container.textContent = 'No ports found.';
            return;
        }

        // ------------------------------
        // Fetch GitHub releases for download counts
        // ------------------------------
        const apiRes = await fetch(`https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases`);
        if (!apiRes.ok) throw new Error('Failed to fetch GitHub releases');
        const releases = await apiRes.json();

        // Map asset download counts by filename
        const downloadCounts = {};
        releases.forEach(release => {
            release.assets.forEach(asset => {
                downloadCounts[asset.name] = asset.download_count;
            });
        });

        // ------------------------------
        // Populate Dropdown Helper
        // ------------------------------
        const populateDropdown = (dropdown, values, mapFn = v => v) => {
            values.forEach(v => {
                const opt = document.createElement('option');
                opt.value = v;
                opt.textContent = mapFn(v);
                dropdown.appendChild(opt);
            });
        };

        // ------------------------------
        // Populate Genre Dropdown
        // ------------------------------
        const genreSet = new Set(ports.flatMap(p => p.attr?.genres || []));
        populateDropdown(genreDropdown, Array.from(genreSet).sort(), g => g.charAt(0).toUpperCase() + g.slice(1));

        // ------------------------------
        // Populate Availability Dropdown
        // ------------------------------
        const availabilitySet = new Set(ports.map(p => p.attr?.availability).filter(Boolean));
        populateDropdown(availabilityDropdown, Array.from(availabilitySet).sort(), a =>
            ({ full: 'Ready to run', demo: 'Demo files included', free: 'Free, files needed' }[a.toLowerCase()] || a)
        );

        // ------------------------------
        // Populate Requirements Dropdown
        // ------------------------------

        // Define mappings with multiple keys per value
        const mappings = [
            { keys: ['!lowpower'], value: 'Needs moderate CPU' },
            { keys: ['!lowres'], value: 'Needs minimum 640x480 resolution' },
            { keys: ['hires'], value: 'Best on high resolution' },
            { keys: ['power'], value: 'Needs high CPU power' },
            { keys: ['2gb'], value: 'Needs 2GB RAM' },
            { keys: ['4gb','ultra'], value: 'Needs > 2GB RAM' },
            { keys: ['opengl'], value: 'Requires mainline OpenGL' },
            { keys: ['wide'], value: 'Requires widescreen' },
            { keys: ['analog1', 'analog2'], value: 'Requires analog sticks' },
            { keys: ['!arkos'], value: 'Won’t run on ArkOS' }
        ];

        // Generate keyword → value map
        const reqMap = {};
        mappings.forEach(entry => entry.keys.forEach(k => reqMap[k] = entry.value));

        // Generate display order using the first key from each mapping
        const reqOrder = mappings.flatMap(entry => entry.keys);

        // Build unique set of keywords from ports
        const reqSet = new Set();
        ports.forEach(p => (p.attr?.reqs || []).forEach(r =>
            reqSet.add(r.replace(/^analog_/, 'analog').toLowerCase())
        ));

        // Map keywords to descriptions and deduplicate
        const allReqs = Array.from(reqSet)
            .map(k => reqMap[k] || k)          // map to descriptions
            .filter((v, i, a) => a.indexOf(v) === i) // remove duplicates
            .sort((a,b) => {
                const getIndex = desc => {
                    const entry = mappings.find(m => m.value === desc);
                    if(!entry) return 999; // unknown descriptions go last
                    return reqOrder.indexOf(entry.keys[0]);
                };
                return getIndex(a) - getIndex(b);
            });

        // Populate dropdown
        populateDropdown(requirementsDropdown, allReqs, r => r);

        // ------------------------------
        // Add "Most Downloaded" option to sort dropdown if missing
        // ------------------------------
        if (![...sortDropdown.options].some(o => o.value === 'most_downloaded')) {
            const opt = document.createElement('option');
            opt.value = 'most_downloaded';
            opt.textContent = 'Most Downloaded';
            sortDropdown.appendChild(opt);
        }

        // ------------------------------
        // Sorting Function
        // ------------------------------
        const sortPorts = (list, method) => {
            if (method === 'most_recent') {
                return [...list].sort((a,b) => new Date(b.source?.date_updated) - new Date(a.source?.date_updated));
            } else if (method === 'most_downloaded') {
                return [...list].sort((a,b) => {
                    const fileA = a.source.download_url ? a.source.download_url.split('/').pop() : '';
                    const fileB = b.source.download_url ? b.source.download_url.split('/').pop() : '';
                    const countA = downloadCounts[fileA] || 0;
                    const countB = downloadCounts[fileB] || 0;
                    return countB - countA;
                });
            } else {
                return [...list].sort((a,b) => (a.attr?.title || '').localeCompare(b.attr?.title || ''));
            }
        };

        // ------------------------------
        // Render Ports Function
        // ------------------------------
        const renderPorts = (filtered) => {
            const genreVal = genreDropdown.value;
            const availabilityVal = availabilityDropdown.value;
            const reqVal = requirementsDropdown.value;

            let countText = `${filtered.length} released ports`;
            if (genreVal !== 'all') countText += ` in genre "${genreDropdown.selectedOptions[0].text}"`;
            if (availabilityVal !== 'all') countText += ` with availability "${availabilityDropdown.selectedOptions[0].text}"`;
            if (reqVal !== 'all') countText += ` requiring "${reqVal}"`;
            countDisplay.textContent = countText;

            container.innerHTML = filtered.map(port => {
                const title = port.attr.title || port.name;
                const desc = port.attr.desc || '';
                const screenshot = port.source.screenshot_url || '';
                const detailsHref = port.source.readme_url || '';
                const downloadHref = port.source.download_url || '';
                
                const filename = downloadHref ? downloadHref.split('/').pop() : '';
                const downloadCount = downloadCounts[filename] || 0;

                const reqs = (port.attr?.reqs || []).join(', ');
                const genres = (port.attr?.genres || []).join(', ');

                return `
                    <div class="port-card">
                        <img src="${screenshot}" alt="${title} screenshot">
                        <div class="port-info">
                            <h2 class="port-title">${title}</h2>
                            <p class="port-desc">${desc}</p>
                            <div class="port-footer">
                                <p class="download-count"><strong>Downloads since last update:</strong> ${downloadCount}</p>
                                ${reqs ? `<div class="port-reqs">${reqs}</div>` : ''}
                                ${genres ? `<div class="port-genres">${genres}</div>` : ''}
                                <div class="port-buttons">
                                    <a class="details-link" href="${detailsHref}" target="_blank" rel="noopener noreferrer">Details</a>
                                    <a class="download-link" href="${downloadHref}" target="_blank" rel="noopener noreferrer">Download</a>
                                </div>
                            </div>
                        </div>
                    </div>`;
            }).join('');
        };

        // ------------------------------
        // Filter + Display Update
        // ------------------------------
        const updateDisplay = () => {
            const genre = genreDropdown.value;
            const availability = availabilityDropdown.value;
            const req = requirementsDropdown.value;
            const query = searchBar.value.trim().toLowerCase();

            const filtered = ports.filter(p => {
                if (genre !== 'all' && !p.attr?.genres?.includes(genre)) return false;
                if (availability !== 'all' && p.attr?.availability !== availability) return false;
                if (req !== 'all' && !(p.attr?.reqs || []).map(r => r.toLowerCase()).includes(req.toLowerCase())) return false;
                if (query && !(p.attr.title || '').toLowerCase().includes(query)) return false;
                return true;
            });

            renderPorts(sortPorts(filtered, sortDropdown.value));
        };

        // ------------------------------
        // Initial Render & Event Listeners
        // ------------------------------
        updateDisplay();
        [searchBar, genreDropdown, availabilityDropdown, requirementsDropdown, sortDropdown]
            .forEach(el => el.addEventListener('input', updateDisplay));

    } catch(err) {
        container.textContent = 'Error loading ports: ' + err.message;
    }
}

loadPorts();