<script lang="ts">
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import { expoOut } from 'svelte/easing';
  import RefCard from './RefCard.svelte';
  import { macIcons } from '../lib/macIcons';
  import { canAnimateOnScroll, fitStage, stageZoom, wait, whenVisible } from '../lib/motion';
  import { libraryTotal, newReferenceId, recentCount, references, sourceByName, sources, tagById, tags, type SampleReference } from '../data/library';

  let { image }: { image: string } = $props();

  let stage: HTMLElement;
  let filter = $state('all');
  let query = $state('');
  let selected = $state<string | null>(null);
  let arrived = $state(true);
  let total = $state(libraryTotal);
  let formeCount = $state(sourceByName['forme.example'].count);
  let tagCounts = $state(Object.fromEntries(tags.map(tag => [tag.id, tag.count])) as Record<string, number>);
  const newTags = references.find(reference => reference.id === newReferenceId)!.tags;
  let ticking = $state(false);

  // Filters: 'all', 'recent', a source name, or 'tag:<id>'.
  const tagFilter = $derived(filter.startsWith('tag:') ? filter.slice(4) : null);
  const inFilter = (reference: SampleReference) =>
    filter === 'all' || (filter === 'recent' ? reference.recent : tagFilter ? reference.tags.includes(tagFilter) : reference.source === filter);
  const matches = (reference: SampleReference) => {
    const needle = query.trim().toLowerCase();
    const tagNames = reference.tags.map(id => tagById[id].name).join(' ');
    return !needle || `${reference.source} ${reference.note} ${tagNames}`.toLowerCase().includes(needle);
  };
  const visible = $derived(references.filter(reference => (arrived || reference.id !== newReferenceId) && inFilter(reference) && matches(reference)));
  const badgeCount = (name: string) => (name === 'forme.example' ? formeCount : sourceByName[name].count);
  const title = $derived(filter === 'all' ? 'All References' : filter === 'recent' ? 'Recent' : tagFilter ? tagById[tagFilter].name : filter);
  const count = $derived(query.trim() ? visible.length : filter === 'all' ? total : filter === 'recent' ? recentCount : tagFilter ? tagCounts[tagFilter] : badgeCount(filter));
  const plural = (value: number) => `${value} reference${value === 1 ? '' : 's'}`;

  // FLIP under CSS zoom: measured deltas are in zoomed pixels, transforms are not.
  function reflow(node: Element, { from, to }: { from: DOMRect; to: DOMRect }) {
    const zoom = stageZoom(node);
    const dx = (from.left - to.left) / zoom;
    const dy = (from.top - to.top) / zoom;
    return { duration: 560, easing: expoOut, css: (_: number, u: number) => `transform: translate(${u * dx}px, ${u * dy}px)` };
  }
  function appear(_: Element, { arrival = false } = {}) {
    return arrival
      ? { duration: 750, easing: expoOut, css: (t: number) => `opacity: ${t}; transform: translateY(${(1 - t) * -22}px) scale(${.88 + .12 * t})` }
      : { duration: 420, easing: expoOut, css: (t: number) => `opacity: ${t}; transform: scale(${.92 + .08 * t})` };
  }

  onMount(() => {
    fitStage(stage);
    if (!canAnimateOnScroll(stage)) return;
    arrived = false;
    total = libraryTotal - 1;
    formeCount -= 1;
    for (const id of newTags) tagCounts[id] -= 1;
    whenVisible(stage, async () => {
      await wait(350);
      arrived = true;
      await wait(450);
      ticking = true;
      total = libraryTotal;
      formeCount += 1;
      for (const id of newTags) tagCounts[id] += 1;
      await wait(250);
      selected = newReferenceId;
    });
  });
</script>

