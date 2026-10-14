export const helperPath = '/Applications/Refs.app/Contents/MacOS/refs-mcp';

/** Replaced in the browser with the absolute URL of the download on the current site. */
export const downloadToken = '{download-url}';

// The connect step matches Settings › Agents in the app (Sources/Refs/Settings/SettingsView.swift).
// curl leaves no quarantine flag, so the development build opens without a Gatekeeper prompt.
export const setupPrompt = `Set up Refs, a Mac app for saving UI references, and connect it to this agent:
1. If /Applications/Refs.app doesn't exist, download ${downloadToken} with curl, unzip it, move Refs.app to /Applications and open it.
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
