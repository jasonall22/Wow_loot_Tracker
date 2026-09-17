import test from 'node:test';
import assert from 'node:assert/strict';
import { ACTIONS, permissionsFor, requirePermission, requireID } from '../src/permissions.mjs';
import { GUILD, OTHER_GUILD, OTHER_USER, principal, membership } from './fixtures.mjs';

test('regular member views ordinary data, not comparisons, edits, upload or administration', () => {
  assert.deepEqual(permissionsFor(principal, membership, GUILD), {
    viewRaids: true, viewComparisons: false, editRecords: false, uploadRaids: false, manageMembers: false,
  });
});
test('uploader does not inherit officer privileges', () => {
  assert.deepEqual(permissionsFor(principal, { ...membership, can_upload: true }, GUILD), {
    viewRaids: true, viewComparisons: false, editRecords: false, uploadRaids: true, manageMembers: false,
  });
});
test('officer comparison, edit and upload permissions are independent', () => {
  const officer = { ...membership, role: 'officer' };
  assert.deepEqual(permissionsFor(principal, officer, GUILD), {
    viewRaids: true, viewComparisons: true, editRecords: false, uploadRaids: false, manageMembers: false,
  });
  assert.equal(permissionsFor(principal, { ...officer, can_edit: true }, GUILD).editRecords, true);
  assert.equal(permissionsFor(principal, { ...officer, can_upload: true }, GUILD).editRecords, false);
});
test('admin has all capabilities only within their guild', () => {
  const admin = { ...membership, role: 'admin' };
  assert.ok(Object.values(permissionsFor(principal, admin, GUILD)).every(Boolean));
  assert.ok(Object.values(permissionsFor(principal, admin, OTHER_GUILD)).every(x => x === false));
});
for (const [name, change] of Object.entries({
  revoked: { status: 'revoked' }, suspended: { status: 'suspended' }, invalidRole: { role: 'owner' },
  differentUser: { user_id: OTHER_USER }, differentGuild: { guild_id: OTHER_GUILD },
})) test(`${name} membership fails closed`, () => {
  assert.ok(Object.values(permissionsFor(principal, { ...membership, ...change }, GUILD)).every(x => x === false));
});
test('anonymous, missing and malformed identities cannot enter any guild', () => {
  for (const identity of [null, {}, { ...principal, isAnonymous: true }, { id: principal.id }, { ...principal, id: 'bad' }]) {
    assert.ok(Object.values(permissionsFor(identity, membership, GUILD)).every(x => x === false));
  }
});
test('client metadata never grants officer privileges', () => {
  const identity = { ...principal, role: 'admin', user_metadata: { role: 'admin', can_edit: true } };
  assert.equal(permissionsFor(identity, membership, GUILD).viewComparisons, false);
});
test('truthy strings and member edit flag do not grant elevated permission', () => {
  assert.equal(permissionsFor(principal, { ...membership, can_upload: 'true', can_edit: true }, GUILD).uploadRaids, false);
  assert.equal(permissionsFor(principal, { ...membership, can_edit: true }, GUILD).editRecords, false);
});
test('unknown and prototype capability names cannot pass', () => {
  for (const action of ['toString', '__proto__', 'constructor', 'deleteEverything']) {
    assert.throws(() => requirePermission(principal, { ...membership, role: 'admin' }, GUILD, action), { status: 403 });
  }
  assert.equal(ACTIONS.length, 5);
});
test('identifiers are normalized and injection-like identifiers rejected', () => {
  assert.equal(requireID(GUILD.toUpperCase()), GUILD);
  for (const id of [null, '', '../anything', `${GUILD},role.eq.admin`]) assert.throws(() => requireID(id), { status: 400 });
});
