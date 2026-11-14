import 'airport_countries.dart';
import 'gmail_access.dart';
import 'local_date.dart';
import 'models.dart';

/// A booking, a change to one, or a cancellation of one.
enum ReceiptKind { booking, amendment, cancellation }

/// Where a preview came from. Fictional rows are not a mailbox read.
enum GmailPlanSource { mailbox, fictional }

/// One Gmail message reduced to text. The text is parsed and then dropped.
class ReceiptMessage {
  const ReceiptMessage({
    required this.messageId,
    required this.fromAddress,
    required this.receivedAt,
    required this.text,
    this.truncated = false,
  });

  final String messageId;
  final String fromAddress;
  final String receivedAt;
  final String text;
  final bool truncated;
}

class ParsedLeg {
  ParsedLeg({required this.flightNumber});

  final String flightNumber;
  String fromIata = '';
  String toIata = '';
  String fromCountry = '';
  String toCountry = '';
  WallTime? depart;
  WallTime? arrive;
  String departTimezone = '';
  String arriveTimezone = '';
  final List<String> flags = <String>[];
}

class ParsedReceipt {
  const ParsedReceipt({
    required this.messageId,
    required this.fromAddress,
    required this.receivedAt,
    required this.kind,
    required this.passenger,
    required this.itineraryRef,
    required this.legs,
    required this.previousLegs,
    required this.flags,
    required this.ignored,
    required this.truncated,
  });

  final String messageId;
  final String fromAddress;
  final String receivedAt;
  final ReceiptKind kind;
  final String passenger;
  final String itineraryRef;
  final List<ParsedLeg> legs;
  final List<ParsedLeg> previousLegs;
  final List<String> flags;
  final bool ignored;
  final bool truncated;
}

class GmailLegProposal {
  const GmailLegProposal({
    required this.externalId,
    required this.messageId,
    required this.fromAddress,
    required this.receivedAt,
    required this.kind,
    required this.passenger,
    required this.itineraryRef,
    required this.flightNumber,
    required this.fromIata,
    required this.toIata,
    required this.fromCountry,
    required this.toCountry,
    required this.depart,
    required this.arrive,
    required this.departTimezone,
    required this.arriveTimezone,
    required this.flags,
    required this.supersedesExternalId,
    required this.duplicate,
    required this.duplicateOf,
    required this.truncated,
  });

  final String externalId;
  final String messageId;
  final String fromAddress;
  final String receivedAt;
  final ReceiptKind kind;
  final String passenger;
  final String itineraryRef;
  final String flightNumber;
  final String fromIata;
  final String toIata;
  final String fromCountry;
  final String toCountry;
  final WallTime? depart;
  final WallTime? arrive;
  final String departTimezone;
  final String arriveTimezone;
  final List<String> flags;
  final String supersedesExternalId;
  final bool duplicate;
  final String duplicateOf;
  final bool truncated;
}

class GmailCancelProposal {
  const GmailCancelProposal({
    required this.messageId,
    required this.fromAddress,
    required this.receivedAt,
    required this.itineraryRef,
    required this.flightNumber,
    required this.targetExternalId,
    required this.blocked,
    required this.reason,
    required this.flags,
  });

  final String messageId;
  final String fromAddress;
  final String receivedAt;
  final String itineraryRef;
  final String flightNumber;
  final String targetExternalId;
  final bool blocked;
  final String reason;
  final List<String> flags;
}

class GmailImportPlan {
  const GmailImportPlan({
    required this.ownerId,
    required this.source,
    required this.legs,
    required this.cancellations,
    required this.withheld,
  });

  final String ownerId;
  final GmailPlanSource source;
  final List<GmailLegProposal> legs;
  final List<GmailCancelProposal> cancellations;

  /// Receipts that were cut short and not parsed into legs.
  final int withheld;
}

class LegCorrection {
  const LegCorrection({
    this.fromIata = '',
    this.toIata = '',
    this.fromCountry = '',
    this.toCountry = '',
    this.departTimezone = '',
    this.arriveTimezone = '',
  });

  final String fromIata;
  final String toIata;
  final String fromCountry;
  final String toCountry;
  final String departTimezone;
  final String arriveTimezone;
}

class ResolvedLeg {
  const ResolvedLeg({
    required this.proposal,
    required this.fromIata,
    required this.toIata,
    required this.fromCountry,
    required this.toCountry,
    required this.departTimezone,
    required this.arriveTimezone,
    required this.flags,
  });

  final GmailLegProposal proposal;
  final String fromIata;
  final String toIata;
  final String fromCountry;
  final String toCountry;
  final String departTimezone;
  final String arriveTimezone;
  final List<String> flags;

