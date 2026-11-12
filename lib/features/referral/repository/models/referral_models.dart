/// Ajak Teman (referral) + Koin payloads, read from the referral RPCs
/// (`get_referral_dashboard`, `open_referral_pack`, `get_koin_balance`, …).
///
/// Hand-written like `BuyerActionCounts.fromJson`: wrong-typed fields read as
/// empty rather than throwing, since the RPCs return jsonb.
library;

int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
String? _str(Object? v) => v is String ? v : null;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map _map(Object? v) => v is Map ? v : const {};
List _list(Object? v) => v is List ? v : const [];

/// Server-side RPC failure carried inside the JSON (`{"error": code}` or
/// `ok:false` + `reason`), not as an HTTP error.
class ReferralException implements Exception {
  const ReferralException(this.code);

  final String code;

  String get message => switch (code) {
    'pack_held' => 'Pack ini menunggu verifikasi.',
    'pack_void' => 'Pack ini tidak memenuhi syarat.',
    'pack_not_found' => 'Pack tidak ditemukan.',
    'unauthorized' => 'Masuk dulu, ya.',
    'username_required' => 'Atur username dulu untuk dapat kode referal.',
    _ => 'Terjadi kesalahan. Coba lagi.',
  };

  @override
  String toString() => 'ReferralException($code)';
}

/// Throws [ReferralException] when an RPC payload carries `error`.
Map<String, dynamic> referralPayload(Object? raw) {
  if (raw is! Map) throw const ReferralException('bad_response');
  final error = raw['error'];
  if (error is String) throw ReferralException(error);
  return Map<String, dynamic>.from(raw);
}

/// Tier keys as the server and assets spell them (the prototype's `umum` is
/// the server's `biasa`).
enum ReferralTierKey {
  biasa('Biasa'),
  spesial('Spesial'),
  langka('Langka'),
  jackpot('Jackpot');

  const ReferralTierKey(this.label);
  final String label;

  static ReferralTierKey? fromRaw(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

class ReferralTier {
  const ReferralTier({
    required this.key,
    required this.odds,
    required this.amount,
    required this.pool,
  });

  final ReferralTierKey key;

  /// Percent; SQL `numeric`, so it may be fractional.
  final num odds;
  final int amount;
  final List<String> pool;

  static ReferralTier? fromJson(Object? raw) {
    final m = _map(raw);
    final key = ReferralTierKey.fromRaw(m['key']);
    if (key == null) return null;
    return ReferralTier(
      key: key,
      odds: m['odds'] is num ? m['odds'] as num : 0,
      amount: _int(m['amount']),
      pool: _list(m['pool']).whereType<String>().toList(),
    );
  }

  /// Largest prize first, the order every display uses.
  static List<ReferralTier> listFromJson(Object? raw) =>
      _list(raw).map(fromJson).whereType<ReferralTier>().toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
}

enum ReferralFriendStatus {
  registered,
  firstOrderPaid,
  firstOrderShipped,
  completed,
  expired,
  voided;

  static ReferralFriendStatus fromRaw(Object? raw) => switch (raw) {
    'registered' => registered,
    'first_order_paid' => firstOrderPaid,
    'first_order_shipped' => firstOrderShipped,
    'completed' => completed,
    'expired' => expired,
    _ => voided,
  };
}

enum ReferralPackStatus {
  ready,
  held,
  opened,
  voided;

  static ReferralPackStatus fromRaw(Object? raw) => switch (raw) {
    'ready' => ready,
    'held' => held,
    'opened' => opened,
    _ => voided,
  };
}

class ReferralFriendPack {
  const ReferralFriendPack({
    required this.id,
    required this.status,
    this.tier,
    this.character,
    this.amount,
  });

  final String id;
  final ReferralPackStatus status;
  final ReferralTierKey? tier;
  final String? character;
  final int? amount;

  static ReferralFriendPack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReferralFriendPack(
      id: _str(raw['id']) ?? '',
      status: ReferralPackStatus.fromRaw(raw['status']),
      tier: ReferralTierKey.fromRaw(raw['tier']),
      character: _str(raw['character']),
      amount: _intOrNull(raw['amount']),
    );
  }
}

class ReferralFriend {
  const ReferralFriend({
    required this.refereeId,
    required this.username,
    required this.status,
    this.avatarUrl,
    this.joinedAt,
    this.pack,
    this.canRemind = false,
    this.nextRemindAt,
  });

