async function loadPorts() {
    const container = document.getElementById('ports-container');
    const countDisplay = document.getElementById('port-count');
    const searchBar = document.getElementById('search-bar');
    const genreDropdown = document.getElementById('genre-filter');
    const availabilityDropdown = document.getElementById('availability-filter');
    const requirementsDropdown = document.getElementById('requirements-filter');
    const sortDropdown = document.getElementById('sort-select');
    const GITHUB_REPO_BASE = 'https://github.com/JeodC/RHH-Ports/tree/main/';

    try {
        const res = await fetch('ports.json');
        if (!res.ok) throw new Error('Failed to load ports.json');
        const ports = await res.json();

        if (!ports.length) {
            container.textContent = 'No ports found.';
            return;
        }

        // ------------------------------
        // Helper to populate dropdowns
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
        const reqSet = new Set();
        ports.forEach(p => (p.attr?.reqs || []).forEach(r => reqSet.add(r.replace(/^analog_/, 'analog').toLowerCase())));
        const reqOrder = [
            '!lowpower',
            'power',
            '!lowres',
            'hires',
            '2gb',
            'ultra',
            'opengl',
            'wide',
            'analog',
            '!arkos'
        ];
        const reqMap = {
            '!lowpower':'Needs moderate CPU',
            '!lowres':'Needs minimum 640x480 resolution',
            'hires':'Best on high resolution',
            'power':'Needs high CPU power',
            '2gb':'Needs 2GB RAM',
            'ultra':'Needs > 2GB RAM',
            'opengl':'Requires mainline OpenGL',
            'wide':'Requires widescreen',
            'analog':'Requires analog sticks',
            '!arkos':'Won’t run on ArkOS'
        };
        const allReqs = Array.from(reqSet).sort((a,b) => {
            const iA = reqOrder.indexOf(a), iB = reqOrder.indexOf(b);
            if(iA===-1 && iB===-1) return a.localeCompare(b);
            if(iA===-1) return 1;
            if(iB===-1) return -1;
            return iA-iB;
        });
        populateDropdown(requirementsDropdown, allReqs, r => reqMap[r] || r);

        // ------------------------------
        // Sorting Function
        // ------------------------------
        const sortPorts = (list, method) => method === 'most_recent'
            ? [...list].sort((a,b) => new Date(b.source?.date_updated) - new Date(a.source?.date_updated))
            : [...list].sort((a,b) => (a.attr?.title || '').localeCompare(b.attr?.title || ''));

        // ------------------------------
        // Render Function
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
                const detailsHref = `${GITHUB_REPO_BASE}/${port.source.url}`;

                // Use last folder of download_url as filename
                let downloadFolderName = 'download';
                if (port.source.download_url) {
                    downloadFolderName = port.source.download_url.replace(/\/+$/, '').split('/').pop();
                }
                const downloadHref = port.source.download_url;

                const reqs = (port.attr?.reqs || []).join(', ');
                const genres = (port.attr?.genres || []).join(', ');

                return `
                    <div class="port-card">
                        <img src="${screenshot}" alt="${title} screenshot">
                        <div class="port-info">
                            <h2 class="port-title">${title}</h2>
                            <p class="port-desc">${desc}</p>
                            <div class="port-footer">
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

        // Initial render
        updateDisplay();

        // Event listeners
        [searchBar, genreDropdown, availabilityDropdown, requirementsDropdown, sortDropdown]
            .forEach(el => el.addEventListener('input', updateDisplay));

    } catch(err) {
        container.textContent = 'Error loading ports: ' + err.message;
    }
}

loadPorts();
