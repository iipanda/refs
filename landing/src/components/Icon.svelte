<script lang="ts">
  import arrowRight from '../assets/icons/arrow-right.svg?raw';
  import arrowUpRight from '../assets/icons/arrow-up-right.svg?raw';
  import crop from '../assets/icons/crop.svg?raw';
  import rotateClockwise from '../assets/icons/rotate-clockwise.svg?raw';

  const icons = { 'arrow-right': arrowRight, 'arrow-up-right': arrowUpRight, crop, 'rotate-clockwise': rotateClockwise };
  let { name, size = 18 }: { name: keyof typeof icons; size?: number } = $props();
</script>

<span class="icon" style:width="{size}px" style:height="{size}px" aria-hidden="true">{@html icons[name]}</span>

<style>
  .icon { display: inline-flex; flex-shrink: 0; }
  .icon :global(svg) { width: 100%; height: 100%; }
</style>