<div class="stage-fit">
  <div class="stage lib-stage" bind:this={stage}>
    <div class="lib mac mac-window" role="group" aria-label="Interactive sample library">
      <div class="lib-side">
        <span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>
        <button type="button" class="side-item" aria-pressed={filter === 'all'} onclick={() => (filter = 'all')}>
          {@html macIcons.grid}All References
          {#key total}<span class="badge" class:is-ticking={ticking}>{total}</span>{/key}
        </button>
        <button type="button" class="side-item" aria-pressed={filter === 'recent'} onclick={() => (filter = 'recent')}>
          {@html macIcons.clock}Recent<span class="badge">{recentCount}</span>
        </button>
        <span class="side-item">{@html macIcons.trash}Trash</span>
        {#each [['Apps', 'app'], ['Websites', 'website']] as [heading, kind]}
          <span class="side-head">{heading}</span>
          {#each sources.filter(source => source.kind === kind) as source (source.name)}
            <button type="button" class="side-item" aria-pressed={filter === source.name} onclick={() => (filter = source.name)}>
              <span class="app-tile {source.tile}">{source.letter ?? ''}</span>{source.name}
              {#key badgeCount(source.name)}<span class="badge" class:is-ticking={ticking && source.name === 'forme.example'}>{badgeCount(source.name)}</span>{/key}
            </button>
          {/each}
        {/each}
        <span class="side-head">Tags</span>
        {#each tags as tag (tag.id)}
          <button type="button" class="side-item" aria-pressed={filter === `tag:${tag.id}`} onclick={() => (filter = `tag:${tag.id}`)}>
            <span class="tag-dot" style:background={tag.color}></span>{tag.name}
            {#key tagCounts[tag.id]}<span class="badge" class:is-ticking={ticking && newTags.includes(tag.id)}>{tagCounts[tag.id]}</span>{/key}
          </button>
        {/each}
        <span class="side-settings">{@html macIcons.gear}Settings</span>
      </div>
      <div class="lib-main">
        <div class="lib-toolbar">
          <span class="lib-toggle" aria-hidden="true">{@html macIcons.sidebar}</span>
          <div class="lib-title"><b>{title}</b><small aria-live="polite">{plural(count)}</small></div>
          <label class="lib-search">
            {@html macIcons.search}<span class="visually-hidden">Search the sample library</span>
            <input type="search" placeholder="Search notes, sites, apps" autocomplete="off" bind:value={query} />
          </label>
        </div>
        <div class="lib-grid">
          {#each visible as reference (reference.id)}
            <div class="cell" animate:reflow in:appear={{ arrival: reference.id === newReferenceId }} out:fade={{ duration: 150 }}>
              <RefCard {reference} {image} selected={selected === reference.id} onselect={() => (selected = selected === reference.id ? null : reference.id)} />
            </div>
          {:else}
            <p class="lib-empty">No matches</p>
          {/each}
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .stage-fit { width: 100%; }
  .lib-stage { --design-w: 760; width: 760px; }
  .lib { display: grid; grid-template-columns: 186px 1fr; grid-template-rows: minmax(0, 1fr); height: 568px; background: #1e1f1f; font-size: 12px; }
  .lib-side { position: relative; display: flex; flex-direction: column; gap: 1px; padding: 46px 9px 0; background: #2a2a2b; box-shadow: inset -.5px 0 0 #000000b3; }
  .lib-side > .lights { position: absolute; left: 16px; top: 17px; }
  .side-item { display: flex; align-items: center; gap: 7px; width: 100%; height: 26px; padding: 0 8px; border: 0; border-radius: 6px; background: none; color: #ffffffe0; font: inherit; text-align: left; white-space: nowrap; }
  button.side-item { cursor: pointer; }
  button.side-item:hover { background: #ffffff0d; }
  .side-item[aria-pressed='true'] { background: #ffffff1f; }
  .side-item :global(svg) { flex-shrink: 0; width: 15px; height: 15px; color: var(--mac-accent); }
  .side-item .app-tile { width: 15px; height: 15px; }
  .tag-dot { flex-shrink: 0; width: 10px; height: 10px; margin-inline: 2.5px; border-radius: 50%; box-shadow: inset 0 0 0 .5px #00000040; }
  .badge { margin-left: auto; color: #ffffff73; font-size: 11px; font-variant-numeric: tabular-nums; }
  .badge.is-ticking { animation: badge-pop .5s var(--ease); }
  .side-head { padding: 11px 8px 3px; color: #ffffff59; font-size: 10.5px; font-weight: 600; }
  .side-settings { display: flex; align-items: center; gap: 7px; margin: auto -9px 0; padding: 12px 18px; color: #ffffff8c; }
  .side-settings :global(svg) { width: 15px; height: 15px; }
  .lib-main { display: flex; flex-direction: column; min-width: 0; min-height: 0; }
  .lib-toggle :global(svg) { display: block; width: 17px; height: 17px; color: #ffffff8c; }
  .lib-search:focus-within { box-shadow: 0 0 0 3px #ffd60a66; }
  .lib-search input { flex: 1; min-width: 0; border: 0; background: none; color: #fff; font: 12px var(--mac-font); outline: 0; }
  .lib-search input::placeholder { color: #ffffff66; }
  .lib-search input::-webkit-search-cancel-button { filter: invert(1) opacity(.5); }
  .lib-grid { position: relative; display: grid; flex: 1; min-height: 0; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px 16px; align-content: start; padding: 16px; overflow: hidden; }
  .cell { min-width: 0; }
  .lib-empty { grid-column: 1 / -1; margin: 90px 0 0; color: #ffffff8c; text-align: center; }
  @keyframes badge-pop { 40% { color: var(--mac-accent); transform: scale(1.25); } }
  @media (max-width: 760px) {
    .lib-stage { --design-w: 460; width: 460px; }
    .lib { grid-template-columns: 1fr; height: 540px; }
    .lib-side { display: none; }
    .lib-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  }
</style>
