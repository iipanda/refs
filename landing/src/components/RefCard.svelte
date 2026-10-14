<script lang="ts">
  import { macIcons } from '../lib/macIcons';
  import { sourceByName, tagById, type SampleReference } from '../data/library';
  import RefThumb from './RefThumb.svelte';

  // A library grid card: thumbnail, source line, and a two-line note.
  let { reference, image, note, selected = false, onselect }: {
    reference: SampleReference;
    image: string;
    note?: string;
    selected?: boolean;
    onselect?: () => void;
  } = $props();
  const source = $derived(sourceByName[reference.source]);
  const tags = $derived(reference.tags.map(id => tagById[id]));
</script>

{#snippet body()}
  <RefThumb kind={reference.thumb} {image} />
  <span class="ref-source">
    {#if reference.video}{@html macIcons.video}{/if}
    <span class="app-tile {source.tile}">{source.letter ?? ''}</span><span class="source-name">{reference.source}</span>
    {#if tags.length}
      <span class="tag-dots" title={tags.map(tag => tag.name).join(', ')}>
        {#each tags as tag (tag.id)}<i style:background={tag.color}></i>{/each}
        <span class="visually-hidden">Tagged {tags.map(tag => tag.name).join(', ')}</span>
      </span>
    {/if}
  </span>
  <span class="ref-note">{note ?? reference.note}</span>
{/snippet}

{#if onselect}
  <button type="button" class="ref-card" class:is-selected={selected} aria-pressed={selected} onclick={onselect}>{@render body()}</button>
{:else}
  <div class="ref-card" class:is-selected={selected}>{@render body()}</div>
{/if}

<style>
  .ref-card { display: flex; flex-direction: column; gap: 6px; width: 100%; min-width: 0; padding: 0; border: 0; background: none; color: inherit; font: inherit; text-align: left; }
  button.ref-card { cursor: pointer; }
  .ref-source { display: flex; align-items: center; gap: 5px; overflow: hidden; font-size: 12px; font-weight: 500; white-space: nowrap; }
  .source-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
  .tag-dots { display: flex; flex-shrink: 0; margin-left: auto; padding-left: 4px; }
  .tag-dots i { width: 8px; height: 8px; border-radius: 50%; box-shadow: 0 0 0 1.5px #1e1f1f; }
  .tag-dots i + i { margin-left: -2px; }
  .ref-note { display: -webkit-box; min-height: 2.6em; overflow: hidden; color: #ffffff8c; font-size: 10.5px; line-height: 1.3; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
</style>
