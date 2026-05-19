import 'package:flutter/material.dart';

/// All theme definitions for Hermes Wingman.
///
/// Each theme is a complete palette mapped to Material theming.
/// The naming convention keeps it simple: background/surface/primary/accent
/// with a custom [AppColorScheme] layered on top of Material's.

class AppColorScheme {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color text;
  final Color textDim;
  final Color textMuted;
  final Color border;
  final Color borderDim;
  final Color success;
  final Color warning;
  final Color error;
  final Color cardBackground;
  final Color selectedBackground;
  final Color scaffoldBackground;
  final Color appBarBackground;
  final Color bottomNavBackground;

  const AppColorScheme({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.text,
    required this.textDim,
    required this.textMuted,
    required this.border,
    required this.borderDim,
    this.success = const Color(0xFF00FF87),
    this.warning = const Color(0xFFFFB800),
    this.error = const Color(0xFFFF3355),
    required this.cardBackground,
    required this.selectedBackground,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.bottomNavBackground,
  });
}

// ── Synthwave '84 ──────────────────────────────────────────────────────────
// Deep purple canvas, electric purple pulse, hot pink accents, cyan glow.
// Matches the Omarchy synthwave84 system theme exactly.
const synthwave84 = AppColorScheme(
  background: Color(0xFF0D0221),
  surface: Color(0xFF240037),
  surfaceAlt: Color(0xFF2D0047),
  primary: Color(0xFF8F00FF),
  secondary: Color(0xFFFF00FF),
  accent: Color(0xFF00FFFF),
  text: Color(0xFFFFFFFF),
  textDim: Color(0xFFC0A0D0),
  textMuted: Color(0xFF663388),
  border: Color(0xFF8F00FF),
  borderDim: Color(0xFF4A0068),
  cardBackground: Color(0xFF240037),
  selectedBackground: Color(0xFF3A0055),
  scaffoldBackground: Color(0xFF0D0221),
  appBarBackground: Color(0xFF0A011A),
  bottomNavBackground: Color(0xFF0A011A),
  success: Color(0xFF00FF41),
  warning: Color(0xFFFFFF66),
  error: Color(0xFFFF0040),
);

// ── Synthwave '84 Light ─────────────────────────────────────────────────────
// Inverted purple: white canvas, electric purple neon accents for daytime.
const synthwave84Light = AppColorScheme(
  background: Color(0xFFF5F0FF),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFEEE8FF),
  primary: Color(0xFF8F00FF),
  secondary: Color(0xFFFF00AA),
  accent: Color(0xFF00BBCC),
  text: Color(0xFF1A0030),
  textDim: Color(0xFF663399),
  textMuted: Color(0xFF9966BB),
  border: Color(0xFF8F00FF),
  borderDim: Color(0xFFDDCCEE),
  cardBackground: Color(0xFFFFFFFF),
  selectedBackground: Color(0xFFF0E0FF),
  scaffoldBackground: Color(0xFFF5F0FF),
  appBarBackground: Color(0xFFFFFFFF),
  bottomNavBackground: Color(0xFFFFFFFF),
  success: Color(0xFF00CC66),
  warning: Color(0xFFCC8800),
  error: Color(0xFFCC2244),
);

// ── Outrun ──────────────────────────────────────────────────────────────────
// Near-black canvas, blazing orange sun, electric cyan, hot pink kick.
const outrun = AppColorScheme(
  background: Color(0xFF0A0A0A),
  surface: Color(0xFF1A1A1A),
  surfaceAlt: Color(0xFF252525),
  primary: Color(0xFFFF6A00),
  secondary: Color(0xFF00FFF5),
  accent: Color(0xFFFF00FF),
  text: Color(0xFFFFF0E0),
  textDim: Color(0xFF888870),
  textMuted: Color(0xFF555540),
  border: Color(0xFFFF6A00),
  borderDim: Color(0xFF332200),
  cardBackground: Color(0xFF1A1A1A),
  selectedBackground: Color(0xFF2A1A00),
  scaffoldBackground: Color(0xFF0A0A0A),
  appBarBackground: Color(0xFF050505),
  bottomNavBackground: Color(0xFF050505),
  success: Color(0xFF00FF87),
  warning: Color(0xFFFFB800),
  error: Color(0xFFFF3355),
);

