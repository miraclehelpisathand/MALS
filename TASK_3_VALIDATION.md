# Task 3: assessment development validation

## Implemented

- Draft quiz and practical-checklist authoring, editing, ordering and preview within versioned courses. Quiz types: single choice, multiple response, true/false and trainer-reviewed short answer. Pass marks, attempt limits and question feedback are configurable.
- Multiple response awards `(correct selections − incorrect selections) / correct options`, with a minimum of zero. Each question has equal weight; short answers are reviewed as correct or incorrect.
- Trainees submit quizzes and request practical assessment without providing evidence. The authorised reviewer marks every checklist item, adds an optional overall comment, and all items must be competent for a competent result. Attempts and signed decisions remain with the assigned course version; each reassessment is a new record.
- Administrators and trainers who directly lead an active group containing the trainee can review. No one can review their own attempt. A reviewed decision cannot be edited in the app. This is an authenticated application record, not a legally compliant electronic signature.

## Checks completed

- Full local suite: 62 tests passed, including embedded PostgreSQL tests for hidden answer keys, unauthorized and anonymous access, authoring restrictions, scoring, attempt limits, trainer scope, group archive revocation, immutable reviews, reassessment and version copying. UI tests exercise authoring, quiz submission, practical requests and trainer review.
- Production build succeeds; the existing bundle-size warning remains.
- Headless browser using a **mocked** Supabase API: assessment authoring at 320 and 390 pixels, with no horizontal overflow.
- Applied `202611010008_assessments.sql` to the MA-LS **development** project. The existing assignment hash and course/block counts remained unchanged; existing blocks defaulted to text.
- A rolled-back development-database workflow using simulated JWT identities exercised quiz and practical authoring, assignment, answer-key redaction, scoring, trainer review, immutable decisions and version copying. Permission metadata confirms anonymous/authenticated users cannot directly read answer-key tables or write attempt records. No test assessments or role changes were retained.

## Still required

- End-to-end browser and signed-in Supabase HTTP/API tests using real test accounts, including attempts to read answer keys and records outside the trainer's scope. Simulated database identities and mocked browser requests are not substitutes for these checks.
- Physical-phone testing and an independent security/production-readiness review remain outstanding. Use fictional test data only.
- Course completion, certificates, expiry/refresher scheduling, external evidence links and secure SharePoint/Google delivery remain future work.
