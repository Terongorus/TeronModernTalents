--[[
	CTalentPlanService: manages up to 20 named per-character talent plans ("Plan Mode").
	A plan is an independent, virtual point allocation - it never reflects real talent state and
	never calls LearnTalent. Assigning/removing a virtual point only ever mutates
	ModernTalents_DB.templates; CTalentIcon/CTalentGrid read it the same way they read real
	GetTalentInfo/GetTalentTabInfo data, via TalentTree.mode switching which source is "current".
--]]

local MAX_PLAN_COUNT = 20
local CHAT_PREFIX = "|cff00ff00ModernTalents:|r "

class "CTalentPlanService"
{
	__init = function(self)
	end;

	-- =================== DB / PLAN LIFECYCLE ======================

	GetMaxPlanCount = function(self)
		return MAX_PLAN_COUNT
	end;

	-- MSB_EnsureTalentsDB() (MSB_TalentCompat.lua) checks and repairs ModernTalents_DB itself
	-- immediately before use, rather than trusting any one-time load-time guarantee - confirmed
	-- live that a load-time-only fix isn't reliable (the global can still be nil well after this
	-- addon's files finish loading). A throwaway placeholder table used to be returned here
	-- instead of crashing when ModernTalents_DB was nil, but that meant Plan Mode writes silently
	-- never persisted whenever this path was hit - now it always mutates the real table.
	EnsureDB = function(self)
		local db = MSB_EnsureTalentsDB()
		if (not db.templates) then
			db.templates = { selectedPlan = 1, plans = {} }
		end
		return db.templates
	end;

	-- Only the requested slot is created (never all 20 up front), matching the reference addon's
	-- own lazy-slot behavior and keeping SavedVariables lean.
	EnsurePlan = function(self, planIndex)
		local db = self:EnsureDB()
		if (not db.plans[planIndex]) then
			db.plans[planIndex] = {
				name = "Template " .. planIndex,
				points = 0,
				[1] = { points = 0 },
				[2] = { points = 0 },
				[3] = { points = 0 },
			}
		end
		return db.plans[planIndex]
	end;

	GetActivePlanIndex = function(self)
		return self:EnsureDB().selectedPlan
	end;

	SetActivePlan = function(self, idx)
		if (idx < 1) then idx = 1 end
		if (idx > MAX_PLAN_COUNT) then idx = MAX_PLAN_COUNT end
		self:EnsureDB().selectedPlan = idx
		self:EnsurePlan(idx)
		self:RepairPlan(idx)
	end;

