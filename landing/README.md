# Refs landing page

An Astro marketing site for Refs, using the approved Quote identity. It builds to static HTML, CSS and a small amount of JavaScript.

## Develop

Requires Node 22.12 or later. From this directory:

```sh
npm install
npm run dev       # http://127.0.0.1:8770, with hot reload
npm run build     # type-checks, then writes the static site to dist/
npm run preview   # serves dist/ at http://127.0.0.1:8770
```

To deploy under a subpath, set `base` in `astro.config.mjs`. Page links to the download stay relative.

## Structure

- `src/pages/index.astro`: assembles the page and prepares the sized studio photo for each use.
- `src/components/`: one component per section (`SiteHeader`, `Hero`, `Intro`, `WorkflowSection`, `LibrarySection`, `AgentsSection`, `Faq`, `Closing`, `SiteFooter`).
  - **Native UI illustrations:** `HeroScene.astro` (capture → save → menu-bar sequence), `SavePanel.svelte`, `RefCard.svelte` and `RefThumb.svelte`.
  - **Svelte islands:** `WorkflowDemo.svelte` (the interactive three-step demo) and `LibraryWindow.svelte` (searchable sample library).
- `src/data/library.ts`: sample sources and references (fictional) shared by the library and the demo.
- `src/lib/motion.ts`: timing helpers (`tween`, `whenVisible`, `fitStage`) and the reduced-motion check. `macIcons.ts` holds the SF Symbol stand-ins.
- `src/styles/global.css`: tokens, fonts, base elements and buttons.
- `src/styles/mac.css`: shared native-UI pieces (window chrome, buttons, app tiles, capture overlay, library toolbar).
- Section styles live in their components. Astro uses `scopedStyleStrategy: 'where'`, so scoping adds no specificity.

Fixed-size illustrations (the hero desktop, the library window) are drawn at a design width and scaled to their column with CSS `zoom` (`fitStage`). The library's card reflow divides measured offsets by that zoom.

## Interaction

The hero plays a one-time illustration of the native capture flow: the area-selection overlay and HUD, the save panel with a typed note, and the capture landing under Recent in the menu-bar menu. A Replay control appears when it finishes. Native UI recreations use the app's real labels and layout, shown in dark mode with the macOS yellow accent.

The sample capture progresses through a personal note and a copyable reference:
- Capturing plays a short selection drag.
- The note step mirrors the save panel.
- The reuse step shows the new card in the library.

The sample library window filters by search and by sidebar source, and a new capture arrives once when it scrolls into view. The agent session types itself once when visible, using the real `list_references` and `get_reference` tool names.

The three tabs support arrow keys, Home and End. Reset restores the sample. Empty notes have a recovery message. Copy actions report clipboard failures. With reduced motion, every illustration renders in its final state without playing. The page has no repeating animation loop, tracking, form submission or external API call.

The example website and agent handoff are illustrative. They don't request screen access or read the owner's reference library.
- The primary CTA downloads the latest DMG from GitHub Releases.
- The secondary action opens the GitHub repository.
- The header links to the walkthrough, library, agents and FAQ sections.

## Assets

- `src/assets/brand/refs-light.svg`: a copy of the approved light icon master in `Resources/`.
- Fonts:
  - Bricolage Grotesque and Manrope are self-hosted, from the files distributed through Google Fonts.
  - They were converted from TTF to WOFF2 with fontTools.
  - The OFL licenses are served from `public/licenses/`.
- Interface icons:
  - Tabler SVGs; the MIT license is in `public/licenses/`.
  - `github.svg` is the GitHub mark from Simple Icons (CC0).
- `src/assets/agents/`: agent marks for the "Works with" list. The marks are trademarks of their owners, used only to show compatibility.
  - `claude.svg`, `claudecode.svg`, `cursor.svg` and `pi.svg` come from Simple Icons 16.35 (CC0). Its Pi icon is sourced from pi.dev.
  - `codex.svg` comes from LobeHub Icons 1.95 (MIT).
  - `ohmypi.svg` is `assets/icon.svg` from the Oh My Pi repository (MIT) and keeps its own colors. The other marks are tinted to the chip's text color.
- `src/assets/studio.jpg`:
  - Sourced from https://images.unsplash.com/photo-1494438639946-1ebd1d20bf85?auto=format&fit=crop&w=1100&q=85. The origin is also embedded in its JPEG metadata.
  - The build emits WebP versions at 960, 480 and 120 px.
  - It is cropped by CSS in the synthetic sample references.

## Validation

- Chrome, at 1440, 900, 390 and 320 px.
- The port to Astro was compared against the previous static build with reduced motion enabled:
  - Section positions and heights were identical at every width.
  - Remaining pixel differences come from icon anti-aliasing and the WebP photo.
- Checked flows:
  - The hero sequence, demo capture, custom note, empty-note validation, save, copy and reset.
  - Keyboard tabs.
  - Library search, source filtering and the arrival animation.
  - The agent session.
- No horizontal overflow and no console errors.
