# Moving Blindensport Graz from CloudKit to Firebase — Implications

**Status:** analysis only (2026-09-29). Nothing has been changed.
**Context:** today every CloudKit record type is `GRANT READ TO "_world"` and every app install — even
anonymous — downloads all data, including the Benutzerverwaltung (SVNR, IBAN, birth date, last medical
examination) and every account's password hash. CloudKit cannot automatically restrict reading to "people
listed in the Benutzerverwaltung": its security roles are assigned manually per iCloud account in the
CloudKit Console. Firebase would enforce such rules on the server. This document lists everything that
moving to Firebase implies for this project.

---

## 1. Summary

| | |
|---|---|
| **What you gain** | Server-enforced access rules (Firestore Security Rules), automatic "member / admin" roles tied to the Benutzerverwaltung, built-in email/password login with proper hashing, email verification and password reset, real-time sync with offline queue, crash reporting (Crashlytics), a path to Android/web later |
| **What it costs** | Rewrite of the sync layer (~2,500 lines), all services that push to CloudKit, RootCLI (~2,000 lines, Swift has no official Firebase Admin SDK), push notifications (need Cloud Functions), a one-time data + account migration (all users must set a new password), a credit card on file (Blaze plan) |
| **Biggest blocker** | **Firebase Authentication stores and processes account data only in the United States.** For an Austrian club with sensitive member data this needs a legal assessment (see §8). |
| **Effort** | Roughly **4–7 weeks** of focused development plus on-device testing, in 8 phases (§12) |
| **Running cost** | Very likely **€0/month** at this club's size, but the Blaze (pay-as-you-go) plan is mandatory (§9) |

**Recommendation:** Firebase would solve the access-control problem properly, but the US-only
authentication, the RootCLI rewrite and the loss of the "no own infrastructure, no Google account" property
are significant. Before committing, compare with the two alternatives in §14 — **Supabase** (EU hosting,
same server-side rules model) and **CloudKit sharing** (stay on Apple, no third party).

---

## 2. Current architecture (what would be replaced)

| Area | Today (CloudKit) | Size |
|---|---|---|
| Sync | `Sync/CloudKit/` — 17 files; every sync is a full pull of every record type (`CloudKitSync.syncAll`) | ~1,700 lines |
| Offline / outbox | `PendingPush`, `SyncState`, `SyncOrchestrationService`, `NetworkMonitor`, `PushNotifications` | ~760 lines |
| Services | 19 `*Service` files call `CloudKitSync.push…` after local saves | ~740 lines |
| Other CloudKit references | 32 app files outside `Sync/` (services, models, backup, welcome content, …) | — |
| Local store | SwiftData, 17 `@Model` classes (incl. `SportEvent` → `Training`/`Tournament` inheritance) | — |
| Login | Own email/password (HMAC-SHA256, hashes synced via CloudKit, verified on device) + Sign in with Apple | — |
| Files | `EventImage`, `ExpenseReceipt` as CKAssets | — |
| Push | `CKQuerySubscription` alerts for new trainings/tournaments | — |
| Admin tooling | RootCLI: `rootcli` + `clubmembersapi` (Vapor REST + web UI, Docker + Caddy, **also serves the calendar feed**) via CloudKit Server-to-Server key | ~2,000 lines |
| Tests | 35 test files, 16 of them touch CloudKit types | — |
| Data | ~309 records in Production (2026-09-14) | — |

**Unaffected:** all SwiftUI screens (apart from login/registration), the design system, widget, share
extension, App Intents (they read the local store), invitation import, PRAE/KostZ/Sammelabrechnung/
Trainingsfrequenzliste exports.

---

## 3. Target architecture on Firebase

| Firebase product | Replaces | Notes |
|---|---|---|
| **Cloud Firestore** | CloudKit public database | Documents + collections, real-time listeners, offline cache and write queue built in |
| **Firebase Authentication** | Own password hashing, `UserIdentity` hashes | Email/password (server-side scrypt), Sign in with Apple, email verification, password reset, account deletion |
| **Security Rules** | Client-side checks (`AccessPolicy`, role checks in views) | Enforced by Google's servers on every read/write |
| **Custom claims** (`member`, `admin`, `coach`, `treasurer`) | `AppRole` stored in a world-readable record | Set only by server code; embedded in the user's token |
| **Cloud Functions** | — (new) | Keeps claims in sync with the Benutzerverwaltung; sends push notifications |
| **Cloud Storage** | CKAssets (photos, receipts) | Needs Storage Security Rules as well |
| **Cloud Messaging (FCM)** | `CKQuerySubscription` | Needs an APNs key uploaded to Firebase |
| **App Check (App Attest)** | "only apps signed by our team can reach the container" | Important: Firestore is reachable from the internet; App Check blocks requests that don't come from the genuine app |
| **Crashlytics** (optional) | Manual `devicectl` crash-log pulls | Would have saved hours on bug-352/371 |