  bool get saveable {
    if (proposal.duplicate || proposal.truncated) return false;
    if (proposal.depart == null || proposal.arrive == null) return false;
    if (!RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(proposal.flightNumber)) {
      return false;
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(fromIata) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(toIata)) {
      return false;
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(fromCountry) ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(toCountry)) {
      return false;
    }
    if (!_zoneOk(departTimezone) || !_zoneOk(arriveTimezone)) return false;
    if (proposal.externalId.length > 80) return false;
    return flags.every((flag) => !blockingReceiptFlags.contains(flag));
  }
}

bool _zoneOk(String zone) =>
    zone.isNotEmpty && zone.length <= 64 && timezonePattern.hasMatch(zone);

const blockingReceiptFlags = <String>{
  'ambiguous_time',
  'ambiguous_from_airport',
  'ambiguous_to_airport',
  'unknown_depart_timezone',
  'unknown_arrive_timezone',
  'ambiguous_depart_timezone',
  'ambiguous_arrive_timezone',
  'unknown_from_country',
  'unknown_to_country',
  'truncated_receipt',
};

class GmailDraft {
  const GmailDraft({
    this.saveExternalIds = const <String>{},
    this.rejectExternalIds = const <String>{},
    this.corrections = const <String, LegCorrection>{},
    this.allowFictionalIntoConnected = false,
  });

  final Set<String> saveExternalIds;
  final Set<String> rejectExternalIds;
  final Map<String, LegCorrection> corrections;
  final bool allowFictionalIntoConnected;
}

class GmailMutations {
  const GmailMutations({
    this.create = const <FlightRecord>[],
    this.reject = const <FlightRecord>[],
    this.refusal,
  });

  const GmailMutations.refused(String this.refusal)
    : create = const <FlightRecord>[],
      reject = const <FlightRecord>[];

  final List<FlightRecord> create;
  final List<FlightRecord> reject;
  final String? refusal;
}

String receiptFlagLabel(String code) => switch (code) {
  'unknown_depart_timezone' || 'unknown_arrive_timezone' =>
    'A time zone is missing, so none was guessed.',
  'ambiguous_depart_timezone' || 'ambiguous_arrive_timezone' =>
    'A time zone was only an abbreviation or offset, so it was not used.',
  'ambiguous_time' => 'The clock time is missing or is not a single time.',
  'ambiguous_from_airport' || 'ambiguous_to_airport' =>
    'The airport is not a single three-letter code.',
  'unknown_from_country' || 'unknown_to_country' =>
    'That airport code is not in the country table.',
  'ambiguous_passenger' =>
    'More than one passenger is named, so none was chosen.',
  'ambiguous_reference' =>
    'More than one booking reference is present, so none was used to link versions.',
  'ambiguous_link' =>
    'More than one earlier flight matches, so none was linked.',
  'unlinked_cancellation' => 'No earlier flight matches this cancellation.',
  'accepted_unchanged' =>
    'The earlier flight is already accepted. This import does not change it.',
  'already_rejected' => 'The earlier flight is already rejected.',
  'not_saved_yet' =>
    'The earlier booking is only in this preview. Leave it unchecked and nothing is saved.',
  'no_earlier_version' =>
    'No earlier version of this booking is in your flights.',
  'truncated_receipt' => 'The receipt was cut short, so it was not imported.',
  'timezone_entered' => 'Time zone entered during review.',
  _ => 'This value needs a decision.',
};

String gmailExternalId(String messageId, int leg) {
  final clean = messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  final trimmed = clean.length > 60 ? clean.substring(0, 60) : clean;
  return 'g:$trimmed:$leg';
}

