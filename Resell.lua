local _G = _G

-- From Auctionator
local gRs_Buy_NumBought;
local gRs_Buy_BuyoutPrice;
local gRs_Buy_ItemName;
local gRs_Buy_StackSize;
local gRs_Buy_PreviousNumBought = 0;
local gRs_Buy_ItemSession;

local gRs_TradeSkill_Reagents;
local gRs_TradeSkill_ProductName;

-- Flags
local auctionHouseFirstShown = true


Resell = LibStub("AceAddon-3.0"):NewAddon("Resell", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

Resell.tradeSkillOpen= false
Resell.atAuctionHouse = false


-- available classes
Resell.DBOperation = {}
Resell.Inventory = {}
Resell.UTILS = {}
Resell.GUI = {}
Resell.GUI.Component = {}


Resell.CONSTANT = {
	INVENTORY = {
		TYPE = 1,
		SHORT = 'S',
		BAGSLOTS = {KEYRING_CONTAINER, 0, 1, 2, 3, 4}
	},
	BANK = {
		TYPE = 2,
		SHORT = 'B',
		BAGSLOTS = {BANK_CONTAINER, 5, 6, 7, 8, 9, 10, 11}
	},
	GUILDBANK = {
		TYPE = 3,
		SHORT = 'G',
		BAGSLOTS = {1, 2, 3, 4, 5, 6}
	},
	
}

Resell.gRs_lastEventUpdate = {}
Resell.gRs_debounceLock = {
	["GUILDBANKBAGSLOTS_CHANGED"] = false,
	["BAG_UPDATE"] = false
}
Resell.gRs_latestChanges = {}

local defaults = {
	global = {
		["ResellItemDatabase"] = {},
		["ResellTradeSkillSkillsDatabase"] = {},
		["GUILDBANK"] = {}
	},
	char = {
		-- bags and bank
		["BAG"] = {},
	}
}

function Resell:OnInitialize()
	self.atBank = false
	self.atGuildBank = false
	
    self.db = LibStub("AceDB-3.0"):New("ResellDB", defaults, true)	    
	
	self:ScheduleTimer("InitializeInventory", 0.5) -- small delay to ensure inventory contents are loaded.
	self:SetupHookFunctions()
	self:Print("Initialized.")	
end


function Resell:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_CLOSE")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
	self:RegisterEvent("GUILDBANKFRAME_OPENED")
    self:RegisterEvent("GUILDBANKFRAME_CLOSED")
    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("BANKFRAME_CLOSED")
	self:RegisterEvent("LOOT_SLOT_CLEARED")
	self:RegisterEvent("LOOT_CLOSED")
	self:RegisterEvent("ADDON_LOADED")
end

function Resell:OnDisable()
	self:UnregisterAllEvents()
	self:CancelAllTimers()
end

function Resell:SetupHookFunctions()
	Resell:Atr_Buy_ConfirmOK_OnClick()
	Resell:Atr_Scan_FullScanDone_OnClick()
end

function Resell:ADDON_LOADED(event, name)
	if name == "Blizzard_TradeSkillUI" then
		tradeSkillLoaded = true
		Resell:InitializeGUI()
		for i=1,GetNumTradeSkills()
		do
			local frame = _G["TradeSkillSkill"..i]
			Resell.UTILS.AddTradeSkillSkill(i)
			if frame then						
				frame:HookScript("OnClick", function()
					self:OnSkillChange()
				end)
			end
		end
	end
end

function Resell:TRADE_SKILL_SHOW()
	self.tradeSkillOpen = true
	if Resell.atAuctionHouse then
		Resell.GUI.Component.Container:ClearAllPoints()
		Resell.GUI.Component.Container:SetPoint("TOPRIGHT", TradeSkillFrame, "BOTTOMLEFT")
	else
		Resell.GUI.Component.Container:ClearAllPoints()
		Resell.GUI.Component.Container:SetPoint("LEFT", TradeSkillFrame, "RIGHT", 0, 0)
	end
	-- Resell.GUI.Component.Container:Show()
end

function Resell:InitializeGUI()
	Resell.GUI.InitializeComponents()
end

function Resell.GUI.InitializeComponents()	
	local numRows = 6
	local width, height = TradeSkillFrame:GetSize()

	-- store frames for profit panel items
	Resell.GUI.profitItemFrames = {}
	Resell.GUI.reagentItemFrames = {}
	
	Resell.GUI.Component.Container = CreateFrame("Frame", nil, TradeSkillFrame)
	Resell.GUI.Component.Container:SetSize(width + 32, height / 4)
	Resell.GUI.Component.Container:SetPoint("LEFT", TradeSkillFrame, "RIGHT", 0, 0)

	Resell.GUI.Component.Container:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } });
	Resell.GUI.Component.Container:SetBackdropColor(0.1,0.1,0.2,1);
	Resell.GUI.Component.Container:SetBackdropBorderColor(0.1,0.1,0.1,1);

	Resell.GUI:CreateProfitPanelFrames(numRows)
	Resell.GUI:CreateItemFrames(numRows)
