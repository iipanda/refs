import { downloadUrl } from '../lib/links';

export const helperPath = '/Applications/Refs.app/Contents/MacOS/refs-mcp';

// The connect step matches Settings › Agents in the app (Sources/Refs/Settings/SettingsView.swift).
export const setupPrompt = `Set up Refs, a Mac app for saving UI references, and connect it to this agent:
1. If /Applications/Refs.app doesn't exist, download ${downloadUrl} with curl -fL, mount the DMG with hdiutil, copy Refs.app to /Applications, eject the disk image and open Refs.
2. Add a stdio MCP server named "refs" that runs ${helperPath} with no arguments to your user-level config, keeping existing servers.
3. Call get_library_info to confirm it works, or tell me if you need a restart.`;

// Agents with setup instructions in Settings › Agents. Any MCP client that runs stdio servers also works.
// `logo` names a file in src/assets/agents.
export const supportedAgents = [
  { name: 'Claude Code', logo: 'claudecode' },
  { name: 'Codex', logo: 'codex' },
  { name: 'Cursor', logo: 'cursor' },
  { name: 'Claude Desktop', logo: 'claude' },
  { name: 'Pi Agent', logo: 'pi' },
  { name: 'Oh My Pi', logo: 'ohmypi' },
] as const;

export const claudeCommand = `claude mcp add --scope user refs -- ${helperPath}`;
