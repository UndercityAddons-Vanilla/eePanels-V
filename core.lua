--[[
-- TODO:
-- implement caching for individual menu tables(http://www.wowace.com/wiki/Coding_Tips)
-- come up with better frame check.  If not possible, try using table caching
-- Move menu stuff to a separate file
-- put in 'warning' system
-- cleanup my ugly ass guidePanel implementation
-- reduce table lookups:: create a local value for tables when doing more than 1 access to a key
-- change my "eePanels:" notation.  Use "self:" inside all of my functions.  Refer to all "addon-global" variables as self.localVarName.foo
--]]

local L  = AceLibrary("AceLocale-2.2"):new("eePanels")
local tablet = AceLibrary("Tablet-2.0")

 

-- Keys in the following tables are actually what we use in our frames.
-- Values are the localized strings associated with them.  We do this because
-- AceOption tables display the value of associative tables, not the key
local bgColorStyleOpt		= { ["Solid"] = L["Solid"], ["Gradient"] = L["Gradient"] }
local borderTextureOpt		= { [""] = L["None"], ["Interface\\Tooltips\\UI-Tooltip-Border"]=L["Tooltip"], ["Interface\\DialogFrame\\UI-DialogBox-Border"]=L["Dialog"] }
local bgGradOrientationOpt	= { ["HORIZONTAL"]=L["Horizontal"], ["VERTICAL"]=L["Vertical"]}
local frameStrataOpt		= { ["BACKGROUND"]=L["Background"], ["LOW"]=L["Low"], ["MEDIUM"]=L["Medium"], ["HIGH"]=L["High"], ["DIALOG"]=L["Dialog"], ["TOOLTIP"]=L["Tooltip"] }
local blendModeOpt			= { ["DISABLE"]=L["Disable"], ["BLEND"]=L["Blend"], ["ADD"]=L["Add"], ["MOD"]=L["Mod"] }


--[[
-- Confirm + reset all panels
--]]
StaticPopupDialogs["EEPANELSRESET"] = 
{
	text = L["Reset?"],
	button1 = L["Yes"],
	button2 = L["No"],
	OnAccept = function() eePanels:Reset() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1
}

StaticPopupDialogs["EEPUPGRADEWARNING"] =
{
	text = "eePanels: a new version of this addon is about to come out, but your current layout won't be compatible.  Don't upgrade if you don't want to lose your settings",
	button1 = "OK",
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}


--[[
-- Round a number to the nearest integer
--]]
function math.round( n )
	dec_places = 0
	shift = 10^dec_places
	return math.floor ((n*shift)+0.5)/shift
end


--[[
-- Return a deep copy of a table
--]]
function deepCopy(t, lookup_table)
	local copy = {}
	for i,v in pairs(t) do
		if type(v) ~= "table" then
			copy[i] = v
		else
			lookup_table = lookup_table or {}
			lookup_table[t] = copy
			if lookup_table[v] then
				copy[i] = lookup_table[v] -- we already copied this table. reuse the copy.
			else
				copy[i] = deepCopy(v,lookup_table) -- not yet copied. copy it.
			end
		end
	end
	return copy
end


--[[
-- Returns the key associated with value in table
--]]
function rLookup(table,value)
	for k,v in pairs(table) do
		if v == value then return k end
	end
	return nil
end


-- Default panel settings
local dp = 
{
	parent = "UIParent",
	frame = nil,
	guideFrame = nil,
	name = "",
	x = 0,
	y = 0,
	width = 200,
	height = 100,
	visible = true,
	level = 0,
	strata = rLookup(frameStrataOpt, L["Background"]),
	mouse = false,
	texture = "",
	media = "",
	textureAlpha = 1,
	border = 
	{
		color = {r=1,g=1,b=1,a=1},
		texture = rLookup(borderTextureOpt, L["Tooltip"]),
		edgeSize = 16,
		media = "",
	},
	background = 
	{
		frame = nil,
		style = rLookup(bgColorStyleOpt, L["Solid"]),
		color = {r=0,g=0,b=0,a=0.8},
		insetSize = 5,
		tiling = false,
		tileSize = 0,
		gradient =
		{
			blend = rLookup(blendModeOpt, L["Disable"]),-- should have been in table above, not in gradient
			offset = 0,
			color = {r=1,g=1,b=1,a=0},
			orientation = rLookup(bgGradOrientationOpt, L["Horizontal"])
		}
	},
}

--[[
-- Default AceDB settings
--]]
local defaults = 
{
	panels = {},
	defaultPanel = deepCopy(dp), -- should change this variable name; it actually stores the global panel settings
	isLocked = true,
	isAdvanced = false,
	warningShown = false,
}

local frameFound = {}

--[[
-- Initialize our addon
--]]
eePanels = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0", "AceConsole-2.0", "AceDB-2.0", "FuBarPlugin-2.0")
eePanels :RegisterDB("eePanelsDB")
local SharedMedia = AceLibrary("SharedMedia-1.0")

--[[
-- AceOption table
--]]
eePanels.menu = 
{ 
	type='group',
	args = 
	{
		lock = 
		{
			type = 'toggle',
			name = L["Lock"],
			desc = L["LockDesc"],
			get  = function() return eePanels.db.profile.isLocked end,
			set  = function(v) eePanels:ToggleLock() end,
			order = 1,
		},
		
		mode = 
		{
			type = 'toggle',
			name = L["Mode"],
			desc = L["ModeDesc"],
			get  = function() return eePanels.db.profile.isAdvanced end,
			set  = function(v) eePanels.db.profile.isAdvanced = not eePanels.db.profile.isAdvanced eePanels:CreateMenus() end,
			order = 2,
		},

		newPanel = 
		{
			type = 'group',
			name = L["NewPanel"],
			desc = L["NewPanelDesc"],
			order = 3,
			args = 
			{
			
				defaultPanel = 
				{
					type = 'execute',
					name = L["DefaultPanel"],
					desc = L["DefaultPanelDesc"],
					func = function(v) eePanels:CreatePanel(2) end,
					order = 1
				},
			
				globalPanel = 
				{
					type = 'execute',
					name = L["GlobalPanel"],
					desc = L["GlobalPanelDesc"],
					func = function(v) eePanels:CreatePanel(1) end,
					order = 2
				},
			}
		},

		globalSettings = 
		{
			type = 'group',
			name = L["GlobalSettings"],
			desc = L["GlobalSettingsDesc"],
			func = function() end,
			hidden = function() return not (table.getn(eePanels.db.profile.panels) > 0) end,
			order = 4,
			args = 
			{
			
				borderColor = 
				{
					name = L["BorderColor"], desc = L["BorderColorDesc"], type='color',
					get = function()
						local panel = eePanels.db.profile.defaultPanel
						return panel.border.color.r,panel.border.color.g,panel.border.color.b,panel.border.color.a 
					end,
					set = function(ir,ig,ib,ia)
						local panel = eePanels.db.profile.defaultPanel
						panel.border.color = {r=ir,g=ig,b=ib,a=ia} 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].border.color = {r=ir,g=ig,b=ib,a=ia} 
							eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
						end
					end,
					hasAlpha = true,
					order = 10,
				},
			
				borderTexture = 
				{
					type = "group",
					name = L["BorderTexture"], 
					desc = L["BorderTextureDesc"],
					order = 10,
					args = {
						Standard = {
							type = "text", 
							name = L["TextureShared"], 
							desc = L["TextureSharedDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								local panel = eePanels.db.profile.defaultPanel
								return panel.border.media
								end,
							set = function(t) 
								local panel = eePanels.db.profile.defaultPanel
								local sl = SharedMedia:Fetch('border', t)
								panel.border.media = t
								panel.border.texture = sl 
								for i in pairs(eePanels.db.profile.panels) do
									eePanels.db.profile.panels[i].border.media = t
									eePanels.db.profile.panels[i].border.texture = sl 
									eePanels:ChangeBackdrop(eePanels.db.profile.panels[i]) 
									eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
								end
							end,
							validate = SharedMedia:List('border'),
							order = 1,														
						},
						Custom = {
							type = "text", 
							name = L["TextureCustom"], 
							desc = L["TextureCustomDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								local panel = eePanels.db.profile.defaultPanel
								return panel.border.texture
								end,
							set = function(t) 
								local panel = eePanels.db.profile.defaultPanel
								panel.border.texture = t 
								for i in pairs(eePanels.db.profile.panels) do
									eePanels.db.profile.panels[i].border.texture = t 
									eePanels:ChangeBackdrop(eePanels.db.profile.panels[i]) 
									eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
								end
							end,
							order = 2,							
						},
					},
				},
			
				backgroundColorStyle = 
				{
					name = L["BGColorStyle"], desc = L["BGColorStyleDesc"], type='text',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.background.style 
					end,
					set = function(t) 
						local panel = eePanels.db.profile.defaultPanel
						panel.background.style = t
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].background.style = t
							eePanels:ChangeBackdrop(eePanels.db.profile.panels[i]) 
							eePanels:ChangeBackgroundColor(eePanels.db.profile.panels[i]) 
							eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = bgColorStyleOpt,
					order = 11,
				},
			
				backgroundColor = 
				{
					name = L["BGColor"], desc = L["BGColorDesc"], type='color',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.background.color.r,panel.background.color.g,panel.background.color.b,panel.background.color.a 
					end,
					set = function(ir,ig,ib,ia)
						local panel = eePanels.db.profile.defaultPanel
						panel.background.color = {r=ir,g=ig,b=ib,a=ia} 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].background.color = {r=ir,g=ig,b=ib,a=ia} 
							eePanels:ChangeBackgroundColor(eePanels.db.profile.panels[i]) 
						end
					end,
					hasAlpha = true,
					order = 12,
				},
			
				backgroundGradientColor = 
				{
					name = L["BGGradientColor"], desc = L["BGGradientColorDesc"], type='color',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.background.gradient.color.r,panel.background.gradient.color.g,panel.background.gradient.color.b,panel.background.gradient.color.a 
					end,
					set = function(ir,ig,ib,ia)
						local panel = eePanels.db.profile.defaultPanel
						panel.background.gradient.color = {r=ir,g=ig,b=ib,a=ia}
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].background.gradient.color = {r=ir,g=ig,b=ib,a=ia} 
							eePanels:ChangeBackgroundColor(eePanels.db.profile.panels[i])
						end
					end,
					hasAlpha = true,
					order = 13,
				},
			
				backgroundGradientOrientation = 
				{
					name = L["BGOrientation"], desc = L["BGOrientationDesc"], type='text',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.background.gradient.orientation 
					end,
					set = function(t) 
						local panel = eePanels.db.profile.defaultPanel
						panel.background.gradient.orientation = t
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].background.gradient.orientation = t
							eePanels:ChangeBackgroundColor(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = bgGradOrientationOpt,
					order = 14,
				},
			
				backgroundTexture = 
				{
					name = L["BGTexture"], 
					desc = L["BGTextureDesc"],
					type = "group",
					order = 10,
					args = {
						Standard = {
							type = "text", 
							name = L["TextureShared"], 
							desc = L["TextureSharedDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								local panel = eePanels.db.profile.defaultPanel
								return panel.media
							end,
							set = function(t) 
								local panel = eePanels.db.profile.defaultPanel
								local sl = SharedMedia:Fetch('background', t)
								panel.media = t
								panel.texture = sl
								for i in pairs(eePanels.db.profile.panels) do
									eePanels.db.profile.panels[i].media = t 
									eePanels.db.profile.panels[i].texture = sl 
									eePanels:ChangeBackdrop(eePanels.db.profile.panels[i]) 
									eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
								end
							end,
							validate = SharedMedia:List('background'),
							order = 1,														
						},
						Custom = {
							type = "text", 
							name = L["TextureCustom"], 
							desc = L["TextureCustomDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								local panel = eePanels.db.profile.defaultPanel
								return panel.texture
								end,
							set = function(t) 
								local panel = eePanels.db.profile.defaultPanel
								panel.texture = t 
								for i in pairs(eePanels.db.profile.panels) do
									eePanels.db.profile.panels[i].texture = t 
									eePanels:ChangeBackdrop(eePanels.db.profile.panels[i]) 
									eePanels:ChangeBorderColor(eePanels.db.profile.panels[i]) 
								end
							end,
							order = 2,							
						},	
					},				
				},
			
				backgroundBlend = 
				{
					name = L["BGBlend"], desc = L["BGBlendDesc"], type='text',
					get = function()
						local panel = eePanels.db.profile.defaultPanel
						return panel.background.gradient.blend
					end,
					set = function(b)
						local panel = eePanels.db.profile.defaultPanel
						panel.background.gradient.blend = b
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].background.gradient.blend = b
							eePanels:ChangeTextureBlend(eePanels.db.profile.panels[i])
						end
					end,
					validate = blendModeOpt,
					order = 16,
				},
			
				level = 
				{
					name = L["PanelLevel"], desc = L["PanelLevelDesc"], type='range',
					get = function()
						local panel = eePanels.db.profile.defaultPanel
						if not panel.level then panel.level = 0 end
						return panel.level
					end,
					set = function(l)
						local panel = eePanels.db.profile.defaultPanel
						panel.level = l
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].level = l
							eePanels:ChangeLevel(eePanels.db.profile.panels[i])
						end
					end,
					min = 0, max = 20, step = 1, isPercent = false,
					order = 17,
				},
			
				strata = 
				{
					name = L["PanelStrata"], desc = L["PanelStrataDesc"], type='text', 
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.strata 
					end,
					set = function(u) 
						local panel = eePanels.db.profile.defaultPanel
						panel.strata = u 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].strata = u 
							eePanels:ChangeStrata(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = frameStrataOpt,
					order = 18,
				},
			
				width = 
				{
					name = L["PanelWidth"], desc = L["PanelWidthDesc"], type='text', usage=' ',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.width
					end,
					set = function(u) 
						local panel = eePanels.db.profile.defaultPanel
						panel.width = u 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].width = u 
							eePanels:ChangeWidth(eePanels.db.profile.panels[i])
						end
					end,
					validate = function(u) if string.find(u, "%d+%.?%d*%%?") then return true else return false end end,
					order = 19,
				},
			
				height = 
				{
					name = L["PanelHeight"], desc = L["PanelHeightDesc"], type='text', usage=' ',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return panel.height
					end,
					set = function(u) 
						local panel = eePanels.db.profile.defaultPanel
						panel.height = u 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].height = u 
							eePanels:ChangeHeight(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = function(u) if string.find(u, "%d+%.?%d*%%?") then return true else return false end end,
					order = 20,
				},
			
				x = 
				{
					name = L["PanelX"], desc = L["PanelXDesc"], type='text', usage=' ',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return math.round(panel.x) 
					end,
					set = function(u) 
						local panel = eePanels.db.profile.defaultPanel
						panel.x = u 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].x = u 
							eePanels:ChangePosition(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = function(u) if string.find(u, "%d+") then return true else return false end end,
					order = 21,
				},
			
				y = 
				{
					name = L["PanelY"], desc = L["PanelYDesc"], type='text', usage=' ',
					get = function() 
						local panel = eePanels.db.profile.defaultPanel
						return math.round(panel.y) 
					end,
					set = function(u) 
						local panel = eePanels.db.profile.defaultPanel
						panel.y = u 
						for i in pairs(eePanels.db.profile.panels) do
							eePanels.db.profile.panels[i].y = u 
							eePanels:ChangePosition(eePanels.db.profile.panels[i]) 
						end
					end,
					validate = function(u) if string.find(u, "%d+") then return true else return false end end,
					order = 22,
				},
			
			}
		},

		panels = 
		{
			type = 'group',
			name = L["PanelSettings"],
			desc = L["PanelSettingsDesc"],
			hidden = function() return not (table.getn(eePanels.db.profile.panels) > 0) end,
			order = 5,
			args = {}
		},

		space1 = 
		{
			name = " ",
			type = 'header',
			order = 6,
		},
		 
		reset = 
		{
			type = 'execute',
			name = L["Reset"],
			desc = L["ResetDesc"],
			func = function(v) StaticPopup_Show("EEPANELSRESET") end,
			order = 7,
		},
	  
	}
}


