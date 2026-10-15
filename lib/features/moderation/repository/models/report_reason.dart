/// The reasons `report_user` accepts, in web's order and wording
/// (`features/moderation/report-reasons.ts`). The RPC checks the same six
/// values, so drifting from them would offer a choice it rejects.
const userReportReasons = <({String value, String label})>[
  (value: 'harassment', label: 'Pelecehan'),
  (value: 'scam', label: 'Penipuan'),
  (value: 'sexual', label: 'Konten seksual'),
  (value: 'hate', label: 'Ujaran kebencian/SARA'),
  (value: 'spam', label: 'Spam'),
  (value: 'other', label: 'Lainnya'),
];

/// `MAX_USER_REPORT_DETAILS` — the ceiling the route and the table enforce.
const maxUserReportDetails = 1000;

/// Where a report was filed from — `user_reports.context`.
enum UserReportContext {
  chat('chat'),
  store('store'),
  profile('profile');

  const UserReportContext(this.value);
  final String value;
}

/// Web's `BLOCKED_INTERACTION_MESSAGE`: what any refused interaction with a
/// blocked user says, from either side.
const blockedInteractionMessage =
    'Kamu tidak dapat berinteraksi dengan pengguna ini.';
