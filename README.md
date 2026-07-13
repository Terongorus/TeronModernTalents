# Teron's Modern Talents

A full replacement for the default **World of Warcraft Vanilla 1.12.1** talent tree window,
rebuilt to look and feel like the modern Retail talent UI — glowing prerequisite connection
lines, tier-lock indicators, class-colored spec backgrounds, and a **Plan Mode** for
theorycrafting builds without spending a single real point.

Works on **Turtle WoW** and pure **Vanilla 1.12.1** servers such as **TwinStar Kronos V**.

This addon replaces the default talent window directly (opens automatically in place of the
vanilla frame) and needs no other addon to function — [TeronModernSpellBook](../TeronModernSpellBook)
is a nice companion (adds an `/msb talents` toggle and talent-derived spell tagging) but is
entirely optional.

---

## Features

- **Custom talent grid** for all three spec tabs, with tier-lock rows, prerequisite connection
  lines that light up gold once met, and maxed/available/partial/locked icon states.
- **Class-colored spec backgrounds** and a class icon in the header, matching the retail talent
  UI's visual style.
- **Plan Mode** — a "Learned"/"Planned" toggle near the header lets you assign virtual talent
  points independent of your real ones. The entire grid (connections, tier-lock, icon states)
  simulates what your build would look like from the virtual totals when Planned is active,
  without ever spending a real point. Left-click adds a virtual point, right-click removes one;
  removals that would orphan a dependent talent or break another planned talent's tier
  requirement are blocked with a chat explanation instead of silently corrupting the plan.
- **Up to 20 named templates** per character — switchable, renameable, and clearable from the
  settings gear's "Talent Plans" submenu.
- **"Force shift-click learn"** option (settings gear) — when enabled, spending a real talent
  point requires holding Shift, as misclick protection. Only applies to real spending; Plan Mode
  is never gated by it.
- **Expanded spec view** — click a spec panel's background for a detail view showing spec
  description, key abilities, and points invested (mode-aware, reflecting Plan Mode too).
- **Grid line toggles** (vertical/diagonal/horizontal) and coloring/visibility options from the
  settings gear.

## Installation

1. Download or clone this repository into your `Interface\AddOns\` folder.
2. Make sure the folder is named exactly `TeronModernTalents` — WoW requires the folder name to
   match the `.toc` filename inside it, or the client won't detect the addon.
3. Also install **[TeronModernCore](../TeronModernCore)** — this addon requires it (shared class
   framework and icon widget).
4. Restart the game client (or `/reload`).

The custom talent window opens automatically in place of the default one — no slash command or
keybind change needed. If [TeronModernSpellBook](../TeronModernSpellBook) is also installed,
`/msb talents` toggles between this window and the vanilla one.

## Compatibility

- **Turtle WoW** (Interface 11200) — primary original target.
- **Pure Vanilla 1.12.1** (e.g. TwinStar Kronos V) — fully supported, no Turtle-specific
  dependencies.
- **Requires [TeronModernCore](../TeronModernCore)**.
- Works standalone; **TeronModernSpellBook** is an optional companion, not required.

## Credits

- Split out of **TeronModernSpellBook** (itself a Turtle WoW port of the community
  **ModernSpellBook** addon) into its own addon by **Terongorus**, so the talent tree can be used
  independently of the spellbook.
