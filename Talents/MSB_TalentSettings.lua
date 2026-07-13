--[[
	CTalentSettings: Settings dropdown for the talent tree window.
	Grid line toggles, coloring, visibility, reset position/scale.
	Force-shift-click-learn and talent plan switching/renaming/clearing both live in their own
	always-visible top-bar widgets (CTalentTree, see MSB_TalentTree.lua) rather than here - the
	StaticPopupDialogs entries for renaming/clearing a plan are still registered in this file
	since they're popup-system plumbing, but the top-bar buttons are what trigger them.
--]]

-- This client's native StaticPopup implementation normally passes the dialog frame as an explicit
-- first parameter to OnShow/OnAccept, and exposes its edit box as a direct `.editBox` field -
-- confirmed against TeronRosterFilter's own working hasEditBox popup. But some addons (e.g.
-- _LazyPig) cache and re-wrap StaticPopup_OnShow themselves, calling the cached original with
-- zero arguments from inside a plain function rather than a widget script; going through that
-- indirection left both `self` nil AND `.editBox` unpopulated, even though `this` still correctly
-- resolves to the dialog and the edit box still exists as the client's own named global widget
-- (StaticPopup1EditBox etc.) regardless. Falls back through both: `self or this` for the dialog,
-- then `.editBox` or a getglobal(name.."EditBox") lookup for the edit box - whichever path the
-- popup got shown through, at least one of each pair is reliably correct.
local function MSB_TalentPlanRename_GetEditBox(dialog)
	return dialog.editBox or getglobal(dialog:GetName() .. "EditBox")
end

local function MSB_TalentPlanRename_Apply(popupFrame)
	local editBox = MSB_TalentPlanRename_GetEditBox(popupFrame)
	TalentPlanService:RenamePlan(TalentPlanService:GetActivePlanIndex(), editBox:GetText())
	if (TalentTree) then
		TalentTree:RefreshPlanDropdown()
		TalentTree:Refresh()
	end
end

