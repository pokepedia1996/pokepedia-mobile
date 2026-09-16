/// How a seller is named and linked to across the app.
///
/// Ports `resolveSellerDisplay` (`lib/seller/identity.ts`). A seller only has
/// a `store_name`/`store_slug` once they have set a storefront up; plenty of
/// people sell without ever doing that, and their `seller_profiles` row
/// carries a city and a logo but no shop name. Every RPC that returns a
/// listing therefore also returns the seller's `username`, which is the name
/// to show — and the handle to link by — when the shop fields are null.
///
/// Falling back to a literal like "Toko" instead loses a name the row is
/// already carrying, and leaves the tile linking nowhere.
library;

/// Ports web's `isSafeHandle` — what may be spliced into a `/market/...`
/// path.
bool isSafeHandle(String? value) {
  if (value == null || value.isEmpty || value.length > 50) return false;
  return RegExp(r'^[\w.\-]+$').hasMatch(value);
}

/// The last-resort label, for a listing carrying neither a shop name nor a
/// username. Matches web's own fallback.
const sellerDisplayFallback = 'Penjual';

/// What to call this seller: their shop name if they have one, else their
/// username, else [fallback].
///
/// [fallback] is only reached by an account carrying neither — deleted or
/// half-registered. Callers naming the other side of a bid pass 'Pembeli',
/// since that counterparty is a buyer rather than a shop.
String resolveSellerName({
  String? storeName,
  String? username,
  String fallback = sellerDisplayFallback,
}) {
  final shop = storeName?.trim();
  if (shop != null && shop.isNotEmpty) return shop;
  final handle = username?.trim();
  if (handle != null && handle.isNotEmpty) return handle;
  return fallback;
}

/// The handle their storefront is addressed by: the shop slug when they have
/// one, else their username — `get_seller_storefront_by_username` resolves
/// the latter, which is how web's `/market/{username}` works.
///
/// Empty when neither is usable, which is the caller's signal that there is
/// no storefront to open.
String resolveSellerHandle({String? storeSlug, String? username}) {
  final slug = storeSlug?.trim();
  if (slug != null && slug.isNotEmpty) return slug;
  final handle = username?.trim();
  if (handle != null && isSafeHandle(handle)) return handle;
  return '';
}

/// `@username`, shown under a shop name that differs from it. Null when
/// there is no shop name, or when it just repeats the username — mirrors
/// web's `secondaryName`.
String? resolveSellerSecondaryName({String? storeName, String? username}) {
  final shop = storeName?.trim();
  final handle = username?.trim();
  if (shop == null || shop.isEmpty) return null;
  if (handle == null || handle.isEmpty || shop == handle) return null;
  return '@$handle';
}
