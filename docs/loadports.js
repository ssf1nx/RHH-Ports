async function loadPorts() {
	const container = document.getElementById('ports-container');
	const countDisplay = document.getElementById('port-count');
	const searchBar = document.getElementById('search-bar');
	const filterDropdown = document.getElementById('genre-filter');
	const availabilityDropdown = document.getElementById('availability-filter');
	const reqFilterDropdown = document.getElementById('requirements-filter');
	const sortDropdown = document.getElementById('sort-select');

	try {
		const res = await fetch('ports.json');
		if (!res.ok) throw new Error('Failed to load ports.json');
		const ports = await res.json();

		if (!ports.length) {
			container.textContent = 'No ports found.';
			return;
		}

		// ------------------------------
		// Populate Genre Dropdown
		// ------------------------------
		const genreSet = new Set();
		ports.forEach(port => (port.genres || []).forEach(genre => genreSet.add(genre)));
		const allGenres = Array.from(genreSet).sort();
		allGenres.forEach(genre => {
			const option = document.createElement('option');
			option.value = genre;
			option.textContent = genre.charAt(0).toUpperCase() + genre.slice(1);
			filterDropdown.appendChild(option);
		});

		// ------------------------------
		// Populate Availability Dropdown
		// ------------------------------
		const availabilitySet = new Set();
		ports.forEach(port => port.availability && availabilitySet.add(port.availability));
		const allAvailability = Array.from(availabilitySet).sort();
		allAvailability.forEach(avail => {
			const option = document.createElement('option');
			option.value = avail;
			option.textContent = ({
				full: 'Ready to run',
				demo: 'Demo files included',
				free: 'Free, files needed'
			}[avail.toLowerCase()] || avail.charAt(0).toUpperCase() + avail.slice(1));
			availabilityDropdown.appendChild(option);
		});

		// ------------------------------
		// Populate Requirements Dropdown
		// ------------------------------
		const reqSet = new Set();
		ports.forEach(port => {
			(port.requirements?.split(',').map(r => r.trim().toLowerCase()) || []).forEach(r => {
				if (!r) return;
				if (r.startsWith('analog_')) r = 'analog';
				reqSet.add(r);
			});
		});

		let allReqs = Array.from(reqSet);

		// Define custom order
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

		// Sort `allReqs` according to custom order
		allReqs.sort((a, b) => {
			const indexA = reqOrder.indexOf(a.toLowerCase());
			const indexB = reqOrder.indexOf(b.toLowerCase());
			if (indexA === -1 && indexB === -1) return a.localeCompare(b);
			if (indexA === -1) return 1;
			if (indexB === -1) return -1;
			return indexA - indexB;
		});

		// Populate dropdown
		allReqs.forEach(req => {
			const option = document.createElement('option');
			option.value = req;
			option.textContent = ({
				'!lowpower': 'Needs moderate CPU',
				'!lowres': 'Needs minimum 640x480 resolution',
				'hires': 'Best on high resolution',
				'power': 'Needs high CPU power',
				'2gb': 'Needs 2GB RAM',
				'ultra': 'Needs > 2GB RAM',
				'opengl': 'Requires mainline OpenGL',
				'wide': 'Requires widescreen',
				'analog': 'Requires analog sticks',
				'!arkos': 'Won’t run on ArkOS'
			}[req.toLowerCase()] || req.charAt(0).toUpperCase() + req.slice(1));
			reqFilterDropdown.appendChild(option);
		});

		// ------------------------------
		// Sorting Function
		// ------------------------------
		function sortPorts(list, method) {
			if (method === 'most_recent') {
				return list.slice().sort((a, b) => new Date(b.last_modified || 0) - new Date(a.last_modified || 0));
			}
			return list.slice().sort((a, b) => a.title.localeCompare(b.title));
		}

		// ------------------------------
		// Render Function
		// ------------------------------
		function render(filteredPorts) {
			container.innerHTML = '';

			const genreVal = filterDropdown.value;
			const availabilityVal = availabilityDropdown.value;
			const reqVal = reqFilterDropdown.value;

			let countText = `${filteredPorts.length} released ports`;
			if (genreVal !== 'all') {
				const genreText = filterDropdown.options[filterDropdown.selectedIndex].text;
				countText += ` in genre "${genreText}"`;
			}
			if (availabilityVal !== 'all') {
				const availText = availabilityDropdown.options[availabilityDropdown.selectedIndex].text;
				countText += ` with availability "${availText}"`;
			}
			if (reqVal !== 'all') {
				countText += ` requiring "${reqVal}"`;
			}

			countDisplay.textContent = countText;

			for (const port of filteredPorts) {
				const card = document.createElement('div');
				card.className = 'port-card';

				const img = document.createElement('img');
				img.src = port.screenshot_url;
				img.alt = `${port.title} screenshot`;
				card.appendChild(img);

				const info = document.createElement('div');
				info.className = 'port-info';

				const title = document.createElement('h2');
				title.className = 'port-title';
				title.textContent = port.title;
				info.appendChild(title);

				const desc = document.createElement('p');
				desc.className = 'port-desc';
				desc.textContent = port.description;
				info.appendChild(desc);

				const footer = document.createElement('div');
				footer.className = 'port-footer';

				if (port.requirements) {
					const reqs = document.createElement('div');
					reqs.className = 'port-reqs';
					reqs.textContent = port.requirements;
					footer.appendChild(reqs);
				}

				if (port.genres?.length) {
					const genres = document.createElement('div');
					genres.className = 'port-genres';
					genres.textContent = port.genres.join(', ');
					footer.appendChild(genres);
				}

				const buttons = document.createElement('div');
				buttons.className = 'port-buttons';

				const details = document.createElement('a');
				details.className = 'details-link';
				details.href = port.download_url;
				details.target = '_blank';
				details.rel = 'noopener noreferrer';
				details.textContent = 'Details';

				const download = document.createElement('a');
				download.className = 'download-link';
				download.href = `https://download-directory.github.io/?url=${encodeURIComponent(port.download_url)}`;
				download.target = '_blank';
				download.rel = 'noopener noreferrer';
				download.textContent = 'Download';

				buttons.appendChild(details);
				buttons.appendChild(download);
				footer.appendChild(buttons);

				info.appendChild(footer);
				card.appendChild(info);
				container.appendChild(card);
			}
		}

		// ------------------------------
		// Filter + Sort + Render
		// ------------------------------
		function updateDisplay() {
			const selectedGenre = filterDropdown.value;
			const selectedAvailability = availabilityDropdown.value;
			const selectedReq = reqFilterDropdown.value;
			const searchQuery = searchBar.value.trim().toLowerCase();

			let filtered = ports;

			if (selectedGenre !== 'all') {
				filtered = filtered.filter(port => port.genres?.includes(selectedGenre));
			}
			if (selectedAvailability !== 'all') {
				filtered = filtered.filter(port => port.availability === selectedAvailability);
			}
			if (selectedReq !== 'all') {
				filtered = filtered.filter(port => {
					const portReqs = (port.requirements?.split(',') || [])
						.map(r => r.trim().toLowerCase())
						.map(r => r.startsWith('analog_') ? 'analog' : r);
					return portReqs.includes(selectedReq.toLowerCase());
				});
			}
			if (searchQuery) {
				filtered = filtered.filter(port => port.title.toLowerCase().includes(searchQuery));
			}

			const sortMethod = sortDropdown.value;
			filtered = sortPorts(filtered, sortMethod);

			render(filtered);
		}

		// Initial render
		updateDisplay();

		// Event listeners
		searchBar.addEventListener('input', updateDisplay);
		filterDropdown.addEventListener('change', updateDisplay);
		availabilityDropdown.addEventListener('change', updateDisplay);
		reqFilterDropdown.addEventListener('change', updateDisplay);
		sortDropdown.addEventListener('change', updateDisplay);

	} catch (err) {
		container.textContent = 'Error loading ports: ' + err.message;
	}
}

loadPorts();