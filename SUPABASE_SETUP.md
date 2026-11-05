# Miracle Academy: development Supabase setup

This guide is for a **new, dedicated development project only**. Use fictional test records; this is not ready for real trainee data. The demo dashboard remains local-only and separate from the connected development workspace.

## 1. Prepare the project

1. In your Supabase project, confirm email/password authentication is enabled and keep email confirmation enabled.
2. In Authentication's sign-in settings, turn off **Allow new users to sign up** for this development project. Accounts are created by an administrator in the Supabase dashboard for now. This stops public self-registration at the Auth API, not just in the UI.
3. Supabase's default email sender is limited and is suitable for initial testing only. For production, configure an appropriate custom SMTP service and review rate limits.

## 2. Apply the migration

1. In a new dedicated development project, open **SQL Editor**. Copy and run these migration files in order, one at a time: `202610310001_identity_and_groups.sql`, `202611010001_leader_role_enforcement.sql`, `202611010002_profile_display_name.sql`, `202611010003_courses_and_assignments.sql`, `202611010004_leader_course_catalog.sql`, `202611010005_text_block_progress.sql`, `202611010006_trainee_assigned_groups.sql`, `202611010007_course_builder_versions.sql`, `202611010008_assessments.sql`, `202611010009_completion_dashboard.sql`, and `202611010010_recognised_completion_dates.sql` (all in `supabase/migrations/`).
2. Confirm each succeeds before running the next. They are intended for a new project; do not repeatedly run them or apply them to an existing production database. Stop and investigate any error instead of changing permissions to make it pass.
3. If you already applied the initial migration, apply only the later migrations that are not already present. All eleven migrations have already been applied to the connected MA-LS development project; do not run them there again.

The migration creates profiles, roles, groups, directly assigned group leaders, memberships and a membership audit. New Auth users get a profile automatically; **no user is automatically made an administrator**, and user-provided metadata cannot assign roles. A leader must be directly assigned to a group; parent-group permission inheritance is not yet defined.

## 3. Create a test administrator

1. Under **Authentication → Users → Add user**, create a test user with an email address you control and a password you generate. Keep the password private. Do not send it through chat. Confirm the account as appropriate for this development-only test.
2. In the SQL Editor, run the query below **after replacing the example address locally in the dashboard** with that exact test account's email address. It must return one row. This grants a highly privileged role, so only use an account you control. Never grant the administrator role through untrusted app input.

```sql
insert into public.user_roles (user_id, role)
select id, 'administrator'
from auth.users
where lower(email) = lower('replace-with-your-test-email@example.com')
on conflict (user_id, role) do nothing
returning user_id, role;
```

If no row is returned, check the address in Authentication → Users; if the role was previously granted, the conflict clause also returns no row. To check without changing it:

```sql
select r.user_id, r.role
from public.user_roles r join auth.users u on u.id = r.user_id
where lower(u.email) = lower('replace-with-your-test-email@example.com');
```

The connected workspace can manage groups, group leaders, existing test profiles and subgroup membership. It does not yet create Auth accounts; create test users in the Supabase dashboard and assign their roles in the connected workspace.

## 4. Configure the browser app

The app currently defaults to the clearly labelled **demo workspace**. To enable its separate development sign-in:

