/** Independent, least-privilege monitor; credentials belong in the monitor's
 * secret store, never in Vite variables, the repository, or command arguments. */
import { pathToFileURL } from 'node:url';

export async function checkRefresherHealth(env = process.env, request = fetch) {
  const { SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key, MONITOR_EMAIL: email, MONITOR_PASSWORD: password, MONITOR_HEARTBEAT_URL: heartbeat, MONITOR_USER_ID: expectedUserId } = env;
  if (!url || !key || !email || !password || !heartbeat || !expectedUserId) throw new Error('Monitor configuration is incomplete.');
  let base;
  try { base = new URL(url); } catch { throw new Error('Invalid Supabase URL.'); }
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash || base.pathname !== '/') {
    throw new Error('Supabase URL must be a plain HTTPS origin.');
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(expectedUserId)) throw new Error('Monitor user ID is invalid.');
  if (key.startsWith('sb_secret_')) throw new Error('A publishable key is required, not a secret key.');
  // Reject obvious legacy service-role JWTs too. The server still verifies the
  // signature; this check only prevents accidentally using a privileged key.
  if (key.split('.').length === 3) {
    let role;
    try { role = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8')).role; } catch { throw new Error('Invalid legacy API key.'); }
    if (role !== 'anon') throw new Error('A publishable or anon key is required.');
  }
  const post = async (path, headers, body) => {
    let response;
    try {
      response = await request(new URL(path, base), { method: 'POST', headers, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(15000) });
    } catch { throw new Error('Supabase monitor request failed or timed out.'); }
    if (!response.ok) throw new Error(`Supabase monitor request returned HTTP ${response.status}.`);
    try { return await response.json(); } catch { throw new Error('Supabase monitor response was invalid.'); }
  };
  const auth = await post('/auth/v1/token?grant_type=password', { apikey: key, 'Content-Type': 'application/json' }, { email, password });
  if (typeof auth?.access_token !== 'string' || !auth.access_token) throw new Error('Monitor authentication failed.');
  // Never use a session from the wrong account, especially an administrator.
  if (typeof auth.user?.id !== 'string' || auth.user.id.toLowerCase() !== expectedUserId.toLowerCase()) {
    throw new Error('Monitor credentials belong to a different account.');
  }
  const status = await post('/rest/v1/rpc/refresher_monitor_status', {
    apikey: key, Authorization: `Bearer ${auth.access_token}`, 'Content-Type': 'application/json',
  }, {});
  if (!status || status.healthy !== true || status.job_active !== true || status.logging_enabled !== true || typeof status.last_finished !== 'string' || status.recent_errors !== 0 || status.cron_failures !== 0) {
    throw new Error('Refresher scheduler is unhealthy; inspect the operator runbook.');
  }
  // The independent dead-man's-switch receives a ping ONLY on success. If
  // GitHub Actions stops, this script fails, or the job is unhealthy, the
  // missing ping must be configured to alert the operator externally.
  let ping;
  try { ping = new URL(heartbeat); } catch { throw new Error('Invalid heartbeat URL.'); }
  if (ping.protocol !== 'https:' || ping.username || ping.password || ping.hash) throw new Error('Heartbeat URL must use HTTPS.');
  try {
    const result = await request(ping, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000) });
    if (!result.ok) throw new Error('not ok');
  } catch { throw new Error('Independent heartbeat could not be delivered.'); }
  return status;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const status = await checkRefresherHealth();
    console.log(`Refresher scheduler healthy. Last heartbeat: ${status.last_finished}`);
  } catch (error) {
    console.error(`Refresher monitor failed: ${error.message}`);
    process.exitCode = 1;
  }
}
