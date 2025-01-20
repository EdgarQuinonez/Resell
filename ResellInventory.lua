-- Available classes
Resell.Inventory.Bag = {}
Resell.Inventory.GuildBank = {}
Resell.Inventory.GuildBank.Tab = {}

Resell.Inventory.bags = {}
Resell.Inventory.guildBankTabs = {}

Resell.Inventory.Bag.BAG_UPDATE_STACK = {}
-- Resell.Inventory.Bag.PLAYERBANKSLOTS_CHANGED_STACK = {}

function Resell:InitializeInventory()
    self.Inventory.Bag:InitializeBags()
end

-- Bag Constructor
function Resell.Inventory.Bag:Create(bagId, type)
    local self = setmetatable({}, { __index = Resell.Inventory.Bag })
        self.bagId = bagId
        self.type = type
        self.size = GetContainerNumSlots(self.bagId)
        self.name = Resell.Inventory:GetName(type, bagId)
        self.itemCount = {}
    return self
end

function Resell.Inventory:GetName(type, id)
    local short;
    if type == 1 then short = Resell.CONSTANT.INVENTORY.SHORT
    elseif type == 2 then short = Resell.CONSTANT.BANK.SHORT
    elseif type == 3 then short = Resell.CONSTANT.GUILDBANK.SHORT
    else error("Unknown Container type: "..type, 2) end

    return short..id
end

function Resell.Inventory.Bag:InitializeBags()
    for i, slot in pairs(Resell.CONSTANT.INVENTORY.BAGSLOTS)
    do        
        local bag = self:Create(slot, Resell.CONSTANT.INVENTORY.TYPE)
        table.insert(Resell.Inventory.bags, bag)
        local prevCount = Resell.UTILS.CopyTable(Resell.db.char["BAG"][bag.name]) -- copy of what was in db.
        bag:SetCurrentItemCount()

        Resell:UpdateItemCount(bag.itemCount, prevCount)   
    end
end

function Resell.Inventory.Bag:SetCurrentItemCount()
    self.itemCount = {}
    
    for s = 1,self.size
    do
        local itemID = GetContainerItemID(self.bagId, s)
        if itemID then            
            local _, count = GetContainerItemInfo(self.bagId, s)            
            local itemName = GetItemInfo(itemID)
            if not self.itemCount[itemName] then self.itemCount[itemName] = 0 end -- initialize each field
            self.itemCount[itemName] = self.itemCount[itemName] + count
        end
    end
    
    Resell.db.char["BAG"][self.name] = Resell.UTILS.CopyTable(self.itemCount) -- update db
end

function Resell:BAG_UPDATE(event, bagId)

    return Resell.Inventory.Bag:BAG_UPDATE(event, bagId)
end

function Resell.Inventory:GetBag(bagId)
    for i, bag in pairs(self.bags)
    do   
        if bagId == bag.bagId then return bag end        
    end
    return nil
end

function Resell.Inventory.Bag:BAG_UPDATE(event, bagId)
    local bag = Resell.Inventory:GetBag(bagId)
    if not bag then return end -- don' respond to BAG_UPDATE events if bags haven't been initialized.
    if bag.type == Resell.CONSTANT.BANK.TYPE and not Resell.atBank then return end        
    table.insert(self.BAG_UPDATE_STACK, bagId)
    Resell.gRs_lastEventUpdate[event] = GetTime()
    Resell.UTILS.DebouncedEvent(event, function ()
        local totalPrevCount = {}
        local totalCurrCount = {}
        while #self.BAG_UPDATE_STACK > 0 do
            local bagId = table.remove(self.BAG_UPDATE_STACK)
            local bag = Resell.Inventory:GetBag(bagId)
            local dbBag = Resell.db.char["BAG"][bag.name] or {}
            for k, v in pairs(dbBag)
            do
                if not totalPrevCount[k] then totalPrevCount[k] = 0 end
                totalPrevCount[k] = totalPrevCount[k] + v
            end

            bag:SetCurrentItemCount()

            for k, v in pairs(bag.itemCount)
            do
                if not totalCurrCount[k] then totalCurrCount[k] = 0 end
                totalCurrCount[k] = totalCurrCount[k] + v
            end
        end
        Resell:UpdateItemCount(totalCurrCount, totalPrevCount)        
    end, 0.35)
    
end



function Resell:BANKFRAME_OPENED()
    Resell.atBank = true

    for i, slot in pairs(Resell.CONSTANT.BANK.BAGSLOTS)
    do
        local bag = Resell.Inventory:GetBag(slot)
        if not bag then
            bag = Resell.Inventory.Bag:Create(slot, Resell.CONSTANT.BANK.TYPE)
            table.insert(Resell.Inventory.bags, bag)
            local prevCount = Resell.UTILS.CopyTable(Resell.db.char["BAG"][bag.name]) -- copy of what was in db.
            bag:SetCurrentItemCount()
            Resell:UpdateItemCount(bag.itemCount, prevCount) 
        end
    end