// ── Vaporwave ───────────────────────────────────────────────────────────────
// Purple base, pink accents, mint green highlights, retro mall aesthetic.
const vaporwave = AppColorScheme(
  background: Color(0xFF1A0A2E),
  surface: Color(0xFF2D1B69),
  surfaceAlt: Color(0xFF3B2870),
  primary: Color(0xFFFF6EC7),
  secondary: Color(0xFF00FF87),
  accent: Color(0xFFB388FF),
  text: Color(0xFFF0E0FF),
  textDim: Color(0xFF9988BB),
  textMuted: Color(0xFF665588),
  border: Color(0xFFFF6EC7),
  borderDim: Color(0xFF3B2870),
  cardBackground: Color(0xFF2D1B69),
  selectedBackground: Color(0xFF3B2870),
  scaffoldBackground: Color(0xFF1A0A2E),
  appBarBackground: Color(0xFF150828),
  bottomNavBackground: Color(0xFF150828),
  success: Color(0xFF00FF87),
  warning: Color(0xFFFFB800),
  error: Color(0xFFFF3355),
);

// ── Cyberpunk ───────────────────────────────────────────────────────────────
// Total black, aggressive yellow, red pulse, cyan data streams.
const cyberpunk = AppColorScheme(
  background: Color(0xFF000000),
  surface: Color(0xFF0F0F0F),
  surfaceAlt: Color(0xFF1A1A1A),
  primary: Color(0xFFFFD700),
  secondary: Color(0xFF00FFF5),
  accent: Color(0xFFFF0040),
  text: Color(0xFFE0E0C0),
  textDim: Color(0xFF888860),
  textMuted: Color(0xFF555530),
  border: Color(0xFFFFD700),
  borderDim: Color(0xFF332800),
  cardBackground: Color(0xFF0F0F0F),
  selectedBackground: Color(0xFF1A1000),
  scaffoldBackground: Color(0xFF000000),
  appBarBackground: Color(0xFF000000),
  bottomNavBackground: Color(0xFF000000),
  success: Color(0xFF00FF87),
  warning: Color(0xFFFFB800),
  error: Color(0xFFFF0040),
);

// ── Hermes Brand ────────────────────────────────────────────────────────────
// Deep forest teal, cream headers, sage green accents, classical/etched vibe.
// Inspired by hermes-agent.nousresearch.com
const hermes = AppColorScheme(
  background: Color(0xFF051412),
  surface: Color(0xFF0A1F1C),
  surfaceAlt: Color(0xFF0F2925),
  primary: Color(0xFFF5F0E8),
  secondary: Color(0xFF8BA888),
  accent: Color(0xFF4A6B5D),
  text: Color(0xFFE8E8D8),
  textDim: Color(0xFF889988),
  textMuted: Color(0xFF556655),
  border: Color(0xFF4A6B5D),
  borderDim: Color(0xFF1A2F2A),
  cardBackground: Color(0xFF0A1F1C),
  selectedBackground: Color(0xFF0F2925),
  scaffoldBackground: Color(0xFF051412),
  appBarBackground: Color(0xFF030D0B),
  bottomNavBackground: Color(0xFF030D0B),
  success: Color(0xFF8DE0A0),
  warning: Color(0xFFD4A040),
  error: Color(0xFFD04A5A),
);

// ── GREEK PANTHEON ──────────────────────────────────────────────────────

