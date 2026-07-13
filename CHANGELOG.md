# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow major.minor.hotfix (e.g. 1.2.3).

## [1.0.1] - 2026-07-13

### Fixed
- `ModernTalents_DB` could be nil on a genuinely first-ever session for this addon (no prior save
  on disk for this character yet) - `CTalentTree` builds its whole UI synchronously at file-load
  time rather than gating it behind `ADDON_LOADED` the way TeronModernSpellBook's own frame does,
  so an unguarded write in the "Force shift-click learn" checkbox's `OnClick` could throw
  `attempt to index global 'ModernTalents_DB' (a nil value)`, and every other DB write in that
  same broken session (renaming/switching templates, planning talent points) silently no-op'd
  through `EnsureDB()`'s throwaway placeholder instead of persisting. Fixed by guaranteeing
  `ModernTalents_DB` exists as a real table at the very top of the first-loaded file, instead of
  relying on the client to have already set it by the time this addon's code runs.

## [1.0.0] - 2026-07-13

### Added
- Initial release. Split out of **TeronModernSpellBook** into its own addon, now depending on
  **TeronModernCore** for shared library code instead of the spellbook directly, so the talent
  tree can be installed and used independently.
- All features carried over as-is from TeronModernSpellBook 1.7.0: the custom talent grid with
  glowing prerequisite connections and tier-lock indicators, class-colored spec backgrounds, Plan
  Mode (theorycraft builds with up to 20 named templates without spending real points), and
  "Force shift-click learn" misclick protection.
- Now uses its own dedicated `ModernTalents_DB` SavedVariable instead of sharing
  `ModernSpellBook_DB` with the spellbook. This is a clean break, not a migration - existing
  talent settings/plans from a pre-split TeronModernSpellBook install will not carry over and
  will need to be recreated.