end


function Resell:BANKFRAME_CLOSED()
    Resell.atBank = false    
end

function Resell:PLAYERBANKSLOTS_CHANGED(event, slot)    
    if Resell.atBank then        
        self.gRs_lastEventUpdate[event] = GetTime()
        
        self.UTILS.DebouncedEvent(event, function ()
            local bankContainer = Resell.Inventory:GetBag(Resell.CONSTANT.BANK.BAGSLOTS[1]) -- BANK_CONTAINER
            local prevCount = Resell.UTILS.CopyTable(Resell.db.char["BAG"][bankContainer.name])
            bankContainer:SetCurrentItemCount()

            self:UpdateItemCount(bankContainer.itemCount, prevCount)
        end, 0.005)
    end
    
end

function Resell.Inventory.GuildBank.Tab:Create(tabId, type)
    if Resell.atGuildBank == false then return nil end
    local self = setmetatable({},{ __index = Resell.Inventory.GuildBank.Tab })
        self.tabId = tabId
        self.type = type
        self.size = 98
        self.name = Resell.Inventory:GetName(type, tabId)
        self.guildName = GetGuildInfo("player")
        self.itemCount = {}        
    return self
end



function Resell:GUILDBANKFRAME_OPENED()
    self.atGuildBank = true
end

function Resell:GUILDBANKFRAME_CLOSED()
    self.atGuildBank = false
end

function Resell:GUILDBANKBAGSLOTS_CHANGED(event)
    if Resell.atGuildBank then        
        self.gRs_lastEventUpdate[event] = GetTime()
        local tabId = GetCurrentGuildBankTab()
        local tab = Resell.Inventory:GetGuildBankTab(tabId)
        if not tab then
            tab = Resell.Inventory.GuildBank.Tab:Create(tabId, Resell.CONSTANT.GUILDBANK.TYPE)
            table.insert(Resell.Inventory.guildBankTabs, tab)
        end
         
        self.UTILS.DebouncedEvent(event, function ()            
            if not Resell.db.global["GUILDBANK"][tab.guildName] then
                Resell.db.global["GUILDBANK"][tab.guildName] = {}
            end

            local prevCount = Resell.UTILS.CopyTable(Resell.db.global["GUILDBANK"][tab.guildName][tab.name])            
            tab:SetCurrentItemCount()      
            Resell:UpdateItemCount(tab.itemCount, prevCount)
        end, 0.5)  
    end
end


function Resell.Inventory:GetGuildBankTab(tabId)
    for i, tab in pairs(self.guildBankTabs)
    do
        if tabId == tab.tabId then return tab end
    end
    return nil
end

function Resell.Inventory.GuildBank.Tab:SetCurrentItemCount()
    if Resell.atGuildBank then
        self.itemCount = {}   
        local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(self.tabId)
        if not isViewable or numWithdrawals == 0 then return end    
    
        for s=1,self.size
        do
            local itemLink = GetGuildBankItemLink(self.tabId, s)
            if itemLink then            
                local _, count = GetGuildBankItemInfo(self.tabId, s)
                local itemName = GetItemInfo(itemLink)
                if not self.itemCount[itemName] then self.itemCount[itemName] = 0 end
                self.itemCount[itemName] = self.itemCount[itemName] + count       
            end
        end             

        Resell.db.global["GUILDBANK"][self.guildName][self.name] = Resell.UTILS.CopyTable(self.itemCount)
    end  
end

function Resell:UpdateItemCount(currItemCount, prevItemCount)
    local changes = {}

    if not currItemCount then
        error("Can't update item count without current item count.", 2)
    end

    if type(prevItemCount) ~= "table" then prevItemCount = {} end

    for k, v in pairs(currItemCount)
    do
        -- item did not exist on the previous count

        if not prevItemCount[k] then
            prevItemCount[k] = 0
        end
        
        local diff = v - prevItemCount[k]

        if diff ~= 0 then changes[k] = diff end

        Resell.DBOperation.UpdateItem(k, diff, 1, nil, true)
        prevItemCount[k] = nil -- remove updated item to avoid iterating through it again in the next loop 
    end

    for k, v in pairs(prevItemCount) do
        -- item ceased to exist in the current count                
        local diff = -v
        if diff ~= 0 then changes[k] = diff end

        Resell.DBOperation.UpdateItem(k, diff, 1, nil, true)
    end

    Resell.gRs_latestChanges = changes
end