# Qwallet Scan: a counter app for staff

## Problem

Stamping a customer's card means opening a browser, signing in to the
dashboard, and finding the scan page — on a phone, at a till, with a queue.
The web scanner works, but it is a page inside an admin dashboard, and it
carries the whole dashboard's navigation to get to the one thing counter staff
ever do.

It also only really serves reward cards. `/dashboard/scan` looks up a card and
offers stamps, banking and redemption; a points or membership card scanned
there has no action behind it, even though the API has had `POST
/api/passes/points/:cardId` and `POST /api/passes/membership/:cardId` all along.

Three screens are wanted: sign in, scan, and what has been scanned.

## Goals

- A staff member signs in once and stays signed in for the life of the token.
- Scanning a card takes one tap from opening the app, and the action for that
  card — stamp, add points, renew membership — is on the screen that follows.
- Every card type the API supports has an action here. Nothing scans to a dead
  end.
- The scan log answers "what has this shop done today" without leaving the app.
- No API changes. Everything this app needs already exists and is already
  role-gated.

## Non-goals

- **Offline scanning.** A scan that cannot reach the server fails and says so.
  Queueing means local storage, a sync engine, and an answer for a reward
  redeemed on another device while this one was offline — which is a larger app
  than this one. Revisit if staff report the wifi actually dropping.
- **Anything the dashboard does.** No customer list, no card creation, no
  template editing, no analytics, no billing. A staff member who needs those
  uses the web dashboard.
- **Push notifications.** The API pushes to customers' wallets, not to staff.
- **Card creation at the counter.** A customer enrols through the public signup
  page on their own phone. Adding it here would need the whole dynamic field
  form the signup page has.
- **Deleting or editing scan-log rows.** The log is an audit trail.

## Toolchain

Pinned by `.fvmrc`, driven with `fvm flutter …` throughout:

```
Flutter 3.44.8 (stable)   Dart 3.12.2   fvm 4.1.2
```

| Package | Version | Role |
| --- | --- | --- |
| `flutter_riverpod` | ^3.4.3 | state, and the seam tests inject fakes through |
| `go_router` | ^18.0.1 | routing, and the redirect that guards on auth state |
| `mobile_scanner` | ^7.4.0 | camera + barcode decoding, MLKit-backed |
| `flutter_secure_storage` | ^11.0.0 | the token, in Keychain / Keystore |
| `http` | ^1.6.0 | transport under a hand-written client |

Riverpod 3, not 2. `Ref` is unified — write `Ref`, never `Ref<T>`. The
`AutoDisposeNotifier` / `AutoDisposeRef` interfaces are gone; a provider opts
into disposal with `NotifierProvider.autoDispose`, and providers are kept alive
by default. An error rethrown out of `ref.watch` arrives wrapped in a
`ProviderException`.

### Why these

**Riverpod over Bloc.** The scan screen genuinely is a state machine, which
argues for Bloc, but three screens do not carry Bloc's boilerplate. What decides
it is testing: `ProviderScope(overrides:)` swaps a fake `ApiClient` in with one
line, so every notifier is testable with no widget tree.

**`http` with a hand-written client over Dio.** Dio earns its place through
interceptors. This app needs exactly two behaviours — attach the bearer token,
and turn a 401 into a sign-out — which is a small class we own and can fake
without a mocking library.

**Hand-written `fromJson` over freezed / json_serializable.** Five models do not
justify a `build_runner` watch loop in every session. The parsers are where
null-handling bugs hide, so they get direct unit tests either way.

**`mobile_scanner` over `qr_code_scanner`.** The latter is unmaintained.

## What it talks to

No new endpoints. Every call below exists today and already accepts the roles
this app signs in.

### Sign-in

`POST /api/auth/login` with `{ identifier, password }` → `{ token, user: { id,
email, name, role, businessIds } }`.

One endpoint for both audiences. The route matches on `email OR mobile` with no
role filter (`src/routes/auth.js`), and staff created by an owner are inserted
`email_verified = true` (`src/routes/business.js`), so they clear the
verification gate that would otherwise reject them. `/api/auth/staff-login`
exists but adds only a role filter and a `staffRole` field this app has no use
for.

The token is a 7-day JWT. There is no refresh endpoint, so expiry means signing
in again — see Errors.

### Reading a card

`GET /api/passes/:cardId?businessId=…` returns the card, its `templateType`,
and a `merchantData` block. The fields this app reads:

