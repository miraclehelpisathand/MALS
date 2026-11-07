# Miracle Academy

A development foundation and browser-based prototype for the Miracle Academy learning management system. See [the specification](MIRACLE_ACADEMY_SPEC.md) and [Supabase development setup guide](SUPABASE_SETUP.md).

## Run locally

Requires Node.js 20.19+ or 22.12+.

```sh
npm ci
npm run dev
npm test
npm run build
```

Open the URL printed by Vite. For a remote preview, use the platform's preview URL, not localhost.

## What is implemented

The responsive **demo workspace** includes illustrative course/module/block placeholders, groups, assignments and practical review interactions. Its data is stored **only in this browser's local storage**, and remains entirely separate from the connected development workspace. Do not enter real personal or confidential data.

A separate sign-in screen supports Supabase email/password sign-in and password recovery when configured. The connected development workspace supports test-user roles and display names, groups/subgroups, direct group leadership, memberships, text and assessment courses, dated assignments, self-reported text-reading progress, quizzes, practical assessments and completion dashboards. Administrators and authors can edit, delete, reorder and preview draft modules and text blocks, mark blocks required or optional, publish immutable versions, create new draft versions, and author quizzes and practical checklists; administrators and directly assigned group leaders can assign published courses to groups or eligible individuals. Trainees see an Assigned tab with their courses, active groups and group leaders; they can open assigned courses, mark text blocks as read, submit quizzes and request practical assessments; directly authorised leaders and administrators can view reading progress. Test Auth accounts must currently be created in the Supabase dashboard. For a new dedicated development project, apply the migrations in order following [SUPABASE_SETUP.md](SUPABASE_SETUP.md). All eleven migrations have been applied to the connected MA-LS development project; do not re-run them there.

### Course and assignment rules for this development build

- A group assignment gives all current active members the entered date. When someone joins or is restored, the manager must enter a date for each group course. Restoring multiple memberships with group courses must be done one at a time.
- A trainee has one assignment per course version, even when several groups or an individual assignment overlap. The **first target date is retained**; a later date entry does not replace it. Changing target dates or removing an assignment is not yet supported. The user confirmed this behaviour for the development build.
- Archiving/deleting a membership keeps the trainee account and assignment records. Group-only course access ends when there is no other active group source; an individual assignment or another active group keeps access. Restoring an archived membership restores its group course access. The user confirmed this access behaviour for the development build.
- All leaders can see the titles and descriptions of published courses in the catalogue and assign them within their authorised scope. Content is visible to authorised authors/admins, leaders with an assigned group/trainee, and assigned trainees; group data stays directly scoped.
- Reading marks are self-reported and do not prove understanding. Completing every required block marks an assignment complete. Unmarking required text reopens it; completion and reopening events remain in history. An earlier passed quiz or competent practical assessment keeps counting even if a later attempt fails. Certificates are not yet issued.
- Quizzes support single choice, multiple response, true/false and trainer-reviewed short answers. Authors set a pass mark and attempt limit; multiple response uses partial credit. Practical requests are reviewed against a checklist with an optional overall comment. Administrators and trainers who directly lead an active group containing the trainee may review, but cannot review their own attempt. The review queue can be filtered by course version and status. Decisions and attempts are retained for the assigned version. No evidence links or uploads are collected.
- The Overview tab shows authorised active assignments, completion, overdue and review counts, with group/course/status filters. Target dates end at midnight following the date in Pacific/Auckland. Existing work recognised as complete when tracking was introduced is marked with an unverified original completion date and no inferred late result.
- Published versions are locked. A new draft copies content without moving existing assignments, dates, reading marks or group requirements. New versions may be assigned separately; the interface warns about other assigned versions, including when adding or restoring a group membership. Required blocks count towards completion; optional blocks do not. Do not put confidential provider links into text blocks: they would be visible to assigned trainees.

## Important limitations

This is **not a production LMS**. Reading marks are self-reported and do not prove understanding. Certificates and expiry/recurrence scheduling exist only as a disabled, un-deployed local prototype (see `TASK_5_IN_PROGRESS.md`); secure video and SharePoint/Google secure content delivery are not implemented. Assessment sign-off is an authenticated application record, not a claim of legally compliant electronic signature. Publishing and certificate controls in the demo are illustrative, and demo sign-offs do not update completion. Local embedded PostgreSQL access tests and mocked UI/Auth tests do not replace integration tests against the actual Supabase project, security review or production operational setup. Never place service-role/secret keys, database passwords or provider credentials in client code or `VITE_` variables.