end

function Resell.GUI:CreateProfitPanelFrames(numRows)
	local f = CreateFrame("Frame", nil, self.Component.Container)
	local containerWidth, containerHeight = self.Component.Container:GetSize()
	
	f:SetSize(containerWidth / 2, containerHeight)
	f:SetPoint("LEFT", self.Component.Container, "LEFT")

	local offx = 0;
	local offy = 0;
	
	
	local labels = {"On Auction House: ", "Real Craft Cost: ", "Market Craft Cost: ", "Profit: "}
	
	local profitPanelWidth, profitPanelHeight = f:GetSize()
	local rowHeight = profitPanelHeight / numRows

	
	for i = 0, numRows - 1
	do	
		if labels[i + 1] then			
			offy = -rowHeight * i

			local profitItemFrame = self.Component:ProfitItemFrame(profitPanelWidth, rowHeight, labels[i + 1], Resell:GetMoneyString(0))
			profitItemFrame:SetParent(f)
			profitItemFrame:SetPoint("TOPLEFT", f, "TOPLEFT", offx, offy)
			
			table.insert(self.profitItemFrames, profitItemFrame)
		end
	end

	return f
end

function Resell.GUI:CreateItemFrames(numRows)
	local f = CreateFrame("Frame", nil, self.Component.Container)
	local containerWidth, containerHeight = self.Component.Container:GetSize()
	
	f:SetSize(containerWidth / 2, containerHeight)
	f:SetPoint("RIGHT", self.Component.Container, "RIGHT")

	local offx = 0;
	local offy = 0;	
	
	local w, h = f:GetSize()
	local rowHeight = h / numRows

	
	for i = 0, numRows - 1
	do	
				
		offy = -rowHeight * i

		local itemFrame = self.Component:ItemFrame(w, rowHeight, nil, "Reagent "..i+1, "0", Resell:GetMoneyString(0))
		itemFrame:SetParent(f)
		itemFrame:SetPoint("TOPLEFT", f, "TOPLEFT", offx, offy)
		
		table.insert(self.reagentItemFrames, itemFrame)

	end
end

function Resell.GUI.Component:ItemFrame(width, height, texture, reagentName, playerItemCount, price)
	if not texture then
		texture = "Interface\\BUTTONS\\UI-EmptySlot.blp"
	end
	
	local f	= CreateFrame("Frame")
	f:SetSize(width, height)	
		
	f.Icon = CreateFrame("Frame", nil, f)
	f.Icon:SetSize(height - 2, height - 2)
	f.Icon:SetPoint("LEFT", f, "LEFT")
	f.Icon:SetBackdrop({ bgFile = texture, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, tileSize = 8, edgeSize = 12, insets = { left = 1, right = 1, top = 1, bottom = 1 } })

	local iconW, iconH = f.Icon:GetSize()

	local remainingWidth = width - iconW	

	f.Name = self:TextFrame(reagentName)
	f.Name:SetParent(f)
	f.Name:SetSize(remainingWidth / 2, height)
	f.Name:SetPoint("LEFT", f.Icon, "RIGHT")
	f.Name.Text:SetJustifyH("LEFT")	
	local nameW, nameH = f.Name:GetSize()


	f.Count = self:TextFrame(" x "..playerItemCount)
	f.Count:SetParent(f)
	f.Count:SetSize(remainingWidth / 6, height)
	f.Count:SetPoint("LEFT", f.Name, "RIGHT")
	f.Count.Text:SetJustifyH("LEFT")	

	
	local countW, countH = f.Count:GetSize()
	
	f.Price = self:TextFrame(" > "..price)
	f.Price:SetParent(f)
	f.Price:SetSize(remainingWidth / 3, height)
	f.Price:SetPoint("LEFT", f.Count, "RIGHT")
	f.Price.Text:SetJustifyH("LEFT")	


	return f