/// Zeus — Sky Father: Royal purple, lightning gold, storm blue
const zeus = AppColorScheme(
  background: Color(0xFF0D0A1A), surface: Color(0xFF1A1530), surfaceAlt: Color(0xFF282045),
  primary: Color(0xFFC9A84C), secondary: Color(0xFF4A7CFF), accent: Color(0xFF00D4FF),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFC9A84C), borderDim: Color(0xFF1A153080),
  cardBackground: Color(0xFF1A1530), selectedBackground: Color(0xFF282045),
  scaffoldBackground: Color(0xFF0D0A1A), appBarBackground: Color(0xFF0D0A1A80), bottomNavBackground: Color(0xFF0D0A1A80),
);

/// Poseidon — Sea God: Deep ocean blue, teal, seafoam, coral
const poseidon = AppColorScheme(
  background: Color(0xFF061214), surface: Color(0xFF0A1F22), surfaceAlt: Color(0xFF0F2A2E),
  primary: Color(0xFF0077B6), secondary: Color(0xFF00B4D8), accent: Color(0xFF48CAE4),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF0077B6), borderDim: Color(0xFF0A1F2280),
  cardBackground: Color(0xFF0A1F22), selectedBackground: Color(0xFF0F2A2E),
  scaffoldBackground: Color(0xFF061214), appBarBackground: Color(0xFF06121480), bottomNavBackground: Color(0xFF06121480),
);

/// Hades — Underworld: Obsidian black, ember green, flame orange
const hades = AppColorScheme(
  background: Color(0xFF0A0A0A), surface: Color(0xFF141010), surfaceAlt: Color(0xFF1F1515),
  primary: Color(0xFFFF6B35), secondary: Color(0xFF00D4AA), accent: Color(0xFFFFD166),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFFF6B35), borderDim: Color(0xFF14101080),
  cardBackground: Color(0xFF141010), selectedBackground: Color(0xFF1F1515),
  scaffoldBackground: Color(0xFF0A0A0A), appBarBackground: Color(0xFF0A0A0A80), bottomNavBackground: Color(0xFF0A0A0A80),
);

/// Ares — War: Blood crimson, iron grey, bronze, fire
const ares = AppColorScheme(
  background: Color(0xFF0F0505), surface: Color(0xFF1F0A0A), surfaceAlt: Color(0xFF2F0F0F),
  primary: Color(0xFFDC143C), secondary: Color(0xFF8B8B8B), accent: Color(0xFFCD7F32),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFDC143C), borderDim: Color(0xFF1F0A0A80),
  cardBackground: Color(0xFF1F0A0A), selectedBackground: Color(0xFF2F0F0F),
  scaffoldBackground: Color(0xFF0F0505), appBarBackground: Color(0xFF0F050580), bottomNavBackground: Color(0xFF0F050580),
);

/// Apollo — Sun/Arts: Golden radiance, warm orange, sky blue
const apollo = AppColorScheme(
  background: Color(0xFF0F0A05), surface: Color(0xFF1F150A), surfaceAlt: Color(0xFF2F1F0F),
  primary: Color(0xFFFFB703), secondary: Color(0xFFFB8500), accent: Color(0xFF00B4D8),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFFFB703), borderDim: Color(0xFF1F150A80),
  cardBackground: Color(0xFF1F150A), selectedBackground: Color(0xFF2F1F0F),
  scaffoldBackground: Color(0xFF0F0A05), appBarBackground: Color(0xFF0F0A0580), bottomNavBackground: Color(0xFF0F0A0580),
);

/// Artemis — Hunt/Moon: Silver lunar, forest green, midnight blue
const artemis = AppColorScheme(
  background: Color(0xFF0A0D12), surface: Color(0xFF0F1820), surfaceAlt: Color(0xFF152230),
  primary: Color(0xFFC0C0C0), secondary: Color(0xFF2D6A4F), accent: Color(0xFF1B4332),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFC0C0C0), borderDim: Color(0xFF0F182080),
  cardBackground: Color(0xFF0F1820), selectedBackground: Color(0xFF152230),
  scaffoldBackground: Color(0xFF0A0D12), appBarBackground: Color(0xFF0A0D1280), bottomNavBackground: Color(0xFF0A0D1280),
);

