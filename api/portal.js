import { createPortalHandler } from '../src/api.mjs';

// Vercel Node.js Web Handler. No deployment or project binding is made by this file.
export default { fetch: createPortalHandler() };