end

function Resell.GUI.Component:TextFrame(txt)
	local f = CreateFrame("Frame")
	f.Text = f:CreateFontString("FrizQT")
	f.Text:SetAllPoints(f)
	f.Text:SetFont("fonts/frizqt__.ttf", 11)
	f.Text:SetText(txt)

	return f
end


function Resell.GUI.Component:ProfitItemFrame(width, height, labelTxt, contentTxt)
	local f = CreateFrame("Frame")	
	f:SetSize(width, height)	

	f.Label = self:TextFrame(labelTxt)
	f.Content = self:TextFrame(contentTxt)

	f.Label:SetParent(f)
	f.Label:SetSize((width / 2) + 12, height)
	f.Label:SetPoint("LEFT", f, "LEFT")
	f.Label.Text:SetJustifyH("RIGHT")
	

	f.Content:SetParent(f)
	f.Content:SetSize((width / 2) - 12, height)
	f.Content:SetPoint("RIGHT", f, "RIGHT")
	f.Content.Text:SetJustifyH("LEFT")


	return f
end


function Resell:TRADE_SKILL_CLOSE()
	self.tradeSkillOpen = false
	-- for i, component in pairs(self.GUI.Component)
	-- do
	-- 	component:Hide()
	-- end
end

function Resell.UTILS.AddTradeSkillSkill(skillIndex)

	local skillName, skillType = GetTradeSkillInfo(skillIndex)

	if skillType ~= "header" and not Resell.db.global["ResellTradeSkillSkillsDatabase"][skillName] then
		Resell.db.global["ResellTradeSkillSkillsDatabase"][skillName] = {}
	end

end

-- call only in desired RegisterEvent handler
-- threshold in seconds (up to ms precision)
function Resell.UTILS.DebouncedEvent(event, callback, threshold)
	if Resell.gRs_debounceLock[event] then return end
	Resell.gRs_debounceLock[event] = true
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function ()		
		local elapsed = GetTime() - Resell.gRs_lastEventUpdate[event] 
		if threshold - elapsed <= 0 then
			callback()
			Resell.gRs_debounceLock[event] = false
			f:SetScript("OnUpdate", nil)
			f:Hide()
			f:SetParent(nil)
		end
	end)
	
end

-- shallow copy
-- to: tbl
-- from: src tbl
function Resell.UTILS.CopyTable(from, to)
	if type(to) ~= "table" then to = {} end
	if type(from) == "table" then							
		for k, v in pairs(from)
		do
			if type(v) == "table" then
				v = Resell.UTILS.CopyTable(v, to[k])
			end
			to[k] = v
		end
	end
	return to
end

function Resell:AUCTION_HOUSE_SHOW()
	Resell.atAuctionHouse = true
	-- start shopping session
	gRs_Buy_ItemSession = {}	
	if auctionHouseFirstShown then		
		Resell:Atr_Buy1_OnClick_Listener()
		-- Resell:Atr_CreateAuctionButton_OnClick_Listener()
		auctionHouseFirstShown = false
	end
	if Resell.tradeSkillOpen then			
		-- update tooltip position
		Resell.GUI.Component.Container:ClearAllPoints()
		Resell.GUI.Component.Container:SetPoint("TOPRIGHT", TradeSkillFrame, "BOTTOMLEFT")
	end
	
end