/// Strips tags so a script cannot contribute a flight number.
String receiptPlainText(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(
    RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(
    RegExp(r'</(p|div|tr|li|h[1-6]|table)>', caseSensitive: false),
    '\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"');
  return text;
}

ParsedReceipt parseReceipt(ReceiptMessage message) {
  if (message.truncated) {
    return ParsedReceipt(
      messageId: message.messageId,
      fromAddress: message.fromAddress,
      receivedAt: message.receivedAt,
      kind: ReceiptKind.booking,
      passenger: '',
      itineraryRef: '',
      legs: const [],
      previousLegs: const [],
      flags: const ['truncated_receipt'],
      ignored: true,
      truncated: true,
    );
  }
  final text = receiptPlainText(message.text);
  final lines = text.split('\n');
  final kind = _kind(text);
  final passenger = _passenger(lines);
  final reference = _reference(lines);
  final blocks = _blocks(lines);
  final sawCurrent = blocks.any((block) => block.region == 'current');
  final imported = sawCurrent
      ? blocks.where((block) => block.region == 'current')
      : blocks.where((block) => block.region != 'previous');
  final previous = blocks.where((block) => block.region == 'previous');
  final legs = imported.map(_legFrom).toList();
  final previousLegs = previous.map(_legFrom).toList();
  final flags = <String>[
    if (passenger.ambiguous) 'ambiguous_passenger',
    if (reference.ambiguous) 'ambiguous_reference',
  ];
  final hasSignal =
      legs.isNotEmpty ||
      previousLegs.isNotEmpty ||
      reference.value.isNotEmpty;
  return ParsedReceipt(
    messageId: message.messageId,
    fromAddress: message.fromAddress,
    receivedAt: message.receivedAt,
    kind: kind,
    passenger: passenger.ambiguous ? '' : passenger.value,
    itineraryRef: reference.ambiguous ? '' : reference.value,
    legs: legs,
    previousLegs: previousLegs,
    flags: flags,
    ignored: !hasSignal,
    truncated: false,
  );
}

GmailImportPlan planGmailImport({
  required List<ReceiptMessage> messages,
  required List<FlightRecord> existing,
  required String ownerId,
  required GmailPlanSource source,
}) {
  final parsed = messages.map(parseReceipt).toList()
    ..sort((a, b) {
      final byDate = a.receivedAt.compareTo(b.receivedAt);
      if (byDate != 0) return byDate;
      return a.messageId.compareTo(b.messageId);
    });
  final known = <_Known>[
    for (final flight in existing)
      _Known(
        externalId: flight.externalId,
        flightNumber: flight.flightNumber,
        fromIata: flight.fromIata,
        toIata: flight.toIata,
        departIso: flight.depart.iso,
        itineraryRef: flight.itineraryRef,
        review: flight.reviewState,
        stored: true,
      ),
  ];
  final legs = <GmailLegProposal>[];
  final cancellations = <GmailCancelProposal>[];
  var withheld = 0;
  for (final receipt in parsed) {
    if (receipt.truncated) {
      withheld += 1;
      continue;
    }
    if (receipt.ignored) continue;
    if (receipt.kind == ReceiptKind.cancellation) {
      cancellations.addAll(_cancellations(receipt, known));
      continue;
    }
    for (var index = 0; index < receipt.legs.length; index++) {
      final leg = receipt.legs[index];
      final externalId = gmailExternalId(receipt.messageId, index);
      final proposal = _proposeLeg(
        receipt: receipt,
        leg: leg,
        externalId: externalId,
        known: known,
      );
      legs.add(proposal);
      if (!proposal.duplicate) {
        known.add(
          _Known(
            externalId: externalId,
            flightNumber: leg.flightNumber,
            fromIata: leg.fromIata,
            toIata: leg.toIata,
            departIso: leg.depart?.iso ?? '',
            itineraryRef: receipt.itineraryRef,
            review: FlightReviewState.pending,
            stored: false,
          ),
        );
      }
    }
  }
  return GmailImportPlan(
    ownerId: ownerId,
    source: source,
    legs: legs,
    cancellations: cancellations,
    withheld: withheld,
  );
}

ResolvedLeg resolveLeg(GmailLegProposal leg, LegCorrection? correction) {
  var fromIata = leg.fromIata;
  var toIata = leg.toIata;
  var fromCountry = leg.fromCountry;
  var toCountry = leg.toCountry;
  var departTimezone = leg.departTimezone;
  var arriveTimezone = leg.arriveTimezone;
  final flags = [...leg.flags];
  if (correction != null) {
    if (correction.fromIata.trim().isNotEmpty) {
      fromIata = correction.fromIata.trim().toUpperCase();
    }
    if (correction.toIata.trim().isNotEmpty) {
      toIata = correction.toIata.trim().toUpperCase();
    }
    if (correction.fromCountry.trim().isNotEmpty) {
      fromCountry = correction.fromCountry.trim().toUpperCase();
    }
    if (correction.toCountry.trim().isNotEmpty) {
      toCountry = correction.toCountry.trim().toUpperCase();
    }
    if (correction.departTimezone.trim().isNotEmpty) {
      departTimezone = correction.departTimezone.trim();
    }
    if (correction.arriveTimezone.trim().isNotEmpty) {
      arriveTimezone = correction.arriveTimezone.trim();
    }
  }
  _applyAirport(
    code: fromIata,
    country: fromCountry,
    which: 'from',
    flags: flags,
    setCountry: (value) => fromCountry = value,
  );
  _applyAirport(
    code: toIata,
    country: toCountry,
    which: 'to',
    flags: flags,
    setCountry: (value) => toCountry = value,
  );
  if (_zoneOk(departTimezone)) {
    if (leg.departTimezone.isEmpty) flags.add('timezone_entered');
    flags.remove('unknown_depart_timezone');
    flags.remove('ambiguous_depart_timezone');
  }
  if (_zoneOk(arriveTimezone)) {
    if (leg.arriveTimezone.isEmpty) flags.add('timezone_entered');
    flags.remove('unknown_arrive_timezone');
    flags.remove('ambiguous_arrive_timezone');
  }
  return ResolvedLeg(
    proposal: leg,
    fromIata: fromIata,
    toIata: toIata,
    fromCountry: fromCountry,
    toCountry: toCountry,
    departTimezone: departTimezone,
    arriveTimezone: arriveTimezone,
    flags: flags,
  );
}

GmailMutations mutationsFor({
  required GmailImportPlan plan,
  required GmailDraft draft,
  required String sessionOwnerId,
  required GmailLinkState connection,
  required bool connectedDatabase,
  required List<FlightRecord> existing,
}) {
  if (plan.ownerId != sessionOwnerId) {
    return const GmailMutations.refused(
      'This preview is for a different account. Nothing was saved.',
    );
  }
  if (plan.source == GmailPlanSource.mailbox &&
      connection == GmailLinkState.revoked) {
    return const GmailMutations.refused(
      'Gmail access is revoked. Nothing was saved from the mailbox.',
    );
  }
  if (plan.source == GmailPlanSource.mailbox && !scanAllowed(connection)) {
    return const GmailMutations.refused(
      'Gmail is not connected. Nothing was saved from the mailbox.',
    );
  }
  if (plan.source == GmailPlanSource.fictional &&
      connectedDatabase &&
      !draft.allowFictionalIntoConnected) {
    return const GmailMutations.refused(
      'These receipts are fictional. Confirm before copying them into this database.',
    );
  }
  final create = <FlightRecord>[];
  final seen = <String>{};
  for (final externalId in draft.saveExternalIds) {
    if (!seen.add(externalId)) continue;
    GmailLegProposal? proposal;
    for (final leg in plan.legs) {
      if (leg.externalId == externalId) proposal = leg;
    }
    if (proposal == null || proposal.duplicate) continue;
    final resolved = resolveLeg(proposal, draft.corrections[externalId]);
    if (!resolved.saveable) continue;
    final flight = _flightFromResolved(resolved);
    if (flight.reviewState != FlightReviewState.pending) continue;
    if (flight.evidenceStatus != 'booking_only') continue;
    if (flight.inference != InferenceKind.none) continue;
    if (validateFlight(flight) != null) continue;
    if (existing.any((item) => item.externalId == flight.externalId)) {
      continue;
    }
    final key = _flightKey(flight);
    if (existing.any((item) => _flightKey(item) == key)) continue;
    create.add(flight);
  }
  final reject = <FlightRecord>[];
  for (final externalId in draft.rejectExternalIds) {
    GmailCancelProposal? cancel;
    for (final item in plan.cancellations) {
      if (!item.blocked && item.targetExternalId == externalId) cancel = item;
    }
    if (cancel == null) continue;
    FlightRecord? flight;
    for (final item in existing) {
      if (item.externalId == externalId) flight = item;
    }
    if (flight == null) continue;
    if (flight.reviewState == FlightReviewState.accepted) continue;
    if (flight.reviewState == FlightReviewState.rejected) continue;
    final extra =
        'Gmail cancellation. Message ${cancel.messageId}. From ${cancel.fromAddress}. Received ${cancel.receivedAt}. The booking was not treated as presence.';
    reject.add(
      flight.copyWith(
        reviewState: FlightReviewState.rejected,
        notes: _appendNote(flight.notes, extra),
      ),
    );
  }
  return GmailMutations(create: create, reject: reject);
}

String _flightKey(FlightRecord flight) =>
    '${flight.flightNumber}|${flight.fromIata}|${flight.toIata}|${flight.depart.iso}';

FlightRecord _flightFromResolved(ResolvedLeg leg) {
  final proposal = leg.proposal;
  final kind = proposal.kind == ReceiptKind.amendment ? 'amendment' : 'booking';
  return FlightRecord(
    id: '',
    flightNumber: proposal.flightNumber,
    fromIata: leg.fromIata,
    toIata: leg.toIata,
    fromCountry: leg.fromCountry,
    toCountry: leg.toCountry,
    depart: proposal.depart!,
    arrive: proposal.arrive!,
    departTimezone: leg.departTimezone,
    arriveTimezone: leg.arriveTimezone,
    evidenceStatus: 'booking_only',
    inference: InferenceKind.none,
    reviewState: FlightReviewState.pending,
    notes: _notes(leg, kind),
    externalId: proposal.externalId,
    gmailMessageId: _clip(proposal.messageId, 64),
    gmailFrom: _clip(proposal.fromAddress, 200),
    gmailDate: _clip(proposal.receivedAt, 40),
    itineraryRef: _clip(proposal.itineraryRef, 16),
    passengerName: _clip(proposal.passenger, 120),
    supersedesExternalId: _clip(proposal.supersedesExternalId, 80),
    receiptKind: kind,
  );
}

String _notes(ResolvedLeg leg, String kind) {
  final proposal = leg.proposal;
  final parts = <String>[
    'Gmail $kind. Planned travel, not presence.',
    'Message ${proposal.messageId}.',
    if (proposal.fromAddress.isNotEmpty) 'From ${proposal.fromAddress}.',
    if (proposal.receivedAt.isNotEmpty) 'Received ${proposal.receivedAt}.',
    if (proposal.itineraryRef.isNotEmpty) 'Reference ${proposal.itineraryRef}.',
    if (proposal.passenger.isNotEmpty) 'Passenger ${proposal.passenger}.',
    if (proposal.supersedesExternalId.isNotEmpty)
      'Supersedes ${proposal.supersedesExternalId}.',
    if (leg.flags.contains('timezone_entered'))
      'Time zone entered during review.',
  ];
  return _clip(parts.join(' '), 2000);
}

String _appendNote(String notes, String extra) {
  final next = notes.trim().isEmpty ? extra : '${notes.trim()} $extra';
  return next.length > 2000 ? notes : next;
}

String _clip(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

void _applyAirport({
  required String code,
  required String country,
  required String which,
  required List<String> flags,
  required void Function(String value) setCountry,
}) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return;
  flags.remove('ambiguous_${which}_airport');
  final lookedUp = airportCountry(code);
  if (country.isEmpty && lookedUp != null) setCountry(lookedUp);
  if (country.isNotEmpty || lookedUp != null) {
    flags.remove('unknown_${which}_country');
  }
}

class _Known {
  const _Known({
    required this.externalId,
    required this.flightNumber,
    required this.fromIata,
    required this.toIata,
    required this.departIso,
    required this.itineraryRef,
    required this.review,
    required this.stored,
  });

  final String externalId;
  final String flightNumber;
  final String fromIata;
  final String toIata;
  final String departIso;
  final String itineraryRef;
  final FlightReviewState? review;

  /// False when the row exists only as a proposal in this preview.
  final bool stored;
}

GmailLegProposal _proposeLeg({
  required ParsedReceipt receipt,
  required ParsedLeg leg,
  required String externalId,
  required List<_Known> known,
}) {
  final departIso = leg.depart?.iso ?? '';
  final key = departIso.isEmpty
      ? ''
      : '${leg.flightNumber}|${leg.fromIata}|${leg.toIata}|$departIso';
  var duplicate = false;
  var duplicateOf = '';
  for (final item in known) {
    if (item.externalId.isNotEmpty && item.externalId == externalId) {
      duplicate = true;
      duplicateOf = item.externalId;
      break;
    }
  }
  if (!duplicate && key.isNotEmpty) {
    for (final item in known) {
      final itemKey =
          '${item.flightNumber}|${item.fromIata}|${item.toIata}|${item.departIso}';
      if (item.departIso.isNotEmpty && itemKey == key) {
        duplicate = true;
        duplicateOf = item.externalId;
        break;
      }
    }
  }
  final flags = <String>[...receipt.flags, ...leg.flags];
  var supersedes = '';
  if (receipt.kind == ReceiptKind.amendment && !duplicate) {
    final link = _linkAmendment(receipt, leg, known);
    supersedes = link.externalId;
    if (link.flag.isNotEmpty) flags.add(link.flag);
  }
  return GmailLegProposal(
    externalId: externalId,
    messageId: receipt.messageId,
    fromAddress: receipt.fromAddress,
    receivedAt: receipt.receivedAt,
    kind: receipt.kind,
    passenger: receipt.passenger,
    itineraryRef: receipt.itineraryRef,
    flightNumber: leg.flightNumber,
    fromIata: leg.fromIata,
    toIata: leg.toIata,
    fromCountry: leg.fromCountry,
    toCountry: leg.toCountry,
    depart: leg.depart,
    arrive: leg.arrive,
    departTimezone: leg.departTimezone,
    arriveTimezone: leg.arriveTimezone,
    flags: flags,
    supersedesExternalId: supersedes,
    duplicate: duplicate,
    duplicateOf: duplicateOf,
    truncated: false,
  );
}

({String externalId, String flag}) _linkAmendment(
  ParsedReceipt receipt,
  ParsedLeg leg,
  List<_Known> known,
) {
  final pool = known.where((item) => item.flightNumber == leg.flightNumber);
  final previousTimes = receipt.previousLegs
      .where((item) => item.flightNumber == leg.flightNumber && item.depart != null)
      .map((item) => item.depart!.iso)
      .toSet();
  final byPrevious = pool
      .where((item) => previousTimes.contains(item.departIso))
      .toList();
  if (byPrevious.length == 1) {
    return (externalId: byPrevious.single.externalId, flag: '');
  }
  if (byPrevious.length > 1) {
    return (externalId: '', flag: 'ambiguous_link');
  }
  final byRef = receipt.itineraryRef.isEmpty
      ? <_Known>[]
      : pool
            .where(
              (item) =>
                  item.itineraryRef == receipt.itineraryRef &&
                  item.departIso != (leg.depart?.iso ?? ''),
            )
            .toList();
  if (byRef.length == 1) {
    return (externalId: byRef.single.externalId, flag: '');
  }
  if (byRef.length > 1) {
    return (externalId: '', flag: 'ambiguous_link');
  }
  return (externalId: '', flag: 'no_earlier_version');
}

List<GmailCancelProposal> _cancellations(
  ParsedReceipt receipt,
  List<_Known> known,
) {
  final numbers = <String>{
    for (final leg in receipt.legs) leg.flightNumber,
    for (final leg in receipt.previousLegs) leg.flightNumber,
  }..removeWhere((number) => number.isEmpty);
  var pool = known.toList();
  if (receipt.itineraryRef.isNotEmpty) {
    pool = pool
        .where((item) => item.itineraryRef == receipt.itineraryRef)
        .toList();
  }
  if (numbers.isNotEmpty) {
    final byNumber = pool
        .where((item) => numbers.contains(item.flightNumber))
        .toList();
    if (byNumber.isNotEmpty) {
      pool = byNumber;
    } else if (receipt.itineraryRef.isNotEmpty) {
      pool = [];
    } else {
      pool = known
          .where((item) => numbers.contains(item.flightNumber))
          .toList();
    }
  }
  GmailCancelProposal blocked(String reason, String flag, {String target = ''}) {
    return GmailCancelProposal(
      messageId: receipt.messageId,
      fromAddress: receipt.fromAddress,
      receivedAt: receipt.receivedAt,
      itineraryRef: receipt.itineraryRef,
      flightNumber: numbers.length == 1 ? numbers.single : '',
      targetExternalId: target,
      blocked: true,
      reason: reason,
      flags: [...receipt.flags, flag],
    );
  }

  if (pool.isEmpty) {
    return [
      blocked(
        'No earlier flight matches this cancellation.',
        'unlinked_cancellation',
      ),
    ];
  }
  final oneNumber = pool.map((item) => item.flightNumber).toSet().length == 1;
  if (pool.length > 1 && (numbers.isEmpty || oneNumber)) {
    return [
      blocked(
        'More than one earlier flight matches, so none was linked.',
        'ambiguous_link',
      ),
    ];
  }
  return [
    for (final target in pool)
      if (!target.stored)
        blocked(
          'The earlier booking is only in this preview. Leave it unchecked and nothing is saved.',
          'not_saved_yet',
        )
      else if (target.review == FlightReviewState.accepted)
        blocked(
          'The earlier flight is already accepted. This import does not change it.',
          'accepted_unchanged',
          target: target.externalId,
        )
      else if (target.review == FlightReviewState.rejected)
        blocked(
          'The earlier flight is already rejected.',
          'already_rejected',
          target: target.externalId,
        )
      else
        GmailCancelProposal(
          messageId: receipt.messageId,
          fromAddress: receipt.fromAddress,
          receivedAt: receipt.receivedAt,
          itineraryRef: receipt.itineraryRef,
          flightNumber: target.flightNumber,
          targetExternalId: target.externalId,
          blocked: false,
          reason:
              'Reject the earlier pending flight ${target.flightNumber}. It stays until you check this.',
          flags: [...receipt.flags],
        ),
  ];
}

class _Block {
  _Block(this.region, this.flightNumber);

  final String region;
  final String flightNumber;
  final List<String> lines = <String>[];
}

final _previousHeader = RegExp(
  r'^(previous|original|old itinerary)\b',
  caseSensitive: false,
);
final _currentHeader = RegExp(
  r'^(now|new itinerary|updated|current)\b',
  caseSensitive: false,
);
final _flightLine = RegExp(
  r'\bflight\s*:?\s*((?:[A-Z]{2}|[A-Z]\d|\d[A-Z])\s?\d{1,4})\b',
  caseSensitive: false,
);

List<_Block> _blocks(List<String> lines) {
  final blocks = <_Block>[];
  var region = 'preamble';
  _Block? current;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_previousHeader.hasMatch(line)) {
      region = 'previous';
      current = null;
      continue;
    }
    if (_currentHeader.hasMatch(line)) {
      region = 'current';
      current = null;
      continue;
    }
    final flight = _flightLine.firstMatch(line);
    if (flight != null) {
      final number = flight.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      current = _Block(region, number)..lines.add(line);
      blocks.add(current);
      continue;
    }
    current?.lines.add(line);
  }
  return blocks;
}

