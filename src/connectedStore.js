import { certificatesEnabled } from './features.js';
// All reads use the current user's Supabase session and database RLS.
// No elevated or service-role credentials belong in browser code.
async function checked(request) {
  const { data, error } = await request;
  if (error) throw new Error(error.message || 'Database request failed.');
  return data;
}
// PostgREST applies a row limit; page each table rather than silently omitting
// memberships in larger organisations. Stable ordering avoids page overlap.
export async function readAll(client, table, columns, orderColumns) {
  const pageSize = 500;
  const rows = [];
  for (let offset = 0; ; offset += pageSize) {
    let query = client.from(table).select(columns);
    for (const column of orderColumns) query = query.order(column, { ascending: true });
    const page = await checked(query.range(offset, offset + pageSize - 1));
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}
export async function loadDirectory(client) {
  const [profiles, roles, groups, leaders, memberships] = await Promise.all([
    readAll(client, 'profiles', 'id,display_name', ['display_name', 'id']),
    readAll(client, 'user_roles', 'user_id,role', ['user_id', 'role']),
    readAll(client, 'groups', 'id,name,parent_id,created_at', ['name', 'id']),
    readAll(client, 'group_leaders', 'group_id,user_id', ['group_id', 'user_id']),
    readAll(client, 'group_memberships', 'group_id,user_id,status,created_at,updated_at', ['group_id', 'user_id']),
  ]);
  return { profiles, roles, groups, leaders, memberships };
}
export async function createGroup(client, name, parentId) {
  return checked(client.from('groups').insert({ name: name.trim(), parent_id: parentId || null }).select('id,name,parent_id').single());
}
export async function updateDisplayName(client, userId, displayName) {
  const rows = await checked(client.from('profiles').update({ display_name: displayName.trim() }).eq('id', userId).select('id,display_name'));
  if (!rows?.length) throw new Error('No profile was updated. Refresh and check your access.');
}
export async function addRole(client, userId, role) {
  return checked(client.from('user_roles').insert({ user_id: userId, role }).select());
}
export async function addLeader(client, groupId, userId) {
  return checked(client.from('group_leaders').insert({ group_id: groupId, user_id: userId }).select());
}
export async function removeLeader(client, groupId, userId) {
  const rows = await checked(client.from('group_leaders').delete().eq('group_id', groupId).eq('user_id', userId).select());
  if (!rows?.length) throw new Error('No leader assignment was removed. Refresh and check your access.');
}
export async function manageMembership(client, groupId, userId, action, dates = {}) {
  return checked(client.rpc('manage_group_membership', { target_group: groupId, target_user: userId, action, course_dates: dates }));
}

export async function loadLearning(client, enableCertificates=certificatesEnabled) {
  const [courses, modules, blocks, assignments, requirements, catalog, progress, attempts, reviewerNames, completion, completionEvents] = await Promise.all([
    readAll(client, 'courses', 'id,title,description,status,created_at,published_at,family_id,version_number,previous_version_id', ['title','id']),
    readAll(client, 'course_modules', 'id,course_id,title,position', ['course_id','position']),
    readAll(client, 'course_blocks', 'id,module_id,title,body,position,is_required,block_type', ['module_id','position']),
    readAll(client, 'course_assignments', enableCertificates?'id,course_id,user_id,target_date,created_at,refresher_of_certificate_id,access_assignment_id':'id,course_id,user_id,target_date,created_at', ['course_id','user_id','id']),
    readAll(client, 'group_course_requirements', 'group_id,course_id', ['group_id','course_id']),
    readCatalog(client),
    readAll(client, 'course_block_progress', enableCertificates?'user_id,block_id,marked_at,assignment_id':'user_id,block_id,marked_at', ['user_id','block_id']),
    readAll(client, 'assessment_attempts', 'id,block_id,user_id,attempt_number,kind,status,answers,feedback,score,submitted_at,reviewer_id,reviewed_at,review_details,review_comment'+(enableCertificates?',assignment_id':''), ['submitted_at','id']),
    readReviewers(client),
    readCompletion(client),
    readAll(client, 'course_completion_events', 'id,event_sequence,assignment_id,event_type,occurred_at,actor_id,source', ['event_sequence']),
  ]);
  const [certificateSettings,certificates,certificateRequests,certificateVerifications]=enableCertificates?await Promise.all([readAll(client,'course_certificate_settings','course_id,template_id,validity_months,refresher_family_id,lead_days,layout',['course_id']),readAll(client,'certificates','id,assignment_id,qualification_assignment_id,completion_event_id,user_id,award_course_id,policy_course_id,template_id,trainee_name,course_title,course_version,completion_date,expiry_date,validity_months,refresher_family_id,lead_days,layout,issued_at,issued_by,status,revoked_at,revocation_reason,renewal_of_certificate_id',['issued_at','id']),readAll(client,'certificate_reissue_requests','completion_event_id,assignment_id,user_id,status,requested_at,reviewed_by,reviewed_at',['requested_at','completion_event_id']),readAll(client,'certificate_date_verifications','completion_event_id,verified_completion_date,reason,verified_by,verified_at',['verified_at','completion_event_id'])]):[[],[],[],[]];
  return {courses,modules,blocks,assignments,requirements,catalog,progress,attempts,reviewerNames,completion,completionEvents,certificateSettings,certificates,certificateRequests,certificateVerifications};
}
export async function learningAction(client, action, args) { return checked(client.rpc(action,args)); }

async function readCatalog(client) {
  const rows=[];
  for(let start=0;;start+=1000) {
    const page=await checked(client.rpc('list_published_course_catalog').order('title').order('id').range(start,start+999));
    rows.push(...page);
    if(page.length<1000)return rows;
  }
}

// This RPC exposes only the signed-in user's active groups and leader names.
export async function loadMyGroups(client) {
  const rows=[];
  for (let start=0;;start+=500) {
    const page=await checked(client.rpc('list_my_groups_with_leaders').order('group_name').order('group_id').range(start,start+499));
    rows.push(...page);
    if(page.length<500)return rows;
  }
}

async function readReviewers(client) {
  const rows=[];
  for(let start=0;;start+=500) {
    const page=await checked(client.rpc('list_my_assessment_reviewers').order('reviewer_id').range(start,start+499));
    rows.push(...page);
    if(page.length<500)return rows;
  }
}

async function readCompletion(client) {
  const rows=[];
  for(let start=0;;start+=500) {
    const page=await checked(client.rpc('list_assignment_progress').order('assignment_id').range(start,start+499));
    rows.push(...page);
    if(page.length<500)return rows;
  }
}