/// Athena — Wisdom: Sapphire blue, olive green, marble, gold
const athena = AppColorScheme(
  background: Color(0xFF0A0D0F), surface: Color(0xFF101820), surfaceAlt: Color(0xFF182830),
  primary: Color(0xFF1D3557), secondary: Color(0xFFA7C957), accent: Color(0xFFE9C46A),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF1D3557), borderDim: Color(0xFF10182080),
  cardBackground: Color(0xFF101820), selectedBackground: Color(0xFF182830),
  scaffoldBackground: Color(0xFF0A0D0F), appBarBackground: Color(0xFF0A0D0F80), bottomNavBackground: Color(0xFF0A0D0F80),
);

/// Aphrodite — Love: Rose pink, deep crimson, pearl, soft gold
const aphrodite = AppColorScheme(
  background: Color(0xFF140A0F), surface: Color(0xFF241018), surfaceAlt: Color(0xFF341828),
  primary: Color(0xFFE91E63), secondary: Color(0xFFFFB6C1), accent: Color(0xFFFFD700),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFE91E63), borderDim: Color(0xFF24101880),
  cardBackground: Color(0xFF241018), selectedBackground: Color(0xFF341828),
  scaffoldBackground: Color(0xFF140A0F), appBarBackground: Color(0xFF140A0F80), bottomNavBackground: Color(0xFF140A0F80),
);

/// Dionysus — Wine/Festival: Wine red, grape purple, vine green
const dionysus = AppColorScheme(
  background: Color(0xFF120810), surface: Color(0xFF201020), surfaceAlt: Color(0xFF301830),
  primary: Color(0xFF722F37), secondary: Color(0xFF9B59B6), accent: Color(0xFF7DCEA0),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF722F37), borderDim: Color(0xFF20102080),
  cardBackground: Color(0xFF201020), selectedBackground: Color(0xFF301830),
  scaffoldBackground: Color(0xFF120810), appBarBackground: Color(0xFF12081080), bottomNavBackground: Color(0xFF12081080),
);

/// Demeter — Harvest: Wheat gold, earthy brown, leaf green
const demeter = AppColorScheme(
  background: Color(0xFF0F0E0A), surface: Color(0xFF1A1810), surfaceAlt: Color(0xFF282218),
  primary: Color(0xFFD4A373), secondary: Color(0xFF588157), accent: Color(0xFFF4A261),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFD4A373), borderDim: Color(0xFF1A181080),
  cardBackground: Color(0xFF1A1810), selectedBackground: Color(0xFF282218),
  scaffoldBackground: Color(0xFF0F0E0A), appBarBackground: Color(0xFF0F0E0A80), bottomNavBackground: Color(0xFF0F0E0A80),
);

/// Hephaestus — Forge: Molten orange, steel grey, ember red
const hephaestus = AppColorScheme(
  background: Color(0xFF080808), surface: Color(0xFF151515), surfaceAlt: Color(0xFF252020),
  primary: Color(0xFFFF6D00), secondary: Color(0xFF6C6C6C), accent: Color(0xFFFF3D00),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFFF6D00), borderDim: Color(0xFF15151580),
  cardBackground: Color(0xFF151515), selectedBackground: Color(0xFF252020),
  scaffoldBackground: Color(0xFF080808), appBarBackground: Color(0xFF08080880), bottomNavBackground: Color(0xFF08080880),
);

/// Hestia — Hearth: Warm amber, brick red, cream, soft orange
const hestia = AppColorScheme(
  background: Color(0xFF120E08), surface: Color(0xFF201810), surfaceAlt: Color(0xFF302218),
  primary: Color(0xFFE76F51), secondary: Color(0xFFF4A261), accent: Color(0xFFE9C46A),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFE76F51), borderDim: Color(0xFF20181080),
  cardBackground: Color(0xFF201810), selectedBackground: Color(0xFF302218),
  scaffoldBackground: Color(0xFF120E08), appBarBackground: Color(0xFF120E0880), bottomNavBackground: Color(0xFF120E0880),
);

