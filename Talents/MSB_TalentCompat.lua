-- Talent-tree-specific compatibility helpers. Generic polyfills (C_Timer, string.gmatch,
-- HookScript, etc.) live in TeronModernCore's MSB_Compat.lua instead - these three are kept
-- separate because they're specific to talent point/prerequisite math, not generic environment
-- shims.

-- CTalentTree builds its entire UI (including widgets with OnClick handlers that write straight
-- to ModernTalents_DB) synchronously in __init at file-load time, not gated behind ADDON_LOADED
-- the way TeronModernSpellBook's own frame construction is. A one-time guard here at file-load
-- ("if not ModernTalents_DB then ModernTalents_DB = {} end") was NOT enough - confirmed live,
-- the exact same "attempt to index global ModernTalents_DB (a nil value)" crash recurred on a
-- later click even with that guard in place, meaning something after this file runs (most likely
-- the client's own SavedVariablesPerCharacter assignment for a still-brand-new, never-saved-to-disk
-- character/addon pair) can still clobber it back to nil afterward. A load-time fix can't win that
-- race no matter where it's placed, since the clobber happens later. MSB_EnsureTalentsDB() instead
-- checks and repairs the global immediately before every actual write, with zero time gap between
-- the check and the use, which is safe regardless of what happens in between calls.
function MSB_EnsureTalentsDB()
	if (not ModernTalents_DB) then
		ModernTalents_DB = {}
	end
	return ModernTalents_DB
end

-- GetTalentPrereqs isn't available on every client build; wrapped in pcall so a missing/erroring
-- API degrades to "no prerequisite" instead of breaking the caller. Shared between the real
-- talent icon setup and the talent-plan service's own dependent-talent lookups, so both use the
-- exact same defensive call.
function MSB_GetTalentPrereqs(tab, index)
    if (not GetTalentPrereqs) then
        return nil, nil
    end
    local ok, pTier, pCol = pcall(GetTalentPrereqs, tab, index)
    if (ok and pTier and pTier > 0) then
        return pTier, pCol
    end
    return nil, nil
end

-- Total talent points a character has ever earned (spent + unspent), independent of any one
-- talent tab. Vanilla/Turtle: 1 point per level from 10 onward.
function MSB_GetTotalTalentPointsAvailable()
    local n = UnitLevel("player") - 9
    if (n < 0) then n = 0 end
    return n
end

-- The most talent points a character could ever have at max level (60), regardless of the
-- player's actual current level. Plan Mode uses this instead of MSB_GetTotalTalentPointsAvailable
-- - a plan is a theorycrafted end-state build, not limited to points already earned.
function MSB_GetMaxTalentPointsEver()
    return 51
end
