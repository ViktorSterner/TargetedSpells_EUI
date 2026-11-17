# TargetedSpells_EUI

Independent addon that detects hostile nameplate casts targeting your party or raid and displays a circular spell icon on the corresponding EllesmereUI frame. It does not require or load TargetedSpells and contains no floating display containers.

## Install

Keep the `TargetedSpells_EUI` folder in `Interface/AddOns`. The TOC declares EllesmereUI Raid Frames as its only addon dependency. To remove it, delete this folder.

## Position and size

The addon creates `TargetedSpellsEUISaved` automatically. Defaults are a 24 px icon centered on the EUI frame. Edit `size`, `point`, `relativePoint`, `offsetX`, or `offsetY` in the saved variables after the first launch, or change `DEFAULTS` in the Lua file before loading the addon.

## Troubleshooting

Use `/tseui status` to check that the addon, Forever target APIs, and EUI maps are present. Use `/tseui debug` to toggle stage-by-stage logs during a test cast; run it again to turn logging off. Nameplate and cast-start checks are deferred briefly to let unit tokens populate. Logs include event unit tokens and whether a cast, group target, EUI button, and icon were found. They do not print target names, spell IDs, or cast timing values.

## Detection and Forever constraints

Detection listens to unit spellcast, target-change, and nameplate lifecycle events. It uses `UnitSpellTargetName`, `UnitIsSpellTarget` for the exact group member when available, and `PlayerIsSpellTarget` only for the player fallback. It uses cast duration objects and does not parse combat logs or read/convert cast timing values. The icon follows the unit token to its EUI button, including party and raid maps.

This implementation has not been exercised in a live Forever client. It assumes Forever provides the target-query functions used by the existing Forever-aware addon code and delivers the listed unit events for enemy nameplates. If `PlayerIsSpellTarget` is absent, it falls back to checking `caster .. "target"` with `UnitIsUnit`, which depends on Forever exposing that target unit token. Nameplate visibility and the client’s restricted-value rules can limit which casts can be identified.