**Local store:** keep SwiftData as the UI's data source and mirror Firestore listeners into it (same shape
as today's pull code, but incremental). This keeps ~150 view files unchanged. Dropping SwiftData and
binding views to Firestore directly is possible but touches every screen.

---

## 4. Access model (what Firebase makes possible)

| Tier | Who | May read | May write |
|---|---|---|---|
| **Public** | Not signed in | `schedule` (name, day, location, team, status of trainings/tournaments/events) | nothing |
| **Signed in, not listed** | Verified email, no Benutzerverwaltung match | `schedule`, own `users/{uid}`, own membership request | own profile, "Mitgliedschaft beantragen" |
| **Member** | Listed in the Benutzerverwaltung | + event details, teams, own attendance, own Benutzerverwaltung entry (without sensitive fields) | own attendance/participation |
| **Coach** | Member with coach role | + attendance/PRAE of their teams | events/trainings of their teams, attendance |
| **Treasurer** (optional) | Kassier | + budget, receipts, name/address/IBAN | budget, receipts |
| **Admin / root** | Vorstand | everything, incl. SVNR, IBAN, medical fields | everything |

This matches the data-protection authorities' **need-to-know** principle (board: all data; treasurer:
name/address/bank; trainer: own team only; ordinary members: no access to other members' data).

### How "listed in the Benutzerverwaltung" becomes automatic
1. A member registers with email + password → Firebase sends a **verification email**.
2. A Cloud Function (`onUserCreated` / on roster change) looks for a Benutzerverwaltung entry with that
   (lower-cased, **verified**) email and sets the custom claim `member: true` (or `coach`, `admin`).
3. When an admin adds or removes someone in the Benutzerverwaltung, the same function updates the claim.
4. Rules check the claim — no manual console work, unlike CloudKit security roles.

Without Cloud Functions, rules can instead look up a `memberIndex/{email}` document maintained by admins
(`exists(...)` in rules; costs one extra read per request and max. 10 lookups per rule evaluation).

⚠️ **Email verification is mandatory.** Without it, anyone could register with a member's email address
and be treated as that member. (The current app has the same gap — it never verifies emails.)

### Rules sketch
```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn()   { return request.auth != null; }
    function verified()   { return signedIn() && request.auth.token.email_verified == true; }
    function admin()      { return verified() && request.auth.token.admin == true; }
    function member()     { return verified() && (request.auth.token.member == true || admin()); }
    function coachOf(teamId) { return member() && teamId in request.auth.token.get('coachTeams', []); }

    // Public schedule: name, day, location, team, status only
    match /schedule/{id}      { allow read: if true;  allow write: if admin() || coachOf(request.resource.data.teamId); }

    // Full event data (notes, costs, …) and attendance
    match /events/{id} {
      allow read: if member();
      allow write: if admin() || coachOf(resource.data.teamId);
      match /attendance/{personId} {
        allow read: if admin() || coachOf(get(/databases/$(db)/documents/events/$(id)).data.teamId)
                    || personId == request.auth.uid;
        allow write: if admin() || coachOf(get(/databases/$(db)/documents/events/$(id)).data.teamId);
      }
    }

    // Benutzerverwaltung: ordinary fields vs. sensitive sub-document
    match /members/{id} {
      allow read: if admin() || (member() && resource.data.uid == request.auth.uid);
      allow write: if admin();
      match /sensitive/{doc} {           // svnr, iban, birthDate, lastMedicalExamination
        allow read, write: if admin();   // + treasurer for bank data if wanted
      }
    }

    match /users/{uid}        { allow read, write: if request.auth.uid == uid; allow read: if admin(); }
    match /budget/{id}        { allow read, write: if admin() || request.auth.token.treasurer == true; }
    match /roleChangeLog/{id} { allow read: if admin(); allow write: if false; }   // written by Functions only
    match /{document=**}      { allow read, write: if false; }                      // deny by default
  }
}
```
Rules can be unit-tested with the **Firebase Local Emulator Suite** on this Mac (Node-based, no iOS
Simulator needed) — a good fit for the project's no-simulator rule.

---

## 5. Data model changes

