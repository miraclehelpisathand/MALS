# Miracle Academy — LMS requirements and proposed specification

**Status:** Draft for discussion · **Date:** 29 October 2026

## 1. Purpose and decisions so far

Miracle Academy is a browser-based learning management system (LMS) for creating training, assigning it to people, assessing knowledge and practical competence, and giving leaders visibility of their groups' progress.

**Confirmed:** Produce a detailed specification first; plan for up to 200 trainees and 30 trainers. Use dedicated email-and-password accounts and Supabase for authentication and LMS records. The browser experience should use HTML, link to material held in SharePoint or Google Docs/Drive to avoid storing large amounts of course content in the LMS, and include a free built-in video player for compatible sources. Practical assessments use a checklist and trainer sign-off. Users can be assigned courses with target dates; groups can have one or more leaders, and new group members automatically receive existing group assignments. Certificates, expiry dates and recurring refresher training are required. Certificate validity starts on course completion and is configured in course details, where the refresher may be set to the same course or a different course. Learners receive a certificate for their records and optional printing, and course settings must allow a custom certificate template to be loaded. A group leader sets a separate target date for each course when adding a trainee to a group. Trainees who leave have their details retained until a group leader archives or deletes as appropriate. A group leader can assign a trainee to multiple subgroups and manage the trainee’s subgroup memberships from the trainee dashboard. Linked files must be checked for access without special individual shares; ideally trainees open them without an additional sign-in after logging into Miracle Academy. Raw source links should not be displayed to trainees, to discourage sharing.

**Not yet decided:** Front-end hosting and budget, the intended access policy for linked files, some content exceptions, detailed reporting permissions and reminder notifications. Recommendations below are not final decisions.

## 2. Product scope

### Roles and permissions

A user may hold multiple roles. Permissions must be enforced on the server for every request, not just by hiding buttons.

| Role | Proposed capabilities |
| --- | --- |
| Administrator | Manage users, roles, groups, assignments, all courses and reports; administer system settings. |
| Course author | Create and edit courses, modules, blocks and assessments; publish if authorised. |
| Trainer | View learners and assessments within their authorised scope; review submissions and sign off practical assessments. |
| Group leader | View progress and the trainee dashboard for members of groups they lead; assign trainees to authorised subgroups and select subgroup memberships to archive or delete. |
| Trainee | View assigned courses, complete learning and submit assessments; view their own results and feedback. |

Group and subgroup membership and leadership are many-to-many: a person may belong to several subgroups, and a group may have several leaders. The precise parent-group/subgroup structure and inherited leader permissions remain to be agreed. A leader should not see learners outside their authorised groups. Decide whether leaders may assign courses, view detailed assessment responses, or only see summary progress. Decide how trainers are allocated to learners or courses and whether authors can publish without approval.

### Course hierarchy and builder

**Recommended hierarchy:** course → ordered modules → ordered blocks. Optional categories organise courses in the catalogue but do not change the hierarchy. A course has a title, description, expected duration, owner, version and publication status. Modules group related learning. Blocks are the smallest units of content or assessment and can be reordered.

Authors should be able to create, edit, reorder and preview modules and blocks, mark blocks required or optional, save drafts, and publish a course. Initial block types:

- Rich text and images, including accessible image descriptions.
- Documents and presentations: add a SharePoint or Google Docs/Drive link; preview through authorised academy delivery where supported; otherwise show an unavailable message.
- Website or embeddable page, displayed only where it can be delivered without exposing the source link; otherwise show an unavailable message.
- Video: link to a compatible source; use HTML5 playback controls via authorised academy delivery where supported, with captions/transcript where available. Do not expose the provider link to trainees.
- Quiz or knowledge check.
- Practical assessment and trainer review.

A course assignment should reference a published course version. Editing a published course should create a new version rather than silently rewriting a learner's historical record. Agreed for this development build: existing assignments stay on their original version. A newer version can be assigned separately, with a warning if another version is already assigned; group requirements and target dates are not silently migrated. External files may change independently of the LMS: a saved URL or LMS version does not freeze a linked document. Where a historical copy matters, use a stable, access-controlled version at the source and record its reference; verify that source permissions and retention preserve access.

### Content and storage approach

**Confirmed:** Keep large course materials in SharePoint or Google Docs/Drive and store links and LMS records rather than copying the materials into the LMS. Authors add links to documents, presentations, web pages and video. Direct file uploads and evidence attachments are not assumed for the first release; use an authorised external link for evidence if needed, subject to the final assessment policy. This reduces LMS media storage, but the external services still have their own storage, access and costs.

