// Sample references for the illustrated library. Sources are fictional.
export type ThumbKind = 'capture' | 'pricing' | 'toolbar' | 'type-spec' | 'empty' | 'settings' | 'photo';

export interface Source {
  name: string;
  tile: string;
  letter?: string;
  kind: 'app' | 'website';
  count: number;
}

export interface Tag {
  id: string;
  name: string;
  /** macOS system color, dark appearance. */
  color: string;
  count: number;
}

export interface SampleReference {
  id: string;
  source: string;
  note: string;
  thumb: ThumbKind;
  recent: boolean;
  tags: string[];
  video?: boolean;
}

export const sources: Source[] = [
  { name: 'Sketchbook', tile: 'tile-sketch', kind: 'app', count: 5 },
  { name: 'Field Notes', tile: 'tile-notes', kind: 'app', count: 3 },
  { name: 'forme.example', tile: 'tile-f', letter: 'f', kind: 'website', count: 7 },
  { name: 'paperhouse.example', tile: 'tile-p', letter: 'p', kind: 'website', count: 4 },
  { name: 'northwind.example', tile: 'tile-n', letter: 'n', kind: 'website', count: 3 },
  { name: 'lumen.example', tile: 'tile-l', letter: 'l', kind: 'website', count: 2 },
];

export const tags: Tag[] = [
  { id: 'typography', name: 'Typography', color: '#bf5af2', count: 6 },
  { id: 'calm', name: 'Calm', color: '#63e6e2', count: 5 },
  { id: 'pricing', name: 'Pricing', color: '#32d74b', count: 3 },
  { id: 'icons', name: 'Icons', color: '#ff9f0a', count: 4 },
];

export const tagById = Object.fromEntries(tags.map(tag => [tag.id, tag])) as Record<string, Tag>;

export const sourceByName = Object.fromEntries(sources.map(source => [source.name, source])) as Record<string, Source>;

/** The capture made in the hero; it arrives in the library when it scrolls into view. */
export const newReferenceId = 'forme-big-type';

export const references: SampleReference[] = [
  { id: newReferenceId, source: 'forme.example', note: 'The big type. The breathing room.', thumb: 'capture', recent: true, tags: ['typography', 'calm'] },
  { id: 'paperhouse-pricing', source: 'paperhouse.example', note: 'Pricing that doesn’t shout. One highlighted plan.', thumb: 'pricing', recent: true, tags: ['pricing', 'calm'] },
  { id: 'sketchbook-toolbar', source: 'Sketchbook', note: 'Toolbar icons with one consistent stroke.', thumb: 'toolbar', recent: true, tags: ['icons'], video: true },
  { id: 'northwind-type', source: 'northwind.example', note: 'Type that holds its own.', thumb: 'type-spec', recent: true, tags: ['typography'] },
  { id: 'lumen-empty', source: 'lumen.example', note: 'A friendly empty state that stays brief.', thumb: 'empty', recent: false, tags: ['calm', 'icons'] },
  { id: 'field-notes-settings', source: 'Field Notes', note: 'Settings grouped by intent, not by feature.', thumb: 'settings', recent: false, tags: [] },
  { id: 'forme-quiet', source: 'forme.example', note: 'The quiet colors around a single object.', thumb: 'photo', recent: false, tags: ['calm'] },
];

export const libraryTotal = 24;
export const recentCount = 4;