1. Find your **Project URL** and **publishable key** (or legacy `anon` key) in Supabase's **Connect** panel or project API settings.
2. In the app workspace, make a private local copy of `.env.example` named `.env.local` and enter those two values as `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. The file is ignored by Git. Use your own editor or the deployment environment's configuration controls; don't paste credentials into chat. In Arena, local environment files and running processes may not survive a new workspace session, so you may need to configure the public values again.
3. Restart the Vite server after changing environment values. Open the preview and select **Sign in** in the top bar. Sign in with the test account you created; the connected People & groups workspace opens. An administrator can give existing test accounts recognisable display names and roles there.

The URL and publishable/anon key are **public client configuration** and are visible in the browser bundle; they are not a substitute for RLS. Never place a Supabase `sb_secret_...` key, legacy `service_role` key, database password, access token, or other secret in `VITE_` variables or client code. The app rejects obvious secret-key mistakes, but this is not a substitute for managing credentials properly.

Arena's sandbox can access only a limited set of outbound hosts. Its server-side tools may therefore be unable to contact Supabase, even when the user's browser can. A successful browser connection must be tested; if it is blocked, use an appropriate deployment environment or approved network configuration rather than weakening access controls.

## 5. Configure password recovery for the preview

In Supabase Authentication → URL Configuration, add the **exact HTTPS Arena preview URL** to the allowed redirect URLs. The app requests resets back to the current preview origin and path; do not use `localhost` for a browser outside the sandbox. Preview URLs can change between sessions, so update the allowlist when necessary. Set the Site URL appropriately for the development environment as well.

Request a reset from **Forgot your password?** and open the email in the **same browser and origin** where you made the request (the app uses PKCE). The built-in email sender may only deliver to authorised project-team addresses and is rate-limited. Do not rely on this configuration for production. Dashboard invite/first-time password setup is not yet implemented in the app; create a controlled test user with a password for now.

## What has and has not been verified

- `npm test` runs UI tests with a mocked Auth client and runs the actual migration and row-level-security checks against embedded PostgreSQL with a simulated Supabase Auth schema.
- For the connected MA-LS development project, all eleven migrations through 010 have been applied during development. The remote migration-history timestamps do not match the local filenames; do not run a naive `supabase db push` or reapply earlier migrations there. Reconcile history and select only unexecuted, reviewed changes. For any other project, verify migration status before applying them. Real Supabase Auth, API access, recovery emails and RLS must be validated using test accounts before any real data is used.
- Access tests currently cover anonymous denial, self-promotion prevention, isolated trainees and leaders, controlled membership archive/restore/delete, and administrator access. The membership operation is available through a controlled database RPC and a connected group-management screen. Embedded database tests also cover dated course assignment, assignment overlap, access after archive, publication immutability, and self-reported progress access and isolation.
- Plain-text courses, assignments, self-reported reading progress, quizzes, trainer-reviewed practical assessments and required-block completion are connected. Certificates, SharePoint and Google delivery, audit/retention policy beyond membership actions, and production readiness remain future work.

## 6. Exercise courses with test accounts

1. Sign in as the test administrator. Open **Courses → Create course**, add modules and text blocks, edit and reorder them, and try **Preview**. Mark blocks required or optional; at least one required block is needed to publish. Only use fictional, non-confidential text. Published versions are locked; create a new draft version to change content.
2. Open the published course and choose **Assign course**. Select a group and a target date. Current active members receive that date. Published titles and descriptions are available to active leaders in their catalogue, and leaders can assign them within their directly authorised groups/people.
3. Add an eligible trainee to that group. Enter a separate target date for each group course. The account must already exist, have the trainee role and be eligible for that leader's scope. Sign in as the trainee and open **Assigned** to read the assigned text, mark a block as read and see their active groups and leaders. Trainees without management roles do not see People or Groups & subgroups tabs. Sign in as a directly authorised leader, open **People**, select the trainee, and check the reading count. A leader outside the scope must not see the person or their progress.
4. Create and publish a second version of a test course. Confirm the original assignment, target date and reading marks remain on version 1. Assign version 2 separately, and check the warning and separate version/date. Check the warning when adding or restoring a trainee to a group with another version. Verify another test trainee outside the group cannot see it. Check on a mobile-sized screen. Mocked UI and local embedded-Postgres tests do not demonstrate real browser/Supabase access; these end-to-end checks still need to be performed.

Each published version is a separate course assignment. Creating or publishing a later version does not move trainees, dates, reading marks or group requirements. Assign a newer version separately if needed; the interface warns when another version is already assigned or may be assigned through a group. A version assigned through multiple groups or individually has one record and retains the original target date. Archiving or deleting the last active group source removes access to a group-only course, but does not delete the assignment history; another active group or individual source preserves access. Restoring a membership with required courses requires dates, and multiple such memberships must be restored one at a time. The user confirmed these overlap and removal rules for the development build. Reading marks remain stored when group access is removed and can be unchecked when access is active. They are self-reported and do not prove understanding. Unmarking required reading reopens a completed assignment; completion and reopening events remain. A prior successful quiz or practical attempt still counts after a later failure. There is currently no interface for editing target dates or unassigning courses. Do not place external document URLs or sensitive content in text blocks.

## 7. Exercise assessments with test accounts

1. In a draft course, add a quiz or practical assessment to a module. For a quiz, author questions, correct choices, feedback, pass mark and attempt limit. One attempt disables retries. For a practical assessment, create an ordered checklist; a trainee requests review without providing evidence. Publish the version and assign it to a test trainee.
2. For a non-administrator reviewer, give a test account both the **trainer** and **group leader** roles and assign them directly as a leader of an active group containing the trainee. Administrators may also review. An account cannot review its own attempt.
3. Sign in as the trainee, submit a quiz or request practical assessment. A short answer waits for review; automatically marked questions are scored server-side. Partial credit for multiple response is `(correct selections − incorrect selections) / number of correct options`, floored at zero. Each question has equal weight.
4. Sign in as the reviewer and open **Reviews**. Mark short answers or every checklist criterion and add an optional overall comment. All practical criteria must be competent for sign-off; otherwise the result is not yet competent. Reassessment creates a new record. Decisions are immutable through the application and identify the authenticated reviewer and time; this is not a claim of a legally compliant electronic signature.
5. Check that the trainee sees the attempt and feedback, and that an unrelated trainee or a leader without the trainer role cannot access or review it. Creating a new course version copies the definitions, not attempts. Actual signed-in API, end-to-end browser and physical-phone checks remain necessary; local SQL and mocked UI checks do not replace them.

Certificate issuance is not deployed to this development project. A local, disabled prototype exists; see `TASK_5_IN_PROGRESS.md` and do not enable its feature flag against the current database. External evidence links/uploads are not implemented. Use fictional test data only.

## 8. Exercise completion and the overview

1. Assign a published test course with required text, a quiz and a practical assessment. As the trainee, mark the text, pass the quiz and request practical review. The required-block count advances; awaiting-review is shown while an unsatisfied required assessment awaits a trainer.
2. As an authorised trainer/leader or administrator, complete the review. When all required blocks are satisfied, the assignment shows completed and records a completion event. Optional blocks do not hold up completion.
3. Unmark required text to reopen the assignment; mark it again to complete it. Check the completion history. A later failed assessment does not negate an earlier pass or competent decision.
4. Open **Overview** as an administrator or group leader. Filter by group, course version or status; counts cover active assignments in the selected scope. Target dates end at the end of the day in Pacific/Auckland, including daylight saving. An overdue flag is not an on-track prediction.
5. Some work may have already satisfied the completion rules when the development database was migrated. Such assignments are shown as completed but labelled **completion date unverified**; their recognition timestamp is not a known historical completion date and no on-time/late result is inferred. Do not use that timestamp as a verified date for future certificates without resolving it.

Real signed-in API and physical-phone checks are still needed. These development checks do not establish production readiness.

## Task 5 prototype status (not deployed)

The certificate editor flattens an uploaded, single-page PDF in the author's browser and stores only its bounded blank PNG image, not the original PDF. Immutable issue details and that image are used to generate a PDF when the learner requests a download. The user confirmed in-app download rather than automatic email; no PDF is retained as a separate stored file. The current upload limit is 3 MB and encrypted files are unsupported. Flattening removes PDF actions and annotations but does not eliminate browser PDF/image-decoder risk; the database validates the PNG structure and dimensions, not its compressed pixels or CRCs. Representative templates, unsupported characters, security and accessibility remain to be tested.

Migrations 011–014 and the scheduled refresher job have **not** been deployed; `VITE_CERTIFICATES_ENABLED` must remain false. The local scheduler does not run automatically and no external monitoring or alerts are installed. See `TASK_5_IN_PROGRESS.md` for the outstanding deployment, security, monitoring and end-to-end validation requirements. Do not reapply deployed migrations 009 or 010.
