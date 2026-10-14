<script lang="ts">
  import { tick } from 'svelte';
  import Icon from './Icon.svelte';
  import RefCard from './RefCard.svelte';
  import SavePanel from './SavePanel.svelte';
  import { macIcons } from '../lib/macIcons';
  import { prefersReducedMotion, tween, wait } from '../lib/motion';
  import { references } from '../data/library';

  let { image, thumbImage }: { image: string; thumbImage: string } = $props();

  const steps = [
    { id: 'tab-capture', label: 'Capture' },
    { id: 'tab-note', label: 'Remember' },
    { id: 'tab-reuse', label: 'Reuse' },
  ];
  const initialNote = 'The quiet colors and generous space around a single object.';
  const savedCard = { ...references[0], note: '' };
  const neighbours = references.filter(reference => reference.thumb === 'pricing' || reference.thumb === 'type-spec');

  let step = $state(0);
  let note = $state(initialNote);
  let capturing = $state(false);
  let selection = $state({ x: 0, y: 0, width: 0, height: 0 });
  let copyStatus = $state('');
  let copied = $state(false);
  let tabs: HTMLButtonElement[] = $state([]);
  let target: HTMLElement;
  let noteInput: HTMLTextAreaElement | undefined = $state();
  let copyButton: HTMLButtonElement | undefined = $state();

  const savedNote = $derived(note.trim() || initialNote);
  const referenceText = $derived(`Reference: Studio detail\nSource: forme.example\nWhat I like: ${savedNote}`);

  function select(next: number, focusTab = false) {
    step = next;
    copyStatus = '';
    copied = false;
    if (focusTab) tabs[next].focus({ preventScroll: true });
  }
  function onTabKey(event: KeyboardEvent, index: number) {
    const last = steps.length - 1;
    const next = { ArrowRight: (index + 1) % steps.length, ArrowLeft: (index + last) % steps.length, Home: 0, End: last }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    select(next, true);
  }
  async function capture() {
    if (capturing) return;
    if (!prefersReducedMotion()) {
      capturing = true;
      const area = { x: 12, y: 42, width: target.clientWidth - 24, height: target.clientHeight - 54 };
      await tween(700, t => { selection = { ...area, width: area.width * t, height: area.height * t }; });
      await wait(280);
      capturing = false;
      selection = { x: 0, y: 0, width: 0, height: 0 };
    }
    select(1);
    await tick();
    noteInput?.focus({ preventScroll: true });
  }
  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!note.trim()) {
      noteInput!.setCustomValidity('Add a short note about the detail you like.');
      noteInput!.reportValidity();
      return;
    }
    select(2);
    await tick();
    copyButton?.focus({ preventScroll: true });
  }
  function reset() {
    note = initialNote;
    noteInput?.setCustomValidity('');
    select(0);
  }
  async function copyReference() {
    try {
      await navigator.clipboard.writeText(referenceText);
      copyStatus = 'Copied. Ready for your next brief.';
      copied = true;
    } catch {
      copyStatus = 'Clipboard access is unavailable. Select and copy the text above.';
    }
  }
</script>