eePanels.OnMenuRequest			= eePanels.menu
eePanels.name					= L["eePanels"]
eePanels.hasIcon				= true
eePanels.defaultMinimapPosition	= 35
eePanels.cannotDetachTooltip	= true
eePanels.independentProfile		= true
eePanels.defaultPosition		= "LEFT"
eePanels.hideWithoutStandby		= true
eePanels.hasNoColor				= true
eePanels.badParents				= {}
eePanels.recheckTime			= 2


--[[
-- Set left mouse-click on icon to cause toggle frame locking on/off
--]]
function eePanels:OnClick()
	eePanels:ToggleLock()
end


--[[
-- Setup Tooltip
--]]
function eePanels:OnTooltipUpdate()
	local cat = tablet:AddCategory(
		'columns', 2,
		'child_textR', 1,
		'child_textG', 1,
		'child_textB', 0,
		'child_text2R', 1,
		'child_text2G', 1,
		'child_text2B', 1
	)
	-- Change text depending on if panels are locked/unlocked
	if eePanels.db.profile.isLocked then
		cat:AddLine(
			'text', L["Lock"], 
		'	text2', "|cffff0000" .. L["On"] .. "|r"
		)
	else
		cat:AddLine(
			'text', L["Lock"], 
		'	text2', "|cffff0000" .. L["Off"] .. "|r"
		)
	end
	tablet:SetHint(L["LockToggle"])
