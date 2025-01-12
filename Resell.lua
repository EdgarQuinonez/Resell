local _G = _G

-- From Auctionator
local gRs_Buy_NumBought;
local gRs_Buy_BuyoutPrice;
local gRs_Buy_ItemName;
local gRs_Buy_StackSize;
local gRs_Buy_PreviousNumBought = 0;
local gRs_Craft_CraftCost;


-- Flags
local tradeSkillFirstShown = true
local auctionHouseFirstShown = true
-- local TradeSkillFrame = _G["TradeSkillFrame"]

Resell = LibStub("AceAddon-3.0"):NewAddon("Resell", "AceConsole-3.0", "AceEvent-3.0")

-- available classes
Resell.DBOperation = {}
Resell.UTILS = {}

local defaults = {
	global = {
		["ResellItemDatabase"] = {},
		["ResellProductDatabase"] = {},
	}
}

function Resell:OnInitialize()
	-- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("ResellDB", defaults, true)



	self:RegisterEvent("TRADE_SKILL_SHOW", "OnTradeSkillShow")
	-- self:RegisterEvent("TRADE_SKILL_CLOSE", "KillTradeSkill")		
	self:RegisterEvent("TRADE_SKILL_UPDATE", "OnSkillChange") -- filtering, searching would change selection without click (handler for calling OnSkillChange)	
	-- self:RegisterEvent("AUCTION_HOUSE_CLOSE", "KillAuctionHouse")
	self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
	self:RegisterMessage("RS_TRADE_SKILL_SKILL_CHANGE", "OnSkillChange")
	self:SetupHookFunctions()
	self:Print("Resell is initialized.")
end

function Resell:SetupHookFunctions()
	Resell:Atr_Buy_ConfirmOK_OnClick_Listener()
	-- Resell:Atr_Buy1_OnClick_Listener() -- frame is nill
end

function Resell:OnTradeSkillShow()	
	if tradeSkillFirstShown then		
		for i=1,GetNumTradeSkills()
		do
			local frame = _G["TradeSkillSkill"..i]
			if frame then						
				frame:HookScript("OnClick", function()
					Resell:SendMessage("RS_TRADE_SKILL_SKILL_CHANGE")
				end)
			end
		end
		tradeSkillFirstShown = false
	end
end

function Resell:OnAuctionHouseShow()	
	if auctionHouseFirstShown then		
		Resell:Atr_Buy1_OnClick_Listener()
		auctionHouseFirstShown = false
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

function Resell:OnEnable()
	-- Called when the addon is enabled
end

function Resell:OnDisable()
	-- Called when the addon is disabled
end

function Resell:CalculateCraftCost(skillIndex)
	local nReagents = GetTradeSkillNumReagents(skillIndex)
	local itemTable = Resell.db.global["ResellItemDatabase"]
	local total = 0

	for reagentIndex = 1,nReagents
	do
		local itemLink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
		local reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
		
		if itemTable[reagentName] then
			local item = itemTable[reagentName]
			local price = item["price"]

			total = total + price * reagentCount
		else
			total = total -- missing data defaults to 0 TODO: use scan data values from auctionator instead.
		end		
	end

	return total
end

function Resell:OnSkillChange()
	local skillIndex = GetTradeSkillSelectionIndex()
	local craftCost = Resell:CalculateCraftCost(skillIndex)
	if type(craftCost) == 'number' then		
		local gold = math.floor(craftCost / (100 * 100))
		local silver = math.floor(craftCost / 100) - (gold * 100)
		local copper = craftCost - (silver * 100 + gold * 100 * 100)
	
		Resell:Printf("Craft Cost: %d gold %d silver %d copper.", gold, silver, copper)
	else
		Resell:Print(craftCost)
	end
end


function Resell.DBOperation.RegisterPurchase()
	gRs_Buy_NumBought = GetNumBought()
	gRs_Buy_BuyoutPrice = GetBuyoutPrice()
	gRs_Buy_ItemName = GetItemName()
	gRs_Buy_StackSize = GetStackSize()	

	local numBoughtThisRound = gRs_Buy_NumBought - gRs_Buy_PreviousNumBought
	gRs_Buy_PreviousNumBought = gRs_Buy_NumBought
		

	Resell.DBOperation.UpdateItem(gRs_Buy_ItemName, numBoughtThisRound, gRs_Buy_StackSize, gRs_Buy_BuyoutPrice)	
end

function Resell.DBOperation.RegisterCraft()
	local skillIndex = GetTradeSkillSelectionIndex()
	local craftedProductLink = GetTradeSkillItemLink(skillIndex)
	local productName = GetItemInfo(craftedProductLink)
	local minMade, maxMade = GetTradeSkillNumMade(skillIndex) -- if its random there is no way to know how many were exactly made.
	local craftCost = Resell:CalculateCraftCost(skillIndex) -- making it a little bit more expensive, maybe consider using global variable that hold this when OnSkillChange happens.
	
	local nReagents = GetTradeSkillNumReagents(skillIndex)
	for reagentIndex = 1,nReagents
	do
		-- local itemLink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
		local reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
				
		Resell.DBOperation.UpdateItem(reagentName, -reagentCount, 1)
	end

	Resell.DBOperation.UpdateProduct(productName, 1, minMade, craftCost)	
end

function Resell.DBOperation.UpdateItem(itemName, count, stackSize, price, playerReagentCount)
	local itemTable = Resell.db.global["ResellItemDatabase"]
	
	if not itemTable[itemName] then
		itemTable[itemName] = {}
		itemTable[itemName]["price"] = 0
		itemTable[itemName]["playerItemCount"] = 0
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

	local previousCount = itemTable[itemName]["playerItemCount"]
	local previousPrice = itemTable[itemName]["price"]
	
	local newCount = previousCount + count * stackSize
	-- TODO: Care for newCount == 0
	if newCount <= 0 then
		-- player no longer has item, reset both price and count to 0
		itemTable[itemName]["playerItemCount"] = 0
		itemTable[itemName]["price"] = 0
		return
	end

	local newPrice = (previousCount * previousPrice + count * price) / newCount

	itemTable[itemName]["playerItemCount"] = math.floor(newCount)
	itemTable[itemName]["price"] = math.floor(newPrice)
end

function Resell.DBOperation.UpdateProduct(productName, count, stackSize, craftCost)
	local productTable = Resell.db.global["ResellProductDatabase"]
	Resell:Print(productName)
	if not productTable[productName] then
		productTable[productName] = {}
		productTable[productName]["craftCost"] = 0
	end
	
end


function Resell:OnBuyout()
	Resell.DBOperation.RegisterPurchase()
end

function Resell:OnCraft()
	Resell.DBOperation.RegisterCraft()
end