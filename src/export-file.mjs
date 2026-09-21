// Read one encoded raid from WoW SavedVariables without evaluating Lua.
// The full SavedVariables file stays in the browser; only the decoded raid is sent.
export function extractRaidExport(savedVariables) {
  if (typeof savedVariables !== 'string') throw new Error('Choose APOCLootTrackerBeta.lua.');
  const match = savedVariables.match(/^APOCLootTrackerBetaExport\s*=\s*"([A-Za-z0-9+/]+={0,2})"\s*$/m);
  if (!match) throw new Error('No raid export found. Click Export in Loot Tracker, then type /reload before choosing the file.');
  if (match[1].length > 1_500_000 || match[1].length % 4 !== 0) throw new Error('Raid export is too large or damaged.');
  let raid;
  try {
    const binary = atob(match[1]);
    const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
    raid = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch { throw new Error('The raid export is damaged or incomplete.'); }
  if (raid?.format !== 'apoc-loot-tracker-export-v1' || !raid.session || !Array.isArray(raid.drops) || !Array.isArray(raid.members)) {
    throw new Error('This is not a supported Loot Tracker raid export.');
  }
  return raid;
}
