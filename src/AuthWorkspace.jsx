import React, { useEffect, useState } from 'react';
import { ArrowLeft, ArrowRight, CheckCircle2, LockKeyhole, ShieldCheck } from 'lucide-react';
import './styles.css';
import { ConnectedWorkspace } from './ConnectedWorkspace.jsx';

export function AuthWorkspace({ client, configError, onDemo }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(Boolean(client));
  const [mode, setMode] = useState('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [roles, setRoles] = useState([]);
  const [roleError, setRoleError] = useState('');

  useEffect(() => {
    if (!client) return;
    let alive = true;
    let authEventReceived = false;
    const { data: { subscription } } = client.auth.onAuthStateChange((event, nextSession) => {
      if (!alive) return;
      authEventReceived = true;
      setSession(nextSession);
      setLoading(false);
      if (event === 'PASSWORD_RECOVERY') { setMode('newPassword'); setNotice(''); setError(''); }
      if (event === 'SIGNED_OUT') { setMode('signin'); setRoles([]); }
    });
    client.auth.getSession().then(({ data, error: sessionError }) => {
      if (!alive || authEventReceived) return;
      setSession(data?.session || null);
      if (sessionError) setError('Could not restore your session. Please sign in again.');
      setLoading(false);
    }).catch(() => { if (alive && !authEventReceived) { setLoading(false); setError('Could not connect to Supabase.'); } });
    return () => { alive = false; subscription.unsubscribe(); };
  }, [client]);

  useEffect(() => {
    if (!client || !session?.user?.id || mode === 'newPassword') return;
    let alive = true;
    setRoles([]); setRoleError('');
    client.from('user_roles').select('role').eq('user_id', session.user.id).then(({ data, error: queryError }) => {
      if (!alive) return;
      if (queryError) setRoleError('Role information is unavailable. Check that the development migration has been applied.');
      else setRoles((data || []).map(row => row.role));
    }).catch(() => { if (alive) setRoleError('Could not load role information.'); });
    return () => { alive = false; };
  }, [client, session?.user?.id, mode]);

  const changeMode = (next) => { setMode(next); setError(''); setNotice(''); setPassword(''); setConfirmation(''); };
  const submit = async (event) => {
    event.preventDefault(); setBusy(true); setError(''); setNotice('');
    try {
      if (mode === 'signin') {
        const { error: authError } = await client.auth.signInWithPassword({ email: email.trim(), password });
        if (authError) throw authError;
        setPassword('');
      } else if (mode === 'forgot') {
        // Auth redirect URLs must be explicitly allowlisted in Supabase.
        const redirectTo = `${window.location.origin}${window.location.pathname}`;
        const { error: authError } = await client.auth.resetPasswordForEmail(email.trim(), { redirectTo });
        if (authError) throw authError;
        setNotice('If the account exists, password reset instructions will be sent.');
      } else {
        if (password !== confirmation) { setError('The passwords do not match.'); setBusy(false); return; }
        const { error: authError } = await client.auth.updateUser({ password });
        if (authError) throw authError;
        setPassword(''); setConfirmation(''); setMode('signin'); setNotice('Your password has been updated.');
      }
    } catch {
      setError(mode === 'signin' ? 'Unable to sign in. Check your details and try again.' : mode === 'forgot' ? 'Unable to request a reset. Please try again later.' : 'Unable to update your password. Request a new reset link and try again.');
    } finally { setBusy(false); }
  };
  const signOut = async () => {
    setError(''); setBusy(true);
    try { const { error: signOutError } = await client.auth.signOut(); if (signOutError) throw signOutError; }
    catch { setError('Unable to sign out. Please try again.'); }
    finally { setBusy(false); }
  };

  if (!loading && client && session && mode !== 'newPassword') {
    return <ConnectedWorkspace client={client} session={session} roles={roles} roleError={roleError} onSignOut={signOut} signOutBusy={busy} signOutError={error} onDemo={onDemo}/>;
  }

  return <main className="auth-page"><div className="auth-top"><button className="back-link" onClick={onDemo}><ArrowLeft size={15}/> Back to demo</button><span className="demo-pill">Development workspace</span></div><div className="auth-card"><div className="auth-brand"><span className="brand-mark">✳</span><span className="brand-text"><strong>miracle<span>.</span></strong><small>ACADEMY</small></span></div>
    {loading ? <p className="auth-intro" role="status">Checking your session…</p> : !client ? <><div className="auth-symbol"><ShieldCheck size={23}/></div><h1>Connect your workspace</h1><p className="auth-intro">The development project is not connected to this preview yet. Follow the setup guide to configure a project URL and publishable key.</p><div className="auth-alert" role="status">{configError || 'Supabase is not configured yet.'} Never put secret or service-role keys in browser configuration.</div><button className="button secondary full" onClick={onDemo}>Explore the demo instead</button></> : <><div className="auth-symbol"><LockKeyhole size={22}/></div><div className="section-kicker">MIRACLE ACADEMY · DEVELOPMENT</div><h1>{mode === 'forgot' ? 'Reset your password' : mode === 'newPassword' ? 'Choose a new password' : 'Welcome back.'}</h1><p className="auth-intro">{mode === 'forgot' ? 'Enter your email and we’ll send reset instructions.' : mode === 'newPassword' ? 'Enter your new password below.' : 'Sign in with your academy email and password.'}</p><form onSubmit={submit}>
      {mode !== 'newPassword' && <label className="field"><span>Email address</span><input autoComplete="email" type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@example.com"/></label>}
      {mode !== 'forgot' && <label className="field"><span>{mode === 'newPassword' ? 'New password' : 'Password'}</span><input autoComplete={mode === 'newPassword' ? 'new-password' : 'current-password'} type="password" minLength={mode === 'newPassword' ? 8 : undefined} required value={password} onChange={e=>setPassword(e.target.value)} /></label>}
      {mode === 'newPassword' && <label className="field"><span>Confirm new password</span><input autoComplete="new-password" type="password" minLength="8" required value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></label>}
      {error && <p className="auth-error" role="alert">{error}</p>}{notice && <p className="auth-success" role="status">{notice}</p>}
      <button type="submit" className="button primary full" disabled={busy}>{busy ? 'Please wait…' : mode === 'forgot' ? 'Send reset instructions' : mode === 'newPassword' ? 'Update password' : 'Sign in'} <ArrowRight size={15}/></button>
    </form>{mode === 'signin' ? <button className="auth-text-button" onClick={()=>changeMode('forgot')}>Forgot your password?</button> : mode === 'forgot' && <button className="auth-text-button" onClick={()=>changeMode('signin')}>Back to sign in</button>}
    <p className="auth-footnote">Accounts are created by an administrator. Use test accounts only.</p></>}
  </div></main>;
}
