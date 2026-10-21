export const screens = [
	{
		id: 'adventure',
		name: 'The adventure',
		tag: 'PLAY',
		title: 'A choice. A roll. A whole new direction.',
		description:
			'Read the scene, choose your approach, and see where the story takes you. Your hero, companions, choices, and unfolding narrative share one screen.',
		points: [
			'Branching stories and open-ended quests',
			'Turn-based combat and explained dice rolls',
			'Scene art that follows your journey'
		]
	},
	{
		id: 'hero',
		name: 'Your hero',
		tag: 'CHARACTER',
		title: 'More than a name on a character sheet.',
		description:
			'Build someone worth getting into trouble with. Start from a preset or shape a hero from race and class to skills, appearance, and backstory.',
		points: [
			'Point buy, standard array, or roll 4d6',
			'Inventory, spells, conditions, and notes',
			'Level-ups, subclasses, and multiclassing'
		]
	},
	{
		id: 'map',
		name: 'The map',
		tag: 'EXPLORE',
		title: 'Every journey leaves a trace.',
		description:
			'Find your place in the world. Explore an interactive map, revisit known locations, and keep the details of each place close to hand.',
		points: [
			'Overworld and dungeon maps',
			'Visited locations and place notes',
			'World facts connected to the places you explore'
		]
	},
	{
		id: 'camp',
		name: 'Camp & companions',
		tag: 'CONNECT',
		title: 'Some stories happen between adventures.',
		description:
			'Rest, train, research, brew a potion, or spend time with a companion. Loyalty opens personal quests, and your decisions shape how those stories end.',
		points: [
			'Persistent downtime and camp progress',
			'Companion loyalty and personal arcs',
			'Lasting resolutions, rewards, and departures'
		]
	},
	{
		id: 'memory',
		name: 'World memory',
		tag: 'REMEMBER',
		title: 'The next chapter remembers the last.',
		description:
			'Places change hands. Promises matter. Relationships evolve. Search the world’s current facts and see what changed, why it changed, and in which chapter.',
		points: [
			'Search, pin, and correct remembered facts',
			'Before-and-after consequence history',
			'Shared context for AI narration and conversations'
		]
	},
	{
		id: 'tales',
		name: 'Tales',
		tag: 'IMAGINE',
		title: 'Leave the rulebook. Keep the adventure.',
		description:
			'Step into a text adventure across nine genres. Pick a handcrafted story or create one with AI, then read in book or terminal layout.',
		points: [
			'Sci-fi, horror, western, noir, and cyberpunk',
			'Post-apocalyptic, fantasy, pirates, and comedy',
			'People, choices, memory, and story tools'
		]
	},
	{
		id: 'codex',
		name: 'The codex',
		tag: 'DISCOVER',
		title: 'Your rulebook, within reach.',
		description:
			'Look up the creature in your path or the spell in your hand. The compendium brings core rules and reference material into the same app as your adventure.',
		points: [
			'Races, classes, and spells',
			'Equipment, monsters, and conditions',
			'Core rules and optional AI codex artwork'
		]
	},
	{
		id: 'dice',
		name: 'The dice tray',
		tag: 'ROLL',
		title: 'A little chance goes a long way.',
		description:
			'Keep a tactile dice tray in your pocket. Roll your favorite polyhedrals, add modifiers, and reach for random tables when the story needs a spark.',
		points: [
			'd4, d6, d8, d10, d12, and d20',
			'Dice animation and optional haptics',
			'Standalone rolls and inspiration tables'
		]
	},
	{
		id: 'art',
		name: 'Art studio',
		tag: 'CREATE',
		title: 'Give your world a face.',
		description:
			'Explore on-device scenes, portraits, creatures, and maps. Bring in your own pictures, build a collection, or use optional AI artwork.',
		points: [
			'Procedural art without an AI service',
			'Imported images and saved collections',
			'Portrait, creature, map, and scene tools'
		]
	},
	{
		id: 'music',
		name: 'Music studio',
		tag: 'LISTEN',
		title: 'Set the mood before the first word.',
		description:
			'Compose and explore music, themes, and soundscapes. The app’s synthesized music, effects, and ambience can follow the scene as you play.',
		points: [
			'Music composer and personal tracks',
			'Scene-aware music and ambient sound',
			'A separate sound-effects designer'
		]
	},
	{
		id: 'settings',
		name: 'Make it yours',
		tag: 'CONTROL',
		title: 'Your story. Your settings.',
		description:
			'Choose your AI providers, reading preferences, narration, and spending limits. Keep the parts you enjoy and tune the rest to suit you.',
		points: [
			'Offline play or optional AI providers',
			'Device and AI narration, plus voice input',
			'Accessibility, backups, and usage controls'
		]
	},
	{
		id: 'home',
		name: 'Your library',
		tag: 'RETURN',
		title: 'Pick up where the adventure left off.',
		description:
			'Keep heroes, adventures, and campaigns together. Return to a save, start a new journey, or switch your home screen to text adventures.',
		points: [
			'Saved adventures and reusable heroes',
			'Campaigns that continue across chapters',
			'Guided tutorial and ready-made starting points'
		]
	}
];

