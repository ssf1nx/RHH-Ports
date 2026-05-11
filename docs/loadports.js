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

    const mappings = [
        { keys: ['!lowpower'], value: 'Needs moderate CPU' },
        { keys: ['!lowres'], value: 'Needs minimum 640x480 resolution' },
        { keys: ['hires'], value: 'Best on high resolution' },
        { keys: ['power'], value: 'Needs high CPU power' },
        { keys: ['2gb'], value: 'Needs 2GB RAM' },
        { keys: ['4gb', 'ultra'], value: 'Needs > 2GB RAM' },
        { keys: ['opengl'], value: 'Requires mainline OpenGL' },
        { keys: ['vulkan'], value: 'Requires Vulkan' },
        { keys: ['wide'], value: 'Requires widescreen' },
        { keys: ['analog_1', 'analog_2', 'analog_1|analog_2'], value: 'Requires analog sticks' },
        { keys: ['!arkos'], value: 'Won’t run on ArkOS' }
    ];

    try {
        // Fetch data concurrently for speed
        const [res, apiRes] = await Promise.all([
            fetch('ports.json', { cache: 'no-cache' }),
            fetch(`https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases`).catch(() => null)
        ]);

        if (!res.ok) throw new Error('Failed to load ports.json');
        const ports = await res.json();
        const releases = apiRes && apiRes.ok ? await apiRes.json() : [];

        // Map asset download counts
        const downloadCounts = {};
        releases.forEach(release => {
            release.assets.forEach(asset => {
                downloadCounts[asset.name] = asset.download_count;
            });
        });

        // --- Dropdown Population ---
        const populateDropdown = (dropdown, values, mapFn = v => v) => {
            values.forEach(v => {
                const opt = document.createElement('option');
                opt.value = v;
                opt.textContent = mapFn(v);
                dropdown.appendChild(opt);
            });
        };

        const genreSet = new Set(ports.flatMap(p => p.attr?.genres || []));
        populateDropdown(genreDropdown, Array.from(genreSet).sort(), g => g.charAt(0).toUpperCase() + g.slice(1));

        const availabilitySet = new Set(ports.map(p => p.attr?.availability).filter(Boolean));
        populateDropdown(availabilityDropdown, Array.from(availabilitySet).sort(), a =>
            ({ full: 'Ready to run', demo: 'Demo files included', free: 'Free, files needed', paid: "Paid, files needed" }[a.toLowerCase()] || a)
        );

        const keyToLabel = {};
        mappings.forEach(m => m.keys.forEach(k => keyToLabel[k.toLowerCase()] = m.value));

        const reqLabels = new Set();
        ports.forEach(p => (p.attr?.reqs || []).forEach(r => {
            const label = keyToLabel[r.toLowerCase()];
            if (label) reqLabels.add(label);
        }));

        const orderedReqs = mappings.map(m => m.value).filter(v => reqLabels.has(v));
        populateDropdown(requirementsDropdown, orderedReqs);

        if (![...sortDropdown.options].some(o => o.value === 'most_downloaded')) {
            const opt = document.createElement('option');
            opt.value = 'most_downloaded';
            opt.textContent = 'Most Downloaded';
            sortDropdown.appendChild(opt);
        }

        // --- Core Functions ---
        const renderPorts = (filtered) => {
            const genreVal = genreDropdown.value;
            const availabilityVal = availabilityDropdown.value;
            const reqVal = requirementsDropdown.value;

            let countText = `${filtered.length} released ports`;
            if (genreVal !== 'all') countText += ` in "${genreDropdown.selectedOptions[0].text}"`;
            countDisplay.textContent = countText;

            container.innerHTML = filtered.map(port => {
                const title = port.attr.title || port.name;
                const screenshot = port.source.screenshot_url || '';
                const downloadHref = port.source.download_url || '';
                const filename = downloadHref ? downloadHref.split('/').pop() : '';
                const baseLifetime = port.source?.lifetime_downloads ?? 0;
                const downloadCount = downloadCounts?.[filename] ?? 0;
                const totalLifetime = baseLifetime + downloadCount;
                const reqs = (port.attr?.reqs || []).join(', ');
                const genres = (port.attr?.genres || []).join(', ');
                const lastCommit = port.source.last_commit;
                const displayCommit = (!lastCommit || lastCommit.includes('Update ports.json')) 
                    ? "" 
                    : lastCommit;

                return `
                    <div class="port-card">
                        <img src="${screenshot}" alt="${title} screenshot" loading="lazy">
                        <div class="port-info">
                            <h2 class="port-title">${title}</h2>
                            <p class="port-desc">${port.attr.desc || ''}</p>
                            <div class="port-footer">
                                <p class="download-count">
                                    <strong>Downloads since last update:</strong> ${downloadCount}</br>
                                    <strong>Total Downloads:</strong> ${totalLifetime}
                                </p>
                                ${reqs ? `<div class="port-reqs">${reqs}</div>` : ''}
                                ${genres ? `<div class="port-genres">${genres}</div>` : ''}
                                ${displayCommit ? `<div class="port-commit-banner" title="${displayCommit}">${displayCommit}</div>` : ''}
                                <div class="port-buttons">
                                    <a class="details-link" href="${port.source.readme_url || ''}" target="_blank" rel="noopener noreferrer">Details</a>
                                    <a class="download-link" href="${downloadHref}" target="_blank" rel="noopener noreferrer">Download</a>
                                </div>
                            </div>
                        </div>
                    </div>`;
            }).join('');
        };

        const updateDisplay = () => {
            const genre = genreDropdown.value;
            const availability = availabilityDropdown.value;
            const reqLabel = requirementsDropdown.value;
            const query = searchBar.value.trim().toLowerCase();

            const filtered = ports.filter(p => {
                const pReqs = (p.attr?.reqs || []).map(r => r.toLowerCase());
                if (genre !== 'all' && !p.attr?.genres?.includes(genre)) return false;
                if (availability !== 'all' && p.attr?.availability !== availability) return false;
                
                // Fixed requirements check
                if (reqLabel !== 'all') {
                    const mapsToSelected = pReqs.some(key => keyToLabel[key] === reqLabel);
                    if (!mapsToSelected) return false;
                }

                if (query && !(p.attr.title || '').toLowerCase().includes(query)) return false;
                return true;
            });

            // Sorting
            const method = sortDropdown.value;
            const sorted = [...filtered].sort((a, b) => {
                if (method === 'most_recent') {
                    return new Date(b.source?.date_updated) - new Date(a.source?.date_updated);
                } else if (method === 'most_downloaded') {
                    const keyA = a.source?.download_url?.split('/').pop();
                    const keyB = b.source?.download_url?.split('/').pop();
                    const countA = (a.source?.lifetime_downloads ?? 0) + (downloadCounts?.[keyA] ?? 0); 
                    const countB = (b.source?.lifetime_downloads ?? 0) + (downloadCounts?.[keyB] ?? 0);
                    return countB - countA;
                }
                return (a.attr?.title || '').localeCompare(b.attr?.title || '');
            });

            renderPorts(sorted);
        };

        // Listeners
        [searchBar, genreDropdown, availabilityDropdown, requirementsDropdown, sortDropdown]
            .forEach(el => el.addEventListener('input', updateDisplay));

        updateDisplay();

    } catch (err) {
        container.textContent = 'Error loading ports: ' + err.message;
    }
}

loadPorts();
