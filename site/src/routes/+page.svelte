<script lang="ts">
	import { onMount } from 'svelte';
	import { screens, featureGroups, faqs } from '#lib/content.js';
	let scrolled = $state(false);
	let activeSection = $state('');
	let header: HTMLElement;
	let atlas: HTMLDivElement;

	onMount(() => {
		const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
		const sections = Array.from(
			document.querySelectorAll<HTMLElement>('#ways-to-play, #inside, #features, #begin')
		);
		let frame = 0;
		const update = () => {
			frame = 0;
			const y = window.scrollY;
			scrolled = y > 24;
			const range = document.documentElement.scrollHeight - window.innerHeight;
			header.style.setProperty('--read-progress', String(range > 0 ? Math.min(y / range, 1) : 0));
			atlas.style.setProperty('--drift', motion.matches ? '0px' : `${Math.min(y, 900) * 0.09}px`);
			activeSection =
				sections.filter((section) => section.getBoundingClientRect().top <= 160).at(-1)?.id ?? '';
		};
		const schedule = () => {
			if (!frame) frame = requestAnimationFrame(update);
		};
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) {
						entry.target.classList.add('is-visible');
						observer.unobserve(entry.target);
					}
				}
			},
			{ threshold: 0.08, rootMargin: '0px 0px -24px 0px' }
		);
		const reveals = document.querySelectorAll<HTMLElement>(
			'.section-heading, .mode, .screen-tour, .living-copy, .memory-showcase, .studio-grid article, .rules-grid, .feature-index, .faq, .begin'
		);
		for (const element of reveals) {
			// Keep the initial viewport visible and progressively enhance content below it.
			if (element.getBoundingClientRect().top >= window.innerHeight && !motion.matches) {
				element.classList.add('scroll-reveal');
				observer.observe(element);
			}
		}
		const resize = new ResizeObserver(schedule);
		resize.observe(document.body);
		window.addEventListener('scroll', schedule, { passive: true });
		window.addEventListener('resize', schedule);
		motion.addEventListener('change', schedule);
		update();
		return () => {
			cancelAnimationFrame(frame);
			observer.disconnect();
			resize.disconnect();
			window.removeEventListener('scroll', schedule);
			window.removeEventListener('resize', schedule);
			motion.removeEventListener('change', schedule);
		};
	});
	let selected = $state(0);
	let menuOpen = $state(false);
	let query = $state('');
	let lightbox: HTMLDialogElement;
	let enlarged = $state(screens[0]);
	const current = $derived(screens[selected]);
	const filtered = $derived(
		featureGroups
			.map((group) => ({
				...group,
				items: group.items.filter((item) =>
					`${group.title} ${item.join(' ')}`.toLowerCase().includes(query.toLowerCase())
				)
			}))
			.filter((group) => group.items.length)
	);
	function zoom(id: string) {
		enlarged = screens.find((screen) => screen.id === id) ?? screens[0];
		lightbox.showModal();
	}
	function tour(id: string) {
		selected = screens.findIndex((screen) => screen.id === id);
	}
</script>

<svelte:head>
	<title>DnD — A whole world. A party of one.</title>
	<meta
		name="description"
		content="Meet DnD, your pocket companion for solo Dungeons & Dragons and text adventures. Explore real app screens, offline stories, AI adventures, heroes, living worlds, and creative studios."
	/>
	<meta name="theme-color" content="#0c0e12" />
	<meta name="color-scheme" content="dark" />
	<meta property="og:title" content="DnD — A whole world. A party of one." />
	<meta
		property="og:description"
		content="Solo D&D, text adventures, and worlds that remember. Explore the app, screen by screen."
	/>
	<meta property="og:type" content="website" />
</svelte:head>

