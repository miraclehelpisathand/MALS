# Task 4: completion and dashboards — development validation

## Agreed rules

- Completion requires every required block in the assigned immutable course version: self-reported text marks, a passed quiz, and competent practical sign-off. Optional blocks do not prevent completion. A prior successful assessment attempt continues to count after a later failure.
- If required text is unmarked, the assignment reopens. Completion and reopening events are preserved; re-completing records a new completion time.
- A target date ends at the end of that date in Pacific/Auckland, including daylight saving. Overdue applies to incomplete work; a known completion after that cutoff is marked completed late. The application does not claim to predict whether a trainee is on track.
- Assessment review permissions remain administrators, or trainers who directly lead an active group containing the trainee; no one may review their own attempt.

## Checks completed

- Local UI and embedded PostgreSQL/RLS tests cover required and optional progress, pending reviews, pass/sign-off, reopening, retained earlier passes, overdue/late flags, daylight-saving boundaries, trainer and trainee isolation, archived group-only access, immutable event history and the initial migration backfill.
- Development migrations `202611010009_completion_dashboard.sql` and `202611010010_recognised_completion_dates.sql` have been applied. Counts and hashes of existing assignments, reading marks and assessment attempts did not change.
- One existing assignment already satisfied the new completion rules and was recognised when the migration ran. Its original completion date is **unverified**; the app labels it accordingly and does not infer whether it was late. Its recognition timestamp must not be treated as a verified date for a future certificate.
- A rolled-back development database workflow, using simulated identities, checked progress, pending review, sign-off, reopening, event history and cross-trainee isolation. A simulated authenticated trainee saw only their own active progress. Direct authenticated event inserts/state updates and anonymous progress RPC access are denied by privileges.
- Headless browser checks using mocked Supabase requests passed overview filters and person navigation at 320 and 390 pixels; trainee progress and completion passed at 320, 390, 768 and 1280 pixels. These were not physical-device or real authenticated HTTP tests.

## Remaining validation and scope

- Signed-in browser/API security testing with real test accounts and physical-phone checks remain outstanding. Use fictional test data only; an independent production security review is still needed.
- Certificates, certificate validity after a reopening, expiry and refreshers, secure document/video delivery, target-date editing, and production readiness remain future work.