<div class="demo">
  <div class="demo-controls" role="tablist" aria-label="Reference workflow">
    {#each steps as item, index (item.id)}
      <button
        bind:this={tabs[index]}
        id={item.id}
        role="tab"
        aria-selected={step === index}
        aria-controls="demo-panel"
        tabindex={step === index ? 0 : -1}
        onclick={() => select(index)}
        onkeydown={event => onTabKey(event, index)}
      ><span>{index + 1}</span>{item.label}</button>
    {/each}
    <button class="replay" id="reset-demo" aria-label="Reset the interactive demo" onclick={reset}>Start again <Icon name="rotate-clockwise" /></button>
  </div>
  <div class="demo-panel" id="demo-panel" role="tabpanel" aria-labelledby={steps[step].id} tabindex="0">
    <div class="demo-visual">
      {#if step === 0}
        <div class="capture-target" class:is-capturing={capturing} bind:this={target}>
          <div class="mini-site-title">forme.</div>
          <div class="mini-site-copy">A little less.<br />A little better.</div>
          <img src={image} alt="Sample website detail featuring a studio lamp" width="960" height="642" />
          <div class="cap-overlay" aria-hidden="true">
            <div class="sel" style="--sx:{selection.x}px;--sy:{selection.y}px;--sw:{selection.width}px;--sh:{selection.height}px">
              <span class="sel-size">{Math.round(selection.width * 2)} × {Math.round(selection.height * 2)}</span>
            </div>
          </div>
          <button id="capture-button" class="button button-dark" onclick={capture}><Icon name="crop" size={19} />Capture this detail</button>
        </div>
      {:else if step === 1}
        <div class="demo-save"><SavePanel note={savedNote} image={thumbImage} /></div>
      {:else}
        <div class="mini-lib mac">
          <div class="lib-toolbar">
            <span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>
            <div class="lib-title"><b>All References</b><small>25 references</small></div>
            <span class="lib-search">{@html macIcons.search}<span>Search notes, sites, apps</span></span>
          </div>
          <div class="mini-grid">
            <div class="is-new"><RefCard reference={savedCard} note={savedNote} image={thumbImage} selected /></div>
            {#each neighbours as reference (reference.id)}
              <div class="shifted"><RefCard {reference} image={thumbImage} /></div>
            {/each}
          </div>
          <div class="mini-inspector"><span class="mac-btn">Copy Reference</span><span class="mac-btn">Reveal</span><span class="mac-btn is-destructive">Move to Trash</span></div>
        </div>
      {/if}
    </div>
    <div class="demo-explanation">
      {#if step === 0}
        <div class="demo-copy">
          <h3>Follow your eye.</h3>
          <p>Grab an area or a window. Refs keeps where it came from, so you can focus on what caught your attention.</p>
          <div class="shortcut"><kbd>⇧</kbd><kbd>⌘</kbd><kbd>2</kbd><span>One shortcut. One good detail.</span></div>
          <p class="demo-hint">Click the capture button to try the next step.</p>
        </div>
      {:else if step === 1}
        <form class="demo-copy" id="note-form" onsubmit={save}>
          <h3>Keep the “why.”</h3>
          <p>A screenshot remembers the pixels.<br />Your note remembers the idea.</p>
          <label for="reference-note">What do you like about it?</label>
          <textarea id="reference-note" maxlength="180" rows="3" bind:this={noteInput} bind:value={note} oninput={() => noteInput?.setCustomValidity('')}></textarea>
          <div class="note-meta"><span>Saved with its source</span><span id="note-count">{note.length} / 180</span></div>
          <button class="button button-yellow" type="submit">Save the reference <Icon name="arrow-right" /></button>
        </form>
      {:else}
        <div class="demo-copy">
          <h3>Give the idea a next life.</h3>
          <p>Copy a reference into a brief, or let your coding agent find it in your library.</p>
          <div class="reference-output"><span>Reference for your next build</span><p id="reference-text">{referenceText}</p></div>
          <button id="copy-reference" class="button button-yellow" bind:this={copyButton} onclick={copyReference}>{copied ? 'Reference copied' : 'Copy reference'} <Icon name="arrow-up-right" /></button>
          <p class="copy-status" id="copy-status" role="status" aria-live="polite">{copyStatus}</p>
        </div>
      {/if}
    </div>
  </div>
  <div class="demo-caption"><span>Interactive example</span><span>No screen access. This sample stays in your browser.</span></div>
</div>

<style>
  .demo { overflow: hidden; border: 1px solid var(--line); border-radius: 14px; background: var(--raised); }
  .demo-controls { display: flex; align-items: center; gap: 35px; min-height: 70px; padding-inline: 29px; border-bottom: 1px solid var(--line); }
  [role='tab'] { display: flex; align-items: center; gap: 10px; min-height: 70px; padding: 0; border: 0; border-bottom: 2px solid transparent; background: none; color: var(--secondary); font-size: 13px; font-weight: 600; }
  [role='tab'] span { display: grid; place-items: center; width: 21px; height: 21px; border: 1px solid #8b8f7d; border-radius: 50%; font-size: 12px; }
  [aria-selected='true'] { border-bottom-color: var(--yellow); color: var(--yellow); }
  [aria-selected='true'] span { border-color: var(--yellow); background: var(--yellow); color: var(--ink); }
  .replay { display: flex; align-items: center; gap: 10px; margin-left: auto; padding: 0; border: 0; background: none; color: var(--secondary); font-size: 12px; }
  .replay:hover { color: var(--yellow); }
  .demo-panel { display: grid; grid-template-columns: 1.1fr 1fr; min-height: 402px; }
  .demo-visual { display: grid; place-items: center; overflow: hidden; padding: 30px; background: #e8e6dc; color: var(--ink); }

  .capture-target { position: relative; width: 100%; max-width: 410px; padding: 21px 23px 23px; background: #f9f7ef; }
  .mini-site-title { font: 700 21px/1 Bricolage, sans-serif; }
  .mini-site-copy { margin: 23px 0 20px; font: 600 32px/1.08 Bricolage, sans-serif; letter-spacing: -.02em; }
  .capture-target > img { width: 100%; height: 143px; object-position: center 60%; }
  .capture-target .cap-overlay { transition: opacity .2s; }
  .capture-target.is-capturing .cap-overlay { opacity: 1; }
  .capture-target .sel-size { top: auto; bottom: 10px; }
  .capture-target > .button { position: absolute; left: 50%; bottom: 35px; gap: 9px; min-height: 40px; font-size: 13px; white-space: nowrap; box-shadow: 0 8px 20px #00000045; transform: translateX(-50%); transition: opacity .2s, transform .25s var(--ease); }
  .capture-target > .button:hover { transform: translateX(-50%) translateY(-2px); }
  .capture-target.is-capturing > .button { opacity: 0; pointer-events: none; }

  .demo-save { display: grid; place-items: center; width: 100%; font-size: 11.5px; animation: panel-in .6s var(--ease) both; }
  .demo-save :global(.save-panel) { font-size: inherit; }
  .mini-lib { width: 100%; max-width: 520px; overflow: hidden; border-radius: 12px; background: #1e1f1f; box-shadow: 0 0 0 .5px #000000cc, inset 0 0 0 .5px #ffffff24, 0 18px 40px #0000004d; animation: panel-in .5s var(--ease) both; }
  .mini-lib .lib-toolbar { height: 46px; }
  .mini-lib .lib-search { width: 170px; }
  .mini-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 12px; padding: 14px; --thumb-height: 84px; }
  .mini-grid > div { min-width: 0; }
  .is-new { animation: card-land .7s .2s var(--ease) both; }
  .shifted { animation: card-shift .6s .1s var(--ease) both; }
  .mini-inspector { display: flex; align-items: center; gap: 6px; padding: 10px 14px; background: #232424; box-shadow: inset 0 .5px 0 #000000cc; font-size: 11px; }

  .demo-explanation { display: flex; align-items: center; padding: 39px 40px; }
  .demo-copy { width: 100%; max-width: 370px; animation: state-in .4s var(--ease); }
  .demo-copy h3 { margin-bottom: 17px; font-size: 31px; }
  .demo-copy > p { color: var(--secondary); font-size: 14px; line-height: 1.85; }
  .shortcut { display: flex; align-items: center; gap: 6px; margin-top: 27px; }
  .shortcut kbd { display: grid; place-items: center; min-width: 27px; height: 28px; border: 1px solid #61665a; border-radius: 5px; font: 12px system-ui, sans-serif; }
  .shortcut span { margin-left: 6px; color: var(--secondary); font-size: 12px; }
  .demo-copy .demo-hint { margin-top: 22px; color: var(--secondary); font-size: 13px; }
  label { display: block; margin: 23px 0 9px; font-size: 13px; font-weight: 600; }
  textarea { display: block; width: 100%; min-height: 86px; max-height: 170px; padding: 12px; border: 1px solid #69705e; border-radius: 7px; background: #252825; color: var(--paper); font-size: 14px; line-height: 1.7; caret-color: var(--yellow); resize: vertical; }
  .note-meta { display: flex; justify-content: space-between; gap: 10px; margin: 8px 0 19px; color: var(--secondary); font-size: 12px; }
  .note-meta span:last-child { font-variant-numeric: tabular-nums; }
  .demo-copy .button { gap: 12px; min-height: 46px; font-size: 13px; }
  .reference-output { margin: 21px 0 18px; padding: 15px; border: 1px solid #505549; border-radius: 7px; background: #222522; }
  .reference-output > span { color: var(--yellow); font-size: 12px; }
  .reference-output p { margin-top: 9px; color: var(--paper); font-size: 13px; line-height: 1.7; white-space: pre-line; overflow-wrap: anywhere; }
  .copy-status { min-height: 20px; margin-top: 10px; color: var(--yellow); font-size: 12px; }
  .demo-caption { display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 14px 28px; border-top: 1px solid var(--line); color: var(--secondary); font-size: 12px; }

  @keyframes panel-in { from { opacity: 0; transform: translateY(10px) scale(.96); filter: blur(6px); } }
  @keyframes card-land { from { opacity: 0; transform: translateY(-16px) scale(.9); } }
  @keyframes card-shift { from { transform: translateX(calc(-100% - 12px)); } }
  @keyframes state-in { from { opacity: .3; transform: translateY(9px); } }

  @media (max-width: 1100px) {
    .demo-explanation { padding: 30px; }
    .demo-visual { padding: 25px; }
    .shortcut { flex-wrap: wrap; }
  }
  @media (max-width: 760px) {
    .demo-controls { position: relative; gap: 12px; min-height: 62px; padding-inline: 16px; }
    [role='tab'] { gap: 7px; min-height: 62px; font-size: 12px; }
    [role='tab'] span { width: 18px; height: 18px; }
    .replay { gap: 0; font-size: 0; }
    .demo-panel { grid-template-columns: 1fr; }
    .demo-visual { min-height: 324px; padding: 25px; }
    .capture-target { padding: 18px; }
    .capture-target > img { height: 134px; }
    .mini-site-copy { margin-block: 19px 17px; font-size: 30px; }
    .demo-save { font-size: 10px; }
    .mini-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .mini-grid > div:nth-child(3) { display: none; }
    .mini-lib .lib-search { display: none; }
    .demo-explanation { align-items: start; min-height: 330px; padding: 30px 25px; }
    .demo-copy { max-width: none; }
    .demo-copy h3 { font-size: 29px; }
    .demo-caption { display: block; padding: 12px 16px; }
    .demo-caption span { display: block; }
    .demo-caption span + span { margin-top: 4px; }
  }
  @media (max-width: 360px) {
    .demo-controls { gap: 9px; padding-inline: 13px; }
  }
</style>