end


--[[
-- Initialize addon settings
--]]
function eePanels:OnInitialize()
	-- Listen for addons being enabled
	self:RegisterEvent("ADDON_LOADED","ScheduleParentCheck");
	-- Save default database values, if they don't exist
	self:RegisterDefaults('profile', defaults )
	-- listen for command-line requests
	self:RegisterChatCommand( {L["/eePanels"]}, eePanels.menu )
	-- Modify disable text if FuBar isn't installed
	if not FuBar then
		self.OnMenuRequest.args.hide.guiName = L["HideIcon"]
		self.OnMenuRequest.args.hide.desc = L["HideIcon"]
	end
end


--[[
-- This function schedules calls UpdateBadParent() (hopefully once) after all addons have been loaded
-- This is a workaround to allow us to bind 3rd party addons as parents to eePanel panels
-- Since the frames created by the addon probably aren't created when the addon is loaded, we defer
-- execution time for a few seconds and hope that's enough time
--]]
function eePanels:ScheduleParentCheck(addonName)
	-- We want to minimize the number of UpdateBadParents() calls we make (hopefully only after the last addon is loaded), so
	-- cancel any previously scheduled event, and re-schedule a new one in its palce
	self:CancelScheduledEvent("eeParentCheck")
	-- An addon might take a few seconds to build it's frames, so we'll wait until it's finishedS
	self:ScheduleEvent("eeParentCheck", eePanels.UpdateBadParents, eePanels.recheckTime)
