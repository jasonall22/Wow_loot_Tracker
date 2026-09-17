export class PortalError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = 'PortalError';
    this.status = status;
    this.code = code;
  }
}

export const unauthorized = () => new PortalError(401, 'sign_in_required', 'Sign in again to continue.');
export const forbidden = () => new PortalError(403, 'access_denied', 'You do not have access to this guild or feature.');
export const unavailable = () => new PortalError(503, 'cloud_unavailable', 'The online service is unavailable. Please try again.');
export const badRequest = () => new PortalError(400, 'invalid_request', 'Check the requested view and identifiers.');
export const notFound = () => new PortalError(404, 'not_found', 'That record is not available.');

export function jsonResponse(value, status = 200, extraHeaders = {}) {
  return Response.json(value, {
    status,
    headers: {
      'Cache-Control': 'private, no-store, max-age=0',
      'CDN-Cache-Control': 'no-store',
      'Vercel-CDN-Cache-Control': 'no-store',
      'Vary': 'Authorization',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      ...extraHeaders,
    },
  });
}

export function errorResponse(error) {
  const safe = error instanceof PortalError ? error : unavailable();
  return jsonResponse({ error: { code: safe.code, message: safe.message } }, safe.status);
}