export const featureGroups = [
	{
		title: 'Stories & ways to play',
		items: [
			[
				'Handcrafted adventures',
				'11 included modules, including a guided tutorial and the three-part Ember Crown campaign. Branching paths and multiple endings invite another playthrough.'
			],
			[
				'Endless quests & AI Dungeon Master',
				'Play procedural offline quests or connect an AI storyteller for open-ended adventures. Set the premise, setting, tone, and difficulty.'
			],
			[
				'Tales across nine genres',
				'Play preset or AI text adventures without a D&D character sheet. Switch between book and terminal layouts, including within an existing story.'
			],
			[
				'Story controls',
				'Use suggested choices or enter your own action where supported. Restart with a fresh copy, revisit story tools, or choose hardcore D&D play with permadeath and no rewind.'
			]
		]
	},
	{
		title: 'Heroes, combat & exploration',
		items: [
			[
				'Character creation',
				'Choose race, class, background, skills, appearance, and ability scores. Use point buy, standard array, 4d6 rolls, or one of 12 presets; optional AI helps with heroes and backstories.'
			],
			[
				'A complete character sheet',
				'Manage hit points, Inspiration, conditions, inventory, equipment, spells, and notes. Progress through level-ups, subclasses, feats, and multiclassing. Share a character card or copy your sheet.'
			],
			[
				'Combat & dice',
				'Fight turn-based battles with companions and a battle grid. Read roll explanations in the log and manage spells and resources. Use the standalone dice tray, ask the oracle, or roll random tables for names, rumors, weather, and loot.'
			],
			[
				'Maps, quests & supplies',
				'Explore interactive maps, track quests, visit shops, manage loot, and rest. Show or hide check difficulty numbers to suit your play style.'
			]
		]
	},
	{
		title: 'A world that carries forward',
		items: [
			[
				'Living campaigns',
				'Continue across chapters with relationships, conversations, notes, and world consequences intact. Chapter recaps show the changes to your world and party.'
			],
			[
				'World memory & canon',
				'Search facts, pin important details, correct what the world remembers, and inspect before-and-after history with causes and chapter references. Edit the story summary and remembered canon.'
			],
			[
				'People & private conversations',
				'Talk to people you meet, build relationships, and keep private conversation histories. Companions can approach you about quests and important changes; AI chats use your world state.'
			],
			[
				'Camp & personal quests',
				'Train, work, brew potions, research, and bond. At 60 loyalty, companions reveal a personal arc. Follow leads or complete their quest, then choose a lasting resolution at camp. Town activities need a settlement.'
			]
		]
	},
	{
		title: 'Art, music & voice',
		items: [
			[
				'Art studio & gallery',
				'Create procedural portraits, scenes, monsters, and maps on device. Import your own images, collect creations, and save gallery artwork to your phone.'
			],
			[
				'Music & sound-effects studios',
				'Compose music, explore themes and soundscapes, design effects, and use personal tracks and sounds. Control music, effects, and ambience volumes independently.'
			],
			[
				'Optional AI images & video',
				'Choose models for portraits, scene and map art, special moments, and video clips. Generate manually or enable automatic generation, with media limits and cost visibility. Requires a compatible provider.'
			],
			[
				'Read aloud & speak',
				'Use device text-to-speech, compatible AI voices, or ElevenLabs. Choose character voices and narrator delivery; cached AI lines can be replayed. Voice input lets you dictate actions on supported devices.'
			]
		]
	},
	{
		title: 'AI on your terms',
		items: [
			[
				'Bring your provider',
				'Connect Vercel AI Gateway or OpenRouter with your own key, or use a model running on your computer through LM Studio. LM Studio supports text; image and voice services are configured separately.'
			],
			[
				'Choose models by task',
				'Pick a story model and a faster model for chats, recaps, ideas, and summaries. Adjust creativity, streaming, story themes, combat narration, and automatic recaps.'
			],
			[
				'Keep long stories coherent',
				'Story summaries, remembered facts, and world state provide context for narration and character conversations. AI tools can help with ideas without spending a story turn.'
			],
			[
				'Usage & limits',
				'View token and estimated cost breakdowns by message, media, model, and story. Set daily and per-story budgets, token limits, and image/video limits. Provider billing may differ from estimates.'
			]
		]
	},
	{
		title: 'Reference, comfort & keeping your stories',
		items: [
			[
				'The compendium',
				'Browse races, classes, spells, equipment, monsters, conditions, and core rules, with optional AI illustrations for codex entries.'
			],
			[
				'Reading & accessibility',
				'Choose serif, sans, or mono story text and adjust text size, typewriter speed, high contrast, reduced motion, and haptics. Use book or terminal layouts for Tales.'
			],
			[
				'Exports & playable saves',
				'Export stories as PDF, HTML, Markdown, text, or to the clipboard. Exports include world memory, consequence history, companion arcs, camp progress, and private conversations. Playable saves let you resume.'
			],
			[
				'Backups, profile & achievements',
				'Export and import your library of heroes, stories, campaigns, achievements, profile, codex art, and studio creations. Track achievements and stats, and personalize your profile.'
			]
		]
	}
];