/// Nyx — Night: Deep purple-black, star silver, midnight
const nyx = AppColorScheme(
  background: Color(0xFF05030F), surface: Color(0xFF0A0720), surfaceAlt: Color(0xFF100B30),
  primary: Color(0xFF7B2D8E), secondary: Color(0xFFE0BBE4), accent: Color(0xFF3D5A80),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF7B2D8E), borderDim: Color(0xFF0A072080),
  cardBackground: Color(0xFF0A0720), selectedBackground: Color(0xFF100B30),
  scaffoldBackground: Color(0xFF05030F), appBarBackground: Color(0xFF05030F80), bottomNavBackground: Color(0xFF05030F80),
);

/// Eos — Dawn: Rosy pink, golden orange, soft lavender, sky blue
const eos = AppColorScheme(
  background: Color(0xFF120A0F), surface: Color(0xFF201520), surfaceAlt: Color(0xFF302030),
  primary: Color(0xFFFF9E9E), secondary: Color(0xFFFFC8A2), accent: Color(0xFF87CEEB),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFFF9E9E), borderDim: Color(0xFF20152080),
  cardBackground: Color(0xFF201520), selectedBackground: Color(0xFF302030),
  scaffoldBackground: Color(0xFF120A0F), appBarBackground: Color(0xFF120A0F80), bottomNavBackground: Color(0xFF120A0F80),
);

/// Hypnos — Sleep: Soft lavender, midnight blue, silvery dream
const hypnos = AppColorScheme(
  background: Color(0xFF080A14), surface: Color(0xFF101828), surfaceAlt: Color(0xFF182838),
  primary: Color(0xFF9B72CF), secondary: Color(0xFF6B8DD6), accent: Color(0xFFC8B6E5),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF9B72CF), borderDim: Color(0xFF10182880),
  cardBackground: Color(0xFF101828), selectedBackground: Color(0xFF182838),
  scaffoldBackground: Color(0xFF080A14), appBarBackground: Color(0xFF080A1480), bottomNavBackground: Color(0xFF080A1480),
);

/// Iris — Rainbow: Multicolor spectrum, bright cyan, pink, gold
const iris = AppColorScheme(
  background: Color(0xFF0A0A12), surface: Color(0xFF181828), surfaceAlt: Color(0xFF282838),
  primary: Color(0xFF00BCD4), secondary: Color(0xFFFF69B4), accent: Color(0xFFFFD700),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF00BCD4), borderDim: Color(0xFF18182880),
  cardBackground: Color(0xFF181828), selectedBackground: Color(0xFF282838),
  scaffoldBackground: Color(0xFF0A0A12), appBarBackground: Color(0xFF0A0A1280), bottomNavBackground: Color(0xFF0A0A1280),
);

/// Tyche — Fortune: Emerald green, lucky gold, red accents
const tyche = AppColorScheme(
  background: Color(0xFF080C08), surface: Color(0xFF101810), surfaceAlt: Color(0xFF182418),
  primary: Color(0xFF2D6A4F), secondary: Color(0xFFD4AF37), accent: Color(0xFFE63946),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF2D6A4F), borderDim: Color(0xFF10181080),
  cardBackground: Color(0xFF101810), selectedBackground: Color(0xFF182418),
  scaffoldBackground: Color(0xFF080C08), appBarBackground: Color(0xFF080C0880), bottomNavBackground: Color(0xFF080C0880),
);