function Resell:AUCTION_HOUSE_CLOSED(event)
	Resell.atAuctionHouse = false
	Resell.gRs_lastEventUpdate[event] = GetTime()
	-- end shopping session
	Resell.UTILS.DebouncedEvent(event, function ()
		for itemName, v in pairs(gRs_Buy_ItemSession)
		do			
			Resell.DBOperation.UpdateItem(itemName, v.count, 1, v.price)
		end

		if Resell.tradeSkillOpen then			
			-- update tooltip position
			Resell.GUI.Component.Container:ClearAllPoints()
			Resell.GUI.Component.Container:SetPoint("LEFT", TradeSkillFrame, "RIGHT", 0, 0)
		end

	end, 0.005)

end

function Resell:InitializeTradeSkill()
	self:SetTradeSkillSkillListener()
end

function Resell:Atr_Buy_ConfirmOK_OnClick()
	local buyoutBtnframe = _G["Atr_Buy_Confirm_OKBut"]
	if buyoutBtnframe then
		buyoutBtnframe:HookScript("OnClick", function ()
			self:OnBuyout()
		end)
	end
end

function Resell:Atr_Buy1_OnClick_Listener()
	local buyBtnFrame = _G["Atr_Buy1_Button"]	
	if buyBtnFrame then
		buyBtnFrame:HookScript("OnClick", function ()			
			gRs_Buy_PreviousNumBought = 0
		end)
	end
end

function Resell:Atr_Scan_FullScanDone_OnClick()
	local doneBtnFrame = _G["Atr_FullScanDone"]
	if doneBtnFrame then
		doneBtnFrame:HookScript("OnClick", function ()
			Resell:UpdateScannedPriceOnItemDatabase()
		end)
	end
end

-- function Resell:Atr_CreateAuctionButton_OnClick_Listener()
-- 	local frame = _G["Atr_CreateAuctionButton"]
-- 	if frame then
-- 		frame:HookScript("OnClick", function ()
-- 			Resell:OnAuctionCreate()
-- 		end)
-- 	end
-- end

function Resell:UpdateScannedPriceOnItemDatabase()
	for itemName, _ in pairs(Resell.db.global["ResellItemDatabase"])
	do
		Resell.db.global["ResellItemDatabase"][itemName]["scannedPrice"] = GetItemScannedPrice(itemName) or 0
	end
end



function Resell:CalculateCraftCost(reagentList, numMade)
	if type(reagentList) ~= "table" then return end
	if not numMade then numMade = 1 end

	local realCraftCost = 0
	local marketCraftCost = 0

	for name, count in pairs(reagentList)
	do
		if not Resell.db.global.ResellItemDatabase[name] then Resell.UTILS.InitItem(name) end

		realCraftCost = realCraftCost + Resell.db.global.ResellItemDatabase[name].price * count
		marketCraftCost = marketCraftCost + Resell.db.global.ResellItemDatabase[name].scannedPrice * count
	end

	return realCraftCost / numMade, marketCraftCost / numMade
end

function Resell:OnSkillChange()	
	if Resell.tradeSkillOpen then

		local skillIndex = GetTradeSkillSelectionIndex()
		local minMade, maxMade = GetTradeSkillNumMade(skillIndex)
		

		if skillIndex == 0 then return end

		local itemName = GetItemInfo(GetTradeSkillItemLink(skillIndex))

		local reagentList = {}

		for i = 1,#Resell.GUI.reagentItemFrames
		do
			Resell.GUI.reagentItemFrames[i]:Hide()
		end

		for i = 1,GetTradeSkillNumReagents(skillIndex)
		do
			local name, texture, count = GetTradeSkillReagentInfo(skillIndex, i)
			reagentList[name] = count
			
			if not Resell.db.global.ResellItemDatabase[name] then
				Resell.UTILS.InitItem(name)
			end

			local f = Resell.GUI.reagentItemFrames[i]
			f.Icon:SetBackdrop({ bgFile = texture })
			f.Name.Text:SetText(name)
			f.Count.Text:SetText(" x "..Resell.db.global.ResellItemDatabase[name].playerItemCount)
			f.Price.Text:SetText(" > "..Resell:GetMoneyString(Resell.db.global.ResellItemDatabase[name].price))

			f:Show()
		end			
		local realCraftCost, marketCraftCost = Resell:CalculateCraftCost(reagentList, minMade)

		if realCraftCost and marketCraftCost then			
			local ahPrice = GetItemScannedPrice(itemName) or 0
			Resell.GUI.profitItemFrames[1].Content.Text:SetText(Resell:GetMoneyString(ahPrice))
			Resell.GUI.profitItemFrames[2].Content.Text:SetText(Resell:GetMoneyString(realCraftCost))
			Resell.GUI.profitItemFrames[3].Content.Text:SetText(Resell:GetMoneyString(marketCraftCost))
			Resell.GUI.profitItemFrames[4].Content.Text:SetText(Resell:GetMoneyString(Resell:GetProfit(ahPrice, marketCraftCost)))
		end
	end
