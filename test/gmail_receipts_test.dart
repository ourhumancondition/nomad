import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/flight_brackets.dart';
import 'package:nomadic_residence/engine/gmail_access.dart';
import 'package:nomadic_residence/engine/gmail_fixtures.dart';
import 'package:nomadic_residence/engine/gmail_receipts.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';

void main() {
  test('parses airline and OTA receipts without guessing zones', () {
    final ac = _one(airCanadaReceipt());
    expect(ac.flightNumber, 'AC123');
    expect(ac.fromIata, 'YYZ');
    expect(ac.toIata, 'LHR');
    expect(ac.fromCountry, 'CA');
    expect(ac.toCountry, 'GB');
    expect(ac.depart!.iso, '2026-03-02T18:40');
    expect(ac.arrive!.iso, '2026-03-03T06:55');
    expect(ac.departTimezone, 'America/Toronto');
    expect(ac.arriveTimezone, 'Europe/London');
    expect(ac.passenger, 'Jordan Example');
    expect(ac.itineraryRef, 'AB12CD');
    expect(ac.flags, isEmpty);

    final eva = _one(evaReceipt());
    expect(eva.flightNumber, 'BR12');
    expect(eva.fromIata, 'TPE');
    expect(eva.toCountry, 'US');
    expect(eva.departTimezone, 'Asia/Taipei');

    final asiana = _one(asianaReceipt());
    expect(asiana.flightNumber, 'OZ204');
    expect(asiana.fromIata, 'ICN');
    expect(asiana.arriveTimezone, 'America/Los_Angeles');

    final united = _one(unitedReceipt());
    expect(united.flightNumber, 'UA837');
    expect(united.fromIata, 'EWR');
    expect(united.toIata, 'LHR');

    final trip = planGmailImport(
      messages: [tripComReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.fictional,
    );
    expect(trip.legs, hasLength(2));
    expect(trip.legs[0].flightNumber, 'LO26');
    expect(trip.legs[0].flags, isEmpty);
    expect(trip.legs[1].flightNumber, 'ZH9042');
    expect(trip.legs[1].flags, contains('unknown_depart_timezone'));
    expect(trip.legs[1].flags, contains('unknown_arrive_timezone'));
    expect(trip.legs[1].departTimezone, isEmpty);
    expect(resolveLeg(trip.legs[1], null).saveable, isFalse);
  });

  test('flags ambiguous times, zones, airports, and passengers', () {
    final plan = planGmailImport(
      messages: [ambiguousReceipt(), unitedAbbreviationReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.fictional,
    );
    final ambiguous = plan.legs.singleWhere(
      (leg) => leg.messageId == 'amb-msg-001',
    );
    expect(ambiguous.passenger, isEmpty);
    expect(ambiguous.flags, contains('ambiguous_passenger'));
    expect(ambiguous.flags, contains('ambiguous_from_airport'));
    expect(ambiguous.flags, contains('ambiguous_to_airport'));
    expect(ambiguous.flags, contains('ambiguous_time'));
    expect(ambiguous.flags, contains('ambiguous_arrive_timezone'));
    expect(ambiguous.fromIata, isEmpty);
    expect(ambiguous.toIata, isEmpty);
    expect(ambiguous.depart, isNull);
    expect(ambiguous.arriveTimezone, isEmpty);
    expect(resolveLeg(ambiguous, null).saveable, isFalse);

    final abbrev = plan.legs.singleWhere(
      (leg) => leg.messageId == 'ua-msg-est',
    );
    expect(abbrev.departTimezone, isEmpty);
    expect(abbrev.arriveTimezone, isEmpty);
    expect(abbrev.flags, contains('ambiguous_depart_timezone'));
    expect(abbrev.flags, contains('ambiguous_arrive_timezone'));
    expect(abbrev.depart!.iso, '2026-08-11T19:15');
    final filled = resolveLeg(
      abbrev,
      const LegCorrection(
        departTimezone: 'America/New_York',
        arriveTimezone: 'Europe/London',
      ),
    );
    expect(filled.saveable, isTrue);
    expect(filled.flags, contains('timezone_entered'));
    final flight = mutationsFor(
      plan: plan,
      draft: GmailDraft(
        saveExternalIds: {abbrev.externalId},
        corrections: {
          abbrev.externalId: const LegCorrection(
            departTimezone: 'America/New_York',
            arriveTimezone: 'Europe/London',
          ),
        },
      ),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.missing,
      connectedDatabase: false,
      existing: const [],
    ).create.single;
    expect(flight.departTimezone, 'America/New_York');
    expect(flight.reviewState, FlightReviewState.pending);
    expect(flight.evidenceStatus, 'booking_only');
    expect(flight.notes, contains('Time zone entered during review.'));
    expect(flight.notes, isNot(contains('19:15 EST')));
    expect(flight.departTimezone, isNot('EST'));
  });

  test('links an amendment and does not import the previous time', () {
    final plan = planGmailImport(
      messages: [lotBookingReceipt(), lotAmendmentReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(plan.legs, hasLength(2));
    final original = plan.legs.first;
    final changed = plan.legs.last;
    expect(original.flightNumber, 'LO12');
    expect(original.depart!.iso, '2026-04-04T10:15');
    expect(changed.depart!.iso, '2026-04-04T16:40');
    expect(changed.kind, ReceiptKind.amendment);
    expect(changed.supersedesExternalId, original.externalId);
    expect(changed.flags, isNot(contains('no_earlier_version')));
    expect(
      plan.legs.where((leg) => leg.depart!.iso == '2026-04-04T10:15'),
      hasLength(1),
    );
  });

  test('a cancellation can reject a pending flight and cannot change an accepted one', () {
    final pending = _saved(
      externalId: 'g:zh-msg-001:0',
      number: 'ZH9001',
      ref: 'SZX190',
      review: FlightReviewState.pending,
    );
    final accepted = pending.copyWith(
      id: 'accepted-id',
      reviewState: FlightReviewState.accepted,
    );
    final pendingPlan = planGmailImport(
      messages: [shenzhenCancellationReceipt()],
      existing: [pending],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(pendingPlan.legs, isEmpty);
    final cancel = pendingPlan.cancellations.single;
    expect(cancel.blocked, isFalse);
    expect(cancel.targetExternalId, pending.externalId);

    final saved = mutationsFor(
      plan: pendingPlan,
      draft: GmailDraft(rejectExternalIds: {pending.externalId}),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.connected,
      connectedDatabase: true,
      existing: [pending],
    );
    expect(saved.create, isEmpty);
    expect(saved.reject.single.reviewState, FlightReviewState.rejected);
    expect(saved.reject.single.notes, contains('Gmail cancellation'));
    expect(saved.reject.single.notes, isNot(contains('Shenzhen (SZX)')));

    final acceptedPlan = planGmailImport(
      messages: [shenzhenCancellationReceipt()],
      existing: [accepted],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(acceptedPlan.cancellations.single.blocked, isTrue);
    expect(
      acceptedPlan.cancellations.single.flags,
      contains('accepted_unchanged'),
    );
    final untouched = mutationsFor(
      plan: acceptedPlan,
      draft: GmailDraft(rejectExternalIds: {accepted.externalId}),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.connected,
      connectedDatabase: true,
      existing: [accepted],
    );
    expect(untouched.reject, isEmpty);
    expect(untouched.create, isEmpty);
  });

  test('repeat imports are duplicates and never auto-accept', () {
    final first = planGmailImport(
      messages: fictionalGmailReceipts(),
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.fictional,
    );
    final mutations = mutationsFor(
      plan: first,
      draft: GmailDraft(
        saveExternalIds: {
          for (final leg in first.legs)
            if (resolveLeg(leg, null).saveable) leg.externalId,
        },
      ),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.missing,
      connectedDatabase: false,
      existing: const [],
    );
    expect(mutations.refusal, isNull);
    expect(mutations.create, isNotEmpty);
    for (final flight in mutations.create) {
      expect(flight.reviewState, FlightReviewState.pending);
      expect(flight.evidenceStatus, 'booking_only');
      expect(flight.inference, InferenceKind.none);
      expect(
        flightQualifiesForBracket(flight, defaultEvidenceStatuses),
        isFalse,
      );
      expect(flight.notes, isNot(contains('Flight AC')));
      expect(flight.gmailMessageId, isNotEmpty);
      expect(flight.gmailFrom, contains('@'));
      expect(flight.notes, contains('not presence'));
    }
    final again = planGmailImport(
      messages: fictionalGmailReceipts(),
      existing: [
        for (final flight in mutations.create) flight.copyWith(id: flight.externalId),
      ],
      ownerId: 'owner-a',
      source: GmailPlanSource.fictional,
    );
    final saveable = again.legs.where((leg) => resolveLeg(leg, null).saveable);
    expect(saveable, isEmpty);
    expect(again.legs.where((leg) => leg.duplicate), isNotEmpty);
    final second = mutationsFor(
      plan: again,
      draft: GmailDraft(
        saveExternalIds: {for (final leg in again.legs) leg.externalId},
      ),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.missing,
      connectedDatabase: false,
      existing: [
        for (final flight in mutations.create) flight.copyWith(id: flight.externalId),
      ],
    );
    expect(second.create, isEmpty);
  });

  test('a matching flight number and time is not imported twice', () {
    final existing = _saved(
      externalId: 'manual-ac',
      number: 'AC123',
      ref: '',
      review: FlightReviewState.accepted,
      depart: '2026-03-02T18:40',
      from: 'YYZ',
      to: 'LHR',
    );
    final plan = planGmailImport(
      messages: [airCanadaReceipt()],
      existing: [existing],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(plan.legs.single.duplicate, isTrue);
    expect(plan.legs.single.duplicateOf, 'manual-ac');
    final saved = mutationsFor(
      plan: plan,
      draft: GmailDraft(saveExternalIds: {plan.legs.single.externalId}),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.connected,
      connectedDatabase: true,
      existing: [existing],
    );
    expect(saved.create, isEmpty);
  });

  test('revoked mailbox imports and other owners are refused', () {
    final plan = planGmailImport(
      messages: [airCanadaReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    final revoked = mutationsFor(
      plan: plan,
      draft: GmailDraft(saveExternalIds: {plan.legs.single.externalId}),
      sessionOwnerId: 'owner-a',
      connection: GmailLinkState.revoked,
      connectedDatabase: true,
      existing: const [],
    );
    expect(revoked.refusal, contains('revoked'));
    expect(revoked.create, isEmpty);
    expect(scanAllowed(GmailLinkState.revoked), isFalse);
    expect(mailboxReadBlock(GmailLinkState.revoked), contains('revoked'));

    final other = mutationsFor(
      plan: plan,
      draft: GmailDraft(saveExternalIds: {plan.legs.single.externalId}),
      sessionOwnerId: 'owner-b',
      connection: GmailLinkState.connected,
      connectedDatabase: true,
      existing: const [],
    );
    expect(other.refusal, contains('different account'));
    expect(other.create, isEmpty);
  });

  test('html script text is not a flight, and a cut-off receipt is withheld', () {
    final html = planGmailImport(
      messages: [htmlScriptReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.fictional,
    );
    expect(html.legs, hasLength(1));
    expect(html.legs.single.flightNumber, 'AC456');
    expect(html.legs.single.fromIata, 'YUL');
    final cut = planGmailImport(
      messages: [
        ReceiptMessage(
          messageId: 'cut-1',
          fromAddress: 'tickets@aircanada.example',
          receivedAt: '2026-02-03T00:00:00Z',
          text: airCanadaReceipt().text,
          truncated: true,
        ),
      ],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(cut.legs, isEmpty);
    expect(cut.withheld, 1);
  });

  test('an unlinked cancellation does not invent a flight', () {
    final plan = planGmailImport(
      messages: [shenzhenCancellationReceipt()],
      existing: const [],
      ownerId: 'owner-a',
      source: GmailPlanSource.mailbox,
    );
    expect(plan.legs, isEmpty);
    expect(plan.cancellations.single.flags, contains('unlinked_cancellation'));
    expect(plan.cancellations.single.blocked, isTrue);
  });
}

GmailLegProposal _one(ReceiptMessage message) {
  final plan = planGmailImport(
    messages: [message],
    existing: const [],
    ownerId: 'owner-a',
    source: GmailPlanSource.fictional,
  );
  expect(plan.legs, hasLength(1));
  return plan.legs.single;
}

FlightRecord _saved({
  required String externalId,
  required String number,
  required String ref,
  required FlightReviewState review,
  String depart = '2026-05-02T09:20',
  String arrive = '2026-05-02T11:30',
  String from = 'SZX',
  String to = 'BKK',
  String fromCountry = 'CN',
  String toCountry = 'TH',
  String departZone = 'Asia/Shanghai',
  String arriveZone = 'Asia/Bangkok',
}) {
  return FlightRecord(
    id: 'row-$externalId',
    flightNumber: number,
    fromIata: from,
    toIata: to,
    fromCountry: fromCountry,
    toCountry: toCountry,
    depart: WallTime.parse(depart),
    arrive: WallTime.parse(arrive),
    departTimezone: departZone,
    arriveTimezone: arriveZone,
    evidenceStatus: 'booking_only',
    inference: InferenceKind.none,
    reviewState: review,
    externalId: externalId,
    itineraryRef: ref,
    gmailMessageId: 'zh-msg-001',
    gmailFrom: 'eticket@shenzhenair.example',
    gmailDate: '2026-04-01T12:00:00Z',
    receiptKind: 'booking',
  );
}