SharePoint and Google links retain their source permissions; logging into Miracle Academy does not automatically grant access to linked files. Learners may need to sign into the source separately. Embedding depends on provider settings, browser behaviour and the actual link; websites may prohibit framing. Do not show raw source links or provide an external-link fallback to trainees; show an access error and contact/support action if a resource cannot be displayed within the academy. Do not make private training materials public merely to enable embedding.

**Access check requirement:** Authors must check each linked file is accessible to the intended trainees without individual special shares. The builder should offer a link-check action and record the check result, time and checker, with a clear warning when access cannot be verified. Check for a valid supported URL and use provider-supported access checks where available; a successful URL response, author access or an iframe load alone does **not** prove every trainee can open it. Because Miracle Academy email/password login does not itself provide SharePoint/Google identity or permission data, verify with a representative trainee account or an authorised provider integration where feasible. If checking is unavailable or inconclusive, mark access **unverified**, not passed, and provide an author-only test action and a way for learners to report access problems. Source permissions may change after a check. The preferred experience is no further sign-in after entering Miracle Academy. Test this in a fresh browser session with no pre-existing SharePoint or Google session, using sample links; if provider access cannot be established, record the result as unverified and identify the restriction. No actual file access can be verified until sample links and appropriate test access are supplied.

**Security and delivery design:** The user expects that authorisation of SharePoint and Google integrations should be possible, subject to confirmation by an administrator. No integration has yet been connected or authorised. Hiding a link in the interface does **not** prevent sharing. If a browser receives an external URL for an iframe, video or download, a user may be able to recover it using browser tools or network requests. A public or "anyone with the link" URL may then work outside the LMS. Users may also copy, photograph or record content that they are permitted to see. Do not promise that links or viewed content cannot be shared.

To meet the intent for private files, investigate an **authorised server-side delivery layer**: after checking the trainee's active LMS session and course assignment, the server retrieves permitted content from SharePoint/Google using an appropriately scoped provider integration and streams it through an academy-controlled endpoint without revealing the provider URL or credentials. Store provider secrets only on the server, restrict allowed source locations, protect against unsafe URL requests, and audit access. Revoking LMS access must block future requests through this endpoint. This approach depends on provider API permissions, file type, licensing and preview/playback capabilities; it must be validated with real examples. Some provider previews or websites cannot be safely proxied this way. When secure delivery is not possible, show a clear unavailable message instead of silently exposing a link or making the document public. Server-side delivery avoids storing a permanent local copy but still transfers data and may incur bandwidth or provider costs.

**Access verification:** A provider API or service identity may be used to check that the delivery service can retrieve authorised content; that alone does not prove an individual trainee can access it. Test the complete flow with representative learner accounts and source files, including revocation and failure cases. Do not record access as verified merely because an author or integration can open a file. Source permissions can change after a successful check.

The browser's native HTML video player is free and can play media served through an authorised academy endpoint when the format and streaming support are compatible. A generic SharePoint/Google sharing page is not itself a media stream. Provider APIs, range requests, video format and caption support need validation; some videos may not be playable without a different authorised approach. Websites and live presentations may not support secure embedding or server-side rendering. PDF and presentation previews similarly depend on provider and file capabilities. For unsupported content, offer an explanation rather than a trainee-visible external link.

## 3. Learning, assessment and completion

### Quizzes

Recommended first question types:

| Type | Marking | Example |
| --- | --- | --- |
| Single-choice multiple choice | Automatic | Choose one correct answer. |
| Multiple-response | Automatic | Select all correct answers; define partial-credit rules. |
| True/false | Automatic | Select true or false. |
| Short answer | Trainer-reviewed initially | Explain a procedure in a sentence. |

Authors set question text, answer options, feedback, pass mark and attempt limit (one attempt means no retry). Record each attempt, score, submission time and feedback. **Agreed:** multiple-response questions use partial credit: correct selections minus incorrect selections, divided by the number of correct options, with a floor of zero. Questions have equal weight. Short answers are marked correct or incorrect by an authorised trainer. Question banks, randomisation, matching and scenario branching can be considered later. Avoid presenting automatically marked short answers as reliable without a clearly defined matching policy.

### Practical assessments — agreed approach and proposed workflow

