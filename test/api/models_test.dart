import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/api/models/session.dart';

void main() {
  group('Session', () {
    test('reads the token and the businesses the user is linked to', () {
      final session = Session.fromJson(
        jsonDecode('''
        {"token":"jwt","user":{"id":7,"email":"s@x.qa","name":"Sam",
         "role":"staff","businessIds":["biz-1","biz-2"]}}
      '''),
      );

      expect(session.token, 'jwt');
      expect(session.userId, 7);
      expect(session.name, 'Sam');
      expect(session.role, 'staff');
      expect(session.businessIds, ['biz-1', 'biz-2']);
    });

    test('reads the user id the API actually sends, which is a string', () {
      // users.id is BIGSERIAL, and node-postgres hands BIGINT back as a
      // string. A cast to int here threw on every single sign-in.
      final session = Session.fromJson(
        jsonDecode('''
        {"token":"jwt","user":{"id":"2","email":"s@x.qa","name":"Sam",
         "role":"staff","businessIds":["biz-1"]}}
      '''),
      );

      expect(session.userId, 2);
    });

    test('a user linked to nothing yields an empty list, not a crash', () {
      final session = Session.fromJson(
        jsonDecode('''
        {"token":"jwt","user":{"id":7,"email":"s@x.qa","name":"Sam",
         "role":"business","businessIds":[]}}
      '''),
      );

      expect(session.businessIds, isEmpty);
    });
  });

  group('LoyaltyCard', () {
    test('reads a reward card, flattening the merchantData it needs', () {
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":"Ali",
         "userEmail":"a@b.qa","userPhone":"+97433123456","templateType":"reward",
         "stampCount":7,"rewardsAvailable":1,"pointsBalance":0,
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,
         "merchantData":{"businessName":"Wake Qatar",
          "rewardDescription":"A free flat white","stampsRequired":10}}
      '''),
      );

      expect(card.cardId, 'ABC123');
      expect(card.templateType, 'reward');
      expect(card.stampCount, 7);
      expect(card.stampsRequired, 10);
      expect(card.rewardsAvailable, 1);
      expect(card.rewardDescription, 'A free flat white');
      expect(card.businessName, 'Wake Qatar');
    });

    test('parses the nulls the API really sends on a reward card', () {
      // pointsExpiry, membershipExpiry and userPhone are all null on a reward
      // card — the API returns every field for every type.
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":"Ali",
         "userEmail":"a@b.qa","userPhone":null,"templateType":"reward",
         "stampCount":0,"rewardsAvailable":0,"pointsBalance":0,
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,"merchantData":{}}
      '''),
      );

      expect(card.userPhone, isNull);
      expect(card.pointsExpiry, isNull);
      expect(card.membershipExpiry, isNull);
      expect(card.stampsRequired, 0);
      expect(card.rewardDescription, '');
      expect(card.businessName, isNull);
    });

    test('reads a count that arrives as a string', () {
      // node-postgres returns BIGINT and NUMERIC as strings, and this API has
      // handed a bare id back as one before now. A count that silently became
      // 0 would read as an empty card at the counter.
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":"Ali",
         "userEmail":null,"userPhone":null,"templateType":"reward",
         "stampCount":"7","rewardsAvailable":"1","pointsBalance":"250",
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,"merchantData":{"stampsRequired":"10"}}
      '''),
      );

      expect(card.stampCount, 7);
      expect(card.rewardsAvailable, 1);
      expect(card.pointsBalance, 250);
      expect(card.stampsRequired, 10);
    });

    test(
      'a count that is neither a number nor a numeric string reads as zero',
      () {
        final card = LoyaltyCard.fromJson(
          jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":null,
         "userEmail":null,"userPhone":null,"templateType":"reward",
         "stampCount":"not-a-number","rewardsAvailable":null,"pointsBalance":0,
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,"merchantData":{}}
      '''),
        );

        expect(card.stampCount, 0);
        expect(card.rewardsAvailable, 0);
      },
    );

    test('reads a membership card, including its dates', () {
      final card = LoyaltyCard.fromJson(
        jsonDecode('''
        {"cardId":"M1","businessId":"biz-1","userName":"Ali","userEmail":null,
         "userPhone":null,"templateType":"membership","stampCount":0,
         "rewardsAvailable":0,"pointsBalance":0,"pointsExpiry":null,
         "membershipNumber":"MBR-0007","membershipCategory":"Gold",
         "membershipExpiry":"2027-01-31T00:00:00.000Z","merchantData":{}}
      '''),
      );

      expect(card.membershipNumber, 'MBR-0007');
      expect(card.membershipCategory, 'Gold');
      expect(card.membershipExpiry, DateTime.utc(2027, 1, 31));
    });
  });

  group('ScanLogPage', () {
    test('reads both row types out of the union the API returns', () {
      final page = ScanLogPage.fromJson(
        jsonDecode('''
        {"scanLog":[
          {"id":2,"type":"redemption","cardId":"ABC123","staffName":"Sam",
           "customerName":"Ali","customerEmail":"a@b.qa","stampsAdded":10,
           "stampsBefore":10,"stampsAfter":0,
           "loggedAt":"2026-09-07T09:15:00.000Z"},
          {"id":1,"type":"stamp","cardId":"ABC123","staffName":null,
           "customerName":"Ali","customerEmail":"a@b.qa","stampsAdded":1,
           "stampsBefore":6,"stampsAfter":7,
           "loggedAt":"2026-09-07T08:00:00.000Z"}],
         "hasMore":true,"nextCursor":"2026-09-07T08:00:00.000Z"}
      '''),
      );

      expect(page.entries, hasLength(2));
      expect(page.entries.first.type, ScanLogType.redemption);
      expect(page.entries.last.type, ScanLogType.stamp);
      expect(page.entries.last.staffName, isNull);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2026-09-07T08:00:00.000Z');
    });

    test('the last page has no cursor', () {
      final page = ScanLogPage.fromJson(
        jsonDecode('{"scanLog":[],"hasMore":false,"nextCursor":null}'),
      );

      expect(page.entries, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });
}