end


--[[
-- Returns whether or not a frame exists by performing a lookup in the global variables table
--]]
function eePanels:FrameExists(panelName)
	-- See if we've found the frame in a previous search
	if (frameFound[panelName]) then
		return true
	end
	
	-- If we didn't find the frame from a previous search, check the global variable table to see if it exists.
	local f = getglobal(panelName)
	-- Make sure that any match we find is actually a table and within the userspace scope to limit the odds of a false match
	if (f and (type(f) == "table") and type(rawget(f, 0)) == "userdata") then
		-- Store the match in a table to speed up futur searches
		frameFound[panelName] = true
		return true
	end
	
	return false
end


--[[
-- This function will check if a panel's parent now exists.  If it does, we'll re-display the panel based
-- on it's parent
--]]
function eePanels:UpdateBadParents()
	-- Loop through our list of eePanels with non-existant parents
	for k,_ in pairs(eePanels.badParents) do
		local panel = eePanels.db.profile.panels[k]
		
		-- We found the parent exists now
		if eePanels:FrameExists(panel.parent) then
			-- Remove the panel from the dirty list
			eePanels.badParents[k] = false
			-- Update the panel's parent and position and re-enforce its level
			panel.frame:SetParent(panel.parent)
			eePanels:ChangeWidth(panel)
			eePanels:ChangeHeight(panel)
			eePanels:ChangePosition(panel)
			eePanels:ChangeLevel(panel)
			-- Change panel guideFrame color (if it exists)
			if panel.guideFrame ~= nil then
				panel.guideFrame.texture:SetTexture(eePanels:GetHightlightColor(panel))
			end
			-- Might have inherited old parents visibility; if new parent is visible, set to visible
			if panel.frame:GetParent():IsVisible() then panel.frame:Show() end
		end
		
	end
end