	-- Recomputes each tab's point rollup as the true sum of its talent entries (fixing any
	-- desync), then repeatedly trims any talent that no longer satisfies its own tier requirement
	-- or prereq-maxed requirement given that rollup - repeating until a full pass finds nothing
	-- left to trim, since removing one violator can drop the total enough to invalidate another
	-- that was previously borderline-valid. Safety net against any plan left in an inconsistent
	-- state by an earlier, buggier version of PlanTalent/UnplanTalent - SavedVariables persist
	-- across /reload, so old corruption doesn't just go away on its own once the validation logic
	-- is fixed; only newly-created invalid states are prevented, not existing ones repaired.
	RepairPlan = function(self, idx)
		local plan = self:EnsurePlan(idx)
		local tab
		for tab = 1, 3 do
			local tabData = plan[tab]
			if (tabData) then
				local sum = 0
				local i
				for i = 1, GetNumTalents(tab) do
					sum = sum + (tabData[i] or 0)
				end
				tabData.points = sum

				local changed = true
				while (changed) do
					changed = false
					for i = 1, GetNumTalents(tab) do
						local rank = tabData[i] or 0
						if (rank > 0) then
							local _, _, tier = GetTalentInfo(tab, i)
							local ok = not (tier and tabData.points < (tier - 1) * 5)
							if (ok) then
								local prereqTier, prereqCol = MSB_GetTalentPrereqs(tab, i)
								if (prereqTier) then
									local prereqMaxed = false
									local j
									for j = 1, GetNumTalents(tab) do
										local _, _, t, c, _, pMax = GetTalentInfo(tab, j)
										if (t == prereqTier and c == prereqCol) then
											prereqMaxed = (tabData[j] or 0) >= pMax
											break
										end
									end
									ok = prereqMaxed
								end
							end
							if (not ok) then
								tabData.points = tabData.points - rank
								tabData[i] = nil
								changed = true
							end
						end
					end
				end
			end
		end

		local total = 0
		local t
		for t = 1, 3 do
			total = total + ((plan[t] and plan[t].points) or 0)
		end
		plan.points = total
	end;

	GetActivePlan = function(self)
		return self:EnsurePlan(self:GetActivePlanIndex())
	end;

	-- Returns a display name even for a slot that's never been touched, so the settings submenu
	-- can list all 20 slots without silently creating 20 SavedVariables entries just to show them.
	GetPlanName = function(self, idx)
		local plan = self:EnsureDB().plans[idx]
		if (plan and plan.name) then
			return plan.name
		end
		return "Template " .. idx .. " (empty)"
	end;

	RenamePlan = function(self, idx, name)
		if (not name or name == "") then return end
		self:EnsurePlan(idx).name = name
	end;

	-- Wipes a slot's talent data but keeps its name, matching the intuitive "clear this template"
	-- action rather than deleting the named slot entirely.
	ClearPlan = function(self, idx)
		local name = self:GetPlanName(idx)
		self:EnsureDB().plans[idx] = nil
		local fresh = self:EnsurePlan(idx)
		fresh.name = name
	end;

	-- =================== QUERY ===================================

	GetPlannedRank = function(self, tab, talentID)
		local tabData = self:GetActivePlan()[tab]
		return (tabData and tabData[talentID]) or 0
	end;

	GetTabPlannedPoints = function(self, tab)
		local tabData = self:GetActivePlan()[tab]
		return (tabData and tabData.points) or 0
	end;

	GetTotalPlannedPoints = function(self)
		return self:GetActivePlan().points or 0
	end;

	-- ================ DEPENDENT-TALENT HELPERS ====================

	-- Deepest tier (1-based) with any virtual rank in `tab`. Recomputed fresh every call rather
	-- than using a fixed constant (e.g. the grid's row count) - a fixed bound would false-positive
	-- block a removal against tiers that have nothing planned in them at all.
	GetDeepestPlannedTier = function(self, tab)
		local tabData = self:GetActivePlan()[tab]
		if (not tabData) then return 0 end
		local deepest = 0
		local i
		for i = 1, GetNumTalents(tab) do
			if ((tabData[i] or 0) > 0) then
				local _, _, tier = GetTalentInfo(tab, i)
				if (tier and tier > deepest) then
					deepest = tier
				end
			end
		end
		return deepest
	end;

	-- Talents in `tab` whose prerequisite is exactly (prereqTier, prereqColumn). Tier/column pairs
	-- are unique per tab (the same identity CTalentGrid already relies on for connection routing),
	-- so an exact match reliably finds every true dependent with no false positives/negatives.
	GetDependentTalentIndices = function(self, tab, prereqTier, prereqColumn)
		local dependents = {}
		local i
		for i = 1, GetNumTalents(tab) do
			local pTier, pCol = MSB_GetTalentPrereqs(tab, i)
			if (pTier == prereqTier and pCol == prereqColumn) then
				table.insert(dependents, i)
			end
		end
		return dependents
	end;

	-- =================== MUTATION =================================

	PlanTalent = function(self, tab, talentID)
		local name, _, tier, _, _, maxRank = GetTalentInfo(tab, talentID)
		if (not name) then return end

		local plan = self:GetActivePlan()
		local tabData = plan[tab]
		local curPlanned = tabData[talentID] or 0

		if (curPlanned >= maxRank) then return end
		-- Plan Mode simulates a max-level (60) build, not points already earned at your current
		-- level - always cap against the theoretical maximum, not MSB_GetTotalTalentPointsAvailable.
		if ((plan.points or 0) >= MSB_GetMaxTalentPointsEver()) then return end

		local requiredTierPoints = (tier - 1) * 5
		if ((tabData.points or 0) < requiredTierPoints) then return end

		local prereqTier, prereqCol = MSB_GetTalentPrereqs(tab, talentID)
		if (prereqTier) then
			local prereqMaxed = false
			local i
			for i = 1, GetNumTalents(tab) do
				local _, _, t, c, _, pMax = GetTalentInfo(tab, i)
				if (t == prereqTier and c == prereqCol) then
					prereqMaxed = (tabData[i] or 0) >= pMax
					break
				end
			end
			if (not prereqMaxed) then return end
		end

		tabData[talentID] = curPlanned + 1
		tabData.points = (tabData.points or 0) + 1
		plan.points = (plan.points or 0) + 1
	end;

	UnplanTalent = function(self, tab, talentID)
		local name, _, tier, column, _, maxRank = GetTalentInfo(tab, talentID)
		if (not name) then return end

		local plan = self:GetActivePlan()
		local tabData = plan[tab]
		local curPlanned = tabData[talentID] or 0
		if (curPlanned <= 0) then return end

		-- Would this un-max a prereq that a still-planned dependent relies on? Only relevant if
		-- the talent is *currently* maxed - "newRank < maxRank" was true for nearly every
		-- decrement (e.g. 2/3 -> 1/3 also satisfies newRank < maxRank), which ran this dependent
		-- check - and blocked the removal whenever ANY dependent had ANY planned rank - on almost
		-- every single removal attempt, not just ones that actually un-max something.
		local newRank = curPlanned - 1
		if (curPlanned == maxRank) then
			local dependents = self:GetDependentTalentIndices(tab, tier, column)
			local d
			for d = 1, table.getn(dependents) do
				local depID = dependents[d]
				if ((tabData[depID] or 0) > 0) then
					local depName = GetTalentInfo(tab, depID) or "a dependent talent"
					DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Can't remove that planned point - " ..
						depName .. " is still planned and requires it maxed.")
					return
				end
			end
		end

		-- Would this drop the tab's planned total below what some talent that still has virtual
		-- rank afterward requires for its own tier? Checks every talent's rank *after* this
		-- removal, including the one being decremented itself (if it's only a partial decrement,
		-- e.g. 2 -> 1, its own remaining rank must still satisfy its own tier requirement against
		-- the new total too, not just other talents').
		local newTabPoints = (tabData.points or 0) - 1
		local i
		for i = 1, GetNumTalents(tab) do
			local rankAfter = (i == talentID) and newRank or (tabData[i] or 0)
			if (rankAfter > 0) then
				local _, _, otherTier = GetTalentInfo(tab, i)
				if (otherTier and newTabPoints < (otherTier - 1) * 5) then
					DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX ..
						"Can't remove that planned point - another planned talent needs this tier's points.")
					return
				end
			end
		end

		tabData[talentID] = (newRank > 0) and newRank or nil
		tabData.points = newTabPoints
		plan.points = (plan.points or 0) - 1
		if (plan.points < 0) then plan.points = 0 end
	end;
}

TalentPlanService = CTalentPlanService()
