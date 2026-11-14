import 'gmail_receipts.dart';

/// Fictional receipts. None of these are from a mailbox.
List<ReceiptMessage> fictionalGmailReceipts() => <ReceiptMessage>[
  airCanadaReceipt(),
  evaReceipt(),
  asianaReceipt(),
  unitedReceipt(),
  tripComReceipt(),
  lotBookingReceipt(),
  lotAmendmentReceipt(),
  shenzhenBookingReceipt(),
  shenzhenCancellationReceipt(),
  ambiguousReceipt(),
];

ReceiptMessage airCanadaReceipt() => const ReceiptMessage(
  messageId: 'ac-msg-001',
  fromAddress: 'tickets@aircanada.example',
  receivedAt: '2026-02-01T15:00:00Z',
  text: '''
Air Canada booking confirmation
Booking reference: AB12CD
Passenger: Jordan Example

Flight AC123
From: Toronto (YYZ)
To: London (LHR)
Depart: 02 Mar 2026 18:40 America/Toronto
Arrive: 03 Mar 2026 06:55 Europe/London
''',
);

ReceiptMessage evaReceipt() => const ReceiptMessage(
  messageId: 'br-msg-001',
  fromAddress: 'eticket@evaair.example',
  receivedAt: '2026-05-01T09:00:00Z',
  text: '''
EVA Air e-ticket
Record locator: EVA8891
Passenger: Jordan Example

Flight BR 12
Taipei (TPE) to San Francisco (SFO)
Depart: 15 Jun 2026 23:40 Asia/Taipei
Arrive: 15 Jun 2026 19:10 America/Los_Angeles
''',
);

ReceiptMessage asianaReceipt() => const ReceiptMessage(
  messageId: 'oz-msg-001',
  fromAddress: 'receipts@flyasiana.example',
  receivedAt: '2026-06-02T11:00:00Z',
  text: '''
Asiana Airlines itinerary
Confirmation code: OZ4410
Passenger: Jordan Example

Flight OZ 204
Seoul (ICN) → Los Angeles (LAX)
Departure: 2026-07-01 14:20 Asia/Seoul
Arrival: 2026-07-01 10:05 America/Los_Angeles
''',
);

ReceiptMessage unitedReceipt() => const ReceiptMessage(
  messageId: 'ua-msg-001',
  fromAddress: 'confirmations@united.example',
  receivedAt: '2026-07-04T16:00:00Z',
  text: '''
United Airlines flight confirmation
Confirmation code: UA77HK
Passenger: Jordan Example

Flight UA 837
Newark (EWR) to London (LHR)
Depart: 2026-08-09 19:15 America/New_York
Arrive: 2026-08-10 07:25 Europe/London
''',
);

ReceiptMessage tripComReceipt() => const ReceiptMessage(
  messageId: 'trip-msg-001',
  fromAddress: 'noreply@trip.example',
  receivedAt: '2026-08-01T08:00:00Z',
  text: '''
Trip.com booking confirmation
Booking reference: TRP5521
Passenger: Jordan Example

Flight LO 26
Warsaw (WAW) - Frankfurt (FRA)
Depart: 2026-09-03 08:10 Europe/Warsaw
Arrive: 2026-09-03 10:00 Europe/Berlin

Flight ZH 9042
Frankfurt (FRA) - Shenzhen (SZX)
Depart: 2026-09-03 13:40
Arrive: 2026-09-04 06:10
''',
);

ReceiptMessage lotBookingReceipt() => const ReceiptMessage(
  messageId: 'lot-msg-001',
  fromAddress: 'booking@lot.example',
  receivedAt: '2026-03-01T10:00:00Z',
  text: '''
LOT Polish Airlines booking confirmation
Booking reference: LOT88X
Passenger: Jordan Example

Flight LO 12
Warsaw (WAW) to New York (JFK)
Depart: 04 Apr 2026 10:15 Europe/Warsaw
Arrive: 04 Apr 2026 14:05 America/New_York
''',
);

ReceiptMessage lotAmendmentReceipt() => const ReceiptMessage(
  messageId: 'lot-msg-002',
  fromAddress: 'booking@lot.example',
  receivedAt: '2026-03-20T10:00:00Z',
  text: '''
LOT Polish Airlines schedule change
Booking reference: LOT88X
Passenger: Jordan Example

Previous
Flight LO 12
Warsaw (WAW) to New York (JFK)
Depart: 04 Apr 2026 10:15 Europe/Warsaw
Arrive: 04 Apr 2026 14:05 America/New_York

Now
Flight LO 12
Warsaw (WAW) to New York (JFK)
Depart: 04 Apr 2026 16:40 Europe/Warsaw
Arrive: 04 Apr 2026 20:10 America/New_York
''',
);

ReceiptMessage shenzhenBookingReceipt() => const ReceiptMessage(
  messageId: 'zh-msg-001',
  fromAddress: 'eticket@shenzhenair.example',
  receivedAt: '2026-04-01T12:00:00Z',
  text: '''
Shenzhen Airlines booking confirmation
Booking reference: SZX190
Passenger: Jordan Example

Flight ZH 9001
Shenzhen (SZX) to Bangkok (BKK)
Depart: 02 May 2026 09:20 Asia/Shanghai
Arrive: 02 May 2026 11:30 Asia/Bangkok
''',
);

ReceiptMessage shenzhenCancellationReceipt() => const ReceiptMessage(
  messageId: 'zh-msg-002',
  fromAddress: 'eticket@shenzhenair.example',
  receivedAt: '2026-04-15T12:00:00Z',
  text: '''
Shenzhen Airlines cancellation
Booking reference: SZX190
Passenger: Jordan Example

Your flight has been cancelled.
Flight ZH 9001
Shenzhen (SZX) to Bangkok (BKK)
''',
);

ReceiptMessage ambiguousReceipt() => const ReceiptMessage(
  messageId: 'amb-msg-001',
  fromAddress: 'noreply@trip.example',
  receivedAt: '2026-04-20T12:00:00Z',
  text: '''
Trip.com itinerary
Booking reference: AMBIG1
Passenger: Jordan Example
Passenger: Casey Example

Flight CA 1234
From: Shenzhen
To: Shanghai (PVG or SHA)
Depart: 11 May 2026 morning
Arrive: 11 May 2026 11:40 CST
''',
);

ReceiptMessage unitedAbbreviationReceipt() => const ReceiptMessage(
  messageId: 'ua-msg-est',
  fromAddress: 'confirmations@united.example',
  receivedAt: '2026-07-05T16:00:00Z',
  text: '''
United Airlines flight confirmation
Confirmation code: UAEST1
Passenger: Jordan Example

Flight UA 900
Newark (EWR) to London (LHR)
Depart: 2026-08-11 19:15 EST
Arrive: 2026-08-12 07:25 GMT
''',
);

ReceiptMessage htmlScriptReceipt() => const ReceiptMessage(
  messageId: 'html-msg-001',
  fromAddress: 'tickets@aircanada.example',
  receivedAt: '2026-02-02T15:00:00Z',
  text: '''
<html><body>
<script>Flight ZZ9999 From: Toronto (YYZ) To: London (LHR)</script>
<p>Air Canada booking confirmation</p>
<p>Booking reference: HTML01</p>
<p>Passenger: Jordan Example</p>
<p>Flight AC456</p>
<p>From: Montreal (YUL)</p>
<p>To: Paris (CDG)</p>
<p>Depart: 10 Mar 2026 09:00 America/Toronto</p>
<p>Arrive: 10 Mar 2026 21:10 Europe/Paris</p>
</body></html>
''',
);
