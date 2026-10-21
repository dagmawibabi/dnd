# DnD showcase

A responsive SvelteKit showcase for the mobile app, with a 12-screen interactive tour, native screenshot dialog, searchable feature guide, and FAQ. The page is prerendered; the existing Vercel adapter is retained.

## Run

```sh
pnpm install
pnpm dev
pnpm check
pnpm build
```

## Content and captures

- `src/lib/content.ts`: screen descriptions, complete feature guide, and FAQ.
- `src/routes/+page.svelte`: page composition and interactions.
- `src/routes/layout.css`: responsive design and local fonts.
- `static/screens/`: actual Flutter widget renders at 390 × 844 logical pixels, exported at 2×. The fixtures use example saves and the app’s sans-serif reading preference, with audio and typewriter effects off. No production user data is read.

Regenerate screenshots from the Flutter project root:

```sh
flutter test tool/site_screenshots_test.dart --reporter expanded
```

The capture tool loads Georgia from Windows for serif display text; on another host pass `--dart-define=SITE_SERIF_FONT=/path/to/serif.ttf`. No system font files are redistributed. It imports production screens rather than recreating them in HTML. Screenshots can be enlarged using click, tap, or keyboard; Escape closes the dialog. Fonts and images are local, with no third-party requests needed to display the page.

Store URLs were not present in the project. Calls to action lead to the screen tour and the existing source repository; add verified store links when available.

## Design

Campaign-atlas direction: mist `#eaf0f3`, navy ink `#132d46`, paper `#f8fbfc`, lavender `#bba7f3`, slate `#536b7d`, and aqua `#95c7c2`. Georgia display typography pairs with the app’s Inter and JetBrains Mono fonts. The signature is a pair of real app screens plotted against a quiet compass ring. The remainder uses restrained sections so screenshots carry the product story.

Content was checked against the app source, including modules, genres, settings, export services, and screen implementations. No store availability, reviews, or testimonials are invented.