```
cardId, userName, userEmail, userPhone, templateType,
stampCount, rewardsAvailable,
pointsBalance, pointsExpiry,
membershipNumber, membershipCategory, membershipExpiry,
merchantData.businessName, merchantData.rewardDescription,
merchantData.stampsRequired
```

### Acting on a card

All five take `businessId` in the body and are gated
`requireRole('admin','business','staff')`.

| Action | Call | Returns |
| --- | --- | --- |
| Add stamps | `POST /api/passes/:cardId/stamp` `{ businessId, increment }` | `{ cardId, stampCount, stampsRequired, rewardsAvailable }` |
| Add to Rewards | `POST /api/passes/:cardId/add-reward` `{ businessId }` | same shape |
| Redeem a reward | `POST /api/passes/:cardId/redeem` `{ businessId }` | same shape |
| Points | `POST /api/passes/points/:cardId` `{ businessId, points }` | `{ success, pointsBalance, pointsExpiry }` |
| Membership | `POST /api/passes/membership/:cardId` `{ businessId, expiryMonths }` | `{ success, membershipNumber, membershipCategory, membershipExpiry }` |

`points` takes a signed number: positive adds, negative deducts. The API
rejects a mismatched card type with a 400 whose message is already customer-
facing ("This card is not a points-type card").

### The log

`GET /api/passes/scan-log?businessId=…&limit=…&cursor=…` returns
`{ scanLog: [...], hasMore, nextCursor }`, newest first. Each row carries
`type` (`stamp` or `redemption`), `cardId`, `staffName`, `customerName`,
`customerEmail`, `stampsAdded`, `stampsBefore`, `stampsAfter`, `loggedAt`.
`nextCursor` is the last row's `loggedAt`; pass it back to page.

## Screens

### Sign in

Identifier and password, with the identifier labelled to say either an email or
a mobile number works — the API accepts both and a staff member issued only a
mobile has no other way in.

Three outcomes beyond success. A `role` of `customer` is refused with "This app
is for staff" rather than a blank scan screen. An empty `businessIds` means the
account exists but is linked to no business, which is a real state after an
owner removes a staff member from their last shop; it says so. Both are checked
before the token is stored, so a refused sign-in leaves nothing behind.

### Business selection

The token carries `businessIds`. One business is selected silently. More than
one gets a picker, since every single call in this app requires a `businessId`
and there is no defensible default. The choice is stored beside the token and
changeable from the log screen.

Names come from `GET /api/business/:businessId`. If that call fails the picker
still lists the ids, because being unable to read a name must not lock a staff
member out of scanning.

### Scan

Camera fills the screen, with manual card-id entry under it — the web scanner
has the same fallback and it is not decorative: a scratched phone screen, a
denied camera permission, or a customer whose battery died all end with staff
typing the id off the card.

The payload is either a JSON object with a `cardId`, or a bare alphanumeric id.
Both shapes are what the wallet passes actually carry, and `/dashboard/scan`
already accepts both; the parser is shared logic worth its own tests.

On a decoded id: `GET /api/passes/:cardId`, then a result screen chosen by
`templateType`.

- **reward** — name, stamp count against `stampsRequired`, the reward
  description, and the number of rewards waiting. Three actions, named as the
  dashboard names them so staff moving between the two are not learning a
  second vocabulary:
  - **Add Stamps**, with a +/− increment, for the ordinary case.
  - **Add to Rewards** (`/add-reward`) — converts a completed card into a
    banked reward, which is what the customer is owed at that moment even if
    they are not claiming it today.
  - **Redeem** (`/redeem`) — the customer actually taking the free coffee.
    Asks for confirmation first: it is the only action here that takes
    something away, and the API has no undo.

  **Neither of the last two is disabled by a locally computed rule, and this is
  deliberate.** Both conditions look simple and are not:

  - Add to Rewards is not "`stampCount >= stampsRequired`". On a multi-milestone
    card the threshold is the *cumulative* total of every rung up to the current
    one, and only the last rung clears the stamps
    (`src/cardTypes/reward.js`). The two inputs needed to compute that —
    `rewardMilestones` and `currentMilestoneIndex` — are not in what
    `GET /api/passes/:cardId` returns. The app cannot get the threshold right,
    so it must not pretend to know it.
  - Redeem is not "`rewardsAvailable > 0`". The API also allows redeeming
    straight off a completed card without banking first, so a card sitting at
    10/10 with zero banked rewards is legitimately redeemable — and a button
    disabled on `rewardsAvailable == 0` would refuse a customer the shop owes a
    coffee.

  So both stay tappable, and the server decides. Its refusals are already
  precise and readable — "Stamps not yet complete (7/10)" — and the screen shows
  them inline. Duplicating milestone arithmetic in a second codebase, from
  inputs that do not reach it, is how the two drift apart and a customer gets
  told the wrong thing at a counter.
