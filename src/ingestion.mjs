import { createHash, randomBytes } from 'node:crypto';
import { badRequest } from './errors.mjs';

export const MAX_UPLOAD_BYTES = 1_048_576;
export const PAIRING_TTL_SECONDS = 300;

export function digestSecret(value) {
  if (typeof value !== 'string' || value.length < 32 || value.length > 4096) throw badRequest();
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function createPairingChallenge({ now = Date.now(), random = randomBytes } = {}) {
  const raw = random(32).toString('base64url');
  return {
    raw,
    digest: digestSecret(raw),
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + PAIRING_TTL_SECONDS * 1000).toISOString(),
  };
}

export async function parseUploadBody(request) {
  const length = request.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_UPLOAD_BYTES)) throw badRequest();
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_UPLOAD_BYTES) throw badRequest();
  let body;
  try { body = JSON.parse(text); } catch { throw badRequest(); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw badRequest();
  const required = ['requestId', 'sourceKey', 'sourceRevision', 'payloadHash', 'capturedAt'];
  if (required.some(key => !Object.hasOwn(body, key))) throw badRequest();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.requestId) ||
      typeof body.sourceKey !== 'string' || body.sourceKey.length < 1 || body.sourceKey.length > 200 ||
      !Number.isSafeInteger(body.sourceRevision) || body.sourceRevision < 0 ||
      !/^[a-f0-9]{64}$/.test(body.payloadHash) || !Number.isFinite(Date.parse(body.capturedAt))) throw badRequest();
  return body;
}
