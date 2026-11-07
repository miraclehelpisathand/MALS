# Miracle Academy — specification gap analysis and proposed next tasks

**Reviewed:** 7 November 2026. This compares the first-release scope in `MIRACLE_ACADEMY_SPEC.md` with the application, SQL migrations, tests and validation notes. The specification includes recommendations and open questions as well as confirmed requirements; this analysis does not treat every recommendation as an approved policy.

**Status key:**
- **Development implementation**: implemented in code and, through migration 010, previously applied to the development project. This is not production sign-off.
- **Local prototype**: code exists but is disabled or not deployed to the development database.
- **Missing**: not found in the connected application or database implementation.
- **Decision/validation**: requires a decision or evidence; tests and mockups are not proof of real-world operation.

The demo in `src/App.jsx` is separate browser-local sample data; its sample videos, category, duration, settings and other controls are not evidence that the connected LMS implements those features.

## What is already in development

| Area | Evidence | Status and remaining validation |
| --- | --- | --- |
| Email/password sign-in and recovery | `src/AuthWorkspace.jsx`, `src/supabase.js` | Development implementation. Auth users currently need to be created via Supabase dashboard; production email, redirect URLs, session configuration and account lifecycle remain to be decided/tested. |
| Roles, people, group hierarchy and memberships | `src/ConnectedWorkspace.jsx`, `src/GroupTree.jsx`, migrations 001–002, `TASK_1_VALIDATION.md` | Development implementation with direct group-leader scope, multiple memberships/leaders, archive/restore/delete and membership audit. Actual signed-in API and physical-phone validation remain. |
| Course authoring, versions and assignments | `src/CoursesWorkspace.jsx`, migrations 003–007 | Development implementation for **plain text** blocks, versions, publication, group/individual assignment and dates. The first date wins for overlapping sources; joining a group requires a separate date per course. Existing assignments stay on their original version. |
| Quizzes and practical reviews | `src/Assessments.jsx`, migration 008, `TASK_3_VALIDATION.md` | Development implementation for four quiz types and checklist reviews, including the agreed trainer scope and no trainee evidence. More real signed-in security and phone checks are needed. |
| Completion and progress | `src/Completion.jsx`, `src/progress.js`, migrations 009–010, `TASK_4_VALIDATION.md` | Development implementation for required-block completion, history, overdue/late and scoped overview filters, with Pacific/Auckland end-of-date rules. Real signed-in security and phone checks remain. |
| Certificates and refreshers | `src/CertificateEditor.jsx`, `src/Certificates.jsx`, migrations 011–014, `TASK_5_IN_PROGRESS.md` | **Local prototype only**, disabled and not deployed. Automatic refreshers and independent monitoring are not active. |

The latest recorded local full suite passed 156 tests and the build passed with a large-chunk warning. Database emulation, simulated identities and browser mocks do not replace signed-in Supabase HTTP tests, independent security review or physical-device testing. The latest development preflight is recorded in `TASK_5_IN_PROGRESS.md`; it is not a live guarantee.

## First-release gaps and suggested work packages

### 6. Secure documents, presentations and video — missing

The connected course builder only offers text, quizzes and practical assessments; it has no provider-link block, secure document delivery, access-check workflow or actual connected video player. `src/App.jsx` has demo placeholders only. The specification calls for SharePoint/Google content to remain with the provider and for learners not to see raw source links or insecure fallbacks.

Work required:
1. Agree which provider to tackle first, permitted content locations, supported file types and who authorises the integration. No provider integration has been authorised yet.
2. Design and implement a server-side delivery endpoint with session and active-assignment checks on every request, scoped provider access and server-only credentials, restrictions against unsafe URLs, and an appropriate access audit. Never send private provider URLs or credentials to the learner; unauthorised or unsupported resources should fail closed.
3. Add authoring and learner experiences, including author-only source testing, an **unverified** state where individual learner access cannot be proven, and a way to report access problems. An integration account's access alone is not proof of a trainee's access.
4. Validate using fictional/approved sample files and representative authorised and unauthorised learner sessions, including access revocation, fresh browser sessions, and no provider URL in delivered pages or network requests. Verify range requests, format support and captions/transcripts for video. Explain unsupported document/website/preview types instead of exposing links or making files public.

**Dependencies:** provider administrator approval, actual representative documents/videos and permissions, an appropriate server runtime and provider/API/licensing checks. Hiding a URL cannot prevent copying or recording content that a learner can view.

### 7. Reporting and CSV — missing/partial