  final String refereeId;
  final String username;
  final String? avatarUrl;
  final ReferralFriendStatus status;
  final DateTime? joinedAt;
  final ReferralFriendPack? pack;
  final bool canRemind;
  final DateTime? nextRemindAt;

  factory ReferralFriend.fromJson(Object? raw) {
    final m = _map(raw);
    return ReferralFriend(
      refereeId: _str(m['referee_id']) ?? '',
      username: _str(m['username']) ?? '',
      avatarUrl: _str(m['avatar_url']),
      status: ReferralFriendStatus.fromRaw(m['status']),
      joinedAt: _date(m['joined_at']),
      pack: ReferralFriendPack.fromJson(m['pack']),
      canRemind: m['can_remind'] == true,
      nextRemindAt: _date(m['next_remind_at']),
    );
  }

  /// Ingatkan applies only while the friend has not shopped yet;
  /// `next_remind_at` alone can outlive that state.
  bool get isRemindable => status == ReferralFriendStatus.registered;

  /// 1–3 filled progress segments (02 §2.5).
  int get progress => switch (status) {
    ReferralFriendStatus.firstOrderPaid ||
    ReferralFriendStatus.firstOrderShipped => 2,
    ReferralFriendStatus.completed
        when pack?.status != ReferralPackStatus.voided =>
      3,
    _ => 1,
  };
}

class ReadyPack {
  const ReadyPack({
    required this.id,
    required this.fromUsername,
    this.createdAt,
  });

  final String id;
  final String fromUsername;
  final DateTime? createdAt;

  factory ReadyPack.fromJson(Object? raw) {
    final m = _map(raw);
    return ReadyPack(
      id: _str(m['id']) ?? '',
      fromUsername: _str(m['from_username']) ?? '',
      createdAt: _date(m['created_at']),
    );
  }
}

enum ReferralFilter { all, process, packs }

class ReferralDashboard {
  const ReferralDashboard({
    required this.enabled,
    this.code,
    this.link,
    this.couponMaxAmount = 0,
    this.couponMinSubtotal = 0,
    this.koinBalance = 0,
    this.koinEarned = 0,
    this.friendCount = 0,
    this.packCount = 0,
    this.counts = const {},
    this.readyPacks = const [],
    this.friends = const [],
    this.hasMore = false,
    this.tiers = const [],
  });

  static const empty = ReferralDashboard(enabled: false);

  final bool enabled;

  /// Null only when the user has no username yet.
  final String? code;
  final String? link;
  final int couponMaxAmount;
  final int couponMinSubtotal;
  final int koinBalance;
  final int koinEarned;
  final int friendCount;
  final int packCount;
  final Map<ReferralFilter, int> counts;

  /// Oldest first; open `readyPacks.first`.
  final List<ReadyPack> readyPacks;
  final List<ReferralFriend> friends;
  final bool hasMore;
  final List<ReferralTier> tiers;

  /// The biggest prize a pack can hold (tiers are sorted largest first);
  /// the design's Rp50.000 until the server says otherwise.
  int get maxPrize => tiers.isEmpty ? 50000 : tiers.first.amount;

  factory ReferralDashboard.fromJson(Object? raw) {
    final m = referralPayload(raw);
    final coupon = _map(m['coupon']);
    final stats = _map(m['stats']);
    final counts = _map(m['counts']);
    return ReferralDashboard(
      enabled: m['enabled'] == true,
      code: _str(m['code']),
      link: _str(m['link']),
      couponMaxAmount: _int(coupon['max_amount']),
      couponMinSubtotal: _int(coupon['min_subtotal']),
      koinBalance: _int(m['koin_balance']),
      koinEarned: _int(stats['koin_earned']),
      friendCount: _int(stats['friends']),
      packCount: _int(stats['packs']),
      counts: {for (final f in ReferralFilter.values) f: _int(counts[f.name])},
      readyPacks: _list(m['ready_packs']).map(ReadyPack.fromJson).toList(),
      friends: _list(m['friends']).map(ReferralFriend.fromJson).toList(),
      hasMore: m['has_more'] == true,
      tiers: ReferralTier.listFromJson(m['tiers']),
    );
  }
}

/// `open_referral_pack`: the server's roll, stable across repeat calls.
class PackResult {
  const PackResult({
    required this.id,
    required this.tier,
    required this.amount,
    required this.character,
    required this.fromUsername,
    required this.koinBalance,
    this.openedAt,
  });

