// @vitest-environment jsdom
import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Dashboard } from '../Completion.jsx';
import { loadReportData } from '../connectedStore.js';
import { downloadReportWorkbook } from '../reportWorkbook.js';
vi.mock('../connectedStore.js',()=>({loadReportData:vi.fn()}));
vi.mock('../reportWorkbook.js',()=>({downloadReportWorkbook:vi.fn()}));
const directory={groups:[{id:'g1',name:'Team'}],profiles:[{id:'t',display_name:'Alex'}],memberships:[{group_id:'g1',user_id:'t',status:'active'}]};
const learning={courses:[{id:'c1',title:'Safety',version_number:1}],completion:[{assignment_id:'a',course_id:'c1',user_id:'t',active:true,status:'completed',target_date:'2026-01-01',required_done:1,required_total:1,percent:100}]};
const client={},session={user:{id:'manager'}};
afterEach(cleanup);beforeEach(()=>{vi.resetAllMocks();loadReportData.mockResolvedValue({fresh:true});downloadReportWorkbook.mockResolvedValue();});
describe('overview workbook export',()=>{
 it('reloads authorised data and passes current filters and inactive choice',async()=>{
  const user=userEvent.setup();render(<Dashboard learning={learning} directory={directory} client={client} session={session} canExport openPerson={()=>{}}/>);
  await user.selectOptions(screen.getByLabelText('Group'),'g1');await user.selectOptions(screen.getByLabelText('Course version'),'c1');await user.selectOptions(screen.getByLabelText('Status'),'completed');await user.click(screen.getByLabelText('Include inactive assignments in workbook'));
  await user.click(screen.getByRole('button',{name:'Download Excel report'}));
  await waitFor(()=>expect(downloadReportWorkbook).toHaveBeenCalledWith({fresh:true},{group:'g1',course:'c1',status:'completed',includeInactive:false}));
  expect(loadReportData).toHaveBeenCalledWith(client,'manager');
 });
 it('clears a selected inactive-only course when inactive records are excluded',async()=>{
  const user=userEvent.setup();const inactive={...learning,courses:[...learning.courses,{id:'c2',title:'Old course',version_number:1}],completion:[...learning.completion,{...learning.completion[0],assignment_id:'old',course_id:'c2',active:false}]};
  render(<Dashboard learning={inactive} directory={directory} client={client} session={session} canExport openPerson={()=>{}}/>);
  await user.selectOptions(screen.getByLabelText('Course version'),'c2');
  await user.click(screen.getByLabelText('Include inactive assignments in workbook'));
  await waitFor(()=>expect(screen.getByLabelText('Course version').value).toBe(''));
 });
 it('shows an error and does not generate a workbook if fresh access fails',async()=>{
  const user=userEvent.setup();loadReportData.mockRejectedValue(new Error('Your session has changed. Sign in again.'));
  render(<Dashboard learning={learning} directory={directory} client={client} session={session} canExport openPerson={()=>{}}/>);
  await user.click(screen.getByRole('button',{name:'Download Excel report'}));
  expect((await screen.findByRole('alert')).textContent).toContain('Your session has changed');
  expect(downloadReportWorkbook).not.toHaveBeenCalled();
 });
 it('does not show export controls to other roles',()=>{
  render(<Dashboard learning={learning} directory={directory} openPerson={()=>{}}/>);
  expect(screen.queryByRole('button',{name:'Download Excel report'})).toBeNull();
 });
});
