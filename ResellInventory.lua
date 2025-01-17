

-- Available classes
Resell.Inventory.Bag = {}
Resell.Inventory.GuildBank = {}
Resell.Inventory.Bank = {}

-- store instances for each bag
Resell.Inventory.Bag.bags = {}

Resell.Inventory.Bag.BAG_UPDATE_STACK = {}

Resell.Inventory.GuildBank.tabNumSlots = 98
Resell.Inventory.GuildBank.frameIsShown = false
Resell.Inventory.GuildBank.itemCount = {}
-- store instances for each tab
Resell.Inventory.GuildBank.tabs = {}

function Resell.Inventory:InitializeInventory()
    self.Bag:InitializeBags()
    -- self.Bag:UploadItemCount()

    self.GuildBank:InitializeGuildBank()
    

    Resell:RegisterEvent("BAG_UPDATE", "OnBagUpdate")
    -- Resell:RegisterMessage("ITEM_COUNT_UPDATED", "OnItemCountUpdate")
end

-- Bag Constructor
function Resell.Inventory.Bag:Create(bagId, type)
    local self = setmetatable({}, { __index = Resell.Inventory.Bag })
        self.bagId = bagId
        self.type = type
        self.size = GetContainerNumSlots(self.bagId)
    return self
end

function Resell.Inventory.Bag:InitializeBags()
    for b in pairs(Resell.CONSTANT.INVENTORY.BAGSLOTS)
    do
        self.bags[b] = self:Create(b)
        self.bags[b]:SetCurrentItemCount()
        self.bags[b]:UploadItemCount()
    end
end

function Resell.Inventory.Bag:SetCurrentItemCount()
    self.itemCount = {} -- only care about real inventory state, not previous.
    local numSlots = GetContainerNumSlots(self.bagId)
    
    for s = 1,numSlots
    do
        local itemID = GetContainerItemID(self.bagId, s)
        if itemID then            
            local _, count = GetContainerItemInfo(self.bagId, s)            
            local itemName = GetItemInfo(itemID)
            if not self.itemCount[itemName] then self.itemCount[itemName] = 0 end -- initialize each field
            self.itemCount[itemName] = self.itemCount[itemName] + count
        end
    end
end

function Resell:OnBagUpdate(event, bagId)
    return Resell.Inventory.Bag:OnBagUpdate(event, bagId)
end

function Resell.Inventory.Bag:OnBagUpdate(event, bagId)
    local numSlots = GetContainerNumSlots(-2)    
    Resell:Print(numSlots)
    if numSlots > 0 then -- filter out BAG_UPDATE firing with negative indexes
        table.insert(self.BAG_UPDATE_STACK, bagId)
        Resell.gRs_lastEventUpdate[event] = GetTime()
        Resell.UTILS.DebouncedEvent(event, function ()
            local totalPrevCount = {}
            local totalCurrCount = {}
            while #self.BAG_UPDATE_STACK > 0 do
                local bagId = table.remove(self.BAG_UPDATE_STACK)
                local bag = self.bags[bagId]
                for k, v in pairs(bag.itemCount)
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
            Resell:OnItemCountUpdate(totalCurrCount, totalPrevCount)
            -- Resell:SendMessage("ITEM_COUNT_UPDATED", totalCurrCount, totalPrevCount)
        end, 0.005)
    end
end

function Resell.Inventory.GuildBank:InitializeGuildBank()
    Resell:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankShow")
    Resell:RegisterEvent("GUILDBANKFRAME_CLOSED", "OnGuildBankClose")
    Resell:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnGuildBankBagSlotsChanged")
    local guildName = GetGuildInfo("player");
    if guildName then        
        if not Resell.db.global["GUILD_BANK"][guildName] then Resell.db.global["GUILD_BANK"][guildName] = {} end
        self.dbItemCount = Resell.db.global["GUILD_BANK"][guildName]
    end
end

function Resell:OnGuildBankShow()
    return self.Inventory.GuildBank:OnShow()
end

function Resell:OnGuildBankClose()
    return self.Inventory.GuildBank:OnClose()
end

function Resell:OnGuildBankBagSlotsChanged(event)
    return self.Inventory.GuildBank:OnSlotsChanged(event)
end

function Resell.Inventory.GuildBank:OnShow()
    self.frameIsShown = true
    Resell:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnGuildBankBagSlotsChanged")

    -- self:SetCurrentItemCount() -- GUILDBANKBAGSLOTS_CHANGED fires on opened too.
end

function Resell.Inventory.GuildBank:OnClose()
    self.frameIsShown = false
    Resell:UnregisterEvent("GUILDBANKBAGSLOTS_CHANGED")
end

function Resell.Inventory.GuildBank:OnSlotsChanged(event)
    Resell.gRs_lastEventUpdate[event] = GetTime()
     
    Resell.UTILS.DebouncedEvent(event, function ()
        self:SetCurrentItemCount()
    end, 1.5)    
end

function Resell.Inventory.GuildBank:SetCurrentItemCount()
    if self.frameIsShown then
        self.itemCount = {}
        for t = 1,GetNumGuildBankTabs()
        do        
            local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(t)
            if not isViewable or numWithdrawals == 0 then return end    
        
            for s=1,self.tabNumSlots
            do
                local itemLink = GetGuildBankItemLink(t, s)
                if itemLink then            
                    local _, count = GetGuildBankItemInfo(t, s)
                    local itemName = GetItemInfo(itemLink)
                    if not self.itemCount[itemName] then self.itemCount[itemName] = 0 end
                    self.itemCount[itemName] = self.itemCount[itemName] + count       
                end
            end
        end
        -- arg1: current item count
        -- arg2: previous item count
        -- Resell:SendMessage("ITEM_COUNT_UPDATED", self.itemCount, self.dbItemCount)
        Resell:OnItemCountUpdate(self.itemCount, self.dbItemCount)
        Resell.UTILS.CopyTable(self.dbItemCount, self.itemCount)
    end  
end


function Resell:OnItemCountUpdate(currItemCount, prevItemCount)
    local changes = {}

    for k, v in pairs(currItemCount)
    do
        -- item did not exist on the previous count
        if not prevItemCount[k] then
            prevItemCount[k] = 0
        end
        
        local diff = v - prevItemCount[k]

        if diff ~= 0 then changes[k] = diff end

        Resell.DBOperation.UpdateItem(k, diff, 1)
        prevItemCount[k] = nil -- remove updated item to avoid iterating through it again in the next loop 
    end
    for k, v in pairs(prevItemCount) do
        -- item ceased to exist in the current count                
        local diff = -v

        if diff ~= 0 then changes[k] = diff end

        Resell.DBOperation.UpdateItem(k, diff, 1)
    end

    Resell.gRs_latestChanges = changes
    -- for k, v in pairs(Resell.gRs_latestChanges)
    -- do
    --     Resell:Print(k, v)
    -- end
end


-- on first seen, uploads itemCount tbl to persistent item db.
function Resell.Inventory.Bag:UploadItemCount()
    -- upload inventory    
    if Resell.db.char.inventoryFirstSeen then
        for b=0,12
        do
            if self.bags[b] then
                
                for k,v in pairs(self.bags[b].itemCount)
                do                    
                    Resell.DBOperation.UpdateItem(k, v, 1)
                end          
            end
        end
        Resell.db.char.inventoryFirstSeen = false
        Resell:Print("Inventory uploaded.")
    end
end