local _, ADDONSELF = ...
local L = ADDONSELF.L
local RegEvent = ADDONSELF.regevent
local BattleZoneHelper = ADDONSELF.BattleZoneHelper

local elapseCache = {}

local function GetElapseFromCache(nameOrId, instanceID)
    if BattleZoneHelper.BGID_MAPNAME_MAP[nameOrId] then
        nameOrId = BattleZoneHelper.BGID_MAPNAME_MAP[nameOrId]
    end

    local key = nameOrId .. "-" .. instanceID

    local data = elapseCache[key]

    if data then

        if GetServerTime() - data.time > 90 then -- data ttl 90sec (bg will close in 2 min)
            elapseCache[key] = nil
            return nil
        end

        return GetServerTime() - data.time + data.elapse
    end

    return nil
end

local function UpdateInstanceButtonText()
    local mapName, _, _, _, battleGroundID = GetBattlegroundInfo()

    if not mapName then
        return
    end

	for i = 1, BATTLEFIELD_ZONES_DISPLAYED, 1 do
        local button = getglobal("BattlefieldZone"..i)

        local tx = button.title;

        (function()
            if not tx then
                return
            end

            local _, _, instanceID = string.find(tx, mapName .. " (%d+)")

            if not instanceID then
                return
            end

            local elp = GetElapseFromCache(battleGroundID, instanceID)

            if elp then

                -- local start = data.time - data.elapse
                -- print(GetServerTime() - data.time)
                -- print(data.elapse)
                button:SetText(tx .. GREEN_FONT_COLOR:WrapTextInColorCode(" (" .. SecondsToTime(elp) .. ")"))
                -- print()
            end

        end)()


    end
end

RegEvent("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= "BATTLEINFO" then
        return
    end

    sender = strsplit("-", sender)

    if sender == UnitName("player") then
        return
    end

    -- print(sender)
    -- print(text)
    local cmd, arg1, arg2, arg3 = strsplit(" ", text)

    if cmd == "ELAPSE_WANTED" then
        local battleGroundID, instanceID = BattleZoneHelper:GetCurrentBG()

        if battleGroundID and instanceID then
            local key = battleGroundID .. "-" .. instanceID
            local elapse = -1
            if not GetBattlefieldWinner() then
                elapse = floor(GetBattlefieldInstanceRunTime() / 1000)
            end
            C_ChatInfo.SendAddonMessage("BATTLEINFO", "ELAPSE_SYNC " .. key .. " " .. elapse .. " " .. GetServerTime(), "GUILD")
        end
    elseif cmd == "ELAPSE_SYNC" then

        local key = arg1
        local elapse = tonumber(arg2)
        local time = tonumber(arg3)

        if (not key) or (not elapse) or (not time) then
            return
        end
      
        if elapseCache[key] then
            if elapseCache[key].time > time then
                return
            end
        end

        if elapse < 0 then
            elapseCache[key] = nil
        else
            elapseCache[key] = {
                sender = sender,
                elapse = elapse,
                time = time,
            }
        end

        UpdateInstanceButtonText()
    end


end)


local battleList = {}
local function UpdateBattleListCache()
    local mapName = GetBattlegroundInfo()

    if not mapName then
        return
    end

    if not battleList[mapName] then
        battleList[mapName] = {}
    end
    table.wipe(battleList[mapName])
    
    local n = GetNumBattlefields()
    for i = 1, n  do
        local instanceID = GetBattlefieldInstanceInfo(i)
        battleList[mapName][tonumber(instanceID)] = i .. "/" .. n
    end

    UpdateInstanceButtonText()
end

RegEvent("BATTLEFIELDS_SHOW", function()
    C_ChatInfo.SendAddonMessage("BATTLEINFO", "ELAPSE_WANTED", "GUILD")
end)