<a class="skip-link" href="#main">Skip to content</a>
<header class="site-header" bind:this={header} class:scrolled>
	<a class="wordmark" href="#main" aria-label="DnD home"
		><img src="/app-icon.png" alt="" width="38" height="38" />DnD<span>SOLO ADVENTURES</span></a
	>
	<button
		class="menu-toggle"
		aria-expanded={menuOpen}
		aria-controls="navigation"
		onclick={() => (menuOpen = !menuOpen)}>{menuOpen ? 'Close −' : 'Menu +'}</button
	>
	<nav id="navigation" class:open={menuOpen} aria-label="Main navigation">
		<a
			href="#ways-to-play"
			aria-current={activeSection === 'ways-to-play' ? 'location' : undefined}
			onclick={() => (menuOpen = false)}>Ways to play</a
		>
		<a
			href="#inside"
			aria-current={activeSection === 'inside' ? 'location' : undefined}
			onclick={() => (menuOpen = false)}>Inside the app</a
		>
		<a
			href="#features"
			aria-current={activeSection === 'features' ? 'location' : undefined}
			onclick={() => (menuOpen = false)}>Every feature</a
		>
		<a
			class="nav-cta"
			href="#begin"
			aria-current={activeSection === 'begin' ? 'location' : undefined}
			onclick={() => (menuOpen = false)}>Find your adventure <span aria-hidden="true">↗</span></a
		>
	</nav>
</header>

