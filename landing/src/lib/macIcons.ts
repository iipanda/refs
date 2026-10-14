// SF Symbol stand-ins drawn for the native UI illustrations.
const stroke = 'fill="none" stroke="currentColor" stroke-width="1.2"';

export const macIcons = {
  viewfinder: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 5V3a1.5 1.5 0 0 1 1.5-1.5h2M11 1.5h2A1.5 1.5 0 0 1 14.5 3v2M14.5 11v2a1.5 1.5 0 0 1-1.5 1.5h-2M5 14.5H3A1.5 1.5 0 0 1 1.5 13v-2" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/><circle cx="8" cy="8" r="2.2" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
  globe: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="5.6" ${stroke}/><path d="M2.6 8h10.8M8 2.4c1.6 1.6 2.3 3.6 2.3 5.6S9.6 12 8 13.6M8 2.4C6.4 4 5.7 6 5.7 8s.7 4 2.3 5.6" ${stroke}/></svg>`,
  search: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.4" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="m10.4 10.4 3.2 3.2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  sidebar: `<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2.2" ${stroke}/><path d="M6 2.5v11" ${stroke}/></svg>`,
  grid: `<svg viewBox="0 0 16 16" aria-hidden="true"><g ${stroke}><rect x="2" y="2" width="5" height="5" rx="1.2"/><rect x="9" y="2" width="5" height="5" rx="1.2"/><rect x="2" y="9" width="5" height="5" rx="1.2"/><rect x="9" y="9" width="5" height="5" rx="1.2"/></g></svg>`,
  clock: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="5.8" ${stroke}/><path d="M8 4.6V8l2.3 1.4" ${stroke} stroke-linecap="round"/></svg>`,
  trash: `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 4.5h10M6.3 4.5V3h3.4v1.5M4.4 4.5l.7 8.6c.1.8.6 1.4 1.4 1.4h3c.8 0 1.3-.6 1.4-1.4l.7-8.6" ${stroke} stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  gear: `<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="2.1" ${stroke}/><path d="M8 1.8v1.6M8 12.6v1.6M1.8 8h1.6M12.6 8h1.6M3.6 3.6l1.1 1.1M11.3 11.3l1.1 1.1M3.6 12.4l1.1-1.1M11.3 4.7l1.1-1.1" ${stroke} stroke-linecap="round"/></svg>`,
  video: '<svg class="video-badge" viewBox="0 0 16 16" role="img" aria-label="Video"><rect x="1.5" y="3" width="13" height="10" rx="2.2" fill="currentColor"/><path d="M6.6 5.9v4.2l3.6-2.1z" fill="#1e1f1f"/></svg>',
  crosshair: '<svg class="crosshair" viewBox="0 0 22 22" aria-hidden="true"><path d="M11 1v8M11 13v8M1 11h8M13 11h8" stroke="#000" stroke-width="3"/><path d="M11 1v8M11 13v8M1 11h8M13 11h8" stroke="#fff" stroke-width="1.2"/></svg>',
};
