import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { describe, it, expect } from 'vitest';
import { checkRefresherHealth } from '../../scripts/check-refresher-health.mjs';

describe('independent refresher monitoring', () => {
  it('exposes only aggregate status to allowlisted accounts and fails closed', async () => {
    const db = new PGlite();
    const monitor='00000000-0000-4000-8000-000000000001', other='00000000-0000-4000-8000-000000000002';
    try {
      await db.exec("create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email text); create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;");
      const names = (await readdir(new URL('../../supabase/migrations/', import.meta.url))).filter(n=>n.endsWith('.sql') && n <= '202611010013_refresher_scheduler.sql').sort();
      for (const name of names) await db.exec(await readFile(new URL(`../../supabase/migrations/${name}`,import.meta.url),'utf8'));
      await db.query("insert into auth.users(id,email) values($1,'monitor@test'),($2,'other@test')",[monitor,other]);
      const as = async id => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); };
      const status = async () => (await db.query('select public.refresher_monitor_status() status')).rows[0].status;
      await as(other);
      await expect(status()).rejects.toThrow(/Not authorised/);
      await expect(db.query('insert into private.refresher_monitor_users values($1)',[other])).rejects.toThrow();
      await expect(db.query('select * from private.refresher_job_runs')).rejects.toThrow();
      await expect(db.query('select private.run_refresher_scheduler(current_date)')).rejects.toThrow();
      await db.exec('reset role');
      await db.query('insert into private.refresher_monitor_users values($1)',[monitor]);
      await as(monitor);
      expect((await db.query('select id from public.profiles where id=$1',[other])).rows).toHaveLength(0);
      await expect(db.query('select * from private.refresher_job_runs')).rejects.toThrow();
      expect((await status()).healthy).toBe(false); // no heartbeat or cron
      await db.exec('reset role');
      await db.exec("create schema cron; create table cron.job(jobid bigint,jobname text,active boolean,schedule text,command text,database text); create table cron.job_run_details(jobid bigint,status text,start_time timestamptz); insert into cron.job values(1,'miracle-academy-refresher-hourly',true,'17 * * * *','select private.run_refresher_scheduler();',current_database()); insert into private.refresher_job_runs(started_at,finished_at,eligible_count,created_count,error_count,backlog_count) values(now(),now(),0,0,0,0);");
      await as(monitor);
      expect(await status()).toMatchObject({ healthy:false,logging_enabled:false });
      await db.exec("reset role; set cron.log_run='on'");
      await as(monitor);
      expect(await status()).toMatchObject({ healthy:true,job_active:true,logging_enabled:true,backlog_count:0,recent_errors:0,cron_failures:0 });
      await db.exec('reset role; update private.refresher_job_runs set backlog_count=1');
      await as(monitor);expect(await status()).toMatchObject({healthy:false,backlog_count:1});
      await db.exec('reset role; update private.refresher_job_runs set backlog_count=0');
      await db.exec('reset role');
      await db.exec("insert into private.refresher_job_runs(started_at,finished_at,eligible_count,created_count,error_count,backlog_count) values(now()-interval '2 hours',now()-interval '2 hours',1,0,1,0)");
      await as(monitor); expect(await status()).toMatchObject({healthy:false,recent_errors:1});
      await db.exec('reset role');
      await db.exec("delete from private.refresher_job_runs where error_count>0; insert into cron.job_run_details values(1,'failed',now()-interval '1 hour')");
      await as(monitor); expect(await status()).toMatchObject({healthy:false,cron_failures:1});
      await db.exec('reset role');
      await db.exec("delete from cron.job_run_details; update cron.job set command='select 1'");
      await as(monitor); expect(await status()).toMatchObject({healthy:false,job_active:false});
      await db.exec('reset role');
      await db.exec("update cron.job set command='select private.run_refresher_scheduler();'; update private.refresher_job_runs set finished_at=now()-interval '4 hours'");
      await as(monitor); expect((await status()).healthy).toBe(false);
      await db.exec('reset role'); await db.query("insert into public.user_roles(user_id,role) values($1,'trainee')",[monitor]); await as(monitor);
      await expect(status()).rejects.toThrow(/Not authorised/); // accidental role assignment fails closed
      await db.exec('reset role'); await db.query('delete from public.user_roles where user_id=$1',[monitor]);
      const group=(await db.query("insert into public.groups(name) values('Test') returning id")).rows[0].id;
      await db.query("insert into public.group_memberships(group_id,user_id,status) values($1,$2,'archived')",[group,monitor]);
      await as(monitor); await expect(status()).rejects.toThrow(/Not authorised/);
      await db.exec('reset role'); await db.query('delete from public.group_memberships where user_id=$1',[monitor]);
      await db.query('insert into public.group_leaders(group_id,user_id) values($1,$2)',[group,monitor]);
      await as(monitor); await expect(status()).rejects.toThrow(/Not authorised/);
      await db.exec('reset role'); await db.query('delete from public.group_leaders where user_id=$1',[monitor]);
      const course=(await db.query("insert into public.courses(title,description) values('Test','') returning id")).rows[0].id;
      await db.query("insert into public.course_assignments(course_id,user_id,target_date) values($1,$2,'2027-01-01')",[course,monitor]);
      await as(monitor); await expect(status()).rejects.toThrow(/Not authorised/);
      await db.exec('reset role'); await db.query('delete from public.course_assignments where user_id=$1',[monitor]);
      await db.query('delete from private.refresher_monitor_users where user_id=$1',[monitor]); await as(monitor);
      await expect(status()).rejects.toThrow(/Not authorised/);
      await db.exec('reset role; set role anon'); await expect(status()).rejects.toThrow();
    } finally { await db.close(); }
  },30000);

  it('authenticates and checks the endpoint without exposing credentials', async () => {
    const env={SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_example',MONITOR_EMAIL:'monitor@example.test',MONITOR_PASSWORD:'secret',MONITOR_USER_ID:'00000000-0000-4000-8000-000000000001',MONITOR_HEARTBEAT_URL:'https://heartbeat.example.test/unique-token'};
    const calls=[];
    const request=async (url,options)=>{calls.push({url:String(url),options}); return {ok:true,json:async()=>calls.length===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:true,job_active:true,logging_enabled:true,last_finished:'2026-01-01T00:00:00Z',backlog_count:0,recent_errors:0,cron_failures:0}}};
    expect((await checkRefresherHealth(env,request)).healthy).toBe(true);
    expect(calls.map(c=>new URL(c.url).pathname)).toEqual(['/auth/v1/token','/rest/v1/rpc/refresher_monitor_status','/unique-token']);
    expect(calls[2].options.headers).toBeUndefined();
    expect(calls.every(c=>c.options.redirect==='error')).toBe(true);
    expect(calls[1].options.headers.Authorization).toBe('Bearer token');
    await expect(checkRefresherHealth({...env,MONITOR_PASSWORD:''},request)).rejects.toThrow(/incomplete/);
    await expect(checkRefresherHealth({...env,SUPABASE_URL:'http://example.test'},request)).rejects.toThrow(/HTTPS/);
    let count=0;
    await expect(checkRefresherHealth({...env,MONITOR_HEARTBEAT_URL:'http://example.test'},async()=>({ok:true,json:async()=>++count===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:true,job_active:true,logging_enabled:true,last_finished:'2026-01-01',backlog_count:0,recent_errors:0,cron_failures:0}}))).rejects.toThrow(/HTTPS/);
    await expect(checkRefresherHealth({...env,SUPABASE_PUBLISHABLE_KEY:'sb_secret_bad'},request)).rejects.toThrow(/publishable/);
    const serviceKey=`header.${Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')}.signature`;
    await expect(checkRefresherHealth({...env,SUPABASE_PUBLISHABLE_KEY:serviceKey},request)).rejects.toThrow(/anon/);
    const wrongUserCalls=[];
    await expect(checkRefresherHealth(env,async(url)=>{wrongUserCalls.push(String(url));return {ok:true,json:async()=>({access_token:'token',user:{id:'00000000-0000-4000-8000-000000000002'}})}})).rejects.toThrow(/different account/);
    expect(wrongUserCalls).toHaveLength(1); // never use an administrator session for the monitor RPC
    await expect(checkRefresherHealth({...env,MONITOR_USER_ID:'not-a-uuid'},request)).rejects.toThrow(/user ID/);
    let missingBacklogCalls=0;
    await expect(checkRefresherHealth(env,async()=>({ok:true,json:async()=>++missingBacklogCalls===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:true,job_active:true,logging_enabled:true,last_finished:'2026-01-01',recent_errors:0,cron_failures:0}}))).rejects.toThrow(/unhealthy/);
    expect(missingBacklogCalls).toBe(2);
    let backlogCalls=0;
    await expect(checkRefresherHealth(env,async()=>({ok:true,json:async()=>++backlogCalls===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:true,job_active:true,logging_enabled:true,last_finished:'2026-01-01',backlog_count:1,recent_errors:0,cron_failures:0}}))).rejects.toThrow(/unhealthy/);
    expect(backlogCalls).toBe(2);
    let n=0; const unhealthyCalls=[];
    await expect(checkRefresherHealth(env,async(url)=>{unhealthyCalls.push(String(url));return {ok:true,json:async()=>++n===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:false}}})).rejects.toThrow(/unhealthy/);
    expect(unhealthyCalls).toHaveLength(2); // no success ping is sent when unhealthy
    let attempt=0;
    await expect(checkRefresherHealth(env,async()=>{attempt++;return attempt===3?{ok:false}:{ok:true,json:async()=>attempt===1?{access_token:'token',user:{id:env.MONITOR_USER_ID}}:{healthy:true,job_active:true,logging_enabled:true,last_finished:'2026-01-01',backlog_count:0,recent_errors:0,cron_failures:0}}})).rejects.toThrow(/heartbeat could not be delivered/);
    await expect(checkRefresherHealth(env,async()=>{throw Error('secret token in error')})).rejects.toThrow('Supabase monitor request failed or timed out.');
  });
});
