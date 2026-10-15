<script lang="ts">
  import { macIcons } from '../lib/macIcons';

  // Mirrors the native save panel: preview, source row, note field and footer actions.
  let { note = '', image, class: className = '', style = '' }: { note?: string; image: string; class?: string; style?: string } = $props();
</script>

<div class="save-panel mac {className}" {style}>
  <span class="sp-close" aria-hidden="true"></span>
  <div class="sp-preview">
    <div class="sp-shot"><span class="sp-shot-type">Less, but<br />considered.</span><img src={image} width="480" height="321" alt="" /></div>
  </div>
  <div class="sp-source">
    <span class="app-icon tile-browser">{@html macIcons.globe}</span>
    <div><b>Objects | forme.</b><small>forme.example/objects · Safari</small></div>
    <span class="sp-edit">Edit</span>
  </div>
  <div class="sp-note" data-placeholder="What do you like about it?"><span class="sp-typed">{note}</span><i class="caret" aria-hidden="true"></i></div>
  <div class="sp-footer"><small>Return to save · Esc to discard</small><span class="mac-btn">Discard</span><span class="mac-btn is-default">Save</span></div>
</div>

<style>
  .save-panel { position: relative; display: flex; flex-direction: column; gap: .92em; width: 30.8em; max-width: 100%; padding: 2.3em 1.23em 1.23em; border-radius: .85em; background: #262626; font-size: 13px; box-shadow: 0 0 0 .5px #000000b3, inset 0 0 0 .5px #ffffff1f, 0 1.4em 3em #00000080; }
  .sp-close { position: absolute; left: .95em; top: .9em; width: .95em; height: .95em; border-radius: 50%; background: #ff5f57; }
  .sp-preview { display: grid; place-items: center; height: 13em; overflow: hidden; border-radius: .62em; background: #1b1b1b; box-shadow: inset 0 0 0 .5px #ffffff26; }
  .sp-shot { display: flex; flex-direction: column; height: 100%; aspect-ratio: 346 / 270; padding: .9em 1em 0; overflow: hidden; background: #f7f5ee; color: var(--ink); }
  .sp-shot-type { font: 600 2.55em/1.02 Bricolage, sans-serif; letter-spacing: -.03em; }
  .sp-shot img { flex: 1; min-height: 0; width: 100%; margin-top: .8em; object-position: center 64%; }
  .sp-source { display: flex; align-items: center; gap: .77em; padding: .77em; border-radius: .77em; background: #ffffff0f; }
  .sp-source b { display: block; font-weight: 600; }
  .sp-source small { display: block; margin-top: .1em; color: #ffffff8c; font-size: .77em; }
  .sp-edit { margin-left: auto; color: var(--mac-accent); }
  .sp-note { position: relative; min-height: 3.7em; padding: .35em .5em; border-radius: .4em; background: #ffffff0d; line-height: 1.35; box-shadow: inset 0 0 0 .5px #ffffff2e, 0 0 0 .24em #ffd60a59; }
  .sp-note:has(.sp-typed:empty)::before { content: attr(data-placeholder); position: absolute; color: #ffffff59; }
  .caret { display: inline-block; width: 1px; height: 1.15em; margin-left: 1px; vertical-align: -.22em; background: #fff; opacity: 0; }
  .sp-footer { display: flex; align-items: center; gap: .6em; }
  .sp-footer small { margin-right: auto; color: #ffffff8c; font-size: .77em; }
</style>