1. Author creates a practical assessment with instructions and an ordered checklist of criteria. Each criterion can be marked competent, not yet competent or not assessed.
2. Trainee requests assessment. **Agreed:** no trainee evidence is required for this workflow; the trainer completes the checklist and may add an overall comment. Evidence uploads and external evidence links are not included.
3. An authorised trainer observes/reviews the work, records each criterion outcome and may add an overall comment. All criteria must be competent for sign-off; otherwise the attempt is **not yet competent**. Administrators and trainers who directly lead an active group containing the trainee may review; an account cannot review its own attempt.
4. The system records the trainer's authenticated account, date/time, decision, assessment version and any subsequent changes. Reassessment creates a new attempt; prior records remain auditable.
5. Required practical blocks remain incomplete until an authorised trainer signs them off as competent.

This is an authenticated approval record, **not a claim that it is a legally compliant electronic signature**. Whether a handwritten signature, witness or regulatory controls are needed remains open.

### Completion and target dates

Agreed for this development build:

- An assignment is complete when every required block is complete, required quizzes meet their pass marks and required practical assessments are signed off. Optional blocks do not block completion.
- Progress percentage is the number of required blocks completed divided by the total required blocks (rounded down); show the count as well. If there are no required blocks, do not divide by zero: flag the course as needing a completion rule before publication.
- A content block becomes complete when the trainee explicitly marks it complete. This does not prove that they read or understood it. Quiz and practical completion follow their own rules.
- Assignment status: **not started**, **in progress**, **awaiting trainer review**, or **completed**. Unmarking required text reopens a completed assignment; completion and reopening events remain in history. A previously passed quiz or competent practical attempt continues to count even if a later attempt fails. **Overdue** is an additional flag when the due date has passed and the assignment is not complete. A completed assignment can also be labelled **completed late** when appropriate.
- Existing work already satisfying the rules when tracking was introduced is recorded as recognised at migration time; its original completion date and on-time/late result are unverified. Do not treat that recognition timestamp as a verified completion date for future certificates.
- A target date alone cannot objectively establish whether a learner is *on track* before the deadline. Do not infer this from percentage alone. Add milestones or an explicit pacing rule if early warning is required.
- When adding a trainee to a group, a group leader sets a separate target date for each assigned course. Agree whether dates are date-only, which timezone applies, and whether a date can be changed; record changes. For this development build, a date expires at the end of that day in Pacific/Auckland, including daylight saving. Changing target dates remains future work.

## 4. Assignments, groups and dashboards

Administrators can assign a published course to an individual or group. Each trainee has an individual assignment and progress record. **Confirmed:** adding a trainee to a group automatically assigns its existing group courses, and a group leader sets a separate target date for each of the trainee’s assigned courses at that point. If the date cannot be supplied during addition, propose flagging it as pending for leader action rather than silently inventing one; confirm whether adding without a date should be allowed. Proposed default: do not duplicate an active assignment when a person belongs to multiple groups with the same course; record all assignment sources so removing one source does not accidentally remove another. Decide how conflicting group deadlines are resolved. When a trainee leaves, their details remain until a group leader archives or deletes them; leaving alone must not automatically erase the record. The trainee dashboard must show the subgroups the trainee belongs to and let an authorised leader select memberships to archive or delete as appropriate. A membership action must not automatically remove the trainee from unselected subgroups or delete their account or learning history. An archived membership can be restored later; deleting a membership removes that membership permanently. Neither action erases the trainee’s training history. Define the effect on assignments and whether separate account deletion is permitted. Preserve completion and assessment history on reassignment.

**Trainee dashboard:** an **Assigned** tab shows assigned courses, the trainee’s active groups and their group leaders. Trainee-only users do not need the administrator/leader People or Groups & subgroups management tabs. The dashboard should also show progress and required activities, upcoming/overdue targets, pending trainer reviews, completion and feedback as those features are implemented.

**Group leader dashboard:** choose an authorised group and open a trainee’s dashboard to see assigned courses, progress, target dates, overdue flags and review status. From that dashboard, leaders can assign the trainee to authorised subgroups, see their subgroup memberships, select one or more memberships, and archive or delete the selected memberships as necessary. Archived memberships can be restored; deleted memberships are permanently removed, without erasing training history. Show clear confirmation of the affected memberships, and record who made the change and when. Aggregate completion/overdue counts with filters. A leader assigned to multiple groups may switch between them. Clarify visibility and management permissions for other leaders’ subgroups and access to scores and evidence before exposing them.

**Trainer dashboard:** assessment requests, assigned learners, checklist/evidence, decision and feedback, with filtering by course and status.

**Administrator dashboard:** users, groups, assignments, course publication, organisation-wide completion and overdue reporting, and CSV export subject to access controls. Consider reminder emails before and after target dates; timing and opt-out policy need agreement.