/// Thanatos — Death: Pale grey, bone white, deep black, dark teal
const thanatos = AppColorScheme(
  background: Color(0xFF080808), surface: Color(0xFF121212), surfaceAlt: Color(0xFF1C1C1C),
  primary: Color(0xFFD4D4D4), secondary: Color(0xFF2F4F4F), accent: Color(0xFFF5F5DC),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFFD4D4D4), borderDim: Color(0xFF12121280),
  cardBackground: Color(0xFF121212), selectedBackground: Color(0xFF1C1C1C),
  scaffoldBackground: Color(0xFF080808), appBarBackground: Color(0xFF08080880), bottomNavBackground: Color(0xFF08080880),
);

/// Nemesis — Retribution: Dark red, black, steel grey, amber
const nemesis = AppColorScheme(
  background: Color(0xFF0A0505), surface: Color(0xFF150A0A), surfaceAlt: Color(0xFF201010),
  primary: Color(0xFF8B0000), secondary: Color(0xFF708090), accent: Color(0xFFFFBF00),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF8B0000), borderDim: Color(0xFF150A0A80),
  cardBackground: Color(0xFF150A0A), selectedBackground: Color(0xFF201010),
  scaffoldBackground: Color(0xFF0A0505), appBarBackground: Color(0xFF0A050580), bottomNavBackground: Color(0xFF0A050580),
);

/// Hecate — Magic/Witchcraft: Deep purple, eerie green, silver
const hecate = AppColorScheme(
  background: Color(0xFF0A0510), surface: Color(0xFF140A20), surfaceAlt: Color(0xFF201030),
  primary: Color(0xFF5B2C8E), secondary: Color(0xFF00FF87), accent: Color(0xFFC0C0C0),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF5B2C8E), borderDim: Color(0xFF140A2080),
  cardBackground: Color(0xFF140A20), selectedBackground: Color(0xFF201030),
  scaffoldBackground: Color(0xFF0A0510), appBarBackground: Color(0xFF0A051080), bottomNavBackground: Color(0xFF0A051080),
);

/// Hera — Queen of Gods: Royal purple, peacock blue, gold, regal white
const hera = AppColorScheme(
  background: Color(0xFF0E0814), surface: Color(0xFF1C1030), surfaceAlt: Color(0xFF2A1848),
  primary: Color(0xFF6A0DAD), secondary: Color(0xFF1E90FF), accent: Color(0xFFFFD700),
  text: Color(0xFFFFF8F0), textDim: Color(0xFFB0A8C0), textMuted: Color(0xFF706880),
  border: Color(0xFF6A0DAD), borderDim: Color(0xFF1C103080),
  cardBackground: Color(0xFF1C1030), selectedBackground: Color(0xFF2A1848),
  scaffoldBackground: Color(0xFF0E0814), appBarBackground: Color(0xFF0E081480), bottomNavBackground: Color(0xFF0E081480),
);

// ── Light / Professional ────────────────────────────────────────────────────
const lightTheme = AppColorScheme(
  background: Color(0xFFFFFFFF), surface: Color(0xFFF8F9FA), surfaceAlt: Color(0xFFE9ECEF),
  primary: Color(0xFF2563EB), secondary: Color(0xFF3B82F6), accent: Color(0xFF6366F1),
  text: Color(0xFF1A1A2E), textDim: Color(0xFF6B7280), textMuted: Color(0xFF9CA3AF),
  border: Color(0xFFD1D5DB), borderDim: Color(0xFFE5E7EB),
  cardBackground: Color(0xFFFFFFFF), selectedBackground: Color(0xFFEFF6FF),
  scaffoldBackground: Color(0xFFFFFFFF), appBarBackground: Color(0xFFFFFFFF), bottomNavBackground: Color(0xFFFFFFFF),
  success: Color(0xFF059669), warning: Color(0xFFD97706), error: Color(0xFFDC2626),
);

