# PR 33 UI and usability follow-up

Scope comes from Fernando's approved request and all 16 embedded screenshots in
“Things to change.docx”. The pasted request takes precedence over screenshot-only
camera/audio, avatar and template-image controls. Live Figma is not required.

| Reference item | Delivery and source behavior |
| --- | --- |
| 1 Checkbox flicker | PR #33: remove the routine success banner that shifted keyed rows 60px; retain authoritative completion/reconciliation, scroll state and recoverable failures. |
| 2 Unassigned rows | PR #33: hide visible assignment text/icon and spacing when empty; preserve semantic assignment context, assigned identities and editing. |
| 3 Fast item creation | PR #33: shared +/keyboard quick-add, quantity 1, no unit/assignment, existing controller/request recovery, guarded submission and revision-aware draft clearing; detailed edit remains. |
| 4 Split | PR #33: horizontal balance strip, payer-to-recipient suggestions and compact transactions using existing real contracts/initials. Preserve settlement confirmation/history/reversal and integer currencies; no money transfer. |
| 5 Chat | PR #33: incoming/outgoing alignment/colours, external identity and compact composer; preserve text sends, tombstones, paging, retry, unread/navigation and access restrictions. No media controls. |
| 6 Dropdown captions | PR #33: plain persistent AppDialogField captions above all affected filled dropdowns, with selection/validation/semantics retained. |
| 7 Community cards | PR #33: author/title/profile action and publication/count on compact text-only cards with existing text colours. Image selection/preview and image-bearing cards are the next separate feature PR, gated by O-P19/O-A17. |
| 8 Profile avatars | Existing PR #34: gallery selection, replacement/removal and identity rendering. Keep that branch unchanged here; later integrate the updated PR #33 base and verify its button/layout against images 15–16. |
| Additional Language selector | PR #33: System / English / Português, immediate app locale, device-local persistence and recoverable storage errors; preserve route/session/tab/drafts. |

## Verification and remaining QA

Regression coverage must prove stable completion rows and scroll, remote updates,
quick-add defaults/focus/failure/duplicate guards/newer drafts, assignment display
and semantics, language persistence/fallback/state preservation, dropdown captions,
and unchanged Split/Chat navigation and mutation behavior. Exercise EN/PT in both
themes and approximately 200% text with keyboard insets. Generated review images
and logs stay outside the repository.

Automated/widget visual evidence is separate from Samsung physical QA. A built or
installed Dev APK does not establish user sign-in, all-screen correctness,
accessibility on hardware or two-device reconciliation. Record actual observations
and leave unperformed scenarios pending. No hosted rollout, Production access,
PR #34 change, account deletion or retention invocation belongs to this follow-up.
