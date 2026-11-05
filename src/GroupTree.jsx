import React, { useEffect, useMemo, useState } from 'react';
import { ChevronRight, Folder, FolderOpen } from 'lucide-react';

export function groupPath(group, groups) {
  const byId = new Map(groups.map(item => [item.id, item]));
  const names = [], seen = new Set();
  let current = group;
  while (current) {
    if (seen.has(current.id)) { names.unshift('Hierarchy unavailable'); break; }
    seen.add(current.id); names.unshift(current.name);
    if (!current.parent_id) break;
    current = byId.get(current.parent_id);
    if (!current) names.unshift('Parent outside your view');
  }
  return names.join(' / ');
}

// RLS can expose a subgroup without exposing its parent. Keep such groups
// visible as roots instead of inventing or querying an unauthorised ancestor.
export function buildGroupForest(groups) {
  const compare = (a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }) || a.id.localeCompare(b.id);
  const sorted = [...groups].sort(compare);
  const byId = new Map(sorted.map(group => [group.id, group]));
  const children = new Map();
  for (const group of sorted) {
    if (byId.has(group.parent_id)) {
      if (!children.has(group.parent_id)) children.set(group.parent_id, []);
      children.get(group.parent_id).push(group);
    }
  }
  const visited = new Set();
  function node(group, path, hierarchyUnavailable = false) {
    if (visited.has(group.id)) return null;
    visited.add(group.id);
    const missingParent = Boolean(group.parent_id && !byId.has(group.parent_id));
    const nextPath = [...path, group.name];
    return { group, path: nextPath.join(' / '), missingParent, hierarchyUnavailable,
      children: (children.get(group.id) || []).map(child => node(child, nextPath)).filter(Boolean) };
  }
  const roots = sorted.filter(group => !group.parent_id || !byId.has(group.parent_id)).map(group => node(group, [])).filter(Boolean);
  // Defensive fallback for malformed cycles: never hide a visible group or
  // recurse indefinitely. A disconnected root is not presented as top-level.
  for (const group of sorted) if (!visited.has(group.id)) roots.push(node(group, [], true));
  return roots;
}

export function GroupTree({ groups, memberships, selectedId, onSelect }) {
  const [collapsed, setCollapsed] = useState(() => new Set());
  const forest = useMemo(() => buildGroupForest(groups), [groups]);
  // Reveal the selected group after navigation or a refresh (including a newly
  // created subgroup). Manual collapsing remains possible between refreshes.
  useEffect(() => {
    const byId = new Map(groups.map(group => [group.id, group]));
    const ancestors = new Set();
    let current = byId.get(selectedId);
    while (current?.parent_id && byId.has(current.parent_id) && !ancestors.has(current.parent_id)) {
      ancestors.add(current.parent_id);
      current = byId.get(current.parent_id);
    }
    setCollapsed(previous => {
      if (![...ancestors].some(id => previous.has(id))) return previous;
      const next = new Set(previous); for (const id of ancestors) next.delete(id); return next;
    });
  }, [groups, selectedId]);
  const activeCounts = useMemo(() => {
    const counts = new Map();
    for (const membership of memberships) if (membership.status === 'active') counts.set(membership.group_id, (counts.get(membership.group_id) || 0) + 1);
    return counts;
  }, [memberships]);
  function toggle(id) {
    setCollapsed(current => { const next = new Set(current); if (next.has(id)) next.delete(id); else next.add(id); return next; });
  }
  function renderNode(node) {
    const { group, children, missingParent, hierarchyUnavailable, path } = node;
    const expanded = !collapsed.has(group.id);
    const groupLabel = hierarchyUnavailable ? 'Hierarchy unavailable' : missingParent ? 'Subgroup · parent outside your view' : group.parent_id ? 'Subgroup' : 'Group';
    return <li key={group.id}>
      <div className="group-tree-row">
        {children.length ? <button type="button" className="group-tree-toggle" aria-expanded={expanded} aria-label={`${expanded ? 'Collapse' : 'Expand'} ${path} subgroups`} onClick={() => toggle(group.id)}><ChevronRight size={16} className={expanded ? 'expanded' : ''} aria-hidden="true"/></button> : <span className="group-tree-spacer" aria-hidden="true"/>}
        <button type="button" className={`connected-group-item group-tree-item ${selectedId === group.id ? 'selected' : ''}`} aria-pressed={selectedId === group.id} onClick={() => onSelect(group.id)}>
          <span className="group-choice-icon" aria-hidden="true">{children.length && expanded ? <FolderOpen size={17}/> : <Folder size={17}/>}</span>
          <span><strong>{group.name}</strong><small>{groupLabel} · {activeCounts.get(group.id) || 0} active</small></span>
          <ChevronRight size={16} aria-hidden="true"/>
        </button>
      </div>
      {children.length > 0 && expanded && <ul>{children.map(renderNode)}</ul>}
    </li>;
  }
  return <div className="connected-group-list group-tree-scroll"><ul className="group-tree" aria-label="Group hierarchy">{forest.map(renderNode)}</ul></div>;
}
