local _G = _G

-- From Auctionator
local gRs_Buy_NumBought;
local gRs_Buy_BuyoutPrice;
local gRs_Buy_ItemName;
local gRs_Buy_StackSize;
local gRs_Buy_PreviousNumBought = 0;

-- Flags
local tradeSkillFirstShown = true
local auctionHouseFirstShown = true
local mailFirstShown = true

Resell = LibStub("AceAddon-3.0"):NewAddon("Resell", "AceConsole-3.0", "AceEvent-3.0")

-- available classes
Resell.DBOperation = {}
Resell.Inventory = {}
Resell.UTILS = {}

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

	
	self.Inventory:InitializeInventory()
	self:SetupHookFunctions()
	self:Print("Initialized.")
	
end

function Resell:OnEnable()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("GUILDBANKFRAME_OPENED")
    self:RegisterEvent("GUILDBANKFRAME_CLOSED")
    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("BANKFRAME_CLOSED")
end

function Resell:OnDisable()
	self:UnregisterAllEvents()
end

function Resell:SetupHookFunctions()
	Resell:Atr_Buy_ConfirmOK_OnClick_Listener()
	Resell:Atr_Scan_FullScanDone_OnClick_Listener()
end

function Resell:TRADE_SKILL_SHOW()	
	if tradeSkillFirstShown then		
		for i=1,GetNumTradeSkills()
		do
			local frame = _G["TradeSkillSkill"..i]
			Resell.UTILS.AddTradeSkillSkill(i)
			if frame then						
				frame:HookScript("OnClick", function()
					self:OnSkillChange(i)
				end)
			end
		end
		tradeSkillFirstShown = false
	end
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
	if auctionHouseFirstShown then		
		Resell:Atr_Buy1_OnClick_Listener()
		-- Resell:Atr_CreateAuctionButton_OnClick_Listener()
		auctionHouseFirstShown = false
	end
end

function Resell:OnMailShow()
	if mailFirstShown then
		Resell:Postal_PostalOpenAllButton_OnClick_Listener()
		mailFirstShown = false
	end
	
end

function Resell:InitializeTradeSkill()
	self:SetTradeSkillSkillListener()
end

function Resell:Atr_Buy_ConfirmOK_OnClick_Listener()
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

function Resell:Atr_Scan_FullScanDone_OnClick_Listener()
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
		Resell.db.global["ResellItemDatabase"][itemName]["scannedPrice"] = GetItemScannedPrice(itemName)
	end
end



function Resell:CalculateCraftCost(skillIndex)
	local nReagents = GetTradeSkillNumReagents(skillIndex)
	local itemTable = Resell.db.global["ResellItemDatabase"]
	local total = 0

	for reagentIndex = 1,nReagents
	do
		local itemLink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
		local reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)		
		
		if not itemTable[reagentName] then
			itemTable[reagentName] = {}
			itemTable[reagentName]["price"] = 0
			itemTable[reagentName]["playerItemCount"] = playerReagentCount

			itemTable[reagentName]["scannedPrice"] = GetItemScannedPrice(reagentName)						
		end

		local price;

		if not itemTable[reagentName]["scannedPrice"] then
			-- scannedPrice not available, price might be 0
			price = itemTable[reagentName]["price"]
		elseif itemTable[reagentName]["playerItemCount"] == 0 then
			-- player does not have the item, scannedPrice is relevant.
			price = itemTable[reagentName]["scannedPrice"]
		elseif itemTable[reagentName]["playerItemCount"] > 0 and itemTable[reagentName]["price"] == 0 then
			-- player does have the item, however price is 0 because it wasn't bought from AH, he might've farmed the item, still market price would be benefitial to tell if he can make a profit without crafting using the reagent.
			price = itemTable[reagentName]["scannedPrice"]		
		else
			-- price stored in db is relevant
			price = itemTable[reagentName]["price"]
		end

		total = total + price * reagentCount
	end
	return total
end

function Resell:OnSkillChange(skillIndex)	
	local craftCost = Resell:CalculateCraftCost(skillIndex)
	
	local gold = math.floor(craftCost / (100 * 100))
	local silver = math.floor(craftCost / 100) - (gold * 100)
	local copper = craftCost - (silver * 100 + gold * 100 * 100)

	Resell:Printf("Craft Cost: %d gold %d silver %d copper.", gold, silver, copper)	
end


