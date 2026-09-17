import { forbidden, unauthorized, badRequest } from './errors.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ROLES = new Set(['admin', 'officer', 'member']);
export const ACTIONS = Object.freeze(['viewRaids', 'viewComparisons', 'editRecords', 'uploadRaids', 'manageMembers']);

export function validID(value) {
  return typeof value === 'string' && UUID.test(value);
}

export function requireID(value) {
  if (!validID(value)) throw badRequest();
  return value.toLowerCase();
}

// Inputs must come from verified Auth identity and a fresh database membership,
// never from request role flags, user_metadata, a UI selection, or a JWT guild claim.
export function permissionsFor(principal, membership, guildID) {
  const denied = Object.fromEntries(ACTIONS.map(action => [action, false]));
  if (!validID(guildID) || !validID(principal?.id) || principal.isAnonymous !== false) return denied;
  if (!membership || membership.user_id !== principal.id || membership.guild_id !== guildID ||
      membership.status !== 'active' || !ROLES.has(membership.role)) return denied;
  const admin = membership.role === 'admin';
  const officer = membership.role === 'officer';
  return {
    viewRaids: true,
    viewComparisons: admin || officer,
    editRecords: admin || (officer && membership.can_edit === true),
    uploadRaids: admin || membership.can_upload === true,
    manageMembers: admin,
  };
}

export function requirePermission(principal, membership, guildID, action) {
  if (!validID(principal?.id) || principal.isAnonymous !== false) throw unauthorized();
  const permissions = permissionsFor(principal, membership, guildID);
  if (!Object.hasOwn(permissions, action) || permissions[action] !== true) throw forbidden();
  return permissions;
}