ParsedLeg _legFrom(_Block block) {
  final leg = ParsedLeg(flightNumber: block.flightNumber);
  for (final line in block.lines) {
    final lower = line.toLowerCase();
    if (RegExp(r'^(depart|departure)\b').hasMatch(lower)) {
      _applyEndpoint(leg, line, departure: true);
    } else if (RegExp(r'^(arrive|arrival)\b').hasMatch(lower)) {
      _applyEndpoint(leg, line, departure: false);
    } else if (RegExp(r'^from\b').hasMatch(lower)) {
      _applyOneAirport(leg, line.replaceFirst(RegExp(r'^from\s*:?\s*', caseSensitive: false), ''), from: true);
    } else if (RegExp(r'^to\b').hasMatch(lower)) {
      _applyOneAirport(leg, line.replaceFirst(RegExp(r'^to\s*:?\s*', caseSensitive: false), ''), from: false);
    } else {
      final route = RegExp(
        r'^(.+?)\s+(?:to|→|–|—|-)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (route != null && !RegExp(r'\d{1,2}:\d{2}').hasMatch(line)) {
        _applyOneAirport(leg, route.group(1)!, from: true);
        _applyOneAirport(leg, route.group(2)!, from: false);
      }
    }
  }
  _fillCountry(leg);
  return leg;
}