--[[
-- Restore each panel in the database 
-- Display the guide frame if the panel isn't locked
--]]
function eePanels:OnEnable()
	for i in pairs(eePanels.db.profile.panels) do
	
		local panel = eePanels.db.profile.panels[i]
		-- Check if the parent frame exists
		local parentFound = eePanels:FrameExists(panel.parent)
		
		-- If the parent frame wasn't created, mark its index in an array of bad parents for later
		if not parentFound then
			eePanels.badParents[i] = true;
		end
		
		-- Next line fixes a problem which started in patch 2.0.3
		-- The guideFrame value was still being stored in our saved vars, so we
		-- need to manually set it back to nil when we're enabled
		-- (the guideFrame shouldn't exist if yet)
		panel.guideFrame = nil
		eePanels:RestorePanel(panel,i)
		-- If we're in locked mode, create the guideFrame for this panel
		if not eePanels.db.profile.isLocked then 
			eePanels:CreateGuideFrame(panel,i) 
		end
	end
	
	if not self.db.profile.warningShown then
		eePanels:Print("A new version is about to come out.  Your saved layout won't be compatible with the new version.  "..
			"If you don't want to lose your current layout, don't upgrade to any new versions of this mod.  "..
			"For more info, see this thread:  http://www.wowace.com/forums/index.php?topic=3141.0")
		StaticPopup_Show("EEPUPGRADEWARNING")
		self.db.profile.warningShown = true
	end
	
end


--[[
-- Hide all frames when disabled
--]]
function eePanels:OnDisable()
	for i in pairs(eePanels.db.profile.panels) do
		eePanels.db.profile.panels[i].frame:Hide()
	end
end


--[[
-- Removes a created panel
--]]
function eePanels:RemovePanel(index)
	-- Hide the panel and remove it from out database
	eePanels.menu.args.panels.args["panel_"..index] = {}
	eePanels.db.profile.panels[index].frame:Hide()
	eePanels.db.profile.panels[index] = {}
	table.remove(eePanels.db.profile.panels,index)

	-- Recreate individual panel option tables
	eePanels:CreateMenus()

	-- Toggle lock; forces guidePanels to re-generate the name displayed on the guideFrame
	if not eePanels.db.profile.isLocked then
		eePanels:ToggleLock()--lock
		eePanels:ToggleLock()--unlock
	end
end


--[[
-- Create a new panel
--]]
function eePanels:CreatePanel(defType)
	-- Create a new panel from the default template in the database
	--local newPanel = deepCopy(eePanels.db.profile.defaultPanel)
	local newPanel;
	
	-- Determine if we should copy from the user-set global defaults, or the normal addon defaults
	if not defType or defType == 1 then
		newPanel = deepCopy(eePanels.db.profile.defaultPanel)
	else
		newPanel = deepCopy(dp)
	end
	table.insert(eePanels.db.profile.panels, newPanel)
	
	-- Number of this new panel (it's index in our stored table)
	local newi = table.getn(eePanels.db.profile.panels)

	eePanels:CreateFrame(newPanel,newi)
	eePanels:CreateTexture(newPanel)
	eePanels:ChangeStrata(newPanel)
	eePanels:ChangeLevel(newPanel)
	eePanels:ChangeWidth(newPanel)
	eePanels:ChangeHeight(newPanel)
	-- Center the panel, and store it's position
	eePanels:CenterPanel(newPanel)
	-- Now change it's anchoring to 'normal', keeping its current position
	eePanels:ChangePosition(newPanel)
	eePanels:ChangeBackdrop(newPanel)
	eePanels:ChangeBorderColor(newPanel)
	eePanels:ChangeBackgroundColor(newPanel)
	eePanels:ChangeTextureBlend(newPanel)
	eePanels:InterceptMouse(newPanel)
	
	-- If we're in locked mode, create the guideFrame for this panel
	if not eePanels.db.profile.isLocked then 
		eePanels:CreateGuideFrame(eePanels.db.profile.panels[newi],newi) 
	end

	eePanels:CreateMenus()
end


--[[
-- Recreates a panel from the database
--]]
function eePanels:RestorePanel(panel,i)
	-- NEW VARIABLES: make sure any new variables are initialized so we don't break existing layouts from old code
	if not panel.name then panel.name = "" end
	if not panel.level then panel.level = 0 end
	if not panel.parent then panel.parent = "UIParent" end
	if not panel.level then panel.level = 0 end
	if not panel.mouse then panel.mouse = false end
	if not panel.background.insetSize then panel.background.insetSize = 5 end
	if not panel.background.tiling then panel.background.tiling = false end
	if not panel.background.tileSize then panel.background.tileSize = 0 end
	if not panel.border.edgeSize then panel.border.edgeSize = 16 end
	if not panel.media then panel.media = "" end
	if not panel.border.media then panel.border.media = "" end
	
	eePanels:CreateFrame(panel,i)
	eePanels:CreateTexture(panel)
	eePanels:ChangeStrata(panel)
	eePanels:ChangeLevel(panel)
	eePanels:ChangeWidth(panel)
	eePanels:ChangeHeight(panel)
	eePanels:ChangePosition(panel)
	eePanels:ChangeBackdrop(panel)
	eePanels:ChangeBorderColor(panel)
	eePanels:ChangeBackgroundColor(panel)
	eePanels:ChangeTextureBlend(panel)
	eePanels:InterceptMouse(panel)
	
	eePanels:CreateMenus()
end


--[[
-- Creates option table for a panel
--]]
function eePanels:CreateMenus()
	-- Empty the current option table for panels
	eePanels.menu.args.panels.args = {}
	-- Get the number of digits in the number of created panels
	local _, digitCount = string.gsub(getn(eePanels.db.profile.panels), ".","")

	for i in pairs(eePanels.db.profile.panels) do
		-- We must explicitly create a variable for any values we need to dynamically pass through our menu functions
		local index = i
		local panel = eePanels.db.profile.panels[i]
		
		-- Generate a prefix which will sort the panels correctly by panel number in the dewdrop menu
		local _, panelDigits = string.gsub(i, ".","")
		local prefix = ''
		while panelDigits < digitCount do panelDigits = panelDigits+1; prefix =  prefix..'0' end

		-- Create panels option table
		eePanels.menu.args.panels.args["eePanel"..i] = 
		{
			name = prefix..i..'. '..panel.name, desc = prefix..i..'. '..panel.name, type = 'group',
			args = 
			{
				basicSettings = 
				{
					name = "Basic Settings",
					type = 'header',
					order = 1,
				},

				panelName = 
				{
					name = L["PanelName"], desc = L["PanelNameDesc"], type='text', usage=L["PanelNameUsage"],
					get = function() return panel.name end,
					set = function(n) panel.name = n eePanels:CreateMenus() eePanels:ChangeName(panel,i) end,
					order = 9,
				},

				borderColor = 
				{
					name = L["BorderColor"], desc = L["BorderColorDesc"], type='color',
					get = function() return panel.border.color.r,panel.border.color.g,panel.border.color.b,panel.border.color.a end,
					set = function(ir,ig,ib,ia) panel.border.color = {r=ir,g=ig,b=ib,a=ia} eePanels:ChangeBorderColor(panel) end,
					hasAlpha = true,
					order = 10,
				},
				
				backgroundColorStyle = 
				{
					name = L["BGColorStyle"], desc = L["BGColorStyleDesc"], type='text',
					get = function() return panel.background.style end,
					set = function(t) panel.background.style = t eePanels:ChangeBackdrop(panel) eePanels:ChangeBackgroundColor(panel) eePanels:ChangeBorderColor(panel) end,
					validate = bgColorStyleOpt,
					order = 11,
				},

				backgroundColor = 
				{
					name = L["BGColor"], desc = L["BGColorDesc"], type='color',
					get = function() return panel.background.color.r,panel.background.color.g,panel.background.color.b,panel.background.color.a end,
					set = function(ir,ig,ib,ia) panel.background.color = {r=ir,g=ig,b=ib,a=ia} eePanels:ChangeBackgroundColor(panel) end,
					hasAlpha = true,
					order = 12,
				},

				backgroundGradientColor = 
				{
					name = L["BGGradientColor"], desc = L["BGGradientColorDesc"], type='color',
					get = function() return panel.background.gradient.color.r,panel.background.gradient.color.g,panel.background.gradient.color.b,panel.background.gradient.color.a end,
					set = function(ir,ig,ib,ia) panel.background.gradient.color = {r=ir,g=ig,b=ib,a=ia} eePanels:ChangeBackgroundColor(panel) end,
					hasAlpha = true,
					order = 13,
				},

				backgroundGradientOrientation = 
				{
					name = L["BGOrientation"], desc = L["BGOrientationDesc"], type='text',
					get = function() return panel.background.gradient.orientation end,
					set = function(t) panel.background.gradient.orientation = t eePanels:ChangeBackgroundColor(panel) end,
					validate = bgGradOrientationOpt,
					order = 14,
				},

				level = 
				{
					name = L["PanelLevel"], desc = L["PanelLevelDesc"], type='range',
					get = function() return panel.level end,
					set = function(l) panel.level = l eePanels:ChangeLevel(panel) end,
					min = 0, max = 20, step = 1, isPercent = false,
					order = 17,
				},
				
				width = 
				{
					name = L["PanelWidth"], desc = L["PanelWidthDesc"], type='text', usage=' ',
					get = function() return panel.width end,
					set = function(u) panel.width = u eePanels:ChangeWidth(panel) end,
					validate = function(u) if string.find(u, "%d+%.?%d*%%?") then return true else return false end end,
					order = 19,
				},

				height = 
				{
					name = L["PanelHeight"], desc = L["PanelHeightDesc"], type='text', usage=' ',
					get = function() return panel.height end,
					set = function(u) panel.height = u eePanels:ChangeHeight(panel) end,
					validate = function(u) if string.find(u, "%d+%.?%d*%%?") then return true else return false end end,
					order = 20,
				},

				x = 
				{
					name = L["PanelX"], desc = L["PanelXDesc"], type='text', usage=' ',
					get = function() return math.round(panel.x) end,
					set = function(u) panel.x = u eePanels:ChangePosition(panel) end,
					validate = function(u) if string.find(u, "%d+") then return true else return false end end,
					order = 21,
				},

				y = 
				{
					name = L["PanelY"], desc = L["PanelYDesc"], type='text', usage=' ',
					get = function() return math.round(panel.y) end,
					set = function(u) panel.y = u eePanels:ChangePosition(panel) end,
					validate = function(u) if string.find(u, "%d+") then return true else return false end end,
					order = 22,
				},
				
				space = 
				{
					name = " ",
					type = 'header',
					order = 24,
				},
				
				
				advanced = 
				{
					name = "Advanced Settings",
					type = 'header',
					order = 25,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				borderTexture = 
				{
					-- create sub menu here
					name = L["BorderTexture"], 
					desc = L["BorderTextureDesc"], 
					type = "group",
					args = {
						Standard = {
							type = "text", 
							name = L["TextureShared"], 
							desc = L["TextureSharedDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								return panel.border.media 
							end,
							set = function(t) 
								sl = SharedMedia:Fetch('border', t)
								panel.border.media = t
								panel.border.texture = sl 
								eePanels:ChangeBackdrop(panel) 
								eePanels:ChangeBorderColor(panel) 
							end,
							validate = SharedMedia:List('border'),
							order = 1,														
						},
						Custom = {
							type = "text", 
							name = L["TextureCustom"], 
							desc = L["TextureCustomDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								return panel.border.texture
							end,
							set = function(t) 
								panel.texture = t 
								eePanels:ChangeBackdrop(panel) 
								eePanels:ChangeBorderColor(panel) 
							end,
							order = 2,							
						},					
					},
					order = 26,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				borderEdgeSize = 
				{
					name = L["BGEdgeSize"]	, desc = L["BGEdgeSizeDesc"], type='range',
					get = function() return panel.border.edgeSize end,
					set = function(u) panel.border.edgeSize = u eePanels:ChangeBackdrop(panel) eePanels:ChangeBorderColor(panel) end,
					min = 1, max = 100, step = 1, isPercent = false,
					order = 27,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},

				backgroundTexture = 
				{
					name = L["BGTexture"], 
					desc = L["BGTextureDesc"], 
					type="group",
					usage=L["BGTextureUsage"],
					args = {
						Standard = {
							type = "text", 
							name = L["TextureShared"], 
							desc = L["TextureSharedDesc"],
							usage=L["BGTextureUsage"],
							get = function() return panel.media end,
							set = function(t) 
								sl = SharedMedia:Fetch('background', t)
								panel.media = t
								panel.texture = sl 
								eePanels:ChangeBackdrop(panel) 
								eePanels:ChangeBorderColor(panel) 
							end,
						 	validate = SharedMedia:List('background'),
							order = 1,														
						},
						Custom = {
							type = "text", 
							name = L["TextureCustom"], 
							desc = L["TextureCustomDesc"],
							usage=L["BGTextureUsage"],
							get = function() 
								return panel.texture
							end,
							set = function(t) 
								panel.texture = t 
								eePanels:ChangeBackdrop(panel) 
								eePanels:ChangeBorderColor(panel) 
							end,
							order = 2,							
						},					
					},
					order = 40,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},

				backgroundBlend = 
				{
					name = L["BGBlend"], desc = L["BGBlendDesc"], type='text',
					get = function() return panel.background.gradient.blend end,
					set = function(b) panel.background.gradient.blend = b eePanels:ChangeTextureBlend(panel) end,
					validate = blendModeOpt,
					order = 41,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				backgroundInset = 
				{
					name = L["BGInset"]	, desc = L["BGInsetDesc"], type='range',
					get = function() return panel.background.insetSize end,
					set = function(u) 
						panel.background.insetSize = u 
						eePanels:ChangeBackdrop(panel) 
						eePanels:ChangeBorderColor(panel)
						panel.background.frame:SetPoint("TOPLEFT", panel.frame, "TOPLEFT",panel.background.insetSize,-panel.background.insetSize)
						panel.background.frame:SetPoint("BOTTOMRIGHT", panel.frame, "BOTTOMRIGHT",-panel.background.insetSize,panel.background.insetSize)
					end,
					min = 0, max = 100, step = 1, isPercent = false,
					order = 42,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				backgroundTextureTiling = 
				{
					name = L["BGTextureTiling"]	, desc = L["BGTextureTilingDesc"], type='toggle',
					get = function() return panel.background.tiling end,
					set = function(u)  panel.background.tiling = not panel.background.tiling eePanels:ChangeBackdrop(panel) eePanels:ChangeBorderColor(panel) end,
					order = 43,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				backgroundTileSize = 
				{
					name = L["BGTileSize"], desc = L["BGTileSizeDessc"], type='text', usage = '',
					get = function() return panel.background.tileSize end,
					set = function(u) panel.background.tileSize = u eePanels:ChangeBackdrop(panel) eePanels:ChangeBorderColor(panel) end,
					validate = function(u) if string.find(u, "%d+") then return true else return false end end,
					order = 44,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				strata = 
				{
					name = L["PanelStrata"], desc = L["PanelStrataDesc"], type='text', 
					get = function() return panel.strata end,
					set = function(u) panel.strata = u eePanels:ChangeStrata(panel) end,
					validate = frameStrataOpt,
					order = 50,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				parent =
				{
					name = L["PanelParent"], desc=L["PanelParentDesc"], type='text', usage=' ',
					get = function() return panel.parent end,
					set = function(u) panel.parent = u eePanels:ChangeParent(panel) end,
					validate = function(u) if u ~= panel.parent then return true else return false end end, 
					order = 51,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				interceptMouse = 
				{
					name = L["InterceptMouse"], desc = L["InterceptMouseDesc"], type='toggle', 
					get = function() return panel.mouse end,
					set = function(u) panel.mouse = not panel.mouse eePanels:InterceptMouse(panel) end,
					order = 52,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				
				space2 = 
				{
					name = " ",
					type = 'header',
					order = 79,
					disabled = not eePanels.db.profile.isAdvanced,
					hidden = not eePanels.db.profile.isAdvanced,
				},
				

				remove = 
				{
					name = L["PanelRemove"], desc = L["PanelRemoveDesc"], type = 'execute',
					func = function() eePanels:RemovePanel(index) end,
					order = 80,
				},

			},
			
		}
		
	end
end


--[[
-- Resets the AceDB to it's default (no panels)
--]]
function eePanels:Reset()
	-- Hide all existing panels
	for i in pairs(eePanels.db.profile.panels) do
		if eePanels.db.profile.panels[i].frame then 
			eePanels.db.profile.panels[i].frame:Hide() 
		end
		eePanels.db.profile.panels[i] = {}
	end

	-- Empty panel table
	eePanels.db.profile.panels = {}
	-- Empty panel menu table
	eePanels.menu.args.panels.args = {}
	-- Reset the default panel options
	eePanels.db.profile.defaultPanel = deepCopy(dp)
	--eePanels:ResetDB("profile")

	-- Force dewdrop to update so the menu empties itself while it's still open
	if AceLibrary:HasInstance("Dewdrop-2.0") then
		AceLibrary:GetInstance("Dewdrop-2.0"):Refresh(1)
	end
end


--[[
-- Toggle mouse-movement of panels
-- Only works for panels which have their parent set to UIParent
--]]
function eePanels:ToggleLock()
	eePanels.db.profile.isLocked = not eePanels.db.profile.isLocked

	-- Unlocked: show guideFrame
	if not eePanels.db.profile.isLocked then
		for i in pairs(eePanels.db.profile.panels) do
			eePanels:CreateGuideFrame(eePanels.db.profile.panels[i],i)
		end
	-- Locked: hide guideFrame
	else
		for i in pairs(eePanels.db.profile.panels) do
			if eePanels.db.profile.panels[i].guideFrame then
				eePanels.db.profile.panels[i].guideFrame:Hide()
			end
		end
	end
end


--[[
-- Creates a new panel
--]]
function eePanels:CreateFrame(panel,i)
	panel.frame = CreateFrame("Frame", "eePanel"..i, UIParent)
	-- Check to ensure parent exists.  It might not if the parent belongs to an addon that isn't loaded [yet]
	if eePanels:FrameExists(panel.parent) then
		panel.frame:SetParent(panel.parent);
	-- We'll set it to the default for now, so the frame can still be created.  We'll check its parent again later
	else
		panel.frame:SetParent("UIParent")
	end
end


--[[
-- Change the display name of a panel in our menu
--]]
function eePanels:ChangeName(panel,i)
	if not panel.name then panel.name = "" end
	if panel.guideFrame then 
		panel.guideFrame.text:SetText(L["eePanel"]..i..": "..panel.name) 
	end
end


--[[
-- Center a panel to the middle of the screen
--]]
function eePanels:CenterPanel(panel)
	panel.frame:ClearAllPoints()
	panel.frame:SetPoint("CENTER", UIParent, "CENTER")
	panel.x = panel.frame:GetLeft()
	panel.y = panel.frame:GetTop()
end


--[[
-- Reposition a panel based on it's parent
--]]
function eePanels:ChangePosition(panel)
	panel.frame:ClearAllPoints()
	-- Frame should always exist if we've reached this point, but we might as well check
	if (panel.parent == "UIParent" or not eePanels:FrameExists(panel.parent)) then
		panel.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", panel.x, panel.y)
	else
		panel.frame:SetPoint("TOPLEFT", panel.parent, "TOPLEFT", panel.x, panel.y)
	end
end


--[[
-- Change the width of a panel
--]]
function eePanels:ChangeWidth(panel)
	-- Percent size
	if string.find(panel.width, "%d+%.?%d*%%") then
		local uiWidth = panel.frame:GetParent():GetWidth()
		fWidth = string.sub(panel.width,string.find(panel.width, "%d+%.?%d*"))
		panel.frame:SetWidth(uiWidth * (fWidth / (100.0)))
	-- Pixel size
	elseif string.find(panel.width, "%d+") then
		panel.frame:SetWidth(tonumber(panel.width))
	end

	-- Fix for guideFrames not always adjust to changed panel size
	if panel.guideFrame then panel.guideFrame:SetAllPoints(panel.frame) end
end


--[[
-- Change the height of a panel
--]]
function eePanels:ChangeHeight(panel)
	-- Percent size
	if string.find(panel.height, "%d+%.?%d*%%") then
		local uiHeight = panel.frame:GetParent():GetHeight()
		fHeight = string.sub(panel.height,string.find(panel.height, "%d+%.?%d*"))
		panel.frame:SetHeight(uiHeight * (fHeight / (100.0)))
	-- Pixel size
	elseif string.find(panel.width, "%d+") then
		panel.frame:SetHeight(tonumber(panel.height))
	end

	-- Fix for guideFrames not always adjust to changed panel size
	if panel.guideFrame then panel.guideFrame:SetAllPoints(panel.frame) end
end


--[[
-- Change the backdrop of a panel
--]]
function eePanels:ChangeBackdrop(panel)
	-- Change the backdrop
	panel.frame:SetBackdrop(
	{
		bgFile = panel.texture, 
		edgeFile = panel.border.texture,
		edgeSize = panel.border.edgeSize,
		tile = panel.background.tiling,
		tileSize = panel.background.tileSize,
		insets = 
		{ 
			left = panel.background.insetSize,
			right = panel.background.insetSize,
			top = panel.background.insetSize,
			bottom = panel.background.insetSize
		},
	})
	-- Change the backdrop color
	panel.frame:SetBackdropColor(1,1,1,panel.textureAlpha)
end


--[[
-- Creates a texture on the panel's background
--]]
function eePanels:CreateTexture(panel)
	panel.background.frame = panel.frame:CreateTexture(nil, "PARENT")
	panel.background.frame:SetPoint("TOPLEFT", panel.frame, "TOPLEFT",panel.background.insetSize,-panel.background.insetSize)
	panel.background.frame:SetPoint("BOTTOMRIGHT", panel.frame, "BOTTOMRIGHT",-panel.background.insetSize,panel.background.insetSize)
end


--[[
-- Change the blend mode of the background texture
--]]
function eePanels:ChangeTextureBlend(panel)
	panel.background.frame:SetBlendMode(panel.background.gradient.blend)
end


--[[
-- Change the strata of a panel
--]]
function eePanels:ChangeStrata(panel)
	panel.frame:SetFrameStrata(panel.strata)
end


--[[
-- Change a panel's z-level for it's strata
--]]
function eePanels:ChangeLevel(panel)
	panel.frame:SetFrameLevel(panel.level)
end

--[[
-- Change a panel's parent
--]]
function eePanels:ChangeParent(panel)
	panel.frame:SetParent(panel.parent)
	-- If the parent has been changed to UIParent, set size/position back to default
	if panel.parent == "UIParent" or not eePanels:FrameExists(panel.parent) then 
		panel.width = dp.width
		panel.height = dp.height
		-- We need to change the height before we center, or our centering will be off
		eePanels:ChangeHeight(panel)
		eePanels:ChangeWidth(panel)
		eePanels:CenterPanel(panel) 
	-- Otherwise, set it's position to 0,0 for the new parent, and set it's width/height to 100%
	else
		panel.x = 0
		panel.y = 0
		panel.width="100%"
		panel.height="100%"
		eePanels:ChangeHeight(panel)
		eePanels:ChangeWidth(panel)
	end
	
	-- Update it's position
	eePanels:ChangePosition(panel)
	-- Change panel guideFrame color (if it exists)
	if panel.guideFrame ~= ni then
		panel.guideFrame.texture:SetTexture(eePanels:GetHightlightColor(panel))
	end
	-- Might have inherited old parents visibility; if new parent is visible, set to visible
	if panel.frame:GetParent():IsVisible() then panel.frame:Show() end
end


--[[
-- Change a panel's border color
--]]
function eePanels:ChangeBorderColor(panel)
	panel.frame:SetBackdropBorderColor(
		panel.border.color.r,
		panel.border.color.g,
		panel.border.color.b,
		panel.border.color.a )
end


--[[
-- Change the background color of a panel
--]]
function eePanels:ChangeBackgroundColor(panel)
	-- Display flat color
	if panel.background.style == rLookup(bgColorStyleOpt,L["Solid"]) then
		panel.background.frame:SetGradientAlpha(
			panel.background.gradient.orientation,
			panel.background.color.r,
			panel.background.color.g,
			panel.background.color.b,
			panel.background.color.a,
			panel.background.color.r,
			panel.background.color.g,
			panel.background.color.b,
			panel.background.color.a
		)
		panel.background.frame:SetTexture(
			panel.background.color.r,
			panel.background.color.g,
			panel.background.color.b,
			panel.background.color.a
		)
	-- Display gradient color
	else
		panel.background.frame:SetGradientAlpha(
			panel.background.gradient.orientation,
			panel.background.color.r,
			panel.background.color.g,
			panel.background.color.b,
			panel.background.color.a,
			panel.background.gradient.color.r,
			panel.background.gradient.color.g,
			panel.background.gradient.color.b,
			panel.background.gradient.color.a
		)
		panel.background.frame:SetTexture(
			panel.background.color.r,
			panel.background.color.g,
			panel.background.color.b,
			1
		)
	end
end

--[[
-- Change panel to intercept mouse clicks
--]]
function eePanels:InterceptMouse(panel)
	panel.frame:EnableMouse(panel.mouse)
end

