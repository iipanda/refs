---
name: Refs landing page
description: Implemented visual system for the local marketing preview in landing/.
colors:
  yellow: "#ffdc38"
  yellow-hover: "#ffe66e"
  charcoal: "#222423"
  raised: "#2b2e2c"
  paper: "#f4f1e9"
  secondary: "#c0c2b8"
  line: "#474a43"
  ink: "#262820"
  muted-ink: "#5d5c45"
  input-ground: "#252825"
  output-ground: "#222522"
typography:
  display:
    fontFamily: "Bricolage, system-ui, sans-serif"
    fontSize: "clamp(62px, 6.5vw, 92px)"
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Bricolage, system-ui, sans-serif"
    fontSize: "clamp(35px, 4vw, 51px)"
    fontWeight: 700
    lineHeight: 1.07
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Bricolage, system-ui, sans-serif"
    fontSize: "31px"
    fontWeight: 700
    lineHeight: 1.07
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Manrope, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Manrope, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.6
rounded:
  field: "7px"
  button: "8px"
  note: "9px"
  brief: "11px"
  window: "12px"
  demo: "14px"
spacing:
  compact: "12px"
  control-inline: "21px"
  panel: "30px"
  column-gap: "45px"
components:
  button-primary:
    backgroundColor: "{colors.yellow}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.button}"
    padding: "13px 21px"
  button-primary-hover:
    backgroundColor: "{colors.yellow-hover}"
  button-dark:
    backgroundColor: "{colors.charcoal}"
    textColor: "{colors.paper}"
    typography: "{typography.label}"
    rounded: "{rounded.button}"
    padding: "13px 21px"
  note-input:
    backgroundColor: "{colors.input-ground}"
    textColor: "{colors.paper}"
    rounded: "{rounded.field}"
    padding: "12px"
    width: "100%"
  workflow:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.paper}"
    rounded: "{rounded.demo}"
  saved-note:
    backgroundColor: "{colors.yellow}"
    textColor: "{colors.ink}"
    rounded: "{rounded.note}"
    padding: "18px 20px"
  reference-output:
    backgroundColor: "{colors.output-ground}"
    textColor: "{colors.paper}"
    rounded: "{rounded.field}"
    padding: "15px"
---

# Design System: Refs landing page

## Overview

**Creative North Star: "The Designer's Editing Table"**

This is an extraction of the implemented marketing surface in `landing/`, created for code-led local static preview. Warm yellow, charcoal and the user-confirmed quotation icon carry the identity. Generous space, large conversational headings, cropped source material and offset notes make the reference and the reason for keeping it visible together.

The North Star, descriptive color names, typography pairing and page composition document this implementation for review; they are not claimed as a user-approved permanent style. The native Swift UI is not redesigned by this specification. Audience remains a working assumption in `PRODUCT.md`; the user requested a download CTA after approving the landing page. Page strategy and the selection record belong in `landing/DIRECTION.md`.

**Key Characteristics:**

- Warm yellow identity against neutral charcoal.
- Large compact display type with quieter readable workflow text.
- Layered illustrative sources and personal notes.
- User-operated state changes with reduced-motion support.

Review disposition: the three concrete corrections—FORM selection record, 12–14px operative workflow text and SVG icons—are recorded as resolved. This does not claim separate full approval of the new surface or a production launch.

## Colors

The palette pairs a warm signal yellow with slightly green neutral grounds and a warm paper foreground. Frontmatter values are extracted from the current stylesheet; the unused `--gold` declaration is excluded.

### Primary

- **Warm Signal Yellow** (`yellow`): identity, highlighted hero and closing text, primary actions, selected workflow tabs, saved notes, focus outlines and the full library section.
- **Soft Hover Yellow** (`yellow-hover`): primary button hover state.

### Neutral

