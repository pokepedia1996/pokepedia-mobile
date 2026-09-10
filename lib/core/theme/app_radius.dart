/// Corner radii ported from the `--radius-*` tokens in `globals.css`.
///
/// Careful: the names sit one step above web's. `globals.css` runs
/// 4/8/10/12/16/20/24/32 from `xs`, this runs 8/10/12/16/20/24/32/40 — so
/// web's `--radius-md` (10px, "buttons, inputs, icon-buttons, selects") is
/// [sm] here, and its `--radius-lg` (12px, "cards, panels, modals") is [md].
/// Reading a web class name across as the same name here makes every corner
/// a step rounder than the site, which is how the buttons drifted.
class AppRadius {
  AppRadius._();

  static const xs = 8.0;
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xl2 = 24.0;
  static const xl3 = 32.0;
  static const xl4 = 40.0;
  static const full = 999.0;
}

/// Spacing scale used throughout the buyer screens (4px base grid).
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xl2 = 32.0;
  static const xl3 = 40.0;
}
