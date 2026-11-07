// Build worksheets from data freshly retrieved through server-enforced RLS.
// All user-supplied strings are passed as strings, never spreadsheet formulas.
const names={not_started:'Not started',in_progress:'In progress',awaiting_review:'Awaiting trainer review',completed:'Completed',needs_rule:'Needs completion rule'};
const yesNo=value=>value===true?'Yes':value===false?'No':'Unknown';
const timestamp=value=>value ? new Date(value).toISOString() : '';
const header=values=>values.map(value=>({value,fontWeight:'bold'}));

export function makeReportSheets(data,{group='',course='',status='',includeInactive=true}={}) {
  const {userId,isAdmin,profiles,courses,groups,leaders,memberships,completion,completionEvents}=data;
  const managed=new Set(leaders.filter(l=>l.user_id===userId).map(l=>l.group_id));
  if (group && (!groups.some(g=>g.id===group) || (!isAdmin&&!managed.has(group)))) throw Error('The selected group is no longer available. Refresh and try again.');
  // can_view_profile includes archived memberships, so preserve that existing
  // manager scope. The group filter itself matches the overview's active-only
  // membership rule and must not be interpreted as historical group affiliation.
  const scopedUsers=new Set(memberships.filter(m=>managed.has(m.group_id)).map(m=>m.user_id));
  const byProfile=new Map(profiles.map(p=>[p.id,p])),byCourse=new Map(courses.map(c=>[c.id,c]));
  const rows=completion.filter(p=>(isAdmin||scopedUsers.has(p.user_id))&&(includeInactive||p.active)&&(!course||p.course_id===course)&&(!group||memberships.some(m=>m.group_id===group&&m.user_id===p.user_id&&m.status==='active'))&&(!status||(status==='overdue'?p.active&&p.overdue:status==='completed_late'?p.completed_late:p.status===status)));
  if(rows.some(p=>!byProfile.has(p.user_id)||!byCourse.has(p.course_id))) throw Error('Some report details are unavailable. Refresh and try again.');
  const selected=new Map(rows.map(p=>[p.assignment_id,p]));
  const assignmentRows=[header(['Assignment ID','Trainee','Course','Version','Target date (NZ)','Access','Current status','Required blocks done','Required blocks total','Progress %','Overdue','Completed late','Completion (UTC time or NZ date)','Completion date note'])];
  for(const p of rows){
    const profile=byProfile.get(p.user_id),c=byCourse.get(p.course_id);
    const note=p.completion_origin==='initial_recognition'?'Original completion date unverified':p.completion_origin==='verified_historical'?'Verified historical completion date':p.completed_at?'Recorded completion time':'';
    const completed=p.completion_origin==='initial_recognition'?'':p.completion_origin==='verified_historical'?(p.verified_completion_date||''):timestamp(p.completed_at);
    assignmentRows.push([String(p.assignment_id),String(profile.display_name||'Unnamed user'),String(c.title||'Course'),Number(c.version_number||1),p.target_date||'',p.active?'Active':'Inactive',names[p.status]||'Not available',Number(p.required_done),Number(p.required_total),p.percent==null?null:Number(p.percent),p.active?yesNo(p.overdue):'Not applicable',yesNo(p.completed_late),completed,note]);
  }
  const eventRows=[header(['Assignment ID','Trainee','Course','Version','Event','Event recorded at (UTC)','Date note'])];
  for(const e of completionEvents){
    const p=selected.get(e.assignment_id);if(!p)continue;
    eventRows.push([String(e.assignment_id),String(byProfile.get(p.user_id).display_name||'Unnamed user'),String(byCourse.get(p.course_id).title||'Course'),Number(byCourse.get(p.course_id).version_number||1),e.event_type==='completed'?'Completed':e.event_type==='reopened'?'Reopened':'Unknown',timestamp(e.occurred_at),e.source==='initial_recognition'?'Recognition time; original completion date not shown here':'']);
  }
  return [
    {sheet:'Assignments',data:assignmentRows,stickyRowsCount:1,columns:[{width:38},{width:24},{width:32},{width:10},{width:18},{width:12},{width:24},{width:20},{width:20},{width:14},{width:16},{width:18},{width:28},{width:36}]},
    {sheet:'Completion history',data:eventRows,stickyRowsCount:1,columns:[{width:38},{width:24},{width:32},{width:10},{width:16},{width:28},{width:46}]},
  ];
}

export async function downloadReportWorkbook(data, filters) {
  const sheets=makeReportSheets(data,filters);
  const {default:writeExcelFile}=await import('write-excel-file/browser');
  await writeExcelFile(sheets).toFile('miracle-academy-learning-report.xlsx');
}