export const faqs = [
	[
		'Do I need a group or a Dungeon Master?',
		'No. DnD is built for solo play. Handcrafted adventures and the offline engine guide the story, or you can connect an AI Dungeon Master. A guided tutorial and ready-made heroes help you get started.'
	],
	[
		'Can I play without AI or an internet connection?',
		'Yes. Included D&D adventures, procedural quests, preset Tales, character tools, the codex, and on-device art and audio support offline play. Cloud AI features need a provider connection. LM Studio needs access to the computer running your model.'
	],
	[
		'Does AI cost extra?',
		'Cloud AI uses your own provider credentials, and any usage charges come from that provider. The app shows usage estimates and lets you set limits. Offline content does not need an AI key. Local text generation through LM Studio does not use a cloud AI provider.'
	],
	[
		'Are these real app screens?',
		'Yes. Every screen shown here is rendered from the app’s actual Flutter widgets at a mobile viewport, with example characters and adventure data. They are screenshots, not a browser version of the game.'
	],
	[
		'Can I keep or share my adventures?',
		'Yes. Export a readable story in several formats, share character cards, or export playable saves and library backups. World memory, conversations, companion progress, and campaign consequences travel with supported exports.'
	],
	[
		'Where can I get the app?',
		'This page showcases the current project. Visit the source repository for development and build instructions. A verified App Store or Google Play download link has not been published on this site.'
	]
];
