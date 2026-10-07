# Multi-Service Card (Scan App) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let staff stamp, bank and redeem each service of a multi-service card from the Qwallet Scanner app, with a service picker that starts with nothing selected.

**Architecture:**
- **Data.** The card model gains a list of services. The three reward actions on the API client, the fake client and the scan notifier gain an optional `serviceId`. A response's `services` replace the card's.
- **Shared controls.** The body of `RewardActions` becomes a shared `StampControls` widget. It is driven by a `StampTarget`, which describes either a whole reward card or one service.
- **Multi-service screen.** `RewardActions` keeps rendering exactly as today. A new `MultiServiceActions` shows both services' progress, then a picker, then `StampControls` for the chosen service.

**Tech Stack:** Flutter 3.44.8 (through `fvm`), Dart 3, flutter_riverpod 3, go_router, http, flutter_test.

**Spec:** `loyalty-pass-api/docs/superpowers/specs/2026-10-07-multi-service-card-design.md` §4 "Scan app" (on API `main`). API contract: the "Multi-service cards" section of `loyalty-pass-api/API_DOCUMENTATION.md`.

This is plan 3 of 3. The API (plan 1) and the dashboard (plan 2) are merged and deployed.

## Global Constraints

- **Branch and Flutter:** branch `feat/multi-service-card` from `master` (`3af9820`). Work in the worktree `loyalty-scan-app/.claude/worktrees/multi-service-card`. Use `fvm flutter …`, never plain `flutter` (3.38.3 is too old).
- **Card type:** `multi_service`. Each card has exactly 2 services, each with `id` (`s1`/`s2`) and `name`.
- **API:**
  - `POST /api/passes/:cardId/stamp`, `/add-reward` and `/redeem` take `serviceId` in the body. It is required on multi-service cards and refused (400) on any other card.
  - `increment` is an integer from 1 to 100.
  - A multi-service action responds `{ cardId, serviceId, stampCount, rewardsAvailable, services }`, where `stampCount` and `rewardsAvailable` are totals across services.
  - `GET /api/passes/:cardId` returns `services: [{ id, name, stampCount, stampsRequired, rewardsAvailable, stampsUntilReward, currentReward: { description, label }, rewardMilestones: [...] }]`, which is empty for other types.
  - A concurrent update returns 409 with `{ error }`, shown like any other refusal.
- **Picker:** nothing is selected at first. Action controls appear only after staff pick a service.
- **Labels and messages** name the service:
  - Buttons: `Add <name> Stamps`, `Add to <name> Rewards`, `Redeem <name> Reward`.
  - Redeem confirmation title: `Redeem a <name> reward?`
  - Snackbars: `<name> stamped. <n> of <m>.`, `<name> reward banked. <n> waiting.`, `<name> reward redeemed. <n> left.`
- **Repeat-action warning:** it applies per service. Its key is `<cardId>:<serviceId>`, so stamping one service never warns about the other.
- **Increment cap per service:** `remaining = stampsRequired - stampCount`. The cap is `remaining > 0 ? remaining : stampsRequired`, and at most 100. Past the end of the cycle the API resets the count, and a ladder service drops the overflow; the dashboard review found this. Reward cards keep their current, uncapped behaviour; that is out of scope here.
- **Reward, points and membership screens behave exactly as today.** `test/widget/reward_actions_test.dart` must pass unchanged.
- **Baseline:** 123 tests pass. Every task ends with `fvm flutter test` and `fvm flutter analyze` both clean.
- **Commits:** every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Do not push. Releasing to the stores is the user's call.

## Review Focus

1. **Staff tap a service, stamp, and come back for the other one within a minute.** No "Already done" warning, because the warning is per service. Stamping the same service twice still warns. (Task 4)
2. **A service near the end of its cycle.** For example, Blowdry at 4 of 5. `+` stops at 1, so a stamp can never be lost to overflow. (Task 4)
3. **An older card response without `services`, or a reward card.** `services` is empty, the model never crashes, and the card still routes to its own screen. (Task 1)
4. **Numbers arriving as strings, which node-postgres does for BIGINT.** Service counts still parse. (Task 1)
5. **The server refuses a service action, with a 409 or 400.** The card stays on screen with the API's message, the picked service stays picked, and nothing is recorded as done. (Task 4)

---

### Task 0: Worktree setup and baseline

**Files:** none changed.

- [ ] **Step 1: Confirm the worktree and toolchain**

```bash
cd /Users/aihdeveloper/Desktop/Learn/Loyalty/loyalty-scan-app/.claude/worktrees/multi-service-card
git branch --show-current          # feat/multi-service-card
fvm flutter --version | head -1    # Flutter 3.44.8
fvm flutter pub get
```

- [ ] **Step 2: Baseline**

```bash
fvm flutter test 2>&1 | tail -1     # All tests passed! (123)
fvm flutter analyze 2>&1 | tail -1  # No issues found!
```

Record the counts. Later tasks must not reduce them.

---

### Task 1: Services on the card model, the API client and the fake