void _applyEndpoint(ParsedLeg leg, String line, {required bool departure}) {
  final end = departure ? 'depart' : 'arrive';
  final lower = line.toLowerCase();
  if (RegExp(r'\b(morning|afternoon|evening|night|noon)\b').hasMatch(lower)) {
    leg.flags.add('ambiguous_time');
  } else {
    final clocks = RegExp(
      r'\b(\d{1,2}):(\d{2})(?:\s*([AP]M))?\b',
      caseSensitive: false,
    ).allMatches(line).toList();
    if (clocks.length != 1) {
      leg.flags.add('ambiguous_time');
    } else {
      final date = _dateOn(line);
      if (date == null) {
        leg.flags.add('ambiguous_time');
      } else {
        var hour = int.parse(clocks.single.group(1)!);
        final minute = int.parse(clocks.single.group(2)!);
        final ap = clocks.single.group(3)?.toUpperCase();
        if (ap == 'PM' && hour < 12) hour += 12;
        if (ap == 'AM' && hour == 12) hour = 0;
        if (hour > 23 || minute > 59) {
          leg.flags.add('ambiguous_time');
        } else if (departure) {
          leg.depart = WallTime(date: date, hour: hour, minute: minute);
        } else {
          leg.arrive = WallTime(date: date, hour: hour, minute: minute);
        }
      }
    }
  }
  final iana = RegExp(
    r'\b([A-Za-z]{2,}(?:/[A-Za-z0-9._+-]+)+)\b',
  ).firstMatch(line);
  if (iana != null && timezonePattern.hasMatch(iana.group(1)!)) {
    if (departure) {
      leg.departTimezone = iana.group(1)!;
    } else {
      leg.arriveTimezone = iana.group(1)!;
    }
    return;
  }
  final abbrev = RegExp(
    r'\b(UTC|GMT|EST|EDT|CST|CDT|PST|PDT|CET|CEST|JST|KST|HKT|IST|BST|MSK|AEST|AEDT)\b',
    caseSensitive: false,
  );
  final offset = RegExp(
    r'\b(?:UTC|GMT)\s*[+-]\s*\d{1,2}\b',
    caseSensitive: false,
  );
  if (abbrev.hasMatch(line) || offset.hasMatch(line)) {
    leg.flags.add('ambiguous_${end}_timezone');
    return;
  }
  leg.flags.add('unknown_${end}_timezone');
}

