<script lang="ts">
  import type { ThumbKind } from '../data/library';

  let { kind, image }: { kind: ThumbKind; image: string } = $props();
</script>

<span class="ref-thumb th-{kind}">
  {#if kind === 'capture'}
    <span class="th-type">Less, but<br />considered.</span><img src={image} width="420" height="281" alt="" />
  {:else if kind === 'pricing'}
    <i></i><i></i><i></i>
  {:else if kind === 'toolbar'}
    <i></i><i></i><i></i><i></i><i></i>
  {:else if kind === 'type-spec'}
    <span>Make<br />room.</span>
  {:else if kind === 'empty'}
    <i></i><b></b><b></b>
  {:else if kind === 'settings'}
    <i></i><i></i><i></i><i></i>
  {:else}
    <img src={image} width="420" height="281" alt="" />
  {/if}
</span>

<style>
  .ref-thumb { position: relative; display: block; height: var(--thumb-height, 104px); overflow: hidden; border-radius: 8px; background: #ffffff0f; }
  .ref-thumb::after { content: ''; position: absolute; inset: 0; border-radius: inherit; box-shadow: inset 0 0 0 .5px #ffffff1f; transition: box-shadow .2s; pointer-events: none; }
  :global(.is-selected) > .ref-thumb::after { box-shadow: inset 0 0 0 3px var(--mac-accent); }
  .th-capture { padding: 9px 10px; background: #f7f5ee; color: var(--ink); }
  .th-type { display: block; font: 600 17px/1.02 Bricolage, sans-serif; letter-spacing: -.03em; }
  .th-capture img { position: absolute; left: 10px; bottom: 0; width: calc(100% - 20px); height: 42%; object-position: center 62%; }
  .th-pricing { display: flex; align-items: flex-end; gap: 6px; padding: 14px 12px 0; background: #ebe8de; }
  .th-pricing i { flex: 1; height: 72%; border-radius: 4px 4px 0 0; background: linear-gradient(#262820 0 0) 8px 11px / 42% 4px no-repeat, linear-gradient(#26282040 0 0) 8px 23px / 62% 3px no-repeat, linear-gradient(#26282040 0 0) 8px 31px / 48% 3px no-repeat, #fff; }
  .th-pricing i:nth-child(2) { height: 88%; background-color: var(--mac-accent); }
  .th-toolbar { display: flex; gap: 8px; padding: 12px; background: #2b2d2c; }
  .th-toolbar::before { content: ''; position: absolute; inset: 40px 12px -8px; border-radius: 6px; background: #383b39; }
  .th-toolbar i { width: 15px; height: 15px; border: 1.5px solid #e9e6da; border-radius: 4px; }
  .th-toolbar i:nth-child(2) { border-radius: 50%; }
  .th-toolbar i:nth-child(3) { border-color: var(--mac-accent); }
  .th-toolbar i:nth-child(4) { border-radius: 2px 8px; }
  .th-type-spec { padding: 12px 13px; background: #292d27; color: #f4f1e9; }
  .th-type-spec span { font: 700 31px/.95 Bricolage, sans-serif; letter-spacing: -.03em; }
  .th-empty { display: flex; flex-direction: column; align-items: center; gap: 6px; padding-top: 18px; background: #f4f1e9; }
  .th-empty i { width: 34px; height: 34px; margin-bottom: 4px; border-radius: 50%; background: #e2e5d6; box-shadow: inset 0 0 0 1.5px #b5bba3; }
  .th-empty b { width: 56%; height: 5px; border-radius: 3px; background: #5d5c45; }
  .th-empty b + b { width: 38%; height: 4px; background: #b5bba3; }
  .th-settings { display: flex; flex-direction: column; padding: 10px 12px; background: #232524; }
  .th-settings i { height: 19px; background: linear-gradient(#ffffff8c 0 0) 8px 50% / 36% 3px no-repeat, linear-gradient(var(--mac-accent) 0 0) right 8px top 50% / 15px 8px no-repeat, #2f3230; box-shadow: inset 0 -.5px 0 #ffffff1a; }
  .th-settings i:first-child { border-radius: 5px 5px 0 0; }
  .th-settings i:nth-child(2) { border-radius: 0 0 5px 5px; box-shadow: none; }
  .th-settings i:nth-child(3) { margin-top: 7px; border-radius: 5px 5px 0 0; }
  .th-settings i:nth-child(4) { border-radius: 0 0 5px 5px; box-shadow: none; }
  .th-photo img { width: 100%; height: 100%; object-position: center 64%; }
</style>
