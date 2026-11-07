import { describe, it, expect } from 'vitest';
import writeExcelFile from 'write-excel-file/node';
import { unzipSync, strFromU8 } from 'fflate';
import { makeReportSheets } from '../reportWorkbook.js';
import { loadReportData } from '../connectedStore.js';

const fixture=()=>({
 userId:'leader',isAdmin:false,
 profiles:[{id:'a',display_name:'=1+1'},{id:'b',display_name:'Outside'},{id:'old',display_name:'Archived'}],
 courses:[{id:'c1',title:'+Safety',version_number:1},{id:'c2',title:'Tools',version_number:2}],
 groups:[{id:'g1',name:'My group'},{id:'g2',name:'Other group'}],
 leaders:[{group_id:'g1',user_id:'leader'}],
 memberships:[{group_id:'g1',user_id:'a',status:'active'},{group_id:'g1',user_id:'old',status:'archived'},{group_id:'g2',user_id:'b',status:'active'}],
 completion:[
  {assignment_id:'aa',user_id:'a',course_id:'c1',active:true,status:'completed',target_date:'2026-10-01',required_done:1,required_total:1,percent:100,completed_at:'2026-10-02T00:00:00Z',completion_origin:'activity',overdue:false,completed_late:true},
  {assignment_id:'bb',user_id:'b',course_id:'c2',active:true,status:'in_progress',target_date:'2026-10-01',required_done:0,required_total:1,percent:0,overdue:true,completed_late:false},
  {assignment_id:'cc',user_id:'old',course_id:'c2',active:false,status:'completed',target_date:'2026-10-01',required_done:1,required_total:1,percent:100,completed_at:'2026-11-01T00:00:00Z',completion_origin:'initial_recognition',overdue:false,completed_late:null},
 ],
 completionEvents:[{assignment_id:'aa',event_type:'completed',occurred_at:'2026-10-02T00:00:00Z',source:'activity'},{assignment_id:'aa',event_type:'reopened',occurred_at:'2026-10-03T00:00:00Z',source:'activity'},{assignment_id:'cc',event_type:'completed',occurred_at:'2026-11-01T00:00:00Z',source:'initial_recognition'},{assignment_id:'bb',event_type:'completed',occurred_at:'2026-10-03T00:00:00Z',source:'activity'}]
});
const rows=sheet=>sheet.data.slice(1);

describe('learning report workbook',()=>{
 it('limits leaders to their scoped trainees, including archived membership history',()=>{
  const sheets=makeReportSheets(fixture());
  expect(sheets.map(s=>s.sheet)).toEqual(['Assignments','Completion history']);
  expect(rows(sheets[0]).map(r=>r[0])).toEqual(['aa','cc']);
  expect(rows(sheets[1]).map(r=>r[0])).toEqual(['aa','aa','cc']);
  expect(rows(sheets[0])[1][12]).toBe('');
  expect(rows(sheets[0])[1][13]).toMatch(/unverified/);
  expect(rows(sheets[0])[1][11]).toBe('Unknown');
  expect(rows(sheets[1])[2][6]).toMatch(/Recognition time/);
 });
 it('applies group, course, status and inactive choices to both sheets',()=>{
  const data=fixture();
  expect(rows(makeReportSheets(data,{group:'g1'})[0]).map(r=>r[0])).toEqual(['aa']);
  expect(rows(makeReportSheets(data,{course:'c2'})[0]).map(r=>r[0])).toEqual(['cc']);
  expect(rows(makeReportSheets(data,{includeInactive:false})[1]).map(r=>r[0])).toEqual(['aa','aa']);
  expect(rows(makeReportSheets(data,{status:'completed_late'})[0]).map(r=>r[0])).toEqual(['aa']);
  expect(()=>makeReportSheets(data,{group:'g2'})).toThrow(/no longer available/);
  data.isAdmin=true;
  expect(rows(makeReportSheets(data)[0]).map(r=>r[0])).toEqual(['aa','bb','cc']);
  expect(rows(makeReportSheets(data,{group:'g2'})[0]).map(r=>r[0])).toEqual(['bb']);
 });
 it('writes two sheets and treats formula-like names and titles as text',async()=>{
  const bytes=await writeExcelFile(makeReportSheets(fixture())).toBuffer();
  const zip=unzipSync(new Uint8Array(bytes));
  const workbook=strFromU8(zip['xl/workbook.xml']);
  expect(workbook).toContain('Assignments');expect(workbook).toContain('Completion history');
  const xml=Object.entries(zip).filter(([path])=>path.startsWith('xl/worksheets/')&&path.endsWith('.xml')).map(([,value])=>strFromU8(value)).join('');
  const all=Object.values(zip).map(v=>{try{return strFromU8(v)}catch{return ''}}).join('');
  expect(all).toContain('=1+1');expect(all).toContain('+Safety');
  expect(xml).not.toMatch(/<f(?:\s|>)/);
 });
 it('fails closed when a required profile or course is unavailable',()=>{
  const data=fixture();data.profiles=data.profiles.filter(p=>p.id!=='a');
  expect(()=>makeReportSheets(data)).toThrow(/unavailable/);
 });
});

describe('fresh report data access',()=>{
 function fakeClient({roles=[{role:'leader'}],secondRoles=roles,userId='leader'}={}){
  let roleReads=0;const calls=[];
  return {calls,auth:{getUser:async()=>({data:{user:{id:userId}},error:null})},
   from(table){return {select(){return this},order(){return this},eq:async()=>({data:roleReads++?secondRoles:roles,error:null}),range:async(start,end)=>{calls.push({table,start,end});return {data:table==='profiles'&&start===0?Array.from({length:500},(_,i)=>({id:String(i)})):table==='profiles'&&start===500?[{id:'last'}]:[],error:null}}}},
   rpc(){return {order(){return this},range:async()=>({data:[],error:null})}}
  };
 }
 it('requires a manager session, refreshes data and paginates without omitting the last record',async()=>{
  const client=fakeClient();const data=await loadReportData(client,'leader');
  expect(data.profiles).toHaveLength(501);expect(client.calls.filter(c=>c.table==='profiles').map(c=>c.start)).toEqual([0,500]);
 });
 it('fails if the session or manager role is absent or changes during export',async()=>{
  await expect(loadReportData(fakeClient({userId:'other'}),'leader')).rejects.toThrow(/session has changed/);
  await expect(loadReportData(fakeClient({roles:[{role:'trainee'}]}),'leader')).rejects.toThrow(/Only administrators/);
  await expect(loadReportData(fakeClient({secondRoles:[{role:'trainee'}]}),'leader')).rejects.toThrow(/Only administrators/);
  await expect(loadReportData(fakeClient({roles:[{role:'administrator'}],secondRoles:[{role:'leader'}]}),'leader')).rejects.toThrow(/permissions have changed/);
 });
});