void _applyOneAirport(ParsedLeg leg, String fragment, {required bool from}) {
  final orCodes = RegExp(r'\(([A-Z]{3})\s*(?:or|/)\s*([A-Z]{3})\)');
  if (orCodes.hasMatch(fragment)) {
    leg.flags.add(from ? 'ambiguous_from_airport' : 'ambiguous_to_airport');
    return;
  }
  final codes = RegExp(
    r'\(([A-Z]{3})\)',
  ).allMatches(fragment).map((match) => match.group(1)!).toList();
  if (codes.length > 1) {
    leg.flags.add(from ? 'ambiguous_from_airport' : 'ambiguous_to_airport');
    return;
  }
  if (codes.length == 1) {
    if (from) {
      leg.fromIata = codes.single;
    } else {
      leg.toIata = codes.single;
    }
    return;
  }
  final bare = fragment.trim().toUpperCase();
  if (RegExp(r'^[A-Z]{3}$').hasMatch(bare)) {
    if (from) {
      leg.fromIata = bare;
    } else {
      leg.toIata = bare;
    }
    return;
  }
  if (RegExp(r'[A-Za-z]').hasMatch(fragment)) {
    leg.flags.add(from ? 'ambiguous_from_airport' : 'ambiguous_to_airport');
  }
}

