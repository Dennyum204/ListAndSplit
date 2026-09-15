# Next private-beta checkpoint

Base: main `9d6ef896d0d7d00af9afd49546960a90307ed4ea` (PRs 33–36 merged).
Fernando and Susana report successful use of their existing accounts. Preserve
both accounts and all content, including the adopted QA account/list. Never use
the damaged ProjectListsApp checkout.

## Chat and Login

Branch `codex/chat-login-stability`: stable bubble action geometry, a fixed-origin
history sliver, tail following across viewport changes, and named Login hints
without floating labels. Sends retain the existing confirmed-only, request-bound
retry flow; no speculative bubble or second transport was introduced.

42 focused widget checks pass, including pending/reconciled element identity and
geometry, real visible-message pagination anchor, keyboard/multiline resize,
incoming versus history reading, EN/PT light/dark Login and filled-field semantics.
Spoken TalkBack and final device checks remain pending. Full Flutter verification
is required on the final combined source and by each applicable CI gate.

## Following branches

`codex/launcher-welcome` follows the Chat/Login branch. It replaces Flutter's
launcher resources with an original shared-list mark and adds a concurrent cold
start cover. 45 startup/application checks pass, including restored signed-out,
signed-in and recovery routes, early destination/reduced-motion bypass, no resume
replay, failure recovery and EN/PT at 200% text. Dev debug APK compilation passed. Final device checks and the integrated suite
remain pending at this checkpoint. PR #37 CI passed at 1d75bf8.

Launcher/welcome and Android push are separate new draft PRs, stacked as needed.
Firebase CLI 15.30.1 is installed locally; dedicated Spark project setup awaits
the owner's local Firebase login. No Firebase project or hosted push migration
has been created at this checkpoint. No billing, SMTP, Production, app data,
signing keys or existing backend content has changed.

Final packaging must use the existing `.dev` certificate and a versionCode above
every distributed APK (currently 3). Do not label push complete without actual
end-to-end delivery or distribute an unconfigured client. Keep all new PRs draft,
unmerged and with auto-merge disabled.

Device startup correction: the welcome owns its own sibling ProviderScope; the
initialized configured app is a separate root scope. This prevents ordinary
router/repository providers from inheriting an unconfigured welcome ancestor.
A delayed-initialization regression verifies the configured dependent provider
and mounted destination survive cover dismissal. The first integrated v4 QA
artifact exposed this bug and is withheld from sharing; use the corrected build.