**Files:**
- Modify: `lib/api/models/loyalty_card.dart`
- Modify: `lib/api/api_client.dart` (the `addStamps`, `addToRewards` and `redeem` signatures and their bodies)
- Modify: `test/support/fake_api_client.dart`
- Create: `test/support/multi_service_fixtures.dart`
- Test: `test/api/models_test.dart`, `test/api/http_api_client_test.dart`

**Interfaces:**
- Produces:
  - `class CardService { id, name, stampCount, stampsRequired, rewardsAvailable, stampsUntilReward, rewardDescription, isLadder }` with `CardService.fromJson(Map)` and `CardService.missing(String id)`
  - `LoyaltyCard.services` (`List<CardService>`, defaults to `const []`)
  - `LoyaltyCard.withServiceState({required List<CardService> services, required int stampCount, required int rewardsAvailable})`
  - `CardActionResult.services` (`List<CardService>`, defaults to `const []`)
  - `ApiClient.addStamps(…, String? serviceId)`, `addToRewards(…, String? serviceId)`, `redeem(…, String? serviceId)`, with `serviceId` sent only when non-null
  - `FakeApiClient` records `'addStamps:<n>'`, or `'addStamps:<n>@<serviceId>'` when a service is given. `addToRewards` and `redeem` follow the same pattern.
  - Test fixtures: `service(id, name, count, required, {rewards, ladder})` and `multiCard({services})`

- [ ] **Step 1: Write the failing tests**

Append to `test/api/models_test.dart`, inside `main()`:

```dart
  group('LoyaltyCard services', () {
    test('reads each service of a multi-service card', () {
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"MSC1234567","businessId":"biz-1","templateType":"multi_service",
         "stampCount":3,"rewardsAvailable":1,"merchantData":{"stampsRequired":0},
         "services":[
           {"id":"s1","name":"Mani/Pedi","stampCount":2,"stampsRequired":5,
            "rewardsAvailable":1,"stampsUntilReward":3,
            "currentReward":{"description":"Free mani/pedi","label":null},
            "rewardMilestones":[]},
           {"id":"s2","name":"Blowdry","stampCount":"1","stampsRequired":"6",
            "rewardsAvailable":0,"stampsUntilReward":2,
            "currentReward":{"description":"20% off","label":null},
            "rewardMilestones":[
              {"stampsRequired":3,"rewardDescription":"20% off","rewardLabel":null},
              {"stampsRequired":3,"rewardDescription":"Free","rewardLabel":null}]}
         ]}
      '''),
      );

      expect(card.services.map((s) => s.id), ['s1', 's2']);
      expect(card.services[0].name, 'Mani/Pedi');
      expect(card.services[0].rewardsAvailable, 1);
      expect(card.services[0].rewardDescription, 'Free mani/pedi');
      expect(card.services[0].isLadder, isFalse);
      // Counts that arrive as strings still read (node-postgres BIGINT).
      expect(card.services[1].stampCount, 1);
      expect(card.services[1].stampsRequired, 6);
      expect(card.services[1].isLadder, isTrue);
      expect(card.services[1].stampsUntilReward, 2);
    });

    test('a reward card, or an older response, has no services', () {
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"ABC1234567","businessId":"biz-1","templateType":"reward",
         "stampCount":3,"rewardsAvailable":0,"merchantData":{"stampsRequired":10}}
      '''),
      );
      expect(card.services, isEmpty);
    });

    test('an action result carries services when the API sends them', () {
      final withServices = CardActionResult.fromJson({
        'stampCount': 5,
        'rewardsAvailable': 1,
        'services': [
          {'id': 's1', 'name': 'Mani/Pedi', 'stampCount': 4, 'stampsRequired': 5,
           'rewardsAvailable': 1, 'stampsUntilReward': 1,
           'currentReward': {'description': 'Free', 'label': null}, 'rewardMilestones': []},
        ],
      });
      expect(withServices.services.single.stampCount, 4);

      final without = CardActionResult.fromJson({
        'stampCount': 4, 'stampsRequired': 10, 'rewardsAvailable': 0,
      });
      expect(without.services, isEmpty);
    });

    test('withServiceState replaces services and totals, keeping the customer', () {
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"MSC1234567","businessId":"biz-1","templateType":"multi_service",
         "userName":"Mithayel","stampCount":3,"rewardsAvailable":1,"services":[]}
      '''),
      );
      final next = card.withServiceState(
        services: [CardService.missing('s1')],
        stampCount: 7,
        rewardsAvailable: 2,
      );
      expect(next.userName, 'Mithayel');
      expect(next.templateType, 'multi_service');
      expect(next.stampCount, 7);
      expect(next.rewardsAvailable, 2);
      expect(next.services.single.id, 's1');
    });
  });
```

Append to `test/api/http_api_client_test.dart`, inside the `HttpApiClient` group, after the existing `addStamps` test:

