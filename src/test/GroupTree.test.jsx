// @vitest-environment jsdom
import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { buildGroupForest, groupPath, GroupTree } from '../GroupTree.jsx';

afterEach(cleanup);
const groups = [
  {id:'child', name:'North', parent_id:'root'},
  {id:'other', name:'Administration', parent_id:null},
  {id:'grandchild', name:'Ward A', parent_id:'child'},
  {id:'root', name:'Care', parent_id:null},
  {id:'orphan', name:'Training', parent_id:'not-visible'},
];
const memberships = [{group_id:'root',status:'active'},{group_id:'root',status:'archived'},{group_id:'grandchild',status:'active'}];
describe('group hierarchy', () => {
  it('nests visible descendants in order and keeps a subgroup with an unseen parent visible', () => {
    const forest = buildGroupForest(groups);
    expect(forest.map(n=>n.group.name)).toEqual(['Administration', 'Care', 'Training']);
    expect(forest[1].children[0].group.name).toBe('North');
    expect(forest[1].children[0].children[0].group.name).toBe('Ward A');
    expect(forest[2].missingParent).toBe(true);
    expect(groupPath(groups[2],groups)).toBe('Care / North / Ward A');
    expect(groupPath(groups[4],groups)).toBe('Parent outside your view / Training');
    render(<GroupTree groups={groups} memberships={memberships} selectedId="" onSelect={()=>{}}/>);
    const tree = screen.getByRole('list', {name:'Group hierarchy'});
    const care = within(tree).getByRole('button',{name:/^CareGroup/}).closest('li');
    const north = within(care).getByRole('button',{name:/^NorthSubgroup/}).closest('li');
    expect(within(north).getByRole('button',{name:/^Ward ASubgroup/})).toBeTruthy();
    expect(within(care).getByText('Group · 1 active')).toBeTruthy();
    expect(within(tree).getByText(/parent outside your view/)).toBeTruthy();
  });
  it('expands and collapses branches independently without selecting a group', async () => {
    const user = userEvent.setup(), select=vi.fn();
    render(<GroupTree groups={groups} memberships={memberships} selectedId="grandchild" onSelect={select}/>);
    const toggle=screen.getByRole('button',{name:'Collapse Care subgroups'});
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    await user.click(toggle);
    expect(screen.queryByRole('button',{name:/^NorthSubgroup/})).toBeNull();
    expect(select).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button',{name:'Expand Care subgroups'}));
    expect(screen.getByRole('button',{name:/^Ward ASubgroup/}).getAttribute('aria-pressed')).toBe('true');
    const nestedToggle=screen.getByRole('button',{name:'Collapse Care / North subgroups'});
    nestedToggle.focus();await user.keyboard('{Enter}');
    expect(nestedToggle.getAttribute('aria-expanded')).toBe('false');
    expect(screen.queryByRole('button',{name:/^Ward ASubgroup/})).toBeNull();
    await user.click(screen.getByRole('button',{name:/^NorthSubgroup/}));
    expect(select).toHaveBeenCalledWith('child');
  });
  it('does not hide groups or loop if data contains a cycle', () => {
    const bad=[{id:'a',name:'A',parent_id:'b'},{id:'b',name:'B',parent_id:'a'}];
    const forest=buildGroupForest(bad);
    expect(forest[0].hierarchyUnavailable).toBe(true);
    expect(forest[0].children[0].group.name).toBe('B');
    expect(forest[0].children[0].children).toHaveLength(0);
    render(<GroupTree groups={bad} memberships={[]} selectedId="" onSelect={()=>{}}/>);
    expect(screen.getByText(/Hierarchy unavailable/)).toBeTruthy();
    expect(screen.getByRole('button',{name:/^BSubgroup/})).toBeTruthy();
  });
});