RegEvent("ADDON_LOADED", function()
    C_ChatInfo.RegisterAddonMessagePrefix("BATTLEINFO")

    hooksecurefunc("JoinBattlefield", UpdateBattleListCache)
    hooksecurefunc("BattlefieldFrame_Update", UpdateBattleListCache)

    -- HAHAHAHAHA 
    local leavequeuebtn
    do
        local t = CreateFrame("Button", nil, f, "UIPanelButtonTemplate, SecureActionButtonTemplate")
        t:SetFrameStrata("TOOLTIP")
        t:SetText(L["CTRL+Hide=Leave"])
        t:SetAttribute("type", "macro") -- left click causes macro
        -- t:SetAttribute("macrotext", "/click MiniMapBattlefieldFrame RightButton" .. "\r\n" .. "/click DropDownList1Button3") -- text for macro on left click
        t:Hide()

        t.updateMacro = function(showid)
            local queued = 0

            for i = 1, MAX_BATTLEFIELD_QUEUES do
                local status, mapName, instanceID = GetBattlefieldStatus(i)
                local current = i == showid 

                if current then

                    local loc = i * 4 - 1 - queued
                    leavequeuebtn:SetAttribute("macrotext", "/click MiniMapBattlefieldFrame RightButton" .. "\r\n" .. "/stopmacro [combat]" .."\r\n" .. "/click DropDownList1Button" .. (loc)) -- text for macro on left click
                    break
                end

                if status == "queued" then
                    queued = queued + 1
                end
            end
        end


        leavequeuebtn = t
    end

    local joinqueuebtn
    do
        local j = CreateFrame("Button", nil, f, "UIPanelButtonTemplate, SecureActionButtonTemplate")
        j:SetFrameStrata("TOOLTIP")
        j:SetText(ENTER_BATTLE)
        j:SetAttribute("type", "macro") -- left click causes macro
        j:SetAttribute("macrotext", "/click MiniMapBattlefieldFrame RightButton" .. "\r\n" .. "/run JOIN_B=nil if UnitAffectingCombat('player')then SendSystemMessage(ERR_AFFECTING_COMBAT)else local x,f,b=_,_,DropDownList1;for _,x in ipairs({b:GetChildren()})do f=x.value if f==ENTER_BATTLE then JOIN_B=x break end end end local bt=CreateFrame('Button', 'JOIN_BTN', UIParent, 'SecureActionButtonTemplate')bt:SetAttribute('type', 'click')bt:SetAttribute('clickbutton',JOIN_B)".. "\r\n" .. "/stopmacro [combat]".. "\r\n" .. "/click JOIN_BTN") -- text for macro on left click
        j:Hide()
        joinqueuebtn = j
    end    
    
    StaticPopupDialogs["CONFIRM_BATTLEFIELD_ENTRY"].OnHide = function()
        leavequeuebtn:Hide()
        joinqueuebtn:Hide()
    end
    
    StaticPopupDialogs["CONFIRM_BATTLEFIELD_ENTRY"].button2 = L["CTRL+Hide=Leave"]

    -- hooksecurefunc(StaticPopupDialogs["CONFIRM_BATTLEFIELD_ENTRY"], "OnShow", function(self)
    StaticPopupDialogs["CONFIRM_BATTLEFIELD_ENTRY"].OnShow = function(self, data)
        FlashClientIcon()
        local tx = self.text:GetText()
        local isCombat = UnitAffectingCombat('player')
        leavequeuebtn.updateMacro(data)
        
        if not self.button2.batteinfohooked then
            leavequeuebtn:SetAllPoints(self.button2)
            self.button2:SetScript("OnUpdate", function(self)

                if IsControlKeyDown() and not isCombat then
                    leavequeuebtn:Show()
                else
                    leavequeuebtn:Hide()
                end
            end)
            self.button2.batteinfohooked = true
        end

        if not self.button1.batteinfohooked then
            joinqueuebtn:SetAllPoints(self.button1)
            self.button1.batteinfohooked = true
        end

        if isCombat then
            joinqueuebtn:Hide()
        else
            joinqueuebtn:Show()
        end

        if string.find(tx, L["List Position"], 1, 1) or string.find(tx, L["New"], 1 , 1) then			
            return
        end    

        for mapName, instanceIDs in pairs(battleList) do
            local _, _ ,toJ = string.find(tx, ".+" .. mapName .. " (%d+).+")
            toJ = tonumber(toJ)
            if toJ then
                if instanceIDs[toJ] then
                    local text = L["List Position"] .. " " .. instanceIDs[toJ]

                    local elp = GetElapseFromCache(mapName, toJ)
                    if elp then
                        text = SecondsToTime(elp)
                    end

                    text = RED_FONT_COLOR:WrapTextInColorCode(text)

                    self.text:SetText(string.gsub(tx ,toJ , YELLOW_FONT_COLOR:WrapTextInColorCode(toJ) .. "(" .. text .. ")"))
                else
                    local text = GREEN_FONT_COLOR:WrapTextInColorCode(L["New"])
                    self.text:SetText(string.gsub(tx ,toJ , YELLOW_FONT_COLOR:WrapTextInColorCode(toJ) .. "(" .. text .. ")"))

                end
                break
            end
        end
        
    end

end)