```dart
    test('service actions send the serviceId, and only when given', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(
          200,
          jsonEncode({
            'cardId': 'MSC1234567',
            'serviceId': 's1',
            'stampCount': 4,
            'rewardsAvailable': 0,
            'services': [],
          }),
          capture: sent,
        ),
      );

      await client.addStamps(
        cardId: 'MSC1234567', businessId: 'biz-1', increment: 2, serviceId: 's1');
      await client.addToRewards(
        cardId: 'MSC1234567', businessId: 'biz-1', serviceId: 's1');
      await client.redeem(
        cardId: 'MSC1234567', businessId: 'biz-1', serviceId: 's2');
      await client.redeem(cardId: 'MSC1234567', businessId: 'biz-1');

      expect(sent.map((r) => jsonDecode(r.body)).toList(), [
        {'businessId': 'biz-1', 'increment': 2, 'serviceId': 's1'},
        {'businessId': 'biz-1', 'serviceId': 's1'},
        {'businessId': 'biz-1', 'serviceId': 's2'},
        {'businessId': 'biz-1'},
      ]);
    });
```

- [ ] **Step 2: Run them to see them fail**

Run: `fvm flutter test test/api`
Expected: compile errors, because `services`, `CardService`, `withServiceState` and the `serviceId:` parameter are undefined.

- [ ] **Step 3: Extend the model**

In `lib/api/models/loyalty_card.dart`:

1. Add `this.services = const [],` as the last constructor parameter of `LoyaltyCard`.
2. Add the field after `membershipExpiry`:

```dart
  /// A multi-service card's services, in the API's order (s1, s2). Empty for
  /// every other card type, and for responses from before services existed.
  final List<CardService> services;
```

3. In each of `withRewardState`, `withPointsState` and `withMembershipState`, pass `services: services,` as the last argument, so no copy drops them.
4. Add this copy method after `withMembershipState`:

```dart
  /// A copy carrying what a service action returned: every service's counts,
  /// and the card totals the server recomputed. The server owns all of them.
  LoyaltyCard withServiceState({
    required List<CardService> services,
    required int stampCount,
    required int rewardsAvailable,
  }) => LoyaltyCard(
    cardId: cardId,
    businessId: businessId,
    userName: userName,
    userEmail: userEmail,
    userPhone: userPhone,
    templateType: templateType,
    stampCount: stampCount,
    rewardsAvailable: rewardsAvailable,
    stampsRequired: stampsRequired,
    rewardDescription: rewardDescription,
    businessName: businessName,
    pointsBalance: pointsBalance,
    pointsExpiry: pointsExpiry,
    membershipNumber: membershipNumber,
    membershipCategory: membershipCategory,
    membershipExpiry: membershipExpiry,
    services: services,
  );
```

5. In `LoyaltyCard.fromJson`, add this as the last argument:

```dart
      services: _services(json['services']),
```

6. Give `CardActionResult` a `this.services = const []` constructor parameter and a `final List<CardService> services;` field. In its `fromJson`, add `services: _services(json['services']),`.

7. Add the class and helper near the bottom, above `_int`:

```dart
/// One service of a multi-service card, as the API's serviceApiShape sends it.
/// Counts are this service's own; the card's stampCount is the total.
class CardService {
  const CardService({
    required this.id,
    required this.name,
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
    required this.stampsUntilReward,
    required this.rewardDescription,
    required this.isLadder,
  });

  final String id;
  final String name;
  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;

  /// Stamps to the next reward — the next rung on a ladder.
  final int stampsUntilReward;

  /// The reward currently on offer: the next rung's on a ladder.
  final String rewardDescription;

  /// A reward ladder banks each rung by itself as stamps land, so there is no
  /// full row waiting to be banked by hand.
  final bool isLadder;

  /// Stands in for a service the card no longer lists, so a stale selection
  /// renders zeros instead of throwing.
  factory CardService.missing(String id) => CardService(
    id: id,
    name: id,
    stampCount: 0,
    stampsRequired: 0,
    rewardsAvailable: 0,
    stampsUntilReward: 0,
    rewardDescription: '',
    isLadder: false,
  );

  factory CardService.fromJson(Map<String, dynamic> json) {
    final reward = ((json['currentReward'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final rungs = json['rewardMilestones'];
    return CardService(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? (json['id'] as String),
      stampCount: _int(json['stampCount']),
      stampsRequired: _int(json['stampsRequired']),
      rewardsAvailable: _int(json['rewardsAvailable']),
      stampsUntilReward: _int(json['stampsUntilReward']),
      rewardDescription: (reward['description'] as String?) ?? '',
      isLadder: rungs is List && rungs.length >= 2,
    );
  }
}

List<CardService> _services(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((m) => CardService.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false)
    : const [];
```

- [ ] **Step 4: Thread `serviceId` through the client**

In `lib/api/api_client.dart`, give the abstract `addStamps`, `addToRewards` and `redeem` each a new named parameter, `String? serviceId,`. Mirror it in `HttpApiClient`, and add `'serviceId': ?serviceId,` to each request body. That is the same null-aware element `fetchScanLog` already uses for `cursor`. For example:

```dart
  @override
  Future<CardActionResult> addStamps({
    required String cardId,
    required String businessId,
    required int increment,
    String? serviceId,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', cardId, 'stamp']),
      // Only on multi-service cards: the API refuses a serviceId anywhere else.
      body: {'businessId': businessId, 'increment': increment, 'serviceId': ?serviceId},
    );
    return CardActionResult.fromJson(json);
  }
```