// ── Dark / Professional ─────────────────────────────────────────────────────
const darkTheme = AppColorScheme(
  background: Color(0xFF111118), surface: Color(0xFF1A1A24), surfaceAlt: Color(0xFF222230),
  primary: Color(0xFF60A5FA), secondary: Color(0xFF818CF8), accent: Color(0xFF34D399),
  text: Color(0xFFE2E8F0), textDim: Color(0xFF94A3B8), textMuted: Color(0xFF64748B),
  border: Color(0xFF334155), borderDim: Color(0xFF1E293B),
  cardBackground: Color(0xFF1A1A24), selectedBackground: Color(0xFF1E293B),
  scaffoldBackground: Color(0xFF111118), appBarBackground: Color(0xFF0D0D14), bottomNavBackground: Color(0xFF0D0D14),
  success: Color(0xFF34D399), warning: Color(0xFFFBBF24), error: Color(0xFFF87171),
);

/// All themes indexed by name for the picker.
const Map<String, AppColorScheme> allThemes = {
  'Synthwave \'84': synthwave84,
  'Synthwave Light': synthwave84Light,
  'Outrun': outrun,
  'Vaporwave': vaporwave,
  'Cyberpunk': cyberpunk,
  'Hermes': hermes,
  'Zeus': zeus,
  'Hera': hera,
  'Poseidon': poseidon,
  'Hades': hades,
  'Ares': ares,
  'Apollo': apollo,
  'Artemis': artemis,
  'Athena': athena,
  'Aphrodite': aphrodite,
  'Dionysus': dionysus,
  'Demeter': demeter,
  'Hephaestus': hephaestus,
  'Hestia': hestia,
  'Nyx': nyx,
  'Eos': eos,
  'Hypnos': hypnos,
  'Iris': iris,
  'Tyche': tyche,
  'Thanatos': thanatos,
  'Nemesis': nemesis,
  'Hecate': hecate,
  'Light': lightTheme,
  'Dark': darkTheme,
};

/// Converts [AppColorScheme] into Material's [ThemeData].
/// Handles dark/light detection automatically via luminance.
ThemeData themeDataFromScheme(AppColorScheme scheme) {
  // Auto-detect dark/light from background luminance
  // Dark backgrounds have luminance < 0.3
  final isDark = scheme.background.computeLuminance() < 0.3;

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: scheme.scaffoldBackground,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: scheme.primary,
      onPrimary: scheme.background,
      secondary: scheme.secondary,
      onSecondary: scheme.background,
      tertiary: scheme.accent,
      onTertiary: scheme.background,
      surface: scheme.surface,
      onSurface: scheme.text,
      error: scheme.error,
      onError: scheme.background,
      outline: scheme.border,
      outlineVariant: scheme.borderDim,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.appBarBackground,
      foregroundColor: scheme.text,
      elevation: 0,
      scrolledUnderElevation: 0.5,
    ),
    cardTheme: CardThemeData(
      color: scheme.cardBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.borderDim, width: 0.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.bottomNavBackground,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.borderDim,
      thickness: 0.5,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceAlt,
      side: BorderSide(color: scheme.borderDim, width: 0.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.borderDim),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.borderDim),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(color: scheme.text, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: scheme.text, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: scheme.text, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: scheme.text, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: scheme.text),
      bodyMedium: TextStyle(color: scheme.textDim),
      bodySmall: TextStyle(color: scheme.textMuted),
      labelLarge: TextStyle(color: scheme.primary),
    ),
  );
}

/// The list of theme names in display order.
const List<String> themeNames = [
  'Synthwave \'84',
  'Synthwave Light',
  'Outrun',
  'Vaporwave',
  'Cyberpunk',
  'Hermes',
  'Zeus',
  'Hera',
  'Poseidon',
  'Hades',
  'Ares',
  'Apollo',
  'Artemis',
  'Athena',
  'Aphrodite',
  'Dionysus',
  'Demeter',
  'Hephaestus',
  'Hestia',
  'Nyx',
  'Eos',
  'Hypnos',
  'Iris',
  'Tyche',
  'Thanatos',
  'Nemesis',
  'Hecate',
  'Light',
  'Dark',
];
