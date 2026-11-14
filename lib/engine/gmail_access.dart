/// Read-only Gmail scope. Modify, send, and full-mailbox scopes are refused.
const gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

const defaultPublicOrigin = 'https://nomad-taupe-omega.vercel.app';

enum GmailLinkState { missing, connected, revoked, disconnected }

GmailLinkState gmailLinkState(String raw) {
  for (final state in GmailLinkState.values) {
    if (state.name == raw) return state;
  }
  return GmailLinkState.missing;
}

/// A mailbox read is allowed only while the link is connected.
bool scanAllowed(GmailLinkState state) => state == GmailLinkState.connected;

/// Why a mailbox read must not start. Null when it may.
String? mailboxReadBlock(GmailLinkState state) {
  if (state == GmailLinkState.revoked) {
    return 'Gmail access is revoked. No mailbox was read.';
  }
  if (state != GmailLinkState.connected) {
    return 'Gmail is not connected. No mailbox was read.';
  }
  return null;
}

bool scopeAllowed(String scope) {
  final parts = scope
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.length == 1 && parts.single == gmailReadonlyScope;
}

/// Constant-time comparison. An empty expected secret never matches.
bool vaultSecretsMatch(String expected, String presented) {
  if (expected.isEmpty || presented.isEmpty) return false;
  if (expected.length != presented.length) return false;
  var mismatch = 0;
  for (var i = 0; i < expected.length; i++) {
    mismatch |= expected.codeUnitAt(i) ^ presented.codeUnitAt(i);
  }
  return mismatch == 0;
}

class VaultDecision {
  const VaultDecision({required this.ok, required this.status});

  final bool ok;
  final int status;
}

/// Vault gate shared by the client checks and the PocketBase hook.
///
/// A record whose user is not [authId] is not found. The body of a request
/// cannot name a different user: [vaultWriteOwner] is the signed-in id.
VaultDecision authorizeVault({
  required String expectedSecret,
  required String presentedSecret,
  required String authId,
  required bool authRequired,
  String recordUserId = '',
}) {
  if (!vaultSecretsMatch(expectedSecret, presentedSecret)) {
    return const VaultDecision(ok: false, status: 403);
  }
  if (authRequired && authId.isEmpty) {
    return const VaultDecision(ok: false, status: 401);
  }
  if (recordUserId.isNotEmpty && recordUserId != authId) {
    return const VaultDecision(ok: false, status: 404);
  }
  return const VaultDecision(ok: true, status: 200);
}

String vaultWriteOwner(String authId) => authId;

List<T> recordsForOwner<T>(
  String authId,
  List<({String userId, T value})> rows,
) {
  return [for (final row in rows) if (row.userId == authId) row.value];
}

/// Origins that may receive the browser after Google redirects.
///
/// Google's redirect URI is the broker callback. [origin] is only the
/// Nomadic Residence page the person started from.
bool returnOriginAllowed(
  String origin, {
  String publicOrigin = defaultPublicOrigin,
}) {
  final uri = Uri.tryParse(origin);
  if (uri == null) return false;
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return false;
  if (uri.path.isNotEmpty && uri.path != '/') return false;
  if (uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
    return true;
  }
  if (uri.scheme != 'https') return false;
  final pub = Uri.tryParse(publicOrigin);
  if (pub == null || pub.host.isEmpty) return false;
  if (uri.host == pub.host) return true;
  if (!uri.host.endsWith('.vercel.app') || !pub.host.endsWith('.vercel.app')) {
    return false;
  }
  final prefix = pub.host.substring(0, pub.host.length - '.vercel.app'.length);
  return uri.host.startsWith('$prefix-');
}
