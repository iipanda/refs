export const EASE = 'cubic-bezier(.16,1,.3,1)';

export const prefersReducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

export const wait = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

/** Runs `update` with an ease-out progress value from 0 to 1. */
export function tween(duration: number, update: (progress: number) => void) {
  return new Promise<void>(resolve => {
    const start = performance.now();
    const frame = (now: number) => {
      const progress = Math.min(1, (now - start) / duration);
      update(1 - Math.pow(1 - progress, 3));
      if (progress < 1) requestAnimationFrame(frame);
      else resolve();
    };
    requestAnimationFrame(frame);
  });
}

export function whenVisible(element: Element, callback: () => void, threshold = .4) {
  const observer = new IntersectionObserver(entries => {
    if (!entries.some(entry => entry.isIntersecting)) return;
    observer.disconnect();
    callback();
  }, { threshold });
  observer.observe(element);
}

/** One-time scroll moments only arm when their element starts below the fold. */
export const canAnimateOnScroll = (element: Element) =>
  !prefersReducedMotion() && 'IntersectionObserver' in window && element.getBoundingClientRect().top > innerHeight * .6;

/** Scales a fixed-size illustration to its column width. */
export function fitStage(stage: HTMLElement) {
  const parent = stage.parentElement!;
  const fit = () => {
    stage.style.zoom = String(parent.clientWidth / Number(getComputedStyle(stage).getPropertyValue('--design-w')));
  };
  new ResizeObserver(fit).observe(parent);
  fit();
}

export const stageZoom = (element: Element) => Number((element.closest('.stage') as HTMLElement | null)?.style.zoom) || 1;