The connected overview has active-assignment counts and group, course and status filters (`src/Completion.jsx`). CSV export is not implemented. The assessment review queue now has course-version and status filters over the records already authorised by the database; actual signed-in and physical-device checks remain. Confirm exactly which roles and fields may be exported, and whether inactive/historical records and certificates should be included. Implement and test export against server-authorised scope, pagination and spreadsheet formula injection; an unrelated leader must not receive another group's data. Certificate reporting must not assume undeployed Task 5 tables.

### 8. Course content and authoring improvements — missing/decision

The connected builder uses plain text and has no rich-text/image editor or image descriptions, document/video blocks, expected duration, course owner or categories as described in the proposed specification. Decide which course metadata and rich-content features are needed for the first release, and how images are stored/delivered and sanitised. Keep content accessible and preserve published-version history. Provider delivery overlaps work package 6.

### 9. Assignment and administrative lifecycle — partial/decision

Group and individual assignment creation and the agreed overlap rules exist. The connected UI does not yet support changing target dates or unassigning courses (`README.md`); the specification leaves date-change policy open. Decide authorisation, reason/audit trail, effect of overlap and already completed assignments before implementing. Account creation remains a dashboard operation; decide whether the first release needs an in-app invitation/deactivation process and a separate account deletion policy. Do not erase trainee history when a membership is archived or deleted.

### 10. Complete Task 5 certificates and refreshers — local prototype

Return to `TASK_5_IN_PROGRESS.md` for the detailed checklist: verify a recoverable development backup and migration history, independently review PDF/image ingestion, test real signed-in workflows and representative templates/printing, decide how third parties can verify current certificate status and respond to revocation, and validate monitoring and ownership. The user accepted single-page unencrypted source PDFs and flattened images up to 3 MB for the initial release. Existing downloaded/printed certificates cannot be recalled.

The user approved preparing development deployment for fictional-data testing **after** satisfactory backup and migration checks, but postponed the backup step. MA-LS dashboard backups were reported unavailable; no manual backup or restore test has been completed. Do not run a naive `supabase db push` or reapply migrations 009/010. Keep the feature flag and automatic scheduler off, and do not merge the draft PR, until the relevant review and approvals are complete. Monitoring must be independently verified before automatic refreshers are enabled; the draft GitHub Actions monitor is for development/testing, not an approved production runner.

### 11. Audit, security and privacy — partial/decision

Membership changes, assessment decisions and completion events have records; certificate historical verification is present in the local prototype. Course publication records a timestamp. The broader spec calls for audit trails for assignment changes, course publication/version changes and role changes; do not assume current records constitute a complete actor/action audit for those areas. Define audit scope, immutability, access and retention before adding it.

Perform independent security review and signed-in HTTP/API tests across roles, including cross-trainee/group reads, hidden quiz answers, author/admin privileges, archive/revocation and any future file delivery/export. Define privacy, account deletion, retention, incident response, credential rotation, and organisational approval. Server-side authorisation is required; hiding controls is not a security boundary.

### 12. Accessibility, devices, operations and release — incomplete validation

Test with physical phones and assistive technology, keyboard-only navigation, screen readers, contrast, focus management and responsive content. Mocked viewport checks do not establish WCAG conformance. Choose front-end hosting, production email/redirects, data region, plan/cost and support ownership. Establish a private backup and test restoration separately; consider storage objects and Auth/platform configuration rather than assuming a database dump includes everything. Validate performance and operational processes for approximately 200 trainees and 30 trainers. Obtain final user acceptance using the criteria in the spec. Keep fictional data until security and operational readiness are established.

## Explicitly later or not yet agreed

Automatic reminder emails, learning paths/prerequisites, bulk import, SSO, advanced analytics, question banks and SCORM/xAPI are later candidates in the spec, not automatic first-release requirements. Practical-assessment evidence uploads/links were explicitly excluded from the agreed workflow. Early 'on track' prediction requires milestones or a pacing policy and must not be inferred from progress percentage alone. Parent/subgroup inherited permissions, detailed report visibility, retention and some source-content/version policies still require decisions; existing development rules should not be silently changed.

## Recommended next step

Treat **work package 6: secure learning materials** as the proposed next feature because the first release needs document and video content and the connected LMS currently has only text and assessments. Start with a provider/file-type decision and a security design; much of the design and local work can proceed without enabling Task 5 or changing MA-LS. A real integration, database deployment and end-to-end acceptance require the dependencies above. If the owner prefers a smaller independent task, reporting/CSV can be scoped first, with access rules agreed before implementation.

## Work started outside Task 6

The trainer assessment review queue now offers course-version and status filters, a matching-record count and a clear empty result. The filters narrow existing database-authorised rows and do not change who may view or review an assessment. Local UI coverage includes combined filters, distinct versions, exclusion of the current user and removal of stale course selections after refresh. Task 6 and the deferred Task 5 backup/deployment remain on hold.
