import React, { useState } from 'react';
import { App } from './App.jsx';
import { AuthWorkspace } from './AuthWorkspace.jsx';
import { createConfiguredClient } from './supabase.js';

// PKCE recovery links return to this page with a code; start auth immediately
// rather than showing demo data. No private key is ever included in the client.
export function Root() {
  const [configured] = useState(() => createConfiguredClient());
  const [showAuth, setShowAuth] = useState(() => new URLSearchParams(window.location.search).has('code') || window.location.hash.includes('type=recovery'));
  return showAuth
    ? <AuthWorkspace client={configured.client} configError={configured.error} onDemo={() => setShowAuth(false)} />
    : <App onOpenAuth={() => setShowAuth(true)} />;
}
