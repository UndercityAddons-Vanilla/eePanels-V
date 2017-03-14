local L  = AceLibrary("AceLocale-2.2"):new("eePanels")


--[[
-- Displays a guideFrame to move a panel by mouse
--]]
function eePanels:CreateGuideFrame(panel,i) 
	-- If the guideFrame exists, just show it
	if panel.guideFrame then
		panel.guideFrame.text:SetText( L["eePanel"]..i..": "..panel.name )
		panel.guideFrame:Show()
	-- Otherwise, create a new guideFrame
	else
		panel.guideFrame = CreateFrame("Frame", "position"..i, panel.frame)
		panel.guideFrame:EnableMouse(true)
		panel.guideFrame:SetResizable(true)
		panel.guideFrame:SetMovable(true)
		panel.guideFrame:SetMinResize(22,22)
		panel.guideFrame:SetFrameStrata("HIGH")
		panel.guideFrame:SetAllPoints(panel.frame)
		panel.guideFrame:SetBackdropColor(1,1,1,0)
		panel.guideFrame.isResizing = false;
		
		-- Create a texture to display a special highlight color when we mouse-over this frame
		panel.guideFrame.texture = panel.guideFrame:CreateTexture(nil, "HIGHLIGHT")
		panel.guideFrame.texture:SetAllPoints(panel.guideFrame)
		panel.guideFrame.texture:SetTexture(eePanels:GetHightlightColor(panel))
		panel.guideFrame.texture:SetAlpha(.3)

		-- Display the frame number on top of our texture when we mouseOver
		panel.guideFrame.text = panel.guideFrame:CreateFontString(nil, "HIGHLIGHT")
		panel.guideFrame.text:SetFontObject(GameFontHighlightSmall)
		panel.guideFrame.text:SetPoint("CENTER", panel.guideFrame, "CENTER", 0, 0)
		panel.guideFrame.text:SetText( L["eePanel"]..i..": "..panel.name )

		-- Resize texture
		resizeTexture = panel.guideFrame:CreateTexture(nil, "HIGHLIGHT")
		resizeTexture:SetHeight(16)
		resizeTexture:SetWidth(16)
		resizeTexture:SetTexture("Interface\\Addons\\eePanels\\resize.tga")
		resizeTexture:SetPoint("BOTTOMRIGHT",-2,2)
		
		-- Set scripts to let us move while dragging
		panel.guideFrame:SetScript("OnMouseUp", self.StopMouseListening)
		panel.guideFrame:SetScript("OnMouseDown",self.StartMouseListening)

		-- Store our panel (which is the guideFrames parent) as a variable of the 
		-- guideFrame, to make it easier to figure out which panel to reposition after
		-- we've moved the guideFrame
		panel.guideFrame.parent = panel.frame
	end
end


--[[
-- Sets the mouse-over highlight color based on the panel's parent
--]]
function eePanels:GetHightlightColor(panel)
	-- Blue-green hover color
	if panel.parent == "UIParent" then
		return 0,1,1
	-- Yellow highlight otherwise (to signify we're not allowing mouse-move)
	else
		return 1,1,0
	end
end


--[[
-- Setup a panel for being moved via cursor
--]]
function eePanels:StartMouseListening()
	-- Don't listen if the frame's parent isn't UIParent
	if arg1 == "LeftButton" and this.parent:GetParent() == UIParent then
	
		-- Set vars to figure out if the mouse is in the resize area or not
		local screenX, screenY = GetCursorPosition()
		local panelX = this:GetRight()
		local panelY = this:GetBottom()

		-- Adjust for screen scale
		local scale = this:GetEffectiveScale()
		panelX = panelX * scale
		panelY = panelY * scale
		
		local check1 = screenX <= panelX + 14
		local check2 = screenX >= panelX - 14
		local check3 = screenY <= panelY + 14
		local check4 = screenY >= panelY - 14

		-- Start resizing
		if check1 and check2 and check3 and check4 then
			-- Attach an OnUpdate call which fires every repaint while we're resizing
			this:SetScript("OnUpdate", eePanels.UpdateSize)
			-- Set a variable so we know when we're resizing over moving
			this.isResizing = true;
			-- System call
			this:StartSizing("BOTTOMRIGHT")
		-- Start moving
		else
			-- Attach an OnUpdate call which fires every repaint while we're moving
			this:SetScript("OnUpdate", eePanels.UpdateMove)
			-- System call
			this:StartMoving()
		end
		
	end
end


--[[
-- Sets the panel to the size of it's guideFrame each time it's dragged
--]]
function eePanels.UpdateSize()
	this.parent:SetWidth(this:GetWidth())
	this.parent:SetHeight(this:GetHeight())
end


--[[
-- Sets the panel to the position of it's guideFrame each time it's moved
--]]
function eePanels:UpdateMove()
	this.parent:ClearAllPoints()
	this.parent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", this:GetLeft(), this:GetTop())
end


--[[
-- Update's a panel's size/coordinates to the guideFrame's once it's finished moving/resizing
--]]
function eePanels:StopMouseListening()
	-- If the panel isn't parented by UIParent, we don't want to modify it's position
	if this.parent:GetParent() ~= UIParent then return end
	
	-- Stop our move or resize
	this:StopMovingOrSizing()
	-- Remove the OnUpdate script for the guideFrame
	this:SetScript("OnUpdate", nil)
	
	-- Finish resize
	if (this.isResizing) then
		this.isResizing = false
		-- Change panel's width/height in database to the guideFrame's size
		for i in pairs(eePanels.db.profile.panels) do
			if eePanels.db.profile.panels[i].guideFrame == this then
				eePanels.db.profile.panels[i].width = this:GetWidth()
				eePanels.db.profile.panels[i].height = this:GetHeight()
			end
		end
		
	-- Finish move
	else
		-- Change panel's x,y coords in database to the guideFrame's coords
		for i in pairs(eePanels.db.profile.panels) do
			if eePanels.db.profile.panels[i].guideFrame == this then
				eePanels.db.profile.panels[i].x = this:GetLeft()
				eePanels.db.profile.panels[i].y = this:GetTop()
			end
		end
	end
end