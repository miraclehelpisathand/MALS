// @vitest-environment jsdom
import React from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { App } from '../App.jsx';

beforeEach(() => localStorage.clear());
afterEach(() => cleanup());

describe('Miracle Academy demo', () => {
  it('creates a draft course and adds a module and block', async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(screen.getByRole('button', { name: /create course/i }));
    await user.type(screen.getByLabelText('Course name'), 'Safe working');
    await user.click(screen.getByRole('button', { name: /create draft/i }));
    expect(screen.getByRole('heading', { name: 'Safe working' })).toBeTruthy();
    await user.click(screen.getByRole('button', { name: /add module/i }));
    await user.type(screen.getByLabelText('Module name'), 'Getting started');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /^add module$/i }));
    await user.click(screen.getByRole('button', { name: /add block/i }));
    await user.selectOptions(screen.getByLabelText('Block type'), 'Quiz');
    await user.type(screen.getByLabelText('Block title'), 'Quick check');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /^add block$/i }));
    expect(screen.getByText('Quick check')).toBeTruthy();
  });

  it('adds a demo trainee with a separate date for every group course', async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(screen.getByRole('button', { name: 'People' }));
    await user.click(screen.getByRole('button', { name: /add demo person/i }));
    await user.type(screen.getByLabelText('Name'), 'Alex Example');
    await user.type(screen.getByLabelText('Demo email'), 'alex@example.com');
    await user.click(screen.getByRole('button', { name: /^add person$/i }));
    await user.click(screen.getByRole('button', { name: /add trainee/i }));
    await user.selectOptions(screen.getByLabelText('Trainee'), screen.getByRole('option', { name: 'Alex Example' }).value);
    const dates = screen.getAllByLabelText(/target date/i);
    expect(dates).toHaveLength(3);
    await user.type(dates[0], '2027-01-01');
    await user.type(dates[1], '2027-02-01');
    await user.type(dates[2], '2027-03-01');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /add trainee/i }));
    expect(screen.getByText('Alex Example')).toBeTruthy();
    const stored = JSON.parse(localStorage.getItem('miracle-academy-demo-v1'));
    const alex = stored.people.find(p => p.name === 'Alex Example');
    expect(stored.assignments.filter(a => a.person === alex.id).map(a => a.due)).toEqual(['2027-01-01', '2027-02-01', '2027-03-01']);
  });

  it('requires every practical criterion before sign-off', async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(within(screen.getByRole('navigation', { name: 'Main navigation' })).getByRole('button', { name: /assessments/i }));
    await user.click(screen.getAllByRole('button', { name: /^review/i })[0]);
    const dialog = screen.getByRole('dialog');
    const signOff = within(dialog).getByRole('button', { name: /sign off assessment/i });
    expect(signOff.disabled).toBe(true);
    for (const checkbox of within(dialog).getAllByRole('checkbox')) await user.click(checkbox);
    expect(signOff.disabled).toBe(false);
    await user.click(signOff);
    expect(screen.getByText('Signed off')).toBeTruthy();
  });
});