- **points** — name, balance, expiry if set. An amount field with Add and
  Deduct, which post a positive and a negative `points`.
- **membership** — name, number, category, expiry. Renew by a number of months.

Scanning is suppressed while a lookup or an action is in flight, so a camera
that re-reads the same code four times a second cannot fire four stamps. This is
the one concurrency bug this app can actually cause and it is a customer-visible
one, so it gets a test.

After a successful action the screen shows the new state and a Scan next
button. It does not auto-return: a staff member needs to see that the stamp
landed.

### Scan log

The business's stamps and redemptions, newest first, grouped by day, infinite
scroll on `nextCursor`, pull to refresh. Each row: what happened, the customer,
the staff member, the stamp movement, the time.

Two states worth designing rather than defaulting: nothing scanned yet, which
says so rather than showing an empty list, and a failed load, which offers
retry rather than an empty list that looks like no activity.

## Errors

One place decides, so the three screens do not each invent an answer.

| What happened | What the app does |
| --- | --- |
| 401 | Clears the token, returns to sign-in, says the session expired. There is no refresh endpoint. |
| 403 | "You don't have access to this business." Reachable if a staff member is unlinked while signed in. |
| 404 on a scan | "No card found for this code." |
| 400 | Shows the server's own message — they are already written for customers. |
| 409 | Shows the server's message; only membership numbers produce it. |
| 5xx | "Something went wrong at our end." Retry offered. |
| No connection | "Can't reach the server." Retry offered. Never silently swallowed — a stamp that did not happen must not look like one that did. |

An action's success is whatever the server returned, never a locally
incremented guess. The response carries the new count; the screen shows that.

## Testing

`flutter_test` only. No integration tests against the live API — there is no
scratch environment for it, and the API's own suite covers those endpoints.

- **Unit.** The QR payload parser, including the shapes it must reject. Every
  `fromJson`, including the nulls the API really sends (`pointsExpiry`,
  `membershipExpiry`, `userPhone`). `ApiClient` error mapping, one case per row
  of the table above.
- **Notifiers.** Each against a fake `ApiClient` injected by
  `ProviderScope(overrides:)`. The scan notifier's re-entrancy guard is a named
  test: a second scan arriving mid-flight must not fire a second action.
- **Widget.** The three result screens against the three card types. On the
  reward screen specifically: that Add to Rewards and Redeem are both tappable
  regardless of the local counts (the rule above, as an executable statement of
  it), that a 400 from either renders the server's message inline rather than as
  a crash or a toast that scrolls away, and the confirmation gate in front of
  Redeem. The log's empty and error states. Sign-in's three refusals.

## Known limitations

- **Points and membership actions do not appear in the scan log.** Only
  `/stamp` writes `scan_log` and only `/redeem` writes `redemption_log`; the
  points, membership and add-reward endpoints write no audit row at all. Staff
  will see stamps and redemptions in this app's log and nothing else. Fixing it
  is an API change and is deliberately out of scope here — but it means the log
  is not a complete record of what this app can do, and staff should not be told
  it is.
- **A 7-day token with no refresh** means a weekly sign-in. Acceptable for a
  device that lives on a counter; irritating if it turns out staff share a phone
  and sign in and out.
- **No card-type upgrade path.** A card whose `templateType` the app does not
  recognise shows "This card type isn't supported in this app" — correct today,
  since the three types are the whole registry, but it is what a fourth type
  would hit.
- **Business names are best-effort.** If `GET /api/business/:businessId` fails,
  the picker shows ids.
- **The reward screen cannot preview whether an action will succeed**, because
  `GET /api/passes/:cardId` returns neither `rewardMilestones` nor
  `currentMilestoneIndex`. Staff on a multi-milestone card learn a reward is not
  ready by pressing the button and reading the refusal. Adding those two fields
  to the card payload would let the screen say so up front; it is an API change
  and out of scope here.