function Resell.DBOperation.RegisterPurchase()
	gRs_Buy_NumBought = GetNumBought()
	gRs_Buy_BuyoutPrice = GetBuyoutPrice()
	gRs_Buy_ItemName = GetItemName()
	gRs_Buy_StackSize = GetStackSize()	

	local numBoughtThisRound = gRs_Buy_NumBought - gRs_Buy_PreviousNumBought
	gRs_Buy_PreviousNumBought = gRs_Buy_NumBought
			
	Resell.DBOperation.UpdateItem(gRs_Buy_ItemName, numBoughtThisRound, gRs_Buy_StackSize, (gRs_Buy_BuyoutPrice / gRs_Buy_StackSize))	
end

function Resell.UTILS.GetSkillIndexBySkillName(skillName)

	-- TradeSkillOnlyShowMakeable(true) -- this makes sense because one only would want to register craft when has the mats available and has already crafted it.
	for i = 1,GetNumTradeSkills()
	do
		-- Resell:Print(GetTradeSkillInfo(i))
		if GetTradeSkillInfo(i) == skillName then return i end		
	end
	return nil
	
end

function Resell.DBOperation.RegisterCraft(skillName)
	local skillIndex = Resell.UTILS.GetSkillIndexBySkillName(skillName)
	-- Resell:Print(skillIndex) -- TODO: FIX skillIndex = nil
	if skillIndex then		
		local craftedProductLink = GetTradeSkillItemLink(skillIndex)
		local productName = GetItemInfo(craftedProductLink)
		local minMade, maxMade = GetTradeSkillNumMade(skillIndex) -- if its random there is no way to know how many were exactly made.
		local craftCost = Resell:CalculateCraftCost(skillIndex) -- making it a little bit more expensive, maybe consider using global variable that hold this when OnSkillChange happens.
		-- serviceType = nill -> produces an item
		local _, _, _, _, serviceType = GetTradeSkillInfo(skillIndex)
	
	
		local nReagents = GetTradeSkillNumReagents(skillIndex)
		for reagentIndex = 1,nReagents
		do
			-- local itemLink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
			local reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
					
			Resell.DBOperation.UpdateItem(reagentName, -reagentCount , 1, nil, playerReagentCount)
		end	
		if not serviceType then		
			Resell.DBOperation.UpdateItem(productName, minMade, 1, craftCost)
		end
	end
end

-- price per item
function Resell.DBOperation.UpdateItem(itemName, count, stackSize, price, playerReagentCount)
	local itemTable = Resell.db.global["ResellItemDatabase"]
	
	if not itemTable[itemName] and itemName then
		itemTable[itemName] = {}
		itemTable[itemName]["price"] = 0
		itemTable[itemName]["playerItemCount"] = 0
		itemTable[itemName]["scannedPrice"] = GetItemScannedPrice(itemName)
		if playerReagentCount then
			-- if update comes from craft, use the playerReagenCount to avoid negative numbers in item db.
			itemTable[itemName]["playerItemCount"] = playerReagentCount		
		end
	end

	-- item already exists but count stored in db is less than blizzard detects (meaning user got items from another non tracked source)
	if playerReagentCount and itemTable[itemName]["playerItemCount"] < playerReagentCount then
		itemTable[itemName]["playerItemCount"] = playerReagentCount
	end

	if not price then
		-- called from RegisterCraft with no price means that the item price must not be updated therefore using the same as previous price will leave it unchanged
		price = itemTable[itemName]["price"]
	end

	if price == 0 and itemTable[itemName]["scannedPrice"] then
		-- it will only get here if item has no record of how the player got it, leaving the price as 0 would not be helpful for calculating crafting costs.
		price = itemTable[itemName]["scannedPrice"]
	end


	local previousCount = itemTable[itemName]["playerItemCount"]
	local previousPrice = itemTable[itemName]["price"] -- might be 0

	if itemTable[itemName]["scannedPrice"] and previousPrice == 0 then
		previousPrice = itemTable[itemName]["scannedPrice"]
	end
	
	local newCount = previousCount + count * stackSize
	if newCount <= 0 then
		-- player no longer has item, reset both price and count to 0
		itemTable[itemName]["playerItemCount"] = 0
		itemTable[itemName]["price"] = 0
		return
	end

	local newPrice = (previousCount * previousPrice + (count * stackSize) * price) / newCount

	itemTable[itemName]["playerItemCount"] = math.floor(newCount)
	itemTable[itemName]["price"] = math.floor(newPrice)
end

function Resell:OnBuyout()
	Resell.DBOperation.RegisterPurchase()
end

function Resell:UNIT_SPELLCAST_SUCCEEDED(event, unit, name)
	-- Filters names to respond only on trade skill names.
	if unit == "player" and Resell.db.global["ResellTradeSkillSkillsDatabase"][name] then		
		Resell.DBOperation.RegisterCraft(name)
	end
end