- **Neutral Charcoal** (`charcoal`): page ground and dark capture actions.
- **Raised Charcoal** (`raised`): enclosing interactive workflow surface.
- **Warm Paper** (`paper`): main dark-ground text and illustrated source window.
- **Quiet Sage Gray** (`secondary`): supporting copy, navigation, captions and inactive workflow tabs.
- **Divider Gray** (`line`): section dividers and workflow boundaries.
- **Dark Olive Ink** (`ink`): text on yellow and pale illustrative grounds.
- **Muted Olive Ink** (`muted-ink`): annotation beneath the reference collection.
- **Field Charcoal** (`input-ground`): editable note ground.
- **Output Charcoal** (`output-ground`): copied-reference preview ground.

**The Identity Rule.** Preserve the confirmed quotation icon and yellow/charcoal identity in this surface; other visual choices remain reviewable implementation decisions.

## Typography

**Display Font:** self-hosted Bricolage Grotesque, named `Bricolage` in CSS, with system-ui and sans-serif fallback; weights 600 and 700.

**Body Font:** self-hosted Manrope, with system-ui and sans-serif fallback; weights 400 and 600.

**Label/Mono Font:** labels use Manrope; keyboard keys use system-ui and the setup command uses ui-monospace, SFMono-Regular, monospace (12px/1.8).

**Character:** compact, rounded display lettering creates the conversational scale; Manrope separates operational instructions from illustrative specimen text. Fonts use `font-display: swap`; the 700 display face is preloaded.

### Hierarchy

- **Display:** frontmatter desktop hero role; the headline remains on two explicit lines. At widths above 1550px it becomes 96px. At 1100px and below it uses `clamp(51px, 6.9vw, 74px)`; at 760px and below, `clamp(56px, 11.8vw, 80px)`.
- **Headline:** frontmatter workflow role; library, agent and closing headings have their own observed responsive clamps. Shared heading rhythm is 1.07 with balanced wrapping.
- **Title:** workflow step heading (31px), reduced to 29px at the mobile breakpoint.
- **Body:** base frontmatter role; operative workflow paragraphs use 14px/1.85, FAQ text 14px/1.9 with a 65ch maximum, hero support 17px/1.75 on desktop and 15px on mobile.
- **Label:** frontmatter button/tab role; workflow counters, hints, captions and output metadata use 12–14px. Mock website and illustrative artifact details intentionally contain smaller specimen type (7–11px), distinct from operative workflow controls.

## Layout

The centered shell has a maximum width of 1264px. Desktop gutters are 56px per side (`calc(100% - 112px)`), becoming 36px at 1100px and 20px at 760px. These are extracted local values, not a universal spacing scale.

The hero is a two-column grid (`.95fr 1.1fr`, 45px gap) with 64px/102px vertical padding and a 660px minimum height. The workflow splits source and explanation (`1.1fr 1fr`) with a 402px panel minimum height. Library uses `1fr 1.1fr`; agent handoff uses equal columns; FAQ uses `.9fr 1.1fr`. Section separation is broad and editorial: workflow 99px/110px, library 87px/97px and agents 107px vertical padding.

At 1100px, hero spacing contracts and illustration sizes reduce. At 760px, hero, workflow panel, library, agents and FAQ become single-column; header navigation is hidden while the identity and Download for Mac action remain. Demo tabs stay in a horizontal row; reset becomes an icon with an accessible name. Captions stack, footer wraps, hero artwork caps at 520px, library collection at 450px and handoff at 480px. Mobile workflow illustration and explanation retain minimum heights of 324px and 330px. The only large-screen override begins at 1550px, expanding hero spacing and the source photo.

## Elevation & Depth

Depth combines tonal boundaries with offset artifact shadows. Page sections remain flat; the browser source, saved note and reference specimens have diffuse shadows that make the illustrative overlap legible. Rotations belong to these illustrations, not every container.

### Shadow Vocabulary

- **Source window:** `0 24px 54px #0000006b`.
- **Hero note:** `0 14px 36px #00000040`.
- **Capture action:** `0 8px 20px #00000045`.
- **Saved preview:** `0 14px 35px #00000024`.
- **Reference specimen:** `0 12px 25px #00000024`.

## Shapes