| CloudKit record type | Firestore | Change |
|---|---|---|
| `Training`, `Tournament`, `SportEvent` | `schedule/{id}` (public part) + `events/{id}` (details, `kind` field) | **Split** public vs. protected — Supabase and Firebase both recommend separate documents/tables over field-level hiding |
| `TrainingAttendance`, `TournamentAttendance` | `events/{id}/attendance/{personId}` | Sub-collection, so rules can use the event's team |
| `ClubMember` | `members/{id}` + `members/{id}/sensitive/data` | SVNR, IBAN, birth date, medical exam move to an admin-only sub-document |
| `UserIdentity` | Firebase Auth user + `users/{uid}` | **Password hash/salt disappear** from the database; role moves to custom claims |
| `Team`, `TeamMembership` | `teams/{id}`, `teams/{id}/members/{uid}` | |
| `BudgetEntry`, `ExpenseReceipt` | `budget/{id}` + Storage `receipts/…` | |
| `EventImage` | Storage `events/{id}/images/…` + metadata doc | |
| `RoleChangeLog` | `roleChangeLog/{id}` | Written by Cloud Functions only (tamper-proof) |
| `MemberChangeRequest`, `EventMembership`, `EventParticipation`, `TrainingFavorite`, `WelcomeContent` | own collections | |

SwiftData stays, so the `@Model` classes change little; relationships are rebuilt from document IDs.
The `SportEvent` → `Training`/`Tournament` inheritance can stay locally.

---

## 6. App changes

1. **Dependency:** Firebase iOS SDK via Swift Package Manager (FirebaseAuth, FirebaseFirestore,
   FirebaseStorage, FirebaseMessaging, FirebaseAppCheck, optionally FirebaseCrashlytics). First large
   third-party dependency besides ZIPFoundation; adds several MB to the app and build time. The SDK
   supports Swift 6 strict concurrency (Sendable work in 11.x/12.x releases).
2. **Configuration:** `GoogleService-Info.plist` (not secret, but project-specific) in the app target;
   APNs key + Sign-in-with-Apple Services ID/key registered in the Firebase console.
3. **Login/registration:** `LoginView`, `RegisterView`, `SetPasswordView` rewritten on Firebase Auth;
   `PasswordHashing.swift` removed; "Passwort vergessen" and email verification come for free. Sign in with
   Apple needs the Firebase nonce flow.
4. **Sync:** `CloudKitSync` + 17 extensions replaced by Firestore listeners that write into SwiftData;
   `PendingPush` outbox removed (Firestore queues offline writes itself); `SyncState`/`SyncStatusBanner`
   adapted to Firestore's pending-writes and connectivity state.
5. **Services:** the 19 `*Service` files write to Firestore instead of pushing CKRecords.
6. **Access tiers:** `AccessPolicy` reads the token's custom claims instead of matching the roster locally;
   the schedule-only UI (already built) stays.
7. **Push notifications:** replace `CKQuerySubscription` with FCM; a Cloud Function sends "Neues Training"
   / "Training abgesagt" to the team's topic.
8. **Files:** photos/receipts upload to Cloud Storage with their own rules.
9. **Full backup/restore** (`FullBackup`, `FullBackupImporter`) re-targeted to Firestore.
10. **Tests:** 16 CloudKit-dependent test files rewritten; rules tests added (Emulator Suite).
11. **Privacy manifest / App Store privacy labels** updated (Firebase collects IP, user agent, device
    tokens; Crashlytics collects crash data).

---

## 7. RootCLI / clubmembersapi / web UI

