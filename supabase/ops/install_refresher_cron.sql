-- PROTOTYPE ONLY — DO NOT RUN until task 5 has passed deployment/security
-- validation and external alerting is operational. Requires a privileged
-- database operator and Supabase pg_cron availability/entitlement.
--
-- Hourly UTC schedule; the function itself derives the calendar day in
-- Pacific/Auckland. Its source-certificate uniqueness makes retries safe.
-- Calling cron.schedule with the same name updates an existing named job;
-- check job ownership/permissions and test in a rollback-only environment.
create extension if not exists pg_cron;
select cron.schedule(
  'miracle-academy-refresher-hourly',
  '17 * * * *',
  'select private.run_refresher_scheduler();'
);
-- Operators must independently alert on a missing heartbeat (> 3h),
-- any nonzero error_count in 26h, cron execution failures, and database unavailability.
-- The application health panel alone is NOT an alerting system.