### Certificates, expiry and refresher training

**Confirmed requirements (task 5; implementation is still in progress):**

- An authorised course manager enables certification and uploads a single-page PDF template in course settings. The uploaded PDF is flattened to a non-interactive image for storage; the original PDF is not retained. A visual positioning editor places the trainee name, course/version, completion date, expiry date and certificate ID. The trainee can download and print their individual certificate as a PDF from their account at completion and later; automatic email is not required. Its immutable issue details and flattened template can reproduce it later. Template and issued-record snapshots must preserve history.
- Only issue after all required learning and trainer sign-off are complete. Validity begins on the completion date; a 12-month certificate expires at the **end of its anniversary date in Pacific/Auckland**. Course settings specify validity and refresher lead days; non-expiring certificates are supported.
- The refresher is the original or a different course, configured by the author, and is assigned the configured number of days before expiry, due at the end of the expiry date. Use the latest published version at assignment time. A new, independent learning cycle must not reuse earlier progress or assessment passes. Completing a different refresher renews the original qualification. Earlier completion, assessment and certificate records remain intact.
- Reopening a completed course revokes its certificate. Re-completion creates a replacement request that requires administrator or authorised staff approval, rather than automatically extending validity.
- If an existing completion was initially recognised without its actual completion date, an administrator may record a verified historical date and reason, with an audit trail, before issuing the certificate. Do not infer a date from the recognition timestamp.
- Show authorised people current, expiring and expired certificates and upcoming/outstanding refreshers. Expiry does not erase history. The secured scheduler must be monitored and idempotent. The user selected Healthchecks.io for independent missed-heartbeat alerts; it must be configured and tested before automatic scheduling is enabled. Reminders remain to be agreed.

## 5. Security, accessibility and operations

- Use Supabase Auth for email/password authentication, verification and password reset; let the auth service manage credentials and never store plaintext passwords in LMS tables. Configure appropriate rate limits, secure sessions, HTTPS, redirect URLs and email delivery. Consider MFA and production email provider requirements.
- Use Supabase Postgres for LMS records; enforce role and group boundaries using carefully tested Row Level Security (RLS) and/or authorised server-side functions. Never expose a service-role or secret key in browser code. Restrict role assignment and privileged actions to authorised administrators; test access through the API as well as the interface.
- Run scheduled expiry and refresher processing using a secured server-side job, with monitoring, retries and idempotency. Final hosting, backup and recovery arrangements remain to be agreed; confirm Supabase plan limits, cost and data-region requirements before deployment.
- Server-side authorisation for all data, files, exports and actions; protect against cross-site scripting, cross-site request forgery and unsafe uploads/embeds. Restrict embed domains and sanitise author-entered rich text.
- Maintain an audit trail for assignment changes, course publication/version changes, trainer decisions and role changes. Limit access to evidence and personal information to authorised users.
- Define retention, deletion, backup, recovery, incident response and privacy responsibilities for trainee data and assessment evidence. Review applicable privacy obligations with the organisation's adviser.
- A crisp, clean and uncomplicated responsive HTML interface that works on mobile phones as well as tablets and desktops. Use clear icons or tabs for settings and configuration where helpful; keep common learning tasks easy to find and usable on small touchscreens. Provide keyboard navigation, readable contrast, semantic labels, screen-reader support and caption/transcript support. Target WCAG 2.2 AA where practical and test with users and assistive technology.
- HTML/CSS/JavaScript form the front end. Real multi-user accounts, authorisation, progress and assessments require a backend and database; static HTML alone is not a secure production LMS. Supabase is the chosen backend platform; decide front-end hosting, monitoring and backup arrangements before implementation.

## 6. Suggested first release and later options

**First release:** dedicated accounts and roles; groups and subgroups with multiple leaders and trainee membership management; course/module/block authoring; rich text and controlled delivery of linked documents, presentations and video where provider APIs support it; individual/group assignments, automatic assignment for new group members and target dates; the four quiz types above; practical assessment checklist and authenticated sign-off; trainee, trainer and group leader dashboards; completion tracking; downloadable/printable certificates with per-course custom templates, expiry tracking and recurring refresher assignments; basic administration and CSV reporting. Deployment and operational arrangements remain subject to decisions and cost.

**Later candidates:** automatic reminders, learning paths/prerequisites, bulk import, SSO, advanced analytics, question banks and external content standards such as SCORM/xAPI. SCORM/xAPI support should be explicitly scoped if importing third-party packages is required; it is not implied by ordinary HTML content support.

