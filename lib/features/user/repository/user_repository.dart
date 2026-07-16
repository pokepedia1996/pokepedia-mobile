import '../../../shared/models/user_model.dart';

/// Data access for the User profile / directory feature. Stands in for
/// `public.profiles` joined with `public.user_reputation` in
/// `supabase/migrations/00000000000000_baseline.sql` while this pass only
/// ports the UI with dummy data.
class UserRepository {
  static const _users = [
    UserModel(
      username: 'ashketchum',
      bio: 'Gotta catch \'em all! Kolektor vintage WOTC.',
      collectionCount: 342,
      followerCount: 128,
      joinedAt: 'Bergabung Jan 2023',
      role: ProfileRole.contributor,
      totalTrades: 87,
      positivePct: 98.5,
    ),
    UserModel(
      username: 'mistywaterflower',
      bio: 'Fokus koleksi tipe Water & Psychic.',
      collectionCount: 210,
      followerCount: 76,
      joinedAt: 'Bergabung Mar 2023',
      totalTrades: 34,
      positivePct: 96.2,
    ),
    UserModel(
      username: 'brockrocksolid',
      bio: 'Trainer card enthusiast dari Bandung.',
      collectionCount: 158,
      followerCount: 54,
      joinedAt: 'Bergabung Jun 2023',
      totalTrades: 12,
      positivePct: 100,
    ),
    UserModel(
      username: 'gary_oak99',
      bio: 'Deckbuilder kompetitif, main format Standard.',
      collectionCount: 96,
      followerCount: 40,
      joinedAt: 'Bergabung Sep 2023',
      isCollectionPublic: false,
      totalTrades: 0,
    ),
  ];

  Future<List<UserModel>> search(String query) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) => u.username.toLowerCase().contains(q)).toList();
  }

  Future<UserModel?> fetchByUsername(String username) async {
    await Future.delayed(const Duration(milliseconds: 150));
    for (final u in _users) {
      if (u.username == username) return u;
    }
    return _users.first;
  }
}