<main id="main">
	<section class="hero wrap" aria-labelledby="hero-title">
		<div class="hero-copy">
			<p class="eyebrow">
				<span class="little-star" aria-hidden="true">✧</span> YOUR POCKET-SIZED ESCAPE
			</p>
			<h1 id="hero-title">A whole world.<br />A party <em>of one.</em></h1>
			<p class="hero-description">
				Follow the strange path. Befriend the unlikely ally. Roll for the impossible. Solo D&D and
				text adventures, wherever you find a moment.
			</p>
			<div class="hero-actions">
				<a class="button primary" href="https://github.com/dagmawibabi/dnd/releases" target="_blank" rel="noreferrer"
					>Step inside the app <span aria-hidden="true">↗</span></a
				><a class="text-link" href="#ways-to-play"
					>Choose your kind of story <span aria-hidden="true">↓</span></a
				>
			</div>
			<p class="quiet-note">
				<span aria-hidden="true">◈</span> Plays offline. AI is an option. The story is yours.
			</p>
		</div>
		<div class="hero-atlas" bind:this={atlas}>
			<div class="orbit orbit-one"></div>
			<div class="orbit orbit-two"></div>
			<span class="atlas-label north">N<br />✧</span><span class="atlas-label atlas-note"
				>UNEXPLORED POSSIBILITIES</span
			>
			<button
				class="phone hero-phone back-phone"
				aria-label="Enlarge the character sheet screenshot"
				onclick={() => zoom('hero')}
				><img
					src="/screens/hero.png"
					alt="Real app character sheet showing Brannoc Ironvein’s stats and portrait"
					width="780"
					height="1688"
				/></button
			>
			<button
				class="phone hero-phone front-phone"
				aria-label="Enlarge the app home screenshot"
				onclick={() => zoom('home')}
				><img
					src="/screens/home.png"
					alt="DnD mobile home screen with a saved adventure, hero, and navigation"
					width="780"
					height="1688"
					fetchpriority="high"
				/></button
			>
			
		</div>
		<div class="hero-foot">
			<span>DUNGEONS & DRAGONS · TEXT ADVENTURES</span><span
				>ACTUAL APP SCREENS <span aria-hidden="true">↗</span></span
			>
		</div>
	</section>

	<section class="ways wrap section-space" id="ways-to-play">
		<div class="section-heading">
			<div>
				<p class="eyebrow">TAKE YOUR OWN PATH</p>
				<h2>What kind of adventure<br />are you in the mood for?</h2>
			</div>
			<p>
				A carefully written quest. A world made up as you go. A completely different genre. There’s
				more than one way in.
			</p>
		</div>
		<div class="mode-grid">
			<article class="mode">
				<span class="mode-symbol" aria-hidden="true">♜</span>
				<p class="eyebrow">HANDCRAFTED · OFFLINE</p>
				<h3>A story to get lost in.</h3>
				<p>
					Step into branching adventures with memorable characters, difficult choices, and more than
					one ending. A guided tutorial shows you the ropes.
				</p>
				<div class="mode-detail">11 adventure modules<br />Including the Ember Crown trilogy</div>
				<a href="#inside" onclick={() => tour('adventure')}
					>Explore D&D adventures <span aria-hidden="true">↗</span></a
				>
			</article>
			<article class="mode">
				<span class="mode-symbol" aria-hidden="true">✧</span>
				<p class="eyebrow">PROCEDURAL OR AI</p>
				<h3>See where “what if” goes.</h3>
				<p>
					Follow an endless offline quest or bring your own AI Dungeon Master. Set the tone, invent
					a premise, and decide what your hero does next.
				</p>
				<div class="mode-detail">Your hero. Your approach.<br />Your wonderfully bad idea.</div>
				<a href="#your-rules">Meet your storytelling options <span aria-hidden="true">↗</span></a>
			</article>
			<article class="mode">
				<span class="mode-symbol" aria-hidden="true">☾</span>
				<p class="eyebrow">TALES · NINE GENRES</p>
				<h3>Beyond swords & spells.</h3>
				<p>
					A signal from a derelict ship. A rain-soaked mystery. A pirate’s unfinished business. Play
					text adventures in book or terminal mode.
				</p>
				<div class="mode-detail">
					Preset stories or AI tales<br />No D&D character sheet required
				</div>
				<a href="#inside" onclick={() => tour('tales')}
					>Discover Tales <span aria-hidden="true">↗</span></a
				>
			</article>
		</div>
	</section>

	<section class="inside" id="inside">
		<div class="wrap section-space">
			<div class="section-heading">
				<div>
					<p class="eyebrow">A CLOSER LOOK</p>
					<h2>A whole adventuring kit.<br /><em>One small screen.</em></h2>
				</div>
				<p>
					Explore the actual app, from your first hero to the world you leave behind. Select a
					chapter of the tour.
				</p>
			</div>
			<div class="screen-tour">
				<div class="screen-nav" aria-label="Choose an app screen">
					{#each screens as screen, i}<button
							class:active={selected === i}
							aria-pressed={selected === i}
							onclick={() => (selected = i)}
							><span>{screen.name}</span><span aria-hidden="true">{selected === i ? '↗' : '·'}</span
							></button
						>{/each}
				</div>
				<div class="screen-stage">
					<div class="stage-ring"></div>
					<button
						class="phone tour-phone"
						onclick={() => zoom(current.id)}
						aria-label={`Enlarge ${current.name} screenshot`}
						><img
							src={`/screens/${current.id}.png`}
							alt={`${current.name}: actual DnD app screen`}
							width="780"
							height="1688"
							loading="lazy"
						/></button
					><span class="screen-caption">ACTUAL APP CAPTURE · TAP TO ENLARGE</span>
				</div>
				<div class="screen-story" aria-live="polite" aria-atomic="true">
					<p class="eyebrow">{current.tag}</p>
					<h3>{current.title}</h3>
					<p>{current.description}</p>
					<ul>
						{#each current.points as point}<li>{point}</li>{/each}
					</ul>
					<div class="tour-controls">
						<button
							aria-label="Previous app screen"
							onclick={() => (selected = (selected + screens.length - 1) % screens.length)}
							>←</button
						><span>{String(selected + 1).padStart(2, '0')} / {screens.length}</span><button
							aria-label="Next app screen"
							onclick={() => (selected = (selected + 1) % screens.length)}>→</button
						>
					</div>
				</div>
			</div>
		</div>
	</section>

	<section class="living wrap section-space" id="living-world">
		<div class="living-copy">
			<p class="eyebrow">MORE THAN THE NEXT QUEST</p>
			<h2>You change the world.<br /><em>It remembers.</em></h2>
			<p>
				The village you saved. The promise you made. The companion who stayed. A campaign carries
				your choices into the next chapter.
			</p>
			<div class="memory-list">
				<article>
					<span aria-hidden="true">⌁</span>
					<div>
						<h3>People, not just party slots.</h3>
						<p>
							Build loyalty, have private conversations, and follow a companion’s personal quest
							toward a lasting resolution.
						</p>
					</div>
				</article>
				<article>
					<span aria-hidden="true">⌘</span>
					<div>
						<h3>A history you can follow.</h3>
						<p>
							Search world facts, pin what matters, and trace each change back to its cause and
							chapter.
						</p>
					</div>
				</article>
				<article>
					<span aria-hidden="true">☷</span>
					<div>
						<h3>Room for the quiet moments.</h3>
						<p>
							Train, research, brew potions, or spend a day with a friend. Camp is part of the
							story, too.
						</p>
					</div>
				</article>
			</div>
		</div>
		<div class="memory-showcase">
			<div class="memory-heading">
				<span>THE CAMPAIGN JOURNAL</span><span aria-hidden="true">✧</span>
			</div>
			<button
				class="phone memory-phone"
				onclick={() => zoom('memory')}
				aria-label="Enlarge World memory screenshot"
				><img
					src="/screens/memory.png"
					alt="World memory with remembered locations and an allied faction"
					width="780"
					height="1688"
					loading="lazy"
				/></button
			>
			<p>Not just where you’ve been.<br /><em>What you’ve left behind.</em></p>
		</div>
	</section>

	<section class="studio-section">
		<div class="wrap section-space">
			<div class="section-heading">
				<div>
					<p class="eyebrow">MAKE IT FEEL LIKE YOUR WORLD</p>
					<h2>Paint the place.<br />Set the atmosphere.</h2>
				</div>
				<p>
					Art and sound are part of the adventure. Create them on your device, bring your own, or
					add optional AI media.
				</p>
			</div>
			<div class="studio-grid">
				{#each [{ id: 'art', label: 'Art studio', title: 'A face for every story.', body: 'Portraits, creatures, scenes, and maps. Explore procedural art, import your own images, and collect your creations.' }, { id: 'music', label: 'Music & sound', title: 'A world you can hear.', body: 'Compose music, build soundscapes, and design effects. Let music and ambience follow the scene.' }, { id: 'tales', label: 'Stories with atmosphere', title: 'Turn the page. Or listen.', body: 'Settle into book or terminal mode, tune the reading style, or hear the story through device or optional AI voices.' }] as studio}<article
					>
						<div class="studio-screen">
							<button
								onclick={() => zoom(studio.id)}
								aria-label={`Enlarge ${studio.label} screenshot`}
								><img
									src={`/screens/${studio.id}.png`}
									alt={`${studio.label} actual mobile screen`}
									width="780"
									height="1688"
									loading="lazy"
								/></button
							>
						</div>
						<p class="eyebrow">{studio.label}</p>
						<h3>{studio.title}</h3>
						<p>{studio.body}</p>
					</article>{/each}
			</div>
		</div>
	</section>

	<section class="rules wrap section-space" id="your-rules">
		<div class="section-heading">
			<div>
				<p class="eyebrow">YOUR ADVENTURE, YOUR TERMS</p>
				<h2>Start offline.<br /><em>Open up the possibilities.</em></h2>
			</div>
			<p>
				The core adventure doesn’t need an AI key. When you want AI, choose the provider, the
				models, and the limits.
			</p>
		</div>
		<div class="rules-grid">
			<article>
				<span class="status">READY WITHOUT AI</span>
				<h3>Keep it on your device.</h3>
				<p>
					Handcrafted adventures, procedural quests, preset Tales, heroes, the codex, and procedural
					art and audio are ready for offline play.
				</p>
				<ul>
					<li>No cloud AI account needed for offline content</li>
					<li>Save and return to your adventures</li>
					<li>Export your stories and back up your library</li>
				</ul>
			</article>
			<article>
				<span class="status optional">OPTIONAL AI CONNECTION</span>
				<h3>Choose your storyteller.</h3>
				<p>
					Connect Vercel AI Gateway, OpenRouter, or local text models through LM Studio. Add
					compatible image, video, and voice services separately.
				</p>
				<ul>
					<li>Pick different models for story and quick tasks</li>
					<li>Track tokens and estimated spending</li>
					<li>Set daily, story, and media limits</li>
				</ul>
			</article>
		</div>
		<p class="provider-note">
			Cloud features use your own provider credentials and may incur provider charges. LM Studio
			runs text models on your computer and requires a connection to that computer.
		</p>
	</section>

	<section class="feature-section" id="features">
		<div class="wrap section-space">
			<div class="section-heading">
				<div>
					<p class="eyebrow">THE COMPLETE FIELD GUIDE</p>
					<h2>All the little things.<br />And the big ones.</h2>
				</div>
				<p>From your first ability roll to your last exported chapter. Explore the full toolkit.</p>
			</div>
			<div class="feature-search">
				<label for="feature-search">Find a feature</label>
				<div>
					<span aria-hidden="true">⌕</span><input
						id="feature-search"
						type="search"
						bind:value={query}
						placeholder="Try spells, voice, backups…"
					/>{#if query}<button onclick={() => (query = '')} aria-label="Clear feature search"
							>×</button
						>{/if}
				</div>
			</div>
			<div class="feature-index" aria-live="polite">
				{#each filtered as group}<details open={query.length > 0}>
						<summary
							>{group.title}<span class="feature-count"
								>{group.items.length}
								{group.items.length === 1 ? 'topic' : 'topics'}
								<span class="plus" aria-hidden="true">+</span></span
							></summary
						>
						<div class="feature-items">
							{#each group.items as item}<article>
									<h3>{item[0]}</h3>
									<p>{item[1]}</p>
								</article>{/each}
						</div>
					</details>{/each}{#if filtered.length === 0}<p class="empty-search">
						No features match “{query}”. Try “story”, “art”, or “character”.
					</p>{/if}
			</div>
		</div>
	</section>

	<section class="faq wrap section-space">
		<div>
			<p class="eyebrow">BEFORE YOU SET OUT</p>
			<h2>A few things<br />to know.</h2>
		</div>
		<div>
			{#each faqs as [question, answer]}<details>
					<summary>{question}<span class="plus" aria-hidden="true">+</span></summary>
					<p>{answer}</p>
				</details>{/each}
		</div>
	</section>

	<section class="begin wrap" id="begin">
		<span class="end-star" aria-hidden="true">✧</span>
		<p class="eyebrow">NO PARTY TO ORGANIZE. NO SESSION TO SCHEDULE.</p>
		<h2>Your next chapter<br />starts <em>with you.</em></h2>
		<p>
			Take a closer look at the app or explore the project<br class="desktop-break" /> and its build instructions.
		</p>
		<div class="begin-actions">
			<a class="button primary" href="#inside">Explore the app <span aria-hidden="true">↑</span></a
			><a
				class="button secondary"
				href="https://github.com/dagmawibabi/dnd"
				target="_blank"
				rel="noreferrer">View the project <span aria-hidden="true">↗</span></a
			>
		</div>
		<a class="button secondary" href="https://github.com/dagmawibabi/dnd/releases" target="_blank" rel="noreferrer">Download from GitHub <span aria-hidden="true">↗</span></a>
	</section>
</main>

<footer class="wrap">
	<div class="footer-top">
		<a class="wordmark" href="#main"><img src="/app-icon.png" alt="" width="32" height="32" />DnD</a
		><span>A whole world. A party of one.</span><a
			href="https://github.com/dagmawibabi/dnd"
			target="_blank"
			rel="noreferrer">Source code ↗</a
		>
	</div>
	<div class="footer-bottom">
		<p>
			An independent solo adventure project. Not affiliated with or endorsed by Wizards of the
			Coast.<br />Rules content adapted from the 5e System Reference Document (CC BY 4.0).
		</p>
		<p>Real app screens. Example adventures.<br /><a href="#main">Back to the beginning ↑</a></p>
	</div>
</footer>

<dialog
	bind:this={lightbox}
	class="lightbox"
	onclick={(event) => {
		if (event.target === lightbox) lightbox.close();
	}}
	onkeydown={(event) => {
		if (event.key === 'Escape') lightbox.close();
	}}
	aria-label={`${enlarged.name} screenshot`}
>
	<div class="lightbox-header">
		<span>{enlarged.name} <small>ACTUAL APP SCREEN</small></span><button
			onclick={() => lightbox.close()}
			aria-label="Close screenshot">Close ×</button
		>
	</div>
	<img
		src={`/screens/${enlarged.id}.png`}
		alt={`${enlarged.name}: full-size DnD app screenshot`}
		width="780"
		height="1688"
	/>
	<p>Rendered from the app with example data.</p>
</dialog>
