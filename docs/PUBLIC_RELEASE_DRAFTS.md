# Public release drafts — not published or legally approved

Replace bracketed owner fields, approve commitments and obtain appropriate legal
review before publication. These drafts describe implemented behavior; they do
not resolve O-P18 or authorize public distribution. Operational steps are in
ANDROID_RELEASE.md; current completion status remains in README.

## Privacy notice draft

List & Split is operated by [legal operator, address/jurisdiction], contact
[privacy/support email]. We use account email, username, display name and optional
profile photograph to provide your account and collaborative features. Your
content can include lists/items/notes, memberships and invitations, templates,
friendship/block relationships, Chat messages, and expense/settlement records.
Expense features record shared amounts; the app does not process payments.

Content is available according to feature permissions. Public profile/template
surfaces are available to eligible authenticated users, subject to blocking and
moderation. Shared lists, Chat and Split are available to authorized participants.
Avatars are resized/sanitized PNGs in private storage and returned through an
authenticated authorization check; they are not a public image bucket. Select an
image only if you have permission to use it. Gallery cancellation uploads nothing.

Supabase provides authentication, database, image storage, server functions and
Realtime services in [approved region]. [SMTP provider] delivers account emails.
Service providers may process technical connection, security and operational
logs. [Confirm subprocessors, international transfers and contractual safeguards.]
No advertising or analytics SDK is added by this release; do not interpret this
as a claim that hosting providers generate no technical logs. Chat is not claimed
to be end-to-end encrypted. Android automatic app backup is disabled in the
release configuration.

You can export your own account data and current avatar from the app. You can
request permanent account deletion in Profile (or incomplete Onboarding), with
recent authentication and explicit confirmation. Owned content is removed as
defined by its lifecycle; surviving shared financial history is anonymized, and
independent copies saved by other users can remain. Deletion includes current and
tracked avatar files. It does not erase independently held copies. An external
deletion request route will be provided at [reviewed HTTPS account-deletion URL];
this route is not yet implemented/published.

Existing retention rules include Chat messages up to 365 days, terminal template
sends for 180 days, and closed public-template moderation evidence for 24 months,
with scheduled cleanup. [Confirm backup/log retention, legal exceptions and request
handling periods.] [State applicable rights, complaint authority and how to make
a request for the operator's actual jurisdiction.] [Confirm age eligibility and
children's data policy.] We will publish material changes at [policy URL/date].

## Terms draft

By using List & Split you agree to [operator/contact], [effective date/version],
and [confirmed age eligibility]. Keep your account secure, use content you are
entitled to share and respect other participants. Do not post unlawful, abusive,
threatening, exploitative or privacy-infringing content, impersonate others, evade
blocks, or misuse the service. [Approve exact prohibited-content policy and
enforcement/appeal process under O-P18 before presenting these as accepted terms.]

Lists/templates/Chat are collaborative content. Expense totals and settlements
are records entered by participants, not bank transfers or a payment service.
Check amounts and participant permissions before relying on a record. Independent
template copies can survive changes or deletion of the original. Use the app's
block controls for unwanted contact; [reporting path, moderator response and appeal
contact await implementation and owner approval].

You retain rights in your content and grant [the narrowly required hosting/display
permission, to be reviewed]. [Approve availability/support commitments, suspension,
termination, limitation of liability, governing law and dispute terms consistent
with mandatory consumer rights.] You may export/delete your account using the
documented controls. [Describe notices and treatment of backups consistently with
the approved privacy notice.] No unapproved contractual promises are active.

## Store listing and declaration worksheet

Proposed title: **List & Split**.

Proposed short description: **Shared lists, reusable templates and simple expense records.**

Proposed full description: Plan together with shared lists, assign items and keep
notes with your group. Reuse private templates or discover templates through your
community. Discuss a list in Chat and optionally record shared expenses,
settlements and reversals. Personalize your profile with an optional avatar and
choose English or Portuguese, light or dark appearance. An account and internet
connection are required for collaborative features. Expense records do not move
money. Offline mutation queues and push notifications are not included.

Owner must supply: developer/legal name, support email/website, privacy URL,
external account-deletion URL, approved icon/feature graphic/screenshots, target
audience/age/content rating, countries, access instructions for review, and Play
App Signing choices. Use synthetic content in screenshots, not real personal data.
Do not claim offline sync, payment processing, anonymous access or end-to-end
encryption. Store publication is not authorized by preparation of this worksheet.

Data Safety review inputs (confirm exact Play definitions before submission):
account email/name/user identifiers; optional photo; user-generated list/template/
Chat content; user-entered expense information; provider technical diagnostics.
Document each data type's purpose, optionality, transmission/encryption, service-
provider processing, deletion and retention. Do not automatically equate service-
provider processing with a specific Play “sharing” answer. Validate actual SDKs,
production configuration and subprocessors, then have the owner attest the form.