void _fillCountry(ParsedLeg leg) {
  if (leg.fromIata.isNotEmpty) {
    final country = airportCountry(leg.fromIata);
    if (country == null) {
      leg.flags.add('unknown_from_country');
    } else {
      leg.fromCountry = country;
    }
  }
  if (leg.toIata.isNotEmpty) {
    final country = airportCountry(leg.toIata);
    if (country == null) {
      leg.flags.add('unknown_to_country');
    } else {
      leg.toCountry = country;
    }
  }
}

const _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

LocalDate? _dateOn(String line) {
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(line);
  if (iso != null) {
    return LocalDate.tryParse(
      '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}',
    );
  }
  final named = RegExp(
    r'\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{4})\b',
    caseSensitive: false,
  ).firstMatch(line);
  if (named == null) return null;
  final month = _months[named.group(2)!.substring(0, 3).toLowerCase()];
  if (month == null) return null;
  try {
    return LocalDate(int.parse(named.group(3)!), month, int.parse(named.group(1)!));
  } on ArgumentError {
    return null;
  }
}

ReceiptKind _kind(String text) {
  for (final raw in text.split('\n')) {
    final line = raw.toLowerCase();
    if (line.contains('cancellation policy')) continue;
    if (line.contains('not cancelled') || line.contains('not canceled')) {
      continue;
    }
    if (RegExp(r'\bcancell?ed\b').hasMatch(line) ||
        RegExp(r'\bcancellation\b').hasMatch(line)) {
      return ReceiptKind.cancellation;
    }
  }
  final all = text.toLowerCase();
  if (all.contains('schedule change') ||
      all.contains('has been changed') ||
      all.contains('itinerary change') ||
      all.contains('rebooked') ||
      all.contains('revised itinerary') ||
      RegExp(r'\bamended\b').hasMatch(all)) {
    return ReceiptKind.amendment;
  }
  return ReceiptKind.booking;
}

({String value, bool ambiguous}) _passenger(List<String> lines) {
  final names = <String>[];
  var ambiguous = false;
  for (final raw in lines) {
    final match = RegExp(
      r'^passengers?\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.contains(',') ||
        RegExp(r'\band\b', caseSensitive: false).hasMatch(value)) {
      ambiguous = true;
    }
    names.add(value);
  }
  final unique = names.toSet();
  if (unique.length != 1 || ambiguous) {
    return (value: '', ambiguous: unique.isNotEmpty);
  }
  final name = unique.single;
  return (value: name.length > 120 ? name.substring(0, 120) : name, ambiguous: false);
}

({String value, bool ambiguous}) _reference(List<String> lines) {
  final refs = <String>[];
  for (final raw in lines) {
    final match = RegExp(
      r'^(?:booking reference|record locator|confirmation code|pnr)\s*:\s*([A-Za-z0-9]{5,8})\b',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) continue;
    refs.add(match.group(1)!.toUpperCase());
  }
  final unique = refs.toSet();
  if (unique.length != 1) {
    return (value: '', ambiguous: unique.isNotEmpty);
  }
  return (value: unique.single, ambiguous: false);
}
