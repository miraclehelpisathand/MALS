// @vitest-environment jsdom
import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AuthWorkspace } from '../AuthWorkspace.jsx';
import { createConfiguredClient } from '../supabase.js';

vi.mock('../ConnectedWorkspace.jsx', () => ({ ConnectedWorkspace: ({roles, onSignOut}) => <div><h1>You’re signed in</h1><p>The course and group screens are still separate demonstration data.</p><p>Assigned roles: {roles.join(', ')}</p><button onClick={onSignOut}>Sign out</button></div> }));

afterEach(() => cleanup());
function mockClient() {
  let callback;
  const client = {
    auth: {
      onAuthStateChange: vi.fn(fn => { callback = fn; return { data: { subscription: { unsubscribe: vi.fn() } } }; }),
      getSession: vi.fn(async () => ({ data: { session: null }, error: null })),
      signInWithPassword: vi.fn(async () => ({ error: null })),
      resetPasswordForEmail: vi.fn(async () => ({ error: null })),
      updateUser: vi.fn(async () => ({ error: null })),
      signOut: vi.fn(async () => ({ error: null })),
    },
    from: vi.fn(() => ({ select: () => ({ eq: async () => ({ data: [{ role: 'leader' }], error: null }) }) })),
  };
  return { client, emit: (event, session) => act(() => callback(event, session)) };
}

describe('development sign-in', () => {
  it('keeps the demo separate when configuration is missing', () => {
    render(<AuthWorkspace client={null} configError="Supabase is not configured yet." onDemo={() => {}} />);
    expect(screen.getByRole('heading', { name: 'Connect your workspace' })).toBeTruthy();
    expect(screen.queryByLabelText('Password')).toBeNull();
  });
  it('signs in, loads the caller’s roles and signs out', async () => {
    const { client, emit } = mockClient(); const user = userEvent.setup();
    render(<AuthWorkspace client={client} onDemo={() => {}} />);
    await screen.findByRole('heading', { name: 'Welcome back.' });
    await user.type(screen.getByLabelText('Email address'), 'alex@example.test');
    await user.type(screen.getByLabelText('Password'), 'safe-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(client.auth.signInWithPassword).toHaveBeenCalledWith({ email: 'alex@example.test', password: 'safe-password' });
    emit('SIGNED_IN', { user: { id: 'abc', email: 'alex@example.test' } });
    await screen.findByText('Assigned roles: leader');
    expect(screen.getByText(/still separate demonstration data/)).toBeTruthy();
    await user.click(screen.getByRole('button', { name: 'Sign out' }));
    expect(client.auth.signOut).toHaveBeenCalled();
    emit('SIGNED_OUT', null);
    expect(screen.getByRole('heading', { name: 'Welcome back.' })).toBeTruthy();
  });
  it('requests a reset and handles the recovery event', async () => {
    const { client, emit } = mockClient(); const user = userEvent.setup();
    render(<AuthWorkspace client={client} onDemo={() => {}} />);
    await screen.findByRole('heading', { name: 'Welcome back.' });
    await user.click(screen.getByRole('button', { name: /forgot your password/i }));
    await user.type(screen.getByLabelText('Email address'), 'alex@example.test');
    await user.click(screen.getByRole('button', { name: /send reset instructions/i }));
    expect(client.auth.resetPasswordForEmail).toHaveBeenCalledWith('alex@example.test', { redirectTo: `${window.location.origin}${window.location.pathname}` });
    expect(screen.getByRole('status').textContent).toMatch(/if the account exists/i);
    emit('PASSWORD_RECOVERY', { user: { id:'abc', email:'alex@example.test' } });
    await user.type(screen.getByLabelText('New password'), 'newpassword123');
    await user.type(screen.getByLabelText('Confirm new password'), 'newpassword123');
    await user.click(screen.getByRole('button', { name: 'Update password' }));
    await waitFor(() => expect(client.auth.updateUser).toHaveBeenCalledWith({password:'newpassword123'}));
    expect(screen.getByRole('heading', { name: 'You’re signed in' })).toBeTruthy();
  });
  it('rejects secret and legacy service-role browser keys', () => {
    expect(createConfiguredClient('https://example.supabase.co', 'sb_secret_123').client).toBeNull();
    const payload = btoa(JSON.stringify({role:'service_role'}));
    expect(createConfiguredClient('https://example.supabase.co', `header.${payload}.signature`).client).toBeNull();
    expect(createConfiguredClient('http://insecure.example.com', 'sb_publishable_123').client).toBeNull();
  });
});
