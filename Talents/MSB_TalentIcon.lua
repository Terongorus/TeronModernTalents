--[[
	CTalentIcon: Single talent cell extending CIcon.
	Icon + frame (square/circle) + rank text + haze glow.
	Manages visual states: locked, available, partial, maxed.

	Frame shape determined by isExceptional from GetTalentInfo:
	  Exceptional → square frame (spec-defining talents)
	  Normal      → round frame + circular icon mask
--]]

local TALENT_ASSETS = "Interface\\AddOns\\TeronModernTalents\\Assets\\Talents\\"
local TALENT_ICON_SIZE = 30
local TALENT_ICON_SIZE_EXCEPTIONAL = 34

class "CTalentIcon"
:extends("CIcon")
{
	__init = function(self, parent, cell_size)
		self.cell_size = cell_size or 40

		-- Button frame (clickable)
		self.frame = CreateFrame("Button", nil, parent)
		self.frame:SetWidth(self.cell_size)
		self.frame:SetHeight(self.cell_size)

		CIcon.__init(self, self.frame, TALENT_ICON_SIZE)

		-- Default to square frame
		self.border:SetTexture(TALENT_ASSETS .. "talent-frame-square")
		self.border_frame:SetWidth(TALENT_ICON_SIZE + 3.3)
		self.border_frame:SetHeight(TALENT_ICON_SIZE + 3.3)
		if (self.cooldown) then self.cooldown:Hide() end

		-- Haze glow behind the icon (spec-colored, below everything)
		self.haze_frame = CreateFrame("Frame", nil, self.frame)
		self.haze_frame:SetWidth(self.cell_size * 1.7)
		self.haze_frame:SetHeight(self.cell_size * 1.7)
		self.haze_frame:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
		self.haze_frame:SetFrameLevel(self.frame:GetFrameLevel())
		self.haze_tex = self.haze_frame:CreateTexture(nil, "BACKGROUND")
		self.haze_tex:SetAllPoints(self.haze_frame)
		self.haze_tex:SetTexture(TALENT_ASSETS .. "talent-glow")
		self.haze_tex:SetBlendMode("ADD")
		self.haze_tex:SetAlpha(0)

		-- Rank text (bottom-right) - always real rank, unaffected by Plan Mode
		self.rank_text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.rank_text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, 4)
		self.rank_text:SetFont("Fonts\\FRIZQT__.TTF", 9)
		self.rank_text:SetTextColor(0.5, 0.5, 0.5)

		-- Planned/virtual rank text (bottom-left) - shown whenever nonzero, in either mode, so a
		-- plan stays visible while just browsing Learned mode too. Hidden at 0 rather than always
		-- shown like rank_text, since a cyan "0" under nearly every icon would be pure clutter.
		self.plan_rank_text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.plan_rank_text:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)
		self.plan_rank_text:SetFont("Fonts\\FRIZQT__.TTF", 9)
		self.plan_rank_text:SetTextColor(0, 1, 1)
		self.plan_rank_text:Hide()

		-- Talent data
		self.talent_tab = 0
		self.talent_index = 0
		self.tier = 0
		self.column = 0
		self.curr_rank = 0
		self.max_rank = 0
		self.virtual_rank = 0
		self.is_exceptional = false
		self.is_final = false
		self.visual_state = "locked"
		self.talent_name = ""
		self.prereq_tier = nil
		self.prereq_column = nil
		self.prereq_met = true

		-- Event handlers
		local talent_icon = self
		self.frame:SetScript("OnEnter", function()
			talent_icon.hover_glow:Show()
			GameTooltip:SetOwner(talent_icon.frame, "ANCHOR_RIGHT")
			if (GameTooltip.SetTalent) then
				GameTooltip:SetTalent(talent_icon.talent_tab, talent_icon.talent_index)
			else
				GameTooltip:SetText(talent_icon.talent_name)
			end
			GameTooltip:Show()
		end)

		self.frame:SetScript("OnLeave", function()
			talent_icon.hover_glow:Hide()
			GameTooltip:Hide()
		end)

		self.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		self.frame:SetScript("OnClick", function()
			if (TalentTree and TalentTree.mode == "planned") then
				-- No visual_state pre-check here on purpose: PlanTalent/UnplanTalent already
				-- validate everything themselves (max-rank cap, tier/prereq gates, dependent
				-- checks) and silently no-op if the click isn't valid. A blanket "available or
				-- partial" gate here duplicated that logic incorrectly - a fully-planned talent
				-- has visual_state "maxed", which failed the gate and blocked right-click removal
				-- too, even though removing from a maxed plan is exactly what should be allowed.
				if (arg1 == "LeftButton") then
					TalentPlanService:PlanTalent(talent_icon.talent_tab, talent_icon.talent_index)
				elseif (arg1 == "RightButton") then
					TalentPlanService:UnplanTalent(talent_icon.talent_tab, talent_icon.talent_index)
				end
				if (TalentTree.frame:IsVisible()) then
					TalentTree:Refresh()
				end
				return
			end

			if (arg1 == "LeftButton") then
				if (talent_icon.visual_state ~= "available" and talent_icon.visual_state ~= "partial") then
					return
				end
				local gated = ModernTalents_DB and ModernTalents_DB.forceShiftLearn and not IsShiftKeyDown()
				if (gated) then
					return
				end
				if (LearnTalent) then
					LearnTalent(talent_icon.talent_tab, talent_icon.talent_index)
					if (TalentTree and TalentTree.frame:IsVisible()) then
						TalentTree:Refresh()
					end
				end
			end
		end)
	end;

	-- ==================== DATA ===================================

	SetTalentData = function(self, tab, index)
		self.talent_tab = tab
		self.talent_index = index

		local name, iconTexture, tier, column, currRank, maxRank, isExceptional = GetTalentInfo(tab, index)
		if (not name) then return end

		self.talent_name = name
		self.tier = tier
		self.column = column
		self.curr_rank = currRank
		self.max_rank = maxRank
		self.is_exceptional = (isExceptional and isExceptional == 1)
		self.icon_texture = iconTexture

		-- Query prerequisites
		self.prereq_tier, self.prereq_column = MSB_GetTalentPrereqs(tab, index)

		self:ApplyFrameShape()
		self.rank_text:SetText(currRank .. "/" .. maxRank)

		self.virtual_rank = TalentPlanService:GetPlannedRank(tab, index)
		if (self.virtual_rank > 0) then
			self.plan_rank_text:SetText(self.virtual_rank .. "/" .. maxRank)
			self.plan_rank_text:Show()
		else
			self.plan_rank_text:Hide()
		end
	end;

	RefreshRank = function(self)
		local _, _, _, _, currRank, maxRank = GetTalentInfo(self.talent_tab, self.talent_index)
		if (currRank) then
			self.curr_rank = currRank
			self.max_rank = maxRank
			self.rank_text:SetText(currRank .. "/" .. maxRank)
		end

		self.virtual_rank = TalentPlanService:GetPlannedRank(self.talent_tab, self.talent_index)
		if (self.virtual_rank > 0) then
			self.plan_rank_text:SetText(self.virtual_rank .. "/" .. self.max_rank)
			self.plan_rank_text:Show()
		else
			self.plan_rank_text:Hide()
		end
	end;

	-- Effective rank used for *visual state* decisions (locked/available/partial/maxed, tier
	-- unlock, connection/gridline coloring) - switches to the virtual rank in Plan Mode so the
	-- whole grid can simulate a build, while curr_rank/rank_text stay real-always regardless of
	-- mode for the always-visible real-progress display.
	GetStateRank = function(self)
		if (TalentTree and TalentTree.mode == "planned") then
			return self.virtual_rank
		end
		return self.curr_rank
	end;

	-- =================== FRAME SHAPE =============================

	ApplyFrameShape = function(self)
		-- Fancy overlay for final talent (additional, not replacing border)
		if (self.is_final and self.is_exceptional and not self.fancy_frame) then
			local fancy_size = TALENT_ICON_SIZE_EXCEPTIONAL + 18
			self.fancy_frame = CreateFrame("Frame", nil, self.frame)
			self.fancy_frame:SetWidth(fancy_size)
			self.fancy_frame:SetHeight(fancy_size)
			self.fancy_frame:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
			self.fancy_frame:SetFrameLevel(self.frame:GetFrameLevel() + 4)
			self.fancy_tex = self.fancy_frame:CreateTexture(nil, "OVERLAY")
			self.fancy_tex:SetAllPoints(self.fancy_frame)
			self.fancy_tex:SetTexture(TALENT_ASSETS .. "talent-frame-square-fancy")
		end

		if (self.is_exceptional) then
			self.icon:SetTexture(self.icon_texture)
			self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			self.icon:SetWidth(TALENT_ICON_SIZE_EXCEPTIONAL)
			self.icon:SetHeight(TALENT_ICON_SIZE_EXCEPTIONAL)
			
			self.hover_frame:SetWidth(TALENT_ICON_SIZE_EXCEPTIONAL)
			self.hover_frame:SetHeight(TALENT_ICON_SIZE_EXCEPTIONAL)
			self.hover_glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")

			self.border:SetTexture(TALENT_ASSETS .. "talent-frame-square")
			self.socket:SetTexture(TALENT_ASSETS .. "talent-socket-square")
			self.border_frame:SetWidth(TALENT_ICON_SIZE_EXCEPTIONAL + 3.3)
			self.border_frame:SetHeight(TALENT_ICON_SIZE_EXCEPTIONAL + 3.3)
			self.socket:SetWidth(self.size + 2)
			self.socket:SetHeight(self.size + 2)

			-- Exceptional icons have a visibly larger border (and, if also final, an even bigger
			-- "fancy" overlay) than regular circular ones, so the standard rank-text offset left
			-- almost no clearance between the text and the icon's own border - push both further
			-- down/out to match.
			self.rank_text:ClearAllPoints()
			self.rank_text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, -5)
			self.plan_rank_text:ClearAllPoints()
			self.plan_rank_text:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, -5)
		else

			SetPortraitToTexture(self.icon, self.icon_texture)
			SetPortraitToTexture(self.hover_glow, "Interface\\Buttons\\CheckButtonHilight")

			self.border:SetTexture(TALENT_ASSETS .. "talent-frame-circle")
			self.socket:SetTexture(TALENT_ASSETS .. "talent-socket-circle")
			self.socket:SetWidth(self.size + 4)
			self.socket:SetHeight(self.size + 4)

			self.rank_text:ClearAllPoints()
			self.rank_text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, 4)
			self.plan_rank_text:ClearAllPoints()
			self.plan_rank_text:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)
		end
		self.socket:Show()
	end;

	-- ================== VISUAL STATE =============================

	UpdateVisualState = function(self, points_spent, prereq_checker, points_remaining)
		local required_points = (self.tier - 1) * 5

		-- Check if prerequisite talent is maxed
		self.prereq_met = true
		if (self.prereq_tier and prereq_checker) then
			self.prereq_met = prereq_checker(self.prereq_tier, self.prereq_column)
		end

		self.tier_unlocked = (points_spent >= required_points)

		local state_rank = self:GetStateRank()
		if (state_rank == self.max_rank) then
			self.visual_state = "maxed"
		elseif (state_rank > 0) then
			self.visual_state = "partial"
		elseif (self.tier_unlocked and self.prereq_met and points_remaining and points_remaining > 0) then
			self.visual_state = "available"
		elseif (self.tier_unlocked and not (UnitLevel("player") >= 60 and (not points_remaining or points_remaining <= 0))) then
			self.visual_state = "locked_in_unlocked_tier"
		else
			self.visual_state = "locked_in_locked_tier"
		end

		self:ApplyVisualState()
	end;

	ApplyVisualState = function(self)
		local state = self.visual_state
		
		self.socket:SetAlpha(1)
		
		local is_completely_locked = (state == "locked_in_locked_tier")
		local is_locked = (state == "locked_in_locked_tier") or (state == "locked_in_unlocked_tier")
		
		if (is_completely_locked) then
			
			self.rank_text:SetTextColor(0.5, 0.5, 0.5)
		
			if (self.is_exceptional) then
                self.icon:SetAlpha(0.3)
                self.border:SetAlpha(0.5)
            else
                self.icon:SetAlpha(0.3)
    			self.border:SetAlpha(0.5)
            end
			
		else
			self.rank_text:SetTextColor(1, 1, 1)
			self.icon:SetAlpha(1)
			self.border:SetAlpha(1)
		end
		
		self:SetDesaturated(is_locked)
		if (self.fancy_tex) then
            self.fancy_tex:SetDesaturated(is_locked)
        end
		
		if (is_locked) then
			self.hover_glow:Hide()
			if (self.fancy_tex) then
				self.fancy_tex:SetAlpha(0.6)
			end
		end

		if (state == "locked_in_locked_tier") then
			self.haze_tex:SetAlpha(0)
			self:ApplyFrameShape()
		elseif (state == "locked_in_unlocked_tier") then
			self.haze_tex:SetAlpha(0)
			self:ApplyFrameShape()
		elseif (state == "available") then
			self.haze_tex:SetAlpha(1.0)
			if (self.is_exceptional) then
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-square-green")
			else
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-circle-green")
			end
        elseif (state == "partial") then
			self.haze_tex:SetAlpha(0.7)
			if (self.is_exceptional) then
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-square-green")
			else
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-circle-green")
			end
		elseif (state == "maxed") then
			self.haze_tex:SetAlpha(0.7)
			if (self.is_exceptional) then
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-square-gold")
			else
				self.border:SetTexture(TALENT_ASSETS .. "talent-frame-circle-gold")
			end
		end

		-- hover_glow uses Interface\Buttons\CheckButtonHilight with no vertex color override, so
		-- it shows that texture's own natural (yellow-green) tint on hover - fine over a green
		-- "available"/"partial" border, but visibly clashes and shifts a gold "maxed" border
		-- toward looking green. Tint it to match whichever state is actually active instead.
		if (state == "maxed") then
			self.hover_glow:SetVertexColor(1, 0.9, 0.5)
		elseif (state == "available" or state == "partial") then
			self.hover_glow:SetVertexColor(0.6, 1, 0.6)
		else
			self.hover_glow:SetVertexColor(1, 1, 1)
		end
	end;

	-- ================== POSITIONING ==============================

	SetGridPosition = function(self, row, col, offset_x, offset_y)
		self.frame:ClearAllPoints()
		self.frame:SetPoint("TOPLEFT", self.frame:GetParent(), "TOPLEFT",
			offset_x + col * self.cell_size,
			-(offset_y + row * self.cell_size))
	end;

	-- =================== HAZE ====================================

	SetHazeColor = function(self, r, g, b)
		self.haze_tex:SetVertexColor(r, g, b)
	end;

	-- ===================== DELEGATION ============================

	Hide = function(self)
		self.frame:Hide()
	end;

	Show = function(self)
		self.frame:Show()
	end;
}