  final String id;
  final ReferralTierKey tier;
  final int amount;
  final String character;
  final String fromUsername;
  final int koinBalance;
  final DateTime? openedAt;

  factory PackResult.fromJson(Object? raw) {
    final m = referralPayload(raw);
    final tier = ReferralTierKey.fromRaw(m['tier']);
    if (tier == null) throw const ReferralException('bad_response');
    return PackResult(
      id: _str(m['id']) ?? '',
      tier: tier,
      amount: _int(m['amount']),
      character: _str(m['character']) ?? '',
      fromUsername: _str(m['from_username']) ?? '',
      koinBalance: _int(m['koin_balance']),
      openedAt: _date(m['opened_at']),
    );
  }
}

/// `mark_referral_reminded`: `ok:false` means reminded within the window.
class RemindResult {
  const RemindResult({required this.ok, this.nextAllowedAt});

  final bool ok;
  final DateTime? nextAllowedAt;

  factory RemindResult.fromJson(Object? raw) {
    final m = referralPayload(raw);
    return RemindResult(
      ok: m['ok'] == true,
      nextAllowedAt: _date(m['next_allowed_at']),
    );
  }
}

class KoinBalance {
  const KoinBalance({
    this.balance = 0,
    this.nextExpiryAmount,
    this.nextExpiryAt,
  });

  static const zero = KoinBalance();

  final int balance;
  final int? nextExpiryAmount;
  final DateTime? nextExpiryAt;

  factory KoinBalance.fromJson(Object? raw) {
    final m = referralPayload(raw);
    final next = m['next_expiry'];
    return KoinBalance(
      balance: _int(m['balance']),
      nextExpiryAmount: next is Map ? _intOrNull(next['amount']) : null,
      nextExpiryAt: next is Map ? _date(next['at']) : null,
    );
  }
}

class KoinEntry {
  const KoinEntry({
    required this.id,
    required this.delta,
    required this.reason,
    this.expiresAt,
    this.remaining,
    this.balanceAfter = 0,
    this.createdAt,
  });

  final int id;
  final int delta;
  final String reason;
  final DateTime? expiresAt;

  /// Unspent part of a credit lot; null on debit rows.
  final int? remaining;
  final int balanceAfter;
  final DateTime? createdAt;

  String get label => switch (reason) {
    'referral_pack' => 'Hadiah Ajak Teman',
    'admin' => 'Koin dari Pokepedia',
    'checkout_spend' => 'Dipakai belanja',
    'checkout_refund' => 'Dikembalikan (pesanan batal)',
    'expire' => 'Hangus',
    _ => 'Koin',
  };

  /// Show "hangus {date}" only on a lot that still holds Koin.
  bool get showsExpiry =>
      (remaining ?? 0) > 0 &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  factory KoinEntry.fromJson(Object? raw) {
    final m = _map(raw);
    return KoinEntry(
      id: _int(m['id']),
      delta: _int(m['delta']),
      reason: _str(m['reason']) ?? '',
      expiresAt: _date(m['expires_at']),
      remaining: _intOrNull(m['remaining']),
      balanceAfter: _int(m['balance_after']),
      createdAt: _date(m['created_at']),
    );
  }
}

class KoinHistoryPage {
  const KoinHistoryPage({this.rows = const [], this.hasMore = false});

  final List<KoinEntry> rows;
  final bool hasMore;

  factory KoinHistoryPage.fromJson(Object? raw) {
    final m = referralPayload(raw);
    return KoinHistoryPage(
      rows: _list(m['rows']).map(KoinEntry.fromJson).toList(),
      hasMore: m['has_more'] == true,
    );
  }
}
