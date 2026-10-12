# Refs landing page

A buildless, browser-local marketing preview using the approved Quote identity.

From the repository root:

```sh
python3 -m http.server 8770 --bind 127.0.0.1 --directory landing
```

Open http://127.0.0.1:8770/. No package installation or build step is required.

## Interaction

The sample capture progresses through a personal note and a copyable reference. The three tabs support arrow keys, Home and End. Reset restores the sample. Empty notes have a recovery message. Copy actions report clipboard failures. The specimen play button animates once on demand. CSS honors reduced motion; the page has no autoplay loop, tracking, form submission or external API call.

The example website and agent handoff are illustrative. They don't request screen access or read the owner's reference library. The primary CTA downloads `downloads/Refs-macOS.zip`; the secondary action opens the walkthrough. The ZIP is the current signed development build, not a notarized production release. No waitlist or hosted deployment is configured.

## Assets

- `refs-light.svg` and `refs-dark.svg`: copies of the approved local icon masters in Resources.
- Bricolage Grotesque and Manrope: self-hosted font files distributed through Google Fonts; OFL licenses included.
- Interface icons: Tabler SVGs, MIT license included.
- `studio.jpg`: sourced from https://images.unsplash.com/photo-1494438639946-1ebd1d20bf85?auto=format&fit=crop&w=1100&q=85 ; origin is also embedded in its JPEG metadata. Cropped by CSS in synthetic sample references.

## Validation

Capture, custom note, save, clipboard, reset, keyboard tabs, empty-note validation, FAQ command copying and sample animation were verified in Chrome. Desktop at 1440 and 1280 pixels and mobile at 390 pixels had no horizontal overflow. Images and fonts loaded; no browser warnings or errors were reported. The design reviewer scored the three requested corrections resolved. The reduced-motion implementation is present in CSS; an OS reduced-motion setting was not changed for testing.

## Package the download

From the repository root:

```sh
./scripts/package-download.sh
```

This builds and signs Refs using the existing signing workflow, then creates the app ZIP in `landing/downloads/`. The generated binary folder is ignored by Git; run the packaging script before serving or deploying the site. Download links use the relative path `downloads/Refs-macOS.zip` and remain valid under a subdirectory.