end

function Resell:GetProfit(ahPrice, craftCost)
	return (ahPrice - craftCost) - ahPrice * 0.05
end

function Resell:GetMoneyString(money)
	if money < 0 then
		return format(COPPER_AMOUNT_TEXTURE, 0, 0, 0)
	end

	local gold = floor(money / 10000)
	local silver = floor((money - gold * 10000) / 100)
	local copper = mod(money, 100)
	if gold > 0 then
		return format(GOLD_AMOUNT_TEXTURE.." "..SILVER_AMOUNT_TEXTURE.." "..COPPER_AMOUNT_TEXTURE, gold, 0, 0, silver, 0, 0, copper, 0, 0)
	elseif silver > 0 then
		return format(SILVER_AMOUNT_TEXTURE.." "..COPPER_AMOUNT_TEXTURE, silver, 0, 0, copper, 0, 0)
	else
		return format(COPPER_AMOUNT_TEXTURE, copper, 0, 0)
	end
	
end

function Resell.DBOperation.RegisterPurchase()
	gRs_Buy_NumBought = GetNumBought()
	gRs_Buy_BuyoutPrice = GetBuyoutPrice()
	gRs_Buy_ItemName = GetItemName()
	gRs_Buy_StackSize = GetStackSize()	

	local numBoughtThisRound = gRs_Buy_NumBought - gRs_Buy_PreviousNumBought
	gRs_Buy_PreviousNumBought = gRs_Buy_NumBought
	
	if not gRs_Buy_ItemSession[gRs_Buy_ItemName] then gRs_Buy_ItemSession[gRs_Buy_ItemName] = { count = 0, price = 0} end

	local previousCount = gRs_Buy_ItemSession[gRs_Buy_ItemName].count
	local previousPrice = gRs_Buy_ItemSession[gRs_Buy_ItemName].price

	gRs_Buy_ItemSession[gRs_Buy_ItemName].count = gRs_Buy_ItemSession[gRs_Buy_ItemName].count + numBoughtThisRound * gRs_Buy_StackSize
	gRs_Buy_ItemSession[gRs_Buy_ItemName].price = (previousPrice * previousCount + numBoughtThisRound * gRs_Buy_BuyoutPrice) / gRs_Buy_ItemSession[gRs_Buy_ItemName].count -- calculate average in session

	-- only update at the end of session.
	-- Resell.DBOperation.UpdateItem(gRs_Buy_ItemName, numBoughtThisRound, gRs_Buy_StackSize, (gRs_Buy_BuyoutPrice / gRs_Buy_StackSize))	
end


function Resell:RegisterCraft()
	Resell.DBOperation.RegisterCraft()
end

function Resell.DBOperation.RegisterCraft()
	if type(Resell.gRs_latestChanges) ~= "table" then return end

	local productCount = 0

	for name, count in pairs(Resell.gRs_latestChanges)
	do
		if name == gRs_TradeSkill_ProductName then
			productCount = count
			break
		end		
	end
	local realCraftCost, marketCraftCost = Resell:CalculateCraftCost(gRs_TradeSkill_Reagents, productCount)	
		
	if gRs_TradeSkill_ProductName and productCount > 0 then		
		Resell.DBOperation.UpdateItem(gRs_TradeSkill_ProductName, productCount, 1, realCraftCost, false, realCraftCost, marketCraftCost)
	end
end

function Resell.UTILS.InitItem(itemName)
	local itemTable = Resell.db.global["ResellItemDatabase"]
	
	if not itemTable[itemName] and itemName then
		itemTable[itemName] = {}
		itemTable[itemName]["price"] = 0
		itemTable[itemName]["realCraftCost"] = 0 -- craft cost calculated using "price"
		itemTable[itemName]["marketCraftCost"] = 0 -- craft cost calculated using "scannedPrice"
		itemTable[itemName]["playerItemCount"] = 0
		itemTable[itemName]["scannedPrice"] = GetItemScannedPrice(itemName) or 0
	end	
