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
local tradeSkillFirstShown = true
local auctionHouseFirstShown = true

Resell = LibStub("AceAddon-3.0"):NewAddon("Resell", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

Resell.tradeSkillOpen= false


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
	self:RegisterEvent("TRADE_SKILL_CLOSE")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("GUILDBANKFRAME_OPENED")
    self:RegisterEvent("GUILDBANKFRAME_CLOSED")
    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("BANKFRAME_CLOSED")
	self:RegisterEvent("LOOT_SLOT_CLEARED")
	self:RegisterEvent("LOOT_CLOSED")
end

function Resell:OnDisable()
	self:UnregisterAllEvents()
	self:CancelAllTimers()
end

function Resell:SetupHookFunctions()
	Resell:Atr_Buy_ConfirmOK_OnClick()
	Resell:Atr_Scan_FullScanDone_OnClick()
end

function Resell:TRADE_SKILL_SHOW()
	self.tradeSkillOpen = true	
	if tradeSkillFirstShown then		
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
		tradeSkillFirstShown = false
	end
end

function Resell:TRADE_SKILL_CLOSE()
	self.tradeSkillOpen = false
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
	-- start shopping session
	gRs_Buy_ItemSession = {}	
	if auctionHouseFirstShown then		
		Resell:Atr_Buy1_OnClick_Listener()
		-- Resell:Atr_CreateAuctionButton_OnClick_Listener()
		auctionHouseFirstShown = false
	end
end

function Resell:AUCTION_HOUSE_CLOSED(event)
	Resell.gRs_lastEventUpdate[event] = GetTime()
	-- end shopping session
	Resell.UTILS.DebouncedEvent(event, function ()
		for itemName, v in pairs(gRs_Buy_ItemSession)
		do			
			Resell.DBOperation.UpdateItem(itemName, v.count, 1, v.price)
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



function Resell:CalculateCraftCost(reagentList)
	if type(reagentList) ~= "table" then return end

	local realCraftCost = 0
	local marketCraftCost = 0

	for name, count in pairs(reagentList)
	do
		if not Resell.db.global.ResellItemDatabase[name] then Resell.UTILS.InitItem(name) end

		realCraftCost = realCraftCost + Resell.db.global.ResellItemDatabase[name].price * count
		marketCraftCost = marketCraftCost + Resell.db.global.ResellItemDatabase[name].scannedPrice * count
	end

	return realCraftCost, marketCraftCost
end

function Resell:OnSkillChange()	
	if Resell.tradeSkillOpen then
		local skillIndex = GetTradeSkillSelectionIndex()

		local reagentList = {}
		for i = 1,GetTradeSkillNumReagents(skillIndex)
		do
			local name, _, count = GetTradeSkillReagentInfo(skillIndex, i)
			reagentList[name] = count
		end			
		local realCraftCost, marketCraftCost = Resell:CalculateCraftCost(reagentList)

		if realCraftCost and marketCraftCost then			
			Resell:Print("Real Craft Cost: "..Resell:GetMoneyString(realCraftCost))
			Resell:Print("Market Craft Cost: "..Resell:GetMoneyString(marketCraftCost))
		end
	end
end

function Resell:GetMoneyString(money)
	
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
	local realCraftCost, marketCraftCost = Resell:CalculateCraftCost(gRs_TradeSkill_Reagents)	
		
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
		Resell:Print(name, count)		
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