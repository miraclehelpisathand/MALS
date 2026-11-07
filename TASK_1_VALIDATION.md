# Task 1 — development foundation validation

**Date:** 1 November 2026
**Scope:** development project only. Do not use real trainee or confidential data yet.

## Checks completed

- The user previously confirmed that a test group leader sees only their groups and that the updated trainee Assigned view looks workable. This is not a sign-off on every workflow.
- `npm test`: 40 tests passed, including mocked connected UI/auth tests and embedded PostgreSQL RLS/RPC tests. `npm run build` passed with a bundle-size warning.
- On the actual development database, a transaction using simulated authenticated identities tested two group courses and separate join dates, atomic rejection when a date is missing, leader scope, trainee reading progress, overlapping group assignments and original dates, archiving, deleting the remaining active source and restoring the archived group. The transaction was rolled back; no test groups or courses remained.
- Additional read-only checks on the development database with simulated identities confirmed two test trainees could only read their own profiles, memberships, assignments and reading marks; their active assignment and group counts matched database records. Leader group visibility and relevant direct-write/anonymous privileges were checked. These checks did **not** send signed PostgREST requests.
- Headless Chromium rendered the app at 320, 390, 768 and 1280 CSS pixels, with Supabase Auth and API responses mocked. Trainee checks covered sign-in, Assigned tab, group leader, target date and marking text as read; administrator checks at 320 and 390 pixels covered assigning two courses, separate dates, archive and restore. No horizontal page overflow remained in the tested screens. A narrow-screen sign-in/header issue was fixed. These were emulated viewports, not physical-device tests, and the mock API is not evidence of live server authorization.
- Supabase Auth, database and REST health checks reported healthy; the preview responded HTTP 200.

## Still required before declaring every aspect of task 1 complete

1. Repeat the signed-in trainee and administrator/leader workflows against the live Supabase API with test accounts. Verify two different target dates, reading progress and leader visibility. Use only disposable test groups and courses for archive, deletion and overlap testing, preserving existing user records. Do not share passwords, access tokens or service keys.
2. Test the live preview on a physical phone. Confirm sign-in, Assigned, opening the course, marking a block, group/leader names and the leader/admin membership controls are usable.
3. Perform a dedicated authenticated API security/integration test with authorised test sessions, including attempts to read another trainee's records and a group outside a leader's scope. Local mock API and simulated-identity database checks are not substitutes for signed PostgREST requests.

Task 1 validates the development foundation; it does not establish production readiness or implement course completion, assessments, certificates or secure external-file delivery.