end

-- price per item
function Resell.DBOperation.UpdateItem(itemName, count, stackSize, price, updateCount, realCraftCost, marketCraftCost)
	
	if not itemName then
		error("Cannot call UpdateItem without item name.", 2)
	end

	local itemTable = Resell.db.global["ResellItemDatabase"]
	
	Resell.UTILS.InitItem(itemName)

	if not price then
		price = itemTable[itemName].price
	end

	if realCraftCost then
		itemTable[itemName].realCraftCost = realCraftCost
	end

	if marketCraftCost then
		itemTable[itemName].marketCraftCost = marketCraftCost
	end

	local previousCount = itemTable[itemName]["playerItemCount"]
	local previousPrice = itemTable[itemName]["price"]

	local newCount = previousCount + count * stackSize

	if newCount <= 0 then
		-- player no longer has item, reset both price and count to 0
		itemTable[itemName]["playerItemCount"] = 0
		itemTable[itemName]["price"] = 0
		return
	end

	local newPrice = (previousCount * previousPrice + (count * stackSize) * price) / newCount
	itemTable[itemName]["price"] = floor(newPrice)	
	
	if updateCount then		
		itemTable[itemName]["playerItemCount"] = floor(newCount)
	end
end

function Resell:OnBuyout()
	Resell.DBOperation.RegisterPurchase()
end

function Resell:UNIT_SPELLCAST_SENT(event, unit, name)
	if unit == "player" and Resell.db.global["ResellTradeSkillSkillsDatabase"][name] then
		if Resell.tradeSkillOpen then
			local skillIndex = GetTradeSkillSelectionIndex()
			local itemLink = GetTradeSkillItemLink(skillIndex)
			gRs_TradeSkill_ProductName = GetItemInfo(itemLink)
			gRs_TradeSkill_Reagents = {}
			for i = 1,GetTradeSkillNumReagents(skillIndex)
			do
				local name, _, count = GetTradeSkillReagentInfo(skillIndex, i)

				gRs_TradeSkill_Reagents[name] = count
			end			
		end
	end
end

function Resell:UNIT_SPELLCAST_SUCCEEDED(event, unit, name)
	-- Filters names to respond only on trade skill names.
	if unit == "player" and Resell.db.global["ResellTradeSkillSkillsDatabase"][name] then
		Resell:ScheduleTimer("RegisterCraft", 0.7) -- small delay to allow gRs_latestChanges be updated first even if BAG_UPDATE happens after the UNIT_SPELLCAST_SUCCEEDED event
	end
end

function Resell:LOOT_OPENED()
	Resell.lootWindowOpen = true	
end

function Resell:OnLoot()
	local container;
	local price = 0;
	local totalCount = 0;		
	-- find container		
	for name, count in pairs(Resell.gRs_latestChanges)
	do
		if count < 0 then
			container = name
		else
			totalCount = totalCount + count
		end
	end
	
	if container and not Resell.db.global.ResellItemDatabase[container] then
		Resell.UTILS.InitItem(container)
	end

	if container then			
		price = Resell.db.global.ResellItemDatabase[container].price
	end

	if totalCount == 0 then
		Resell:Print("Loot was empty!")
		return
	end
	-- update price on loot
	for name, count in pairs(Resell.gRs_latestChanges)
	do
		if count > 0 then
			Resell.DBOperation.UpdateItem(name, count, 1, price / totalCount, false)			
		end		
	end
	
end

-- only works with auto loot on
function Resell:LOOT_SLOT_CLEARED(event, lootSlot)
	
	Resell.gRs_lastEventUpdate[event] = GetTime()
	
	Resell.UTILS.DebouncedEvent(event, function ()
		Resell:Print("OnLoot fired!")		
		Resell:ScheduleTimer("OnLoot", 0.7)
	end, 0.005)
end

function Resell:LOOT_CLOSED()
	Resell.lootWindowOpen = false
end