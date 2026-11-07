// Run the actual migration against embedded PostgreSQL. Supabase-specific auth
// objects are modelled locally; rerun against the real development project too.
import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const ids = {
  admin: '00000000-0000-4000-8000-000000000001',
  leader1: '00000000-0000-4000-8000-000000000002',
  leader2: '00000000-0000-4000-8000-000000000003',
  trainee1: '00000000-0000-4000-8000-000000000004',
  trainee2: '00000000-0000-4000-8000-000000000005',
  group1: '10000000-0000-4000-8000-000000000001',
  group2: '10000000-0000-4000-8000-000000000002',
  group3: '10000000-0000-4000-8000-000000000003',
};
let db;
async function asUser(id) {
  await db.exec('reset role;');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
  await db.exec('set role authenticated;');
}

describe('identity and group database security', () => {
  beforeAll(async () => {
    db = new PGlite();
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth;
      create table auth.users (id uuid primary key, email text);
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $$;
      grant usage on schema auth to authenticated;
      grant execute on function auth.uid() to authenticated;
    `);
    await db.exec(await readFile(new URL('../../supabase/migrations/202610310001_identity_and_groups.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../supabase/migrations/202611010001_leader_role_enforcement.sql', import.meta.url), 'utf8'));
    await db.exec(await readFile(new URL('../../supabase/migrations/202611010002_profile_display_name.sql', import.meta.url), 'utf8'));
    for (const name of ['admin','leader1','leader2','trainee1','trainee2']) {
      await db.query('insert into auth.users (id, email) values ($1, $2)', [ids[name], `${name}@example.test`]);
    }
    await db.query(`insert into public.user_roles values
      ($1, 'administrator'), ($2, 'leader'), ($3, 'leader'), ($4, 'trainee'), ($5, 'trainee')`,
      [ids.admin, ids.leader1, ids.leader2, ids.trainee1, ids.trainee2]);
    await db.query(`insert into public.groups (id,name) values ($1,'A'),($2,'B'),($3,'C')`, [ids.group1,ids.group2,ids.group3]);
    await db.query(`insert into public.group_leaders values ($1,$4),($2,$4),($3,$5)`, [ids.group1,ids.group2,ids.group3,ids.leader1,ids.leader2]);
    await db.query(`insert into public.group_memberships (group_id,user_id) values ($1,$3),($2,$4)`, [ids.group1,ids.group3,ids.trainee1,ids.trainee2]);
  }, 30000);
  afterAll(async () => { await db?.close(); });

  it('prevents anonymous table reads and mutations', async () => {
    await db.exec('reset role; set role anon;');
    await expect(db.query('select * from public.profiles')).rejects.toThrow();
    await expect(db.query("select public.manage_group_membership($1,$2,'add')", [ids.group2,ids.trainee1])).rejects.toThrow();
  });
  it('limits trainees to their own records and disallows self-promotion', async () => {
    await asUser(ids.trainee1);
    expect((await db.query('select id from public.profiles')).rows.map(r=>r.id)).toEqual([ids.trainee1]);
    expect((await db.query('select id from public.groups')).rows.map(r=>r.id)).toEqual([ids.group1]);
    await expect(db.query("update public.profiles set display_name = 'Changed' where id = $1", [ids.trainee1])).resolves.toMatchObject({ affectedRows: 0 });
    await expect(db.query("update public.profiles set created_at = now()")).rejects.toThrow();
    await expect(db.query("insert into public.user_roles values ($1,'administrator')", [ids.trainee1])).rejects.toThrow();
    await expect(db.query("select public.manage_group_membership($1,$2,'archive')", [ids.group1,ids.trainee1])).rejects.toThrow();
    await expect(db.query("update public.group_memberships set status='archived'")).rejects.toThrow();
  });
  it('limits leaders to their groups and blocks acquiring unrelated trainees', async () => {
    await asUser(ids.leader1);
    expect((await db.query('select id from public.groups order by id')).rows.map(r=>r.id)).toEqual([ids.group1,ids.group2]);
    const profiles=(await db.query('select id from public.profiles')).rows.map(r=>r.id);
    expect(profiles).toContain(ids.trainee1);
    expect(profiles).not.toContain(ids.trainee2);
    await expect(db.query("select public.manage_group_membership($1,$2,'add')", [ids.group2,ids.trainee2])).rejects.toThrow();
    await expect(db.query("select public.manage_group_membership($1,$2,'archive')", [ids.group3,ids.trainee2])).rejects.toThrow();
    await expect(db.query("insert into public.group_leaders values ($1,$2)", [ids.group3,ids.leader1])).rejects.toThrow();
  });
  it('audits scoped add, archive, restore and delete without deleting the trainee', async () => {
    await asUser(ids.leader1);
    for (const action of ['add','archive','restore','delete']) {
      await db.query('select public.manage_group_membership($1,$2,$3)', [ids.group2,ids.trainee1,action]);
    }
    const audit = (await db.query('select action from public.membership_audit order by id')).rows.map(r=>r.action);
    expect(audit).toEqual(['add','archive','restore','delete']);
    expect((await db.query('select * from public.group_memberships where group_id = $1 and user_id = $2', [ids.group2,ids.trainee1])).rows).toHaveLength(0);
    expect((await db.query('select id from public.profiles where id = $1', [ids.trainee1])).rows).toHaveLength(1);
    expect((await db.query('select * from public.group_memberships where group_id = $1 and user_id = $2', [ids.group1,ids.trainee1])).rows).toHaveLength(1);
  });
  it('allows an administrator to manage roles and view across groups', async () => {
    await asUser(ids.admin);
    expect((await db.query('select id from public.profiles')).rows).toHaveLength(5);
    await db.query("update public.profiles set display_name = 'Alex Test' where id = $1", [ids.trainee1]);
    expect((await db.query('select display_name from public.profiles where id = $1',[ids.trainee1])).rows[0].display_name).toBe('Alex Test');
    await db.query("insert into public.user_roles values ($1, 'author')", [ids.trainee1]);
    expect((await db.query('select role from public.user_roles where user_id = $1 order by role', [ids.trainee1])).rows.map(r=>r.role)).toEqual(['author','trainee']);
  });
  it('revokes leader access when the role is removed, even if a group assignment remains', async () => {
    await asUser(ids.admin);
    await db.query("delete from public.user_roles where user_id = $1 and role = 'leader'", [ids.leader1]);
    await asUser(ids.leader1);
    const profiles = (await db.query('select id from public.profiles')).rows.map(r => r.id);
    expect(profiles).not.toContain(ids.trainee1);
    expect((await db.query('select id from public.groups')).rows).toHaveLength(0);
    await expect(db.query("select public.manage_group_membership($1,$2,'archive')", [ids.group1,ids.trainee1])).rejects.toThrow();
  });

});