Apply the same change to `addToRewards` and `redeem`, whose body is `{'businessId': businessId, 'serviceId': ?serviceId}`.

- [ ] **Step 5: Update the fake and add fixtures**

In `test/support/fake_api_client.dart`, add `String? serviceId,` to the same three overrides. Record each call with a `@<serviceId>` suffix when one is given:

```dart
    actions.add(serviceId == null ? 'addStamps:$increment' : 'addStamps:$increment@$serviceId');
```

For the other two, record `'addToRewards'` or `'addToRewards@$serviceId'`, and `'redeem'` or `'redeem@$serviceId'`.

Create `test/support/multi_service_fixtures.dart`:

```dart
import 'package:qwallet_scan/api/models/loyalty_card.dart';

CardService service(
  String id,
  String name,
  int count,
  int required, {
  int rewards = 0,
  bool ladder = false,
}) => CardService(
  id: id,
  name: name,
  stampCount: count,
  stampsRequired: required,
  rewardsAvailable: rewards,
  stampsUntilReward: required - count > 0 ? required - count : 0,
  rewardDescription: 'Free $name',
  isLadder: ladder,
);

/// The Runway card: Mani/Pedi 2 of 5 with a reward waiting, Blowdry 1 of 5.
LoyaltyCard multiCard({List<CardService>? services}) => LoyaltyCard(
  cardId: 'MSC1234567',
  businessId: 'biz-1',
  userName: 'Mithayel',
  userEmail: null,
  userPhone: null,
  templateType: 'multi_service',
  stampCount: 3,
  rewardsAvailable: 1,
  stampsRequired: 0,
  rewardDescription: '',
  businessName: 'Runway',
  pointsBalance: 0,
  pointsExpiry: null,
  membershipNumber: null,
  membershipCategory: null,
  membershipExpiry: null,
  services:
      services ??
      [service('s1', 'Mani/Pedi', 2, 5, rewards: 1), service('s2', 'Blowdry', 1, 5)],
);
```

- [ ] **Step 6: Run, analyze and commit**

```bash
fvm flutter test 2>&1 | tail -1      # All tests passed! (123 + 5)
fvm flutter analyze 2>&1 | tail -1   # No issues found!
git add lib/api/models/loyalty_card.dart lib/api/api_client.dart test/support test/api
git commit -m "feat(api): services on the card model and serviceId on reward actions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Scan notifier — service actions and per-service repeat keys

**Files:**
- Modify: `lib/scan/scan_notifier.dart`
- Test: `test/scan/scan_notifier_test.dart`

**Interfaces:**
- Consumes: `CardActionResult.services`, `LoyaltyCard.withServiceState`, and `ApiClient` with `serviceId` (Task 1).
- Produces:
  - `ScanNotifier.addStamps(int increment, {String? serviceId})`
  - `addToRewards({String? serviceId})`
  - `redeem({String? serviceId})`
  - Successful service actions are recorded in `RecentActions` under `'<cardId>:<serviceId>'`.

- [ ] **Step 1: Write the failing tests**

Add `import 'package:qwallet_scan/scan/recent_actions.dart';` and `import '../support/multi_service_fixtures.dart';` to `test/scan/scan_notifier_test.dart`. Then append this inside `main()`:

```dart
  group('service actions', () {
    test('a stamp on one service sends its id and adopts the returned services', () async {
      final container = containerWith();
      api.card = multiCard();
      await container.read(scanProvider.notifier).lookUp('MSC1234567');
      api.actionResult = CardActionResult(
        stampCount: 5,
        stampsRequired: 0,
        rewardsAvailable: 1,
        services: [
          service('s1', 'Mani/Pedi', 4, 5, rewards: 1),
          service('s2', 'Blowdry', 1, 5),
        ],
      );

      final updated = await container
          .read(scanProvider.notifier)
          .addStamps(2, serviceId: 's1');

      expect(api.actions, ['addStamps:2@s1']);
      expect(updated!.services.first.stampCount, 4);
      expect(updated.stampCount, 5);
      expect(updated.templateType, 'multi_service');
      final state = container.read(scanProvider) as ScanFound;
      expect(state.card.services.first.stampCount, 4);
    });

    test('the repeat memory is per service', () async {
      final container = containerWith();
      api.card = multiCard();
      await container.read(scanProvider.notifier).lookUp('MSC1234567');
      api.actionResult = CardActionResult(
        stampCount: 4, stampsRequired: 0, rewardsAvailable: 1,
        services: multiCard().services,
      );

      await container.read(scanProvider.notifier).redeem(serviceId: 's1');

      final recent = container.read(recentActionsProvider.notifier);
      expect(recent.sinceLast('MSC1234567:s1', CardAction.redeem), isNotNull);
      expect(recent.sinceLast('MSC1234567:s2', CardAction.redeem), isNull);
      expect(recent.sinceLast('MSC1234567', CardAction.redeem), isNull);
    });

    test('a refused service action keeps the card and records nothing (Review Focus 5)', () async {
      final container = containerWith();
      api.card = multiCard();
      await container.read(scanProvider.notifier).lookUp('MSC1234567');
      api.actionError = ApiException.fromResponse(
        409, '{"error":"Card was updated concurrently, please retry"}');

      final updated = await container
          .read(scanProvider.notifier)
          .addToRewards(serviceId: 's2');

      expect(updated, isNull);
      final state = container.read(scanProvider) as ScanFound;
      expect(state.actionError, 'Card was updated concurrently, please retry');
      expect(state.card.services.length, 2);
      expect(
        container.read(recentActionsProvider.notifier)
            .sinceLast('MSC1234567:s2', CardAction.addReward),
        isNull,
      );
    });
  });