StaticPopupDialogs["MSB_TALENT_PLAN_RENAME"] = {
	text = "Rename the current template:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnShow = function(self)
		local dialog = self or this
		local editBox = MSB_TalentPlanRename_GetEditBox(dialog)
		editBox:SetText(TalentPlanService:GetPlanName(TalentPlanService:GetActivePlanIndex()))
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	-- Unlike OnShow (which fires bound to the dialog itself), OnAccept fires from the Accept
	-- button's own OnClick ([string "StaticPopup1Button1:OnClick"] in the trace that caught this),
	-- so `self`/`this` here is the BUTTON, not the dialog - confirmed by both the field and
	-- getglobal fallbacks failing identically, since both were resolving names relative to the
	-- wrong frame. :GetParent() on the button reaches the dialog, same as the edit box's own
	-- handlers below already do for the same reason.
	OnAccept = function(self)
		MSB_TalentPlanRename_Apply((self or this):GetParent())
	end,
	EditBoxOnEnterPressed = function(self)
		local popup = (self or this):GetParent()
		MSB_TalentPlanRename_Apply(popup)
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		(self or this):GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["MSB_TALENT_PLAN_CLEAR"] = {
	text = "Clear all planned talents in the current template? This can't be undone.",
	button1 = "Clear",
	button2 = CANCEL,
	OnAccept = function()
		TalentPlanService:ClearPlan(TalentPlanService:GetActivePlanIndex())
		if (TalentTree) then
			TalentTree:Refresh()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

class "CTalentSettings"
{
	__init = function(self, parent, talentTree)
		self.talent_tree = talentTree

		-- Gear button
		self.button = CreateFrame("Button", nil, parent)
		self.button:SetWidth(20)
		self.button:SetHeight(20)
		self.button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -22)
		self.button:SetFrameLevel(parent:GetFrameLevel() + 20)
		self.button:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
		self.button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
		self.button:SetPushedTexture("Interface\\Icons\\INV_Misc_Gear_01")

		-- Dropdown
		local dropdown = CreateFrame("Frame", "ModernTalentSettingsDropDown", parent)
		dropdown.displayMode = "MENU"
		local settings = self
		dropdown.initialize = function(level)
			settings:InitializeDropdown(level)
		end

		local btn = self.button
		self.button:SetScript("OnClick", function()
			ToggleDropDownMenu(1, nil, dropdown, btn, 0, 0)
		end)
	end;

	Anchor = function(self, anchorFrame)
		self.button:ClearAllPoints()
		self.button:SetPoint("LEFT", anchorFrame, "RIGHT", 8, 0)
	end;

	InitializeDropdown = function(self, level)
		level = level or 1
		local tree = self.talent_tree

		if (level == 1) then
			-- Grid lines submenu
			local info = {}
			info.text = "Grid lines"
			info.hasArrow = 1
			info.notCheckable = 1
			info.value = "gridLines"
			UIDropDownMenu_AddButton(info, level)

			-- Reset position & scale
			info = {}
			info.text = "Reset position & scale"
			info.notCheckable = 1
			info.func = function()
				local db = MSB_EnsureTalentsDB()
				db.position = nil
				db.scale = nil
				tree.frame:SetScale(1)
				tree.frame:ClearAllPoints()
				tree.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)

		elseif (level == 2) then
			if (UIDROPDOWNMENU_MENU_VALUE == "gridLines") then
				local msbTalentsDB = MSB_EnsureTalentsDB()
				if (not msbTalentsDB.gridLines) then
					msbTalentsDB.gridLines = { vertical = true, diagonal = true, horizontal = true }
				end
				local gl = msbTalentsDB.gridLines

				local info = {}
				info.text = "Vertical"
				info.checked = gl.vertical
				info.keepShownOnClick = 1
				info.func = function()
					gl.vertical = not gl.vertical
					tree:RebuildAllGrids()
				end
				UIDropDownMenu_AddButton(info, level)

				info = {}
				info.text = "Diagonal"
				info.checked = gl.diagonal
				info.keepShownOnClick = 1
				info.func = function()
					gl.diagonal = not gl.diagonal
					tree:RebuildAllGrids()
				end
				UIDropDownMenu_AddButton(info, level)

				info = {}
				info.text = "Horizontal"
				info.checked = gl.horizontal
				info.keepShownOnClick = 1
				info.func = function()
					gl.horizontal = not gl.horizontal
					tree:RebuildAllGrids()
				end
				UIDropDownMenu_AddButton(info, level)

				-- Coloring submenu
				info = {}
				info.text = "Coloring"
				info.hasArrow = 1
				info.notCheckable = 1
				info.value = "gridLineColoring"
				UIDropDownMenu_AddButton(info, level)

				-- Visibility submenu
				info = {}
				info.text = "Visibility"
				info.hasArrow = 1
				info.notCheckable = 1
				info.value = "gridLineVisibility"
				UIDropDownMenu_AddButton(info, level)
			end

		elseif (level == 3) then
			if (UIDROPDOWNMENU_MENU_VALUE == "gridLineVisibility") then
				local msbTalentsDB = MSB_EnsureTalentsDB()
				if (not msbTalentsDB.gridLines) then
					msbTalentsDB.gridLines = { vertical = true, diagonal = true, horizontal = true }
				end
				local gl = msbTalentsDB.gridLines
				local visibility = gl.visibility or "unlocked"

				local info = {}
				info.text = "Always"
				info.checked = (visibility == "always")
				info.func = function()
					gl.visibility = "always"
					tree:Refresh()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)

				info = {}
				info.text = "Only unlocked"
				info.checked = (visibility == "unlocked")
				info.func = function()
					gl.visibility = "unlocked"
					tree:Refresh()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)

			elseif (UIDROPDOWNMENU_MENU_VALUE == "gridLineColoring") then
				local msbTalentsDB = MSB_EnsureTalentsDB()
				if (not msbTalentsDB.gridLines) then
					msbTalentsDB.gridLines = { vertical = true, diagonal = true, horizontal = true }
				end
				local gl = msbTalentsDB.gridLines
				local coloring = gl.coloring or "unlocked"

				local info = {}
				info.text = "Always"
				info.checked = (coloring == "always")
				info.func = function()
					gl.coloring = "always"
					tree:Refresh()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)

				info = {}
				info.text = "Only unlocked"
				info.checked = (coloring == "unlocked")
				info.func = function()
					gl.coloring = "unlocked"
					tree:Refresh()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)

				info = {}
				info.text = "Never"
				info.checked = (coloring == "never")
				info.func = function()
					gl.coloring = "never"
					tree:Refresh()
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end;
}
