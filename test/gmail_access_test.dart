import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/engine/gmail_access.dart';

void main() {
  test('vault secrets fail closed', () {
    expect(vaultSecretsMatch('', 'secret'), isFalse);
    expect(vaultSecretsMatch('secret', ''), isFalse);
    expect(vaultSecretsMatch('secret', 'secreT'), isFalse);
    expect(vaultSecretsMatch('secret', 'secret'), isTrue);
    expect(
      authorizeVault(
        expectedSecret: '',
        presentedSecret: 'secret',
        authId: 'owner-a',
        authRequired: true,
      ).status,
      403,
    );
    expect(
      authorizeVault(
        expectedSecret: 'secret',
        presentedSecret: 'nope',
        authId: 'owner-a',
        authRequired: true,
      ).status,
      403,
    );
  });

  test('another owner cannot read or write the vault row', () {
    final denied = authorizeVault(
      expectedSecret: 'secret',
      presentedSecret: 'secret',
      authId: 'owner-b',
      authRequired: true,
      recordUserId: 'owner-a',
    );
    expect(denied.ok, isFalse);
    expect(denied.status, 404);

    final missing = authorizeVault(
      expectedSecret: 'secret',
      presentedSecret: 'secret',
      authId: '',
      authRequired: true,
    );
    expect(missing.status, 401);

    expect(vaultWriteOwner('owner-a'), 'owner-a');
    expect(vaultWriteOwner('owner-a'), isNot('owner-b'));

    final visible = recordsForOwner<String>('owner-b', [
      (userId: 'owner-a', value: 'ciphertext-a'),
      (userId: 'owner-b', value: 'ciphertext-b'),
    ]);
    expect(visible, ['ciphertext-b']);
  });

  test('revoked and disconnected links cannot scan', () {
    expect(scanAllowed(GmailLinkState.connected), isTrue);
    expect(scanAllowed(GmailLinkState.revoked), isFalse);
    expect(scanAllowed(GmailLinkState.disconnected), isFalse);
    expect(scanAllowed(GmailLinkState.missing), isFalse);
    expect(mailboxReadBlock(GmailLinkState.revoked), contains('revoked'));
    expect(mailboxReadBlock(GmailLinkState.disconnected), contains('not connected'));
    expect(mailboxReadBlock(GmailLinkState.connected), isNull);
  });

  test('only the read-only Gmail scope is accepted', () {
    expect(scopeAllowed(gmailReadonlyScope), isTrue);
    expect(
      scopeAllowed('$gmailReadonlyScope https://mail.google.com/'),
      isFalse,
    );
    expect(
      scopeAllowed('https://www.googleapis.com/auth/gmail.modify'),
      isFalse,
    );
    expect(scopeAllowed(''), isFalse);
  });

  test('return origins stay on this app', () {
    expect(
      returnOriginAllowed('https://nomad-taupe-omega.vercel.app'),
      isTrue,
    );
    expect(
      returnOriginAllowed(
        'https://nomad-taupe-omega-git-cursor-gmail-receipt-import-92da-team.vercel.app',
      ),
      isTrue,
    );
    expect(returnOriginAllowed('http://127.0.0.1:43123'), isTrue);
    expect(returnOriginAllowed('http://localhost:43123'), isTrue);
    expect(returnOriginAllowed('https://evil.example'), isFalse);
    expect(returnOriginAllowed('https://nomad-taupe-omega.vercel.app.evil.com'), isFalse);
    expect(
      returnOriginAllowed('https://nomad-taupe-omega.vercel.app/steal'),
      isFalse,
    );
    expect(
      returnOriginAllowed('https://other-project.vercel.app'),
      isFalse,
    );
    expect(
      returnOriginAllowed('https://nomad-taupe-omega.vercel.app/?gmail=connected'),
      isFalse,
    );
  });
}