```

Run `fvm flutter test test/scan/scan_notifier_test.dart`. Expected: compile error on `serviceId:`.

- [ ] **Step 2: Implement**

In `lib/scan/scan_notifier.dart`:

```dart
  Future<LoyaltyCard?> addStamps(int increment, {String? serviceId}) => _act(
    CardAction.stamps,
    serviceId: serviceId,
    (api, card, businessId) => api.addStamps(
      cardId: card.cardId,
      businessId: businessId,
      increment: increment,
      serviceId: serviceId,
    ),
  );

  Future<LoyaltyCard?> addToRewards({String? serviceId}) => _act(
    CardAction.addReward,
    serviceId: serviceId,
    (api, card, businessId) => api.addToRewards(
      cardId: card.cardId,
      businessId: businessId,
      serviceId: serviceId,
    ),
  );

  Future<LoyaltyCard?> redeem({String? serviceId}) => _act(
    CardAction.redeem,
    serviceId: serviceId,
    (api, card, businessId) => api.redeem(
      cardId: card.cardId,
      businessId: businessId,
      serviceId: serviceId,
    ),
  );
```

In `_act`:
- Add the named parameter `{String? serviceId}` after the positional ones.
- Replace the `final updated = current.card.withRewardState(…)` statement and the `record(...)` line with:

```dart
      // A multi-service response carries every service; the card's counts
      // come from it. Any other card keeps its single counter.
      final updated = result.services.isNotEmpty
          ? current.card.withServiceState(
              services: result.services,
              stampCount: result.stampCount,
              rewardsAvailable: result.rewardsAvailable,
            )
          : current.card.withRewardState(
              stampCount: result.stampCount,
              rewardsAvailable: result.rewardsAvailable,
              stampsRequired: result.stampsRequired,
            );
      // Per service, so stamping Mani/Pedi never warns about Blowdry.
      final guardKey = serviceId == null ? updated.cardId : '${updated.cardId}:$serviceId';
      ref.read(recentActionsProvider.notifier).record(guardKey, action);
```

Dart allows named arguments before positional ones, so `_act(CardAction.stamps, serviceId: serviceId, (…) => …)` compiles.

- [ ] **Step 3: Run, analyze and commit**

```bash
fvm flutter test 2>&1 | tail -1 && fvm flutter analyze 2>&1 | tail -1
git add lib/scan/scan_notifier.dart test/scan/scan_notifier_test.dart
git commit -m "feat(scan): service-aware reward actions with per-service repeat memory

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Extract `StampControls` from `RewardActions` (behaviour unchanged)

**Files:**
- Create: `lib/scan/stamp_controls.dart`
- Modify: `lib/scan/reward_actions.dart` (becomes a thin wrapper)
- Test: the existing `test/widget/reward_actions_test.dart` must pass **unchanged**

**Interfaces:**
- Consumes: `ScanNotifier.addStamps / addToRewards / redeem` with `serviceId` (Task 2), and `CardService.missing` (Task 1).
- Produces:
  - `class StampTarget { cardId, stampCount, stampsRequired, rewardsAvailable, rewardDescription, serviceId?, serviceName?, maxIncrement?; factory StampTarget.forCard(LoyaltyCard); factory StampTarget.forService(LoyaltyCard, String serviceId); String get guardKey }`
  - `class StampControls extends ConsumerStatefulWidget { const StampControls({super.key, required LoyaltyCard card, required StampTarget Function(LoyaltyCard) targetOf}) }`