Corners distinguish control scale from container scale: fields and output use the field radius, buttons the button radius, hero notes the note radius, handoff briefs the brief radius, source windows the window radius and workflow the demo radius from frontmatter. Thumbnail rounding is smaller (3–4px). Crop boundaries are rectangular 2px strokes with square handles in the hero. Step markers and response markers are circular. The illustrated source rotates −4°, hero note +5°, brief −2° and collection specimens −6°/+8°/+3°.

## Components

### Buttons

Compact, tactile controls use the frontmatter assignments. Shared minimum height is 52px with a 23px icon gap; workflow actions use a 46px minimum and 12px gap; the overlaid capture action uses a 40px minimum and 9px gap. Primary actions use yellow and ink; the capture action uses charcoal and paper. Hover translates upward 2px, active returns to rest, background changes over 200ms and translation over 250ms with the shared ease. Disabled buttons use 0.5 opacity and a not-allowed cursor.

### Cards / Containers

The workflow container is bordered with divider gray, clips its rounded edges and splits the pale illustrative source from raised explanation. Yellow saved previews have a 12px inset, warm cropped image and note/source pairing. The hero note uses a compact top row, display quotation and divided source footer. Reference output uses the field radius and a 1px `#505549` border, with a yellow label and wrapping pre-line text.

### Inputs / Fields

The note textarea is the implemented field: 14px/1.7 Manrope, 1px `#69705e` border, 86–170px height, vertical resize, yellow caret and a 180-character limit. Its label and live character count remain visible. Empty submit invokes native validation with a custom instruction; the error clears on the next input. No custom red error visual exists.

### Navigation

The header combines quotation icon and Bricolage wordmark with 13px secondary links and an underlined Download for Mac action. Links turn yellow on hover. Header navigation disappears at the mobile breakpoint; the call to action stays. A focusable skip link appears at the upper left on focus.

### Workflow Tabs and State

Capture, Remember and Reuse are real buttons with tab roles and roving tabindex; selected steps use yellow text, underline and filled number marker. Arrow keys wrap; Home and End select endpoints. Capture focuses the note field, Save focuses the copy control, and Reset restores the initial sample. Notes update the saved preview live. Clipboard success/failure is announced in polite status regions. This demonstration uses synthetic sample content in memory; it does not capture the visitor's screen or persist a library.

### FAQ and Setup

Native details/summary provide the accordion. Rows use divider borders, 14px semibold questions and a plus marker that rotates 45° when open. The code block wraps long commands and includes a separate copy action and polite status.

### Focus and Motion

Buttons, links, fields, summaries and focusable panels share a 3px yellow outline with 5px offset. The easing is `cubic-bezier(.16, 1, .3, 1)`. Hero entrance takes 900ms (22px upward travel), state entrance 400ms (9px), and saved preview entrance 650ms (translation, slight rotation and scale). The click-triggered collection sample transitions for 600ms, then returns after a 1200ms timer; no perpetual animation is used. Reduced motion removes animations and transitions, disables smooth scrolling and preserves every control and state.

## Do's and Don'ts

### Do:

- **Do** preserve the confirmed quotation icon and yellow/charcoal identity.
- **Do** keep operative workflow text at the implemented 12–14px sizes.
- **Do** retain labeled synthetic examples, keyboard workflow controls and visible focus.
- **Do** preserve state access when reduced motion is enabled.
- **Do** use this specification only for the implemented landing/ marketing surface.

### Don't:

- **Don't** treat illustrative source windows as screenshots of the native app.
- **Don't** promote this review implementation into an approved permanent style or production launch.
- **Don't** apply this landing-page visual extraction as a redesign of the native Swift UI.
- **Don't** substitute font glyphs for the implemented SVG action icons.

The primary header, hero and closing actions download the packaged Mac development build at `downloads/Refs-macOS.zip`. The hero pairs its yellow download button with a secondary inline demo link in a wrapping flex row (21px gap; 16px on mobile). The platform line identifies macOS 14+, Apple Silicon and development-build status.
