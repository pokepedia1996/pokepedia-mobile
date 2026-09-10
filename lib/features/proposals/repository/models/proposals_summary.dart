/// Ports `ProposalsSummary` — the counts behind the market page's proposal
/// banner.
class ProposalsSummary {
  const ProposalsSummary({
    this.receivedPending = 0,
    this.receivedPendingUnseen = 0,
    this.receivedTotal = 0,
    this.sentPending = 0,
    this.sentTotal = 0,
    this.bidCount = 0,
    this.isActiveSeller = false,
  });

  /// Proposals sellers made on this user's own WTB bids.
  final int receivedPending;

  /// Of those, the ones never opened — what the red dot is for.
  final int receivedPendingUnseen;
  final int receivedTotal;

  /// Proposals this user sent as a seller, still awaiting an answer.
  final int sentPending;
  final int sentTotal;

  /// Open WTB bids, which is what makes receiving proposals possible.
  final int bidCount;
  final bool isActiveSeller;

  int get totalPending => receivedPending + sentPending;
  bool get hasNew => receivedPendingUnseen > 0;

  /// Web hides the banner entirely for someone with no stake in proposals —
  /// no bids, nothing sent, nothing received, and not selling. Showing an
  /// empty inbox to a browsing buyer is noise.
  bool get isVisible =>
      bidCount > 0 || sentTotal > 0 || receivedTotal > 0 || isActiveSeller;

  /// Which tab the banner opens.
  ///
  /// Follows the subtitle: whatever the banner just told the user about is
  /// what the page has to be able to show. Incoming proposals outrank
  /// everything because they are the ones needing an answer; bids come next,
  /// because "N bid aktif" has to land somewhere those rows exist.
  ProposalsDestination get destination {
    if (receivedPending > 0) return ProposalsDestination.received;
    if (sentPending > 0) return ProposalsDestination.sent;
    if (bidCount > 0) return ProposalsDestination.bids;
    return ProposalsDestination.sent;
  }

  /// Kept for the tab-targeting tests; [destination] is the full answer.
  bool get opensReceived => destination == ProposalsDestination.received;

  /// Ports the banner's `subtext` ladder, in the same order.
  String get subtitle {
    if (receivedPending > 0 && sentPending > 0) {
      return '$receivedPending masuk · $sentPending menunggu jawaban';
    }
    if (receivedPending > 0) {
      return '$receivedPending proposal masuk untuk bid kamu';
    }
    if (sentPending > 0) {
      return '$sentPending proposal kamu menunggu jawaban';
    }
    if (bidCount > 0 || sentTotal > 0) {
      return [
        if (bidCount > 0) '$bidCount bid aktif',
        if (sentTotal > 0) '$sentTotal proposal dikirim',
      ].join(' · ');
    }
    return 'Belum ada aktivitas · Pasang bid atau kirim proposal';
  }
}

/// Which tab of the Proposal page the market banner opens.
enum ProposalsDestination { sent, received, bids }