- [ ] **Step 1: Create `lib/scan/stamp_controls.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'action_flow.dart';
import 'recent_actions.dart';
import 'scan_notifier.dart';

/// What the stamp controls show and act on: a whole reward card, or one
/// service of a multi-service card.
class StampTarget {
  const StampTarget({
    required this.cardId,
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
    required this.rewardDescription,
    this.serviceId,
    this.serviceName,
    this.maxIncrement,
  });

  final String cardId;
  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;
  final String rewardDescription;

  /// Null for a reward card.
  final String? serviceId;
  final String? serviceName;

  /// The most one tap may send, or null for no limit (reward cards, as today).
  final int? maxIncrement;

  factory StampTarget.forCard(LoyaltyCard card) => StampTarget(
    cardId: card.cardId,
    stampCount: card.stampCount,
    stampsRequired: card.stampsRequired,
    rewardsAvailable: card.rewardsAvailable,
    rewardDescription: card.rewardDescription,
  );

  /// One service. The increment stops at the end of the service's cycle: past
  /// it the API resets the count, and a ladder service drops the overflow.
  /// A row sitting full starts a fresh cycle, so its cap is a whole cycle.
  factory StampTarget.forService(LoyaltyCard card, String serviceId) {
    final s = card.services.firstWhere(
      (x) => x.id == serviceId,
      orElse: () => CardService.missing(serviceId),
    );
    final remaining = s.stampsRequired - s.stampCount;
    final cycle = remaining > 0 ? remaining : s.stampsRequired;
    return StampTarget(
      cardId: card.cardId,
      stampCount: s.stampCount,
      stampsRequired: s.stampsRequired,
      rewardsAvailable: s.rewardsAvailable,
      rewardDescription: s.rewardDescription,
      serviceId: s.id,
      serviceName: s.name,
      maxIncrement: cycle < 1 ? 1 : (cycle > 100 ? 100 : cycle),
    );
  }

  /// The repeat-warning key: per service, so one service never warns about
  /// the other.
  String get guardKey => serviceId == null ? cardId : '$cardId:$serviceId';

  String named(String plain, String Function(String name) withName) =>
      serviceName == null ? plain : withName(serviceName!);
}

/// Stamp count, increment and the three reward actions, for a reward card or
/// for one chosen service. Live counts come from the scan state through
/// [targetOf], so the screen always shows what the server last said.
class StampControls extends ConsumerStatefulWidget {
  const StampControls({super.key, required this.card, required this.targetOf});

  final LoyaltyCard card;
  final StampTarget Function(LoyaltyCard card) targetOf;

  @override
  ConsumerState<StampControls> createState() => _StampControlsState();
}

class _StampControlsState extends ConsumerState<StampControls> {
  int _increment = 1;

  /// Never above the target's cap, even when an action has just moved the
  /// counts under a raised increment.
  int _shown(StampTarget t) {
    final max = t.maxIncrement;
    return max != null && _increment > max ? max : _increment;
  }

  Future<void> _addStamps(StampTarget t) {
    final count = _shown(t);
    return runCardAction(
      context,
      ref,
      cardId: t.guardKey,
      action: CardAction.stamps,
      proceedLabel: 'Stamp anyway',
      run: () => ref
          .read(scanProvider.notifier)
          .addStamps(count, serviceId: t.serviceId),
      confirmation: (card) {
        final u = widget.targetOf(card);
        return u.named(
          'Stamped. ${u.stampCount} of ${u.stampsRequired}.',
          (n) => '$n stamped. ${u.stampCount} of ${u.stampsRequired}.',
        );
      },
    );
  }

  Future<void> _addToRewards(StampTarget t) => runCardAction(
    context,
    ref,
    cardId: t.guardKey,
    action: CardAction.addReward,
    proceedLabel: 'Add anyway',
    run: () => ref
        .read(scanProvider.notifier)
        .addToRewards(serviceId: t.serviceId),
    confirmation: (card) {
      final u = widget.targetOf(card);
      return u.named(
        'Reward banked. ${u.rewardsAvailable} waiting.',
        (n) => '$n reward banked. ${u.rewardsAvailable} waiting.',
      );
    },
  );

  Future<void> _redeem(StampTarget t) => runCardAction(
    context,
    ref,
    cardId: t.guardKey,
    action: CardAction.redeem,
    proceedLabel: 'Redeem',
    // Redeeming always asks, repeat or not: it spends something the customer
    // earned and the API gives it back to nobody.
    confirmTitle: t.named('Redeem a reward?', (n) => 'Redeem a $n reward?'),
    confirmBody: 'This cannot be undone.',
    run: () => ref.read(scanProvider.notifier).redeem(serviceId: t.serviceId),
    confirmation: (card) {
      final u = widget.targetOf(card);
      return u.named(
        'Reward redeemed. ${u.rewardsAvailable} left.',
        (n) => '$n reward redeemed. ${u.rewardsAvailable} left.',
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final t = widget.targetOf(card);
    final shown = _shown(t);
    final max = t.maxIncrement;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.named(
            '${t.stampCount} / ${t.stampsRequired} stamps',
            (n) => '$n: ${t.stampCount} / ${t.stampsRequired} stamps',
          ),
          style: theme.textTheme.titleLarge,
        ),
        if (t.rewardDescription.isNotEmpty)
          Text(t.rewardDescription, style: theme.textTheme.bodyMedium),
        if (t.rewardsAvailable > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${t.rewardsAvailable} reward'
              '${t.rewardsAvailable == 1 ? '' : 's'} waiting',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove),
              onPressed: shown > 1
                  ? () => setState(() => _increment = shown - 1)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('$shown', style: theme.textTheme.headlineSmall),
            ),
            IconButton.outlined(
              icon: const Icon(Icons.add),
              onPressed: max == null || shown < max
                  ? () => setState(() => _increment = shown + 1)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AsyncButton(
          label: t.named('Add Stamps', (n) => 'Add $n Stamps'),
          busy: busy,
          onPressed: () => _addStamps(t),
        ),
        const SizedBox(height: 8),
        // Not disabled on stampCount >= stampsRequired: on a multi-milestone
        // card the real threshold is the cumulative total of every rung so far,
        // and this screen is not given the milestones to compute it. The server
        // knows, and its refusal is readable.
        AsyncButton(
          label: t.named('Add to Rewards', (n) => 'Add to $n Rewards'),
          tonal: true,
          busy: busy,
          onPressed: () => _addToRewards(t),
        ),
        const SizedBox(height: 8),
        // Not disabled on rewardsAvailable == 0 either: the API also allows
        // redeeming straight off a completed card, so a 10/10 card with nothing
        // banked is legitimately redeemable.
        AsyncButton(
          label: t.named('Redeem', (n) => 'Redeem $n Reward'),
          tonal: true,
          busy: busy,
          onPressed: () => _redeem(t),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
```