- The **Firebase Admin SDK has no official Swift version** (official: Node.js, Java, Python, Go, C#).
  Options: (a) rewrite RootCLI + `clubmembersapi` + web UI in **Node.js/TypeScript** (same language as
  Cloud Functions — recommended), (b) keep Swift and call the Firestore/Identity Toolkit **REST APIs** with
  a service account (more code to maintain), (c) a community Swift package (maintenance risk).
- The **calendar feed** (`CalendarFeedRoutes`, per-user `calendarToken`) must move too — either into this
  server or into an HTTPS Cloud Function.
- Much of RootCLI's admin purpose (roster import/export, CSV) could move into Cloud Functions or the app
  itself once admins have server-enforced write access.
- The Docker/Caddy deployment stays only if a self-hosted admin UI is still wanted.

---

## 8. Data protection (GDPR / DSGVO)

| Topic | Implication |
|---|---|
| **Authentication location** | Google states: *"The Firebase Authentication service is run only from US data centers."* Email addresses, (hashed) passwords, IP addresses and user agents of all members are processed in the US. Legal basis: Google's Data Processing and Security Terms, EU Standard Contractual Clauses and the EU-US Data Privacy Framework. EU-only Firebase Auth is announced but not generally available. |
| **Database / files / functions** | Can be placed in the EU (Firestore `eur3` or `europe-west3` Frankfurt, Storage and Functions in `europe-west3`). **The Firestore location cannot be changed later.** |
| **Processor agreement** | Accept Firebase's Data Processing and Security Terms in the console; Google is processor, the club is controller. |
| **Privacy policy / records of processing** | Update the club's privacy policy and Verzeichnis der Verarbeitungstätigkeiten (new processor: Google; transfer to the US). A transfer impact assessment is advisable. |
| **Special-category data** | `lastMedicalExamination` is health data (Art. 9 GDPR) → explicit written consent, admin-only access. SVNR and IBAN only where the club needs them (e.g. PRAE forms), admin/treasurer only. |
| **Data subject rights** | Account deletion must delete the Auth user *and* Firestore/Storage data (a Cloud Function or the "Delete User Data" extension). |
| **Improvement vs. today** | Password hashes and SVNR/IBAN would no longer be on every phone — a large reduction in exposure regardless of the US question. |

---

## 9. Costs

- **Blaze (pay-as-you-go) plan is required** as soon as Cloud Storage or Cloud Functions are used
  (Storage has required a billing account since 2 Feb 2026, even inside the free tier).
- At this club's size (tens of members, a few hundred documents, photos/receipts) usage stays inside the
  free quotas (Firestore: 1 GiB, 50k reads/day, 20k writes/day; Storage: 5 GB-months; Functions: 2M
  invocations/month) → expected **€0/month**. Set a **budget alert** (e.g. €5) in Google Cloud.
- Real-time listeners replace full pulls, so reads are lower than today's "download everything on every
  launch".
- Someone in the club must own the Google Cloud billing account (a credit card is needed).

---

## 10. Migration of existing data and accounts

1. **Data:** a one-off script (RootCLI S2S export → Node import) copies all ~309 records from CloudKit
   Production into Firestore, splitting schedule/details and moving sensitive roster fields to the
   admin-only sub-documents; photos/receipts go to Storage.
2. **Password accounts cannot be carried over.** Firebase can import HMAC-SHA256 hashes only with **one
   project-wide HMAC key**, but this app uses each user's salt *as* the HMAC key. Options:
   - **Recommended:** import accounts by email only and send every member a "Passwort festlegen" email
     (Firebase password-reset link) — also verifies their email in one step.
   - Alternative: a temporary legacy-login path that verifies the old hash once and then creates the
     Firebase account — more code, keeps the old hashes around longer.
3. **Sign in with Apple accounts** can sign in again; Firebase links them by the same Apple ID when the
   same bundle/Services ID is used.
4. **Cutover:** release a version that reads/writes only Firebase; older app versions must be told to
   update (TestFlight testers only, so manageable). Keep CloudKit read-only for a few weeks as fallback,
   then remove the data and CloudKit entitlement.

---

## 11. Security considerations specific to Firebase

- Firestore is reachable over the internet with the (public) API key. **Security Rules are the only
  protection** → deny-by-default rules, rules unit tests, and **App Check with App Attest** (start in
  monitoring mode, enforce after a week).
- Custom claims are only writable by server code (Functions/Admin SDK) — never trust role fields the
  client writes.
- The service-account key used by RootCLI/Functions is a full-access credential — store it as a secret,
  never in the repo.
- Rules cannot hide individual fields of a document → the schedule/details and members/sensitive
  **splits are required**, not optional.

---

## 12. Suggested phases and effort

| Phase | Work | Estimate |
|---|---|---|
| 0 | Decision, Firebase project (EU region), Blaze + budget alert, legal check of US auth | 1–2 days (+ club decision) |
| 1 | Firebase Auth: login, registration, email verification, password reset, Sign in with Apple; custom-claims Function | 4–6 days |
| 2 | Firestore data model + Security Rules + rules tests in the Emulator Suite | 4–6 days |
| 3 | Read path: listeners → SwiftData for all collections; access tiers from claims | 5–8 days |
| 4 | Write path: services → Firestore; remove `PendingPush` outbox; sync banner | 4–6 days |
| 5 | Storage for photos/receipts; FCM push via Functions; App Check; Crashlytics | 3–5 days |
| 6 | RootCLI/clubmembersapi/calendar feed port (Node.js recommended) | 4–7 days |
| 7 | Migration script, password-set emails, TestFlight cutover, CloudKit fallback period | 3–5 days |
| 8 | Remove CloudKit code, entitlements, CKSchema; update tests/docs | 1–2 days |
| | **Total** | **≈ 4–7 weeks** (plus on-device testing time) |

---

## 13. What you lose by leaving CloudKit

- **No third party:** today all data stays with Apple and needs no Google account or credit card.
- **Implicit app-only access:** CloudKit containers can only be queried by apps signed by this team (or
  team-issued keys); Firestore relies on rules + App Check instead.
- **Existing tooling and know-how:** CloudKit Console, `cktool`, the RootCLI S2S client, the recorded
  CloudKit learnings in `.wolf/cerebrum.md`.
- **iCloud-based identity** — not used for login today, so little is lost here.

---

## 14. Alternatives to compare before deciding

| | Firebase | Supabase | CloudKit sharing (CKShare) |
|---|---|---|---|
| Server-enforced "members only" | ✅ Rules + claims | ✅ Postgres Row-Level Security | ✅ Share participants |
| Automatic membership from the Benutzerverwaltung | ✅ via Cloud Function | ✅ via SQL policy/trigger | ✅ app adds participant by email (member accepts invitation) |
| **Where account data lives** | **US only (Auth)** | EU region selectable; also self-hostable | Apple (iCloud) |
| Third party / account / card | Google, Blaze plan | Supabase (or self-hosted), paid plan for production | none |
| Official Swift SDK (app) | ✅ | ✅ `supabase-swift` | ✅ native |
| Server/admin tooling in Swift | ❌ (REST or Node) | ✅ REST/Postgres, any language | ❌ S2S works only on the public DB |
| Public schedule for anonymous users | ✅ | ✅ | ✅ keep in public DB |
| Members need | email + password | email + password | an iCloud account + accept an invitation |
| Rewrite size | large | large | medium–large (protected data only) |

For this club, **Supabase (EU)** removes the US-authentication question while offering the same
server-rules model, and **CloudKit sharing** avoids any third party. Firebase is the most mature and
best-documented of the three, with the best mobile tooling (Crashlytics, App Check, FCM).

---

## 15. Open questions for the club

1. Is processing members' login data (email, IP) in the US acceptable for the Vorstand / data-protection
   contact?
2. Who owns the Google Cloud billing account?
3. Should RootCLI's web UI and calendar feed survive, or move into the app / Cloud Functions?
4. Which functions need which data (treasurer, coaches)? Are SVNR, IBAN and the medical-exam date really
   needed, and is there written consent for the medical field?
5. Is an Android or web version planned? (Strong argument for Firebase or Supabase over CloudKit.)

---

## Sources

- [Firebase: Privacy and Security (Authentication is US-only; EU locations for Firestore/Storage/Functions; DPA, SCCs, DPF)](https://firebase.google.com/support/privacy)
- [Firebase Data Processing and Security Terms](https://firebase.google.com/terms/data-processing-terms/20230601)
- [Firebase Authentication for EU (feature request)](https://firebase.uservoice.com/forums/948424-general/suggestions/46591651-firebase-authentication-for-eu)
- [Firebase: Default bucket and billing requirements for Cloud Storage](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
- [Firestore pricing](https://cloud.google.com/firestore/pricing)
- [Firebase: Control Access with Custom Claims and Security Rules](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Firebase: Security Rules and Firebase Authentication](https://firebase.google.com/docs/rules/rules-and-auth)
- [Firebase: Fix insecure rules](https://firebase.google.com/docs/firestore/security/insecure-rules)
- [Firebase: Import Users (hash algorithms incl. HMAC_SHA256)](https://firebase.google.com/docs/auth/admin/import-users)
- [Firebase CLI: auth:import and auth:export](https://firebase.google.com/docs/cli/auth-import)
- [Firebase Admin SDK reference (supported languages)](https://firebase.google.com/docs/reference/admin)
- [Firestore client libraries](https://cloud.google.com/firestore/docs/reference/libraries)
- [Firebase App Check](https://firebase.google.com/docs/app-check)
- [Firebase Apple SDK release notes (Swift 6 / Sendable work)](https://firebase.google.com/support/release-notes/ios)
- [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase: Column Level Security (recommends separate tables/RLS instead)](https://supabase.com/docs/guides/database/postgres/column-level-security)
- [Apple: sample-cloudkit-zonesharing](https://github.com/apple/sample-cloudkit-zonesharing)
- [LfDI Baden-Württemberg: Orientierungshilfe Datenschutz im Verein](https://www.baden-wuerttemberg.datenschutz.de/orientierungshilfe-datenschutz-verein/)
- [Dr. Datenschutz: Datenschutz der Mitgliederlisten](https://www.dr-datenschutz.de/konflikt-im-verein-datenschutz-der-mitgliederlisten/)
