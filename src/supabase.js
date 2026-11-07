import { createClient } from '@supabase/supabase-js';

// Vite exposes every VITE_ value in browser code. Only a publishable/anon key
// belongs here; authorization is enforced in the database, not by this key.
export function createConfiguredClient(url = import.meta.env.VITE_SUPABASE_URL, key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY) {
  if (!url || !key) return { client: null, error: 'Supabase is not configured yet.' };
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) throw new Error('Invalid project URL');
    if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('Invalid project URL');
    if (key.startsWith('sb_secret_')) throw new Error('A secret key must never be used in the browser.');
    // Legacy JWT service_role keys are also secret. Reject obvious mistakes.
    if (key.split('.').length === 3) {
      try {
        const payload = JSON.parse(atob(key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
        if (payload.role === 'service_role') throw new Error('A service-role key must never be used in the browser.');
      } catch (error) { if (error.message.includes('service-role')) throw error; }
    }
    return { client: createClient(url, key, { auth: { flowType: 'pkce' } }), error: null };
  } catch (error) {
    return { client: null, error: error.message || 'Invalid Supabase configuration.' };
  }
}