- [ ] **Step 2: Make `RewardActions` a wrapper**

Replace the whole of `lib/scan/reward_actions.dart` with:

```dart
import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';
import 'stamp_controls.dart';

/// A reward card's stamp and reward actions — the whole card is the target.
class RewardActions extends StatelessWidget {
  const RewardActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) =>
      StampControls(card: card, targetOf: StampTarget.forCard);
}
```

- [ ] **Step 3: Prove nothing changed for reward cards**

```bash
fvm flutter test test/widget/reward_actions_test.dart   # every existing test passes, file untouched
fvm flutter test 2>&1 | tail -1 && fvm flutter analyze 2>&1 | tail -1
git diff --stat -- test/widget/reward_actions_test.dart  # empty
```

- [ ] **Step 4: Commit**

```bash
git add lib/scan/stamp_controls.dart lib/scan/reward_actions.dart
git commit -m "refactor(scan): StampControls shared by reward cards and services

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `MultiServiceActions` and routing

**Files:**
- Create: `lib/scan/multi_service_actions.dart`
- Modify: `lib/scan/card_result_view.dart` (the `switch`)
- Test: `test/widget/multi_service_actions_test.dart`

**Interfaces:**
- Consumes: `StampControls`, `StampTarget.forService` (Task 3); `LoyaltyCard.services`, `CardService` (Task 1).
- Produces:
  - `class MultiServiceActions extends ConsumerStatefulWidget { const MultiServiceActions({super.key, required LoyaltyCard card}) }`
  - Service tiles keyed `Key('service-<id>')`

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/multi_service_actions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/action_message.dart';
import 'package:qwallet_scan/scan/card_result_view.dart';
import 'package:qwallet_scan/scan/multi_service_actions.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';
import '../support/multi_service_fixtures.dart';

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester, LoyaltyCard c) async {
    api = FakeApiClient();
    api.card = c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: SingleChildScrollView(child: MultiServiceActions(card: c)),
                ),
              ),
              GoRoute(
                path: '/home',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Dashboard'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  testWidgets('shows both services and no actions until one is picked', (tester) async {
    await pump(tester, multiCard());

    expect(find.text('Mani/Pedi'), findsOneWidget);
    expect(find.text('Blowdry'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('1 reward waiting'), findsOneWidget);
    expect(find.text('4 more to reward'), findsOneWidget);
    expect(find.text('Pick the service the customer had.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('picking a service shows its own controls', (tester) async {
    await pump(tester, multiCard());

    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    expect(button('Add Blowdry Stamps'), findsOneWidget);
    expect(button('Add to Blowdry Rewards'), findsOneWidget);
    expect(button('Redeem Blowdry Reward'), findsOneWidget);
    expect(find.text('Pick the service the customer had.'), findsNothing);
  });

  testWidgets('the increment stops at the end of the cycle (Review Focus 2)', (tester) async {
    await pump(tester, multiCard(services: [
      service('s1', 'Mani/Pedi', 2, 5),
      service('s2', 'Blowdry', 4, 5),
    ]));
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }

    expect(find.text('1'), findsOneWidget);
    final plus = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));
    expect(plus.onPressed, isNull);
  });

  testWidgets('a stamp sends the service and names it in the confirmation', (tester) async {
    await pump(tester, multiCard());
    api.actionResult = CardActionResult(
      stampCount: 5, stampsRequired: 0, rewardsAvailable: 1,
      services: [
        service('s1', 'Mani/Pedi', 2, 5, rewards: 1),
        service('s2', 'Blowdry', 3, 5),
      ],
    );
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pumpAndSettle();

    expect(api.actions, ['addStamps:2@s2']);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(tester.container().read(actionMessageProvider), 'Blowdry stamped. 3 of 5.');
  });

  testWidgets('the repeat warning is per service (Review Focus 1)', (tester) async {
    await pump(tester, multiCard());
    tester.container().read(recentActionsProvider.notifier)
        .record('MSC1234567:s1', CardAction.stamps);
    api.actionResult = CardActionResult(
      stampCount: 4, stampsRequired: 0, rewardsAvailable: 1,
      services: multiCard().services,
    );

    // The other service: no warning, the stamp goes straight through.
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();
    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pumpAndSettle();
    expect(find.text('Already done'), findsNothing);
    expect(api.actions, ['addStamps:1@s2']);
  });

  testWidgets('the same service within a minute still asks', (tester) async {
    await pump(tester, multiCard());
    tester.container().read(recentActionsProvider.notifier)
        .record('MSC1234567:s1', CardAction.stamps);

    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pumpAndSettle();
    await tester.tap(button('Add Mani/Pedi Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('Already done'), findsOneWidget);
    expect(api.actions, isEmpty);
  });

  testWidgets('redeem asks with the service name before taking anything', (tester) async {
    await pump(tester, multiCard());
    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pumpAndSettle();

    await tester.tap(button('Redeem Mani/Pedi Reward'));
    await tester.pumpAndSettle();

    expect(find.text('Redeem a Mani/Pedi reward?'), findsOneWidget);
    expect(api.actions, isEmpty);
  });

  testWidgets('a refusal keeps the card, the reason and the picked service (Review Focus 5)', (tester) async {
    await pump(tester, multiCard());
    api.actionError = ApiException.fromResponse(
      409, '{"error":"Card was updated concurrently, please retry"}');
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('Card was updated concurrently, please retry'), findsOneWidget);
    expect(button('Add Blowdry Stamps'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('the card screen routes a multi-service card here', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(FakeApiClient()),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp(home: Scaffold(body: CardResultView(card: multiCard()))),
      ),
    );
    await tester.pump();

    expect(find.byType(MultiServiceActions), findsOneWidget);
    expect(find.text("This card type isn't supported in this app"), findsNothing);
  });
}
```