## 7. Example acceptance criteria

1. An administrator creates a group, adds trainees and assigns two leaders. Both leaders can view that group's progress; an unrelated leader cannot access it through the UI, API or export.
2. An author creates a course with two modules containing text, a document link, video, a quiz and a practical assessment; previews it and publishes a version.
3. An administrator assigns that version to a group. A group leader adds a trainee and sets separate target dates for two assigned courses. The trainee automatically receives the existing group assignments and sees the correct deadline for each; overlapping groups do not create a duplicate active assignment under the proposed rule.
4. A trainee completes the required content and passes the quiz. The course is not complete while the required practical assessment awaits trainer sign-off.
5. An authorised trainer records checklist outcomes and signs off. The learner's course becomes complete, and the decision records who signed it off and when. An unauthorised user cannot sign it off.
6. An incomplete assignment becomes overdue after its target date under the configured timezone rule. Completing it later records completion and indicates it was late.
7. Authors can check a SharePoint/Google source and see a passed, failed or unverified result appropriate to the actual method used. For supported private content, an authorised learner accesses it via an academy-controlled endpoint without the provider URL or credentials appearing in the delivered page or network requests. An unauthorised learner is denied and revoking access blocks subsequent requests. If a type cannot be securely delivered, show an unavailable message; do not expose the source link. Verify with real providers and representative files. This does not prevent copying or recording viewed content.
8. Republishing course content does not silently modify existing completed LMS records; version behaviour follows the agreed policy. Linked external content may still change independently.
9. A course manager sets certificate validity, loads a custom certificate template, and selects either the original or a different refresher course in course details. Completion of a certificate-enabled course issues a downloadable/printable certificate for the learner, with expiry calculated from the completion date. A scheduled refresher is assigned according to the agreed schedule; repeat processing does not duplicate that assignment. Past completions and certificates remain accessible after expiry and renewal.
10. A trainee cannot read or alter another trainee's records via Supabase APIs; a leader can read only the records authorised for their groups. Privileged keys are absent from browser code.
11. A trainee leaving a group does not automatically delete their details. An authorised group leader can open their dashboard, assign them to multiple authorised subgroups and select memberships to archive or delete. Archived memberships can be restored; deleted memberships cannot. Unselected memberships, the trainee’s account and training history remain intact; other group members’ records must not be unintentionally affected. The action is recorded in the audit trail.

## 8. Decisions to make next

1. **Certificate operations:** Confirm supported PDF constraints, monitoring and the practical approval process before deployment.
2. **Group target dates:** Must every course have a date before a trainee can be added, or can dates be left pending? How are dates set when a new course is assigned to an existing group?
3. **File access:** Are any training files confidential? Can an administrator confirm and authorise suitably scoped SharePoint/Google integrations, and supply representative documents, presentations and videos for testing? What should learners see when a provider or file type cannot be securely delivered?
4. **Subgroup changes:** What happens to incomplete assignments when a subgroup membership is archived or deleted? Can a leader manage every subgroup within their parent group, and can they see memberships outside it? How should conflicting deadlines from multiple groups be resolved? Can group leaders assign courses?
5. **Assessments:** Are external evidence links needed or is the checklist alone enough? Which question types, passing scores and retries are essential at launch?
6. **Hosting and policy:** Where should the front end be hosted, and are there budget, data-region or retention requirements?
7. **Source document changes:** How will externally hosted source documents be versioned for audit purposes? Course assignments remain on their original published version unless a newer version is separately assigned.
8. **Notifications:** Should learners, trainers and leaders receive email reminders for deadlines, sign-offs, expiry and refreshers? When?

## Research references

- [Moodle: Assignment activity](https://docs.moodle.org/503/en/Assignment_activity) — submissions, marking, rubrics and feedback.
- [Moodle: Course completion](https://docs.moodle.org/dev/Course_completion) — examples of activity, grade and manual completion criteria. This is an older design document, used for concepts rather than current feature guarantees.
- [Microsoft: Embed Office documents](https://support.microsoft.com/en-gb/office/embed-an-office-document-in-sway-a860fe56-6308-4dc4-9b26-072c7f3b51f0) — embed codes and source permissions.
- [Microsoft: Embedding content limitations](https://support.microsoft.com/en-us/office/add-content-to-a-sharepoint-space-with-the-embed-web-part-7ffe2898-edcf-4556-88b8-16567fc2ab7a) — websites may prevent embedding.
- [MDN: HTML video element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/video) — built-in video and caption tracks.