Run `fvm flutter test test/widget/multi_service_actions_test.dart`. Expected: compile error, because `multi_service_actions.dart` doesn't exist.

- [ ] **Step 2: Create `lib/scan/multi_service_actions.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import 'scan_notifier.dart';
import 'stamp_controls.dart';

/// A multi-service card at the counter: every service's progress, then a
/// service picker with NOTHING chosen. Controls appear only once staff pick
/// one — defaulting to the first would make the wrong-service stamp the easy
/// one, and the server cannot tell a mistaken stamp from a real one.
class MultiServiceActions extends ConsumerStatefulWidget {
  const MultiServiceActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<MultiServiceActions> createState() =>
      _MultiServiceActionsState();
}

class _MultiServiceActionsState extends ConsumerState<MultiServiceActions> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);
    final selected = _selectedId;

    if (card.services.isEmpty) {
      return const Text('This card has no services.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a service', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, s) in card.services.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ServiceTile(
                  service: s,
                  selected: s.id == selected,
                  onTap: () => setState(() => _selectedId = s.id),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        if (selected == null)
          Text(
            'Pick the service the customer had.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else
          // Keyed by service so switching starts its increment back at one.
          StampControls(
            key: ValueKey(selected),
            card: card,
            targetOf: (c) => StampTarget.forService(c, selected),
          ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final CardService service;
  final bool selected;
  final VoidCallback onTap;

  String get _status {
    final n = service.rewardsAvailable;
    if (n > 0) return '$n reward${n == 1 ? '' : 's'} waiting';
    if (!service.isLadder && service.stampCount >= service.stampsRequired) {
      return 'Reward ready';
    }
    return '${service.stampsUntilReward} more to reward';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rewardish = service.rewardsAvailable > 0 || _status == 'Reward ready';

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          key: Key('service-${service.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${service.stampCount} / ${service.stampsRequired}',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  _status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: rewardish ? scheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Route multi-service cards to it**

In `lib/scan/card_result_view.dart`:
- Add `import 'multi_service_actions.dart';`.
- Add this line to the `switch` after the `'reward'` case:

```dart
          'multi_service' => MultiServiceActions(card: card),
```

- [ ] **Step 4: Run, analyze and commit**

```bash
fvm flutter test test/widget/multi_service_actions_test.dart
fvm flutter test 2>&1 | tail -1 && fvm flutter analyze 2>&1 | tail -1
git add lib/scan/multi_service_actions.dart lib/scan/card_result_view.dart test/widget/multi_service_actions_test.dart
git commit -m "feat(scan): multi-service cards — pick a service, then stamp, bank or redeem it

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Version bump and final checks

**Files:**
- Modify: `pubspec.yaml` (`version:`)

- [ ] **Step 1: Bump the version**

Change `version: 1.0.2+2` to `version: 1.1.0+3`. It's a new feature, and the stores need a higher build number.

- [ ] **Step 2: Full verification**

```bash
fvm flutter test 2>&1 | tail -1      # All tests passed! (≥ 123 + 17)
fvm flutter analyze 2>&1 | tail -1   # No issues found!
git diff --stat master -- test/widget/reward_actions_test.dart   # empty: reward behaviour pinned by unchanged tests
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: version 1.1.0 (build 3) — multi-service cards

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Do not build or upload to the stores. Releasing is the user's call. An installed build needs `fvm flutter build ipa` / `appbundle` and the store flow.
