local LFT = CreateFrame("Frame")
local me = UnitName('player')
local addonVer = '0.0.1.4'
local showedUpdateNotification = false
local LFT_ADDON_CHANNEL = 'LFT'
local LFTTypeDropDown = CreateFrame('Frame', 'LFTTypeDropDown', UIParent, 'UIDropDownMenuTemplate')
local groupsFormedThisSession = 0

--todo test with full group
--test with two smaller groups at the same time [kinda]
--chat channels messed up on er
--eye doesnt stop when group is full [x]
--when someone leaves group, leader can select more than one
local DEV_GROUP_SIZE = 5

LFT.class = ''
LFT.channel = 'LFT'
LFT.channelIndex = 0
LFT.level = UnitLevel('player')
LFT.findingGroup = false
LFT.findingMore = false
LFT:RegisterEvent("ADDON_LOADED")
LFT:RegisterEvent("PLAYER_ENTERING_WORLD")
LFT:RegisterEvent("PARTY_MEMBERS_CHANGED")
LFT:RegisterEvent("PARTY_LEADER_CHANGED")
LFT:RegisterEvent("PLAYER_LEVEL_UP")
LFT.availableDungeons = {}
LFT.group = {}
LFT.oneGroupFull = false
LFT.groupFullCode = ''
LFT.acceptNextInvite = false
LFT.onlyAcceptFrom = ''
LFT.queueStartTime = 0
LFT.types = {
    [1] = 'Suggested Dungeons',
    [2] = 'Random Dungeon',
    [3] = 'All Available Dungeons'
}
LFT.maxDungeonsList = 11
LFT.minimapFrames = {}
LFT.myRandomTime = 0
LFT.random_min = 0
LFT.random_max = 20

LFT.RESET_TIME = 0
LFT.TANK_TIME = 2
LFT.HEALER_TIME = 5
LFT.DAMAGE_TIME = 5
LFT.FULLCHECK_TIME = 26 --time when checkGroupFull is called, has to wait for goingWith messages
LFT.TIME_MARGIN = 30

LFT.foundGroup = false
LFT.inGroup = false
LFT.isLeader = false
LFT.LFMGroup = {}
LFT.LFMDungeonCode = ''
LFT.currentGroupSize = 0

local COLOR_RED = '|cffff222a'
local COLOR_ORANGE = '|cffff8000'
local COLOR_GREEN = '|cff1fba1f'
local COLOR_HUNTER = '|cffabd473'
local COLOR_YELLOW = '|cffffff00'
local COLOR_WHITE = '|cffffffff'
local COLOR_DISABLED = '|cff888888'
local COLOR_TANK = '|cff0070de'
local COLOR_HEALER = COLOR_GREEN
local COLOR_DAMAGE = COLOR_RED

-- channel join delayer

local LFTChannelJoinDelay = CreateFrame("Frame")
LFTChannelJoinDelay:Hide()

LFTChannelJoinDelay:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFTChannelJoinDelay:SetScript("OnHide", function()
    LFT.checkLFTChannel()
end)

LFTChannelJoinDelay:SetScript("OnUpdate", function()
    local plus = 10 --seconds
    local gt = GetTime() * 1000 --22.123 -> 22123
    local st = (this.startTime + plus) * 1000 -- (22.123 + 0.1) * 1000 =  22.223 * 1000 = 22223
    if gt >= st then
        LFTChannelJoinDelay:Hide()
    end
end)

local LFTQueue = CreateFrame("Frame")
LFTQueue:Hide()

-- group invite timer

local LFTInvite = CreateFrame("Frame")
LFTInvite:Hide()
LFTInvite:SetScript("OnShow", function()
    this.startTime = GetTime()
    this.inviteIndex = 1
end)

LFTInvite:SetScript("OnUpdate", function()
    local plus = 0.5 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        this.startTime = GetTime()

        this.inviteIndex = this.inviteIndex + 1

        if this.inviteIndex == 2 then
            if LFT.group[LFT.groupFullCode].healer ~= '' then
                InviteByName(LFT.group[LFT.groupFullCode].healer)
            end
        end
        if this.inviteIndex == 3 then
            if LFT.group[LFT.groupFullCode].damage1 ~= '' then
                InviteByName(LFT.group[LFT.groupFullCode].damage1)
            end
        end
        if this.inviteIndex == 4 and this.inviteIndex <= DEV_GROUP_SIZE then
            if LFT.group[LFT.groupFullCode].damage2 ~= '' then
                InviteByName(LFT.group[LFT.groupFullCode].damage2)
            end
        end
        if this.inviteIndex == 5 and this.inviteIndex <= DEV_GROUP_SIZE then
            if LFT.group[LFT.groupFullCode].damage3 ~= '' then
                InviteByName(LFT.group[LFT.groupFullCode].damage3)
                LFTInvite:Hide()
            end
        end
    end
end)

-- role check timer

local LFTRoleCheck = CreateFrame("Frame")
LFTRoleCheck:Hide()

LFTRoleCheck:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFTRoleCheck:SetScript("OnHide", function()
end)

LFTRoleCheck:SetScript("OnUpdate", function()
    local plus = 25 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        declineRole()
        LFTRoleCheck:Hide()
    end
end)

-- who counter timer

local LFTWhoCounter = CreateFrame("Frame")
LFTWhoCounter:Hide()
LFTWhoCounter.people = 0
LFTWhoCounter.listening = false
LFTWhoCounter:SetScript("OnShow", function()
    this.startTime = GetTime()
    LFTWhoCounter.people = 0
    LFTWhoCounter.listening = true
end)

LFTWhoCounter:SetScript("OnHide", function()
    LFTWhoCounter.people = LFTWhoCounter.people + 1 -- + me
    lfprint('Found ' .. LFTWhoCounter.people .. ' online using LFT addon.')
    LFTWhoCounter.listening = false
end)

LFTWhoCounter:SetScript("OnUpdate", function()
    local plus = 5 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFTWhoCounter:Hide()
    end
end)

-- communication

local LFTComms = CreateFrame("Frame")
LFTComms:Hide()
LFTComms:RegisterEvent("CHAT_MSG_CHANNEL")
LFTComms:RegisterEvent("CHAT_MSG_WHISPER")
LFTComms:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
LFTComms:RegisterEvent("PARTY_INVITE_REQUEST")
LFTComms:RegisterEvent("CHAT_MSG_ADDON")

LFTComms:SetScript("OnEvent", function()
    if event then
        if event == 'CHAT_MSG_ADDON' and arg1 == 'LFT' then
            lfdebug(arg4 .. ' says : ' .. arg2)
            if string.sub(arg2, 1, 11) == 'LFTVersion:' and arg4 ~= me then
                if not showedUpdateNotification then
                    local verEx = string.split(arg2, ':')
                    if LFT.ver(verEx[2]) > LFT.ver(addonVer) then
                        lfprint(COLOR_HUNTER .. 'Looking For Turtles ' .. COLOR_WHITE .. ' - new version available ' ..
                                COLOR_GREEN .. 'v' .. verEx[2] .. COLOR_WHITE .. ' (current version ' ..
                                COLOR_ORANGE .. 'v' .. addonVer .. COLOR_WHITE .. ')')
                        lfprint('Update yours at ' .. COLOR_HUNTER .. 'https://github.com/CosminPOP/LFT')
                        showedUpdateNotification = true
                    end
                end
            end
            -- fake fill minimap frames
            if string.sub(arg2, 1, 11) == 'leaveQueue:' and arg4 ~= me then
                leaveQueue()
            end
            if string.sub(arg2, 1, 8) == 'minimap:' then
                if not LFT.isLeader then
                    local miniEx = string.split(arg2, ':')
                    local code = miniEx[2]
                    local tank = tonumber(miniEx[3])
                    local healer = tonumber(miniEx[4])
                    local damage = tonumber(miniEx[5])
                    LFT.group[code] = {
                        tank = '',
                        healer = '',
                        damage1 = '',
                        damage2 = '',
                        damage3 = ''
                    }
                    if tank == 1 then LFT.group[code].tank = 'DummyTank' end
                    if healer == 1 then LFT.group[code].healer = 'DummyHealer' end
                    if damage > 0 then LFT.group[code].damage1 = 'DummyDamage1' end
                    if damage > 1 then LFT.group[code].damage2 = 'DummyDamage2' end
                    if damage > 2 then LFT.group[code].damage3 = 'DummyDamage3' end
                end
            end
            if string.sub(arg2, 1, 14) == 'LFMPartyReady:' then

                local queueEx = string.split(arg2, ':')
                local mCode = queueEx[2]
                LFT.groupFullCode = mCode
                --untick everything
                for i, frame in LFT.availableDungeons do
                    getglobal('Dungeon_' .. LFT.groupFullCode):SetChecked(false)
                end
                LFT.findingGroup = false
                LFT.findingMore = false
                local background = ''
                local dungeonName = 'unknown'
                for d, data in next, LFT.dungeons do
                    if data.code == mCode then
                        background = data.background
                        dungeonName = d
                    end
                end
                getglobal('LFTGroupReadyBackground'):SetTexture('Interface\\addons\\LFT\\images\\background\\ui-lfg-background-' .. background)
                getglobal('LFTGroupReadyRole'):SetTexture('Interface\\addons\\LFT\\images\\' .. LFT_ROLE .. '2')
                getglobal('LFTGroupReadyMyRole'):SetText(LFT.ucFirst(LFT_ROLE))
                getglobal('LFTGroupReadyDungeonName'):SetText(dungeonName)
                getglobal('LFTGroupReady'):Show()

                PlaySound("ReadyCheck")
                LFT.fixMainButton()
                getglobal('LFTMain'):Hide()
                LFTQueue:Hide() -- todo check this

                if LFT.isLeader then
                    SendChatMessage("[LFT]:lft_group_formed:" .. mCode, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
                end
            end
            if string.sub(arg2, 1, 10) == 'weInQueue:' then
                local queueEx = string.split(arg2, ':')
                LFT.weInQueue(queueEx[2])
            end
            if string.sub(arg2, 1, 10) == 'roleCheck:' then
                lfprint('A role check has been initiated. Your group will be queued when all members have selected a role.')
                UIErrorsFrame:AddMessage("|cff69ccf0[LFT] |cffffff00A role check has been initiated. Your group will be queued when all members have selected a role.")

                local argEx = string.split(arg2, ':')
                local mCode = argEx[2]
                LFT.LFMDungeonCode = mCode
                LFT.resetGroup()

                if LFT.isLeader then
                    if LFT_ROLE == 'tank' then LFT.LFMGroup.tank = me end
                    if LFT_ROLE == 'healer' then LFT.LFMGroup.healer = me end
                    if LFT_ROLE == 'damage' then LFT.LFMGroup.damage1 = me end
                else
                    getglobal('LFTRoleCheckQForText'):SetText(COLOR_WHITE .. "Queued for " .. COLOR_YELLOW .. LFT.dungeonNameFromCode(mCode))
                    getglobal('LFTRoleCheck'):Show()
                    getglobal('LFTGroupReady'):Hide()
                    LFTRoleCheck:Show()
                end
            end

            if string.sub(arg2, 1, 11) == 'acceptRole:' then
                local roleEx = string.split(arg2, ':')
                local roleColor = ''

                if roleEx[2] == 'tank' then
                    LFT.LFMGroup.tank = arg4
                    roleColor = COLOR_TANK
                end
                if roleEx[2] == 'healer' then
                    LFT.LFMGroup.healer = arg4
                    roleColor = COLOR_HEALER
                end
                if roleEx[2] == 'damage' then
                    if LFT.LFMGroup.damage1 == '' then
                        LFT.LFMGroup.damage1 = arg4
                    elseif LFT.LFMGroup.damage2 == '' then
                        LFT.LFMGroup.damage2 = arg4
                    elseif LFT.LFMGroup.damage3 == '' then
                        LFT.LFMGroup.damage3 = arg4
                    end
                    roleColor = COLOR_DAMAGE
                end
                if arg4 == me then
                    lfprint('You have chosen: ' .. roleColor .. LFT.ucFirst(roleEx[2]))
                else
                    lfprint(arg4 .. ' has chosen: ' .. roleColor .. LFT.ucFirst(roleEx[2]))
                end
                LFT.checkLFMgroup()
            end
            if string.sub(arg2, 1, 12) == 'declineRole:' then
                LFT.checkLFMgroup(arg4)
            end
        end
        if event == 'PARTY_INVITE_REQUEST' and LFT.acceptNextInvite then
            if arg1 == LFT.onlyAcceptFrom then
                LFT.AcceptGroupInvite()
                LFT.acceptNextInvite = false
            else
                LFT.DeclineGroupInvite()
            end
        end
        if event == 'CHAT_MSG_CHANNEL_LEAVE' then
            LFT.removePlayerFromVirtualParty(arg2, false) --unknown role
        end
        if event == 'CHAT_MSG_CHANNEL' and string.find(arg1, '[LFT]', 1, true) and arg8 == LFT.channelIndex and arg2 ~= me and --for lfm
                string.find(arg1, '(LFM)', 1, true) then
            --[LFT]:stratlive:(LFM):name
            local mEx = string.split(arg1, ':')
            if mEx[4] == me then
                LFT.onlyAcceptFrom = arg2
                LFT.acceptNextInvite = true
            end
        end
        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFT.channelIndex and string.find(arg1, 'lft_group_formed', 1, true) then
            local gfEx = string.split(arg1, ':')
            local code = gfEx[3]
            groupsFormedThisSession = groupsFormedThisSession + 1
            lfdebug(groupsFormedThisSession .. ' groups formed this session.')
            LFT_FORMED_GROUPS[code] = LFT_FORMED_GROUPS[code] + 1
        end
        if event == 'CHAT_MSG_CHANNEL' and string.find(arg1, '[LFT]', 1, true) and arg8 == LFT.channelIndex and arg2 ~= me and --for lfg
                string.find(arg1, 'party:ready', 1, true) then
            local mEx = string.split(arg1, ':')
            local healer = mEx[5]
            local damage1 = mEx[6]
            local damage2 = mEx[7]
            local damage3 = mEx[8]

            --check if party ready message is for me
            if me ~= healer and me ~= damage1 and me ~= damage2 and me ~= damage3 then return end

            LFT.onlyAcceptFrom = arg2
            LFT.acceptNextInvite = true

            local background = ''
            local dungeonName = 'unknown'
            for d, data in next, LFT.dungeons do
                if data.code == mEx[2] then
                    background = data.background
                    dungeonName = d
                end
            end
            getglobal('LFTGroupReadyBackground'):SetTexture('Interface\\addons\\LFT\\images\\background\\ui-lfg-background-' .. background)
            getglobal('LFTGroupReadyRole'):SetTexture('Interface\\addons\\LFT\\images\\' .. LFT_ROLE .. '2')
            getglobal('LFTGroupReadyMyRole'):SetText(LFT.ucFirst(LFT_ROLE))
            getglobal('LFTGroupReadyDungeonName'):SetText(dungeonName)
            getglobal('LFTGroupReady'):Show()
            getglobal('LFTRoleCheck'):Hide()

            PlaySound("ReadyCheck")
            LFTQueue:Hide()

            LFT.findingGroup = false
            LFT.findingMore = false
            getglobal('LFTMain'):Hide()

            LFT.fixMainButton()
        end

        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFT.channelIndex and arg2 ~= me then
            if string.sub(arg1, 1, 7) == 'whoLFT:' then
                SendChatMessage('meLFT:' .. addonVer, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
            end
            if string.sub(arg1, 1, 6) == 'meLFT:' then
                --lfdebug(arg1)
                if LFTWhoCounter.listening then
                    LFTWhoCounter.people = LFTWhoCounter.people + 1
                end
            end
        end

        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFT.channelIndex and not LFT.oneGroupFull and (LFT.findingGroup or LFT.findingMore) and arg2 ~= me then

            if string.sub(arg1, 1, 6) == 'found:' then
                local foundEx = string.split(arg1, ':')
                local mRole = foundEx[2]
                local mDungeon = foundEx[3]
                local name = foundEx[4]

                if LFT_ROLE == mRole and not LFT.foundGroup and name == me then
                    SendChatMessage('goingWith:' .. arg2 .. ':' .. mDungeon .. ':' .. LFT_ROLE, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
                    LFT.foundGroup = true
                end
            end

            if string.sub(arg1, 1, 10) == 'leftQueue:' then
                local leftEx = string.split(arg1, ':')
                local name = arg2
                local mRole = leftEx[2]
                LFT.removePlayerFromVirtualParty(name, mRole)
            end

            if string.sub(arg1, 1, 10) == 'goingWith:' and (LFT_ROLE == 'tank' or LFT.isLeader) then

                local withEx = string.split(arg1, ':')
                local leader = withEx[2]
                local mDungeon = withEx[3]
                local mRole = withEx[4]
                --                lfdebug('should remove ' .. arg2 .. ' from my group ' .. mDungeon)
                --check if im queued for mDungeon
                for dungeon, _ in next, LFT.group do
                    if dungeon == mDungeon then
                        if leader ~= me then
                            -- only healers and damages respond with goingwith
                            LFT.remHealerOrDamage(mDungeon, arg2)
                        end
                    end
                    -- otherwise, dont care
                end

                -- lfm leader should invite this guy now
                if LFT.isLeader and leader == me then
                    if LFT.isNeededInLFMGroup(mRole, arg2, mDungeon) then
                        LFT.inviteInLFMGroup(arg2)
                    end
                    return true
                end
            end

            if string.sub(arg1, 1, 4) == 'LFG:' then

                local spamSplit = string.split(arg1, ':')
                local mDungeonCode = spamSplit[2]
                local mRole = spamSplit[3] --other's role

                for dungeon, data in next, LFT.dungeons do
                    if data.queued and data.code == mDungeonCode then

                        -- LFM, leader found someone
--                        if LFT.isLeader then
--                            if LFT.isNeededInLFMGroup(mRole, arg2, mDungeonCode) then
--                                LFT.inviteInLFMGroup(arg2)
--                            end
--                            return true
--                        end


                        if LFT_ROLE == 'tank' then
                            LFT.group[mDungeonCode].tank = me

                            if mRole == 'healer' then LFT.addHealer(mDungeonCode, arg2) end
                            if mRole == 'damage' then LFT.addDamage(mDungeonCode, arg2) end
                        end

                        --pseudo fill group for tooltip display
                        if LFT_ROLE == 'healer' then
                            LFT.addHealer(mDungeonCode, me, true)

                            if mRole == 'tank' and LFT.group[mDungeonCode].tank == '' then
                                LFT.group[mDungeonCode].tank = arg2
                            end

                            if mRole == 'damage' then
                                LFT.addDamage(mDungeonCode, arg2, true)
                            end
                        end

                        if LFT_ROLE == 'damage' then
                            LFT.addDamage(mDungeonCode, me, true)
                            if mRole == 'tank' and LFT.group[mDungeonCode].tank == '' then
                                LFT.group[mDungeonCode].tank = arg2
                            end
                            if mRole == 'healer' and LFT.group[mDungeonCode].healer == '' then
                                LFT.group[mDungeonCode].healer = arg2
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- debug and print functions

function lfprint(a)
    if a == nil then
        DEFAULT_CHAT_FRAME:AddMessage(COLOR_HUNTER .. '[LFT]|cff0070de:' .. time() .. '|cffffffff attempt to print a nil value.')
        return false
    end
    DEFAULT_CHAT_FRAME:AddMessage(COLOR_HUNTER .. "[LFT] |cffffffff" .. a)
end

function lferror(a)
    DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0[LFTError]|cff0070de:' .. time() .. '|cffffffff[' .. a .. ']')
end

function lfdebug(a)
    if me ~= 'Holystrike' and me ~= 'Cosmort' and
            me ~= 'Cosmin' and me ~= 'Kzktst' and
            me ~= 'Er' and me ~= 'Rake' and
            me ~= 'Kaizer' and me ~= 'Laciupacapra' and
            me ~= 'Pog' and me ~= 'Xerron' and
            me ~= 'Holystrike' and me ~= 'Xerrtwo' then
        return false
    end
    if type(a) == 'boolean' then
        if a then
            lfprint('|cff0070de[LFTDEBUG:' .. time() .. ']|cffffffff[true]')
        else
            lfprint('|cff0070de[LFTDEBUG:' .. time() .. ']|cffffffff[false]')
        end
        return true
    end
    lfprint('|cff0070de[LFTDEBUG:' .. time() .. ']|cffffffff[' .. a .. ']')
end

LFT:SetScript("OnEvent", function()
    if event then
        if event == "ADDON_LOADED" and arg1 == 'LFT' then
            LFT.init()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            LFT.level = UnitLevel('player')
            LFT.sendMyVersion()
        end
        if event == "PARTY_LEADER_CHANGED" then
            LFT.isLeader = IsPartyLeader()
        end
        if event == "PARTY_MEMBERS_CHANGED" then
            lfdebug('party members changed')
            local someoneJoined = GetNumPartyMembers() + 1 > LFT.currentGroupSize
            local someoneLeft = GetNumPartyMembers() + 1 < LFT.currentGroupSize

            if someoneJoined then lfdebug('someone joined') end
            if someoneLeft then lfdebug('someone left') end

            LFT.currentGroupSize = GetNumPartyMembers() + 1
            LFT.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

            if LFT.inGroup then
                if LFT.isLeader then
                else
                    getglobal('LFTMain'):Hide()
                end
            else -- i left the group OR everybody left
                --getglobal('LFTGroupReady'):Hide()
                leaveQueue()
                return false
            end

            if someoneJoined then
                --todo - check someone's level if it comes from manual!
                -- limit dungeons and notify if new player cant join current dungeon
                --check if its from the queue or manual
                if LFT.findingMore and LFT.isLeader then

                    local newName = ''
                    local someoneJoinedManually = false
                    for i = 1, GetNumPartyMembers() do
                        local fromQueue = false
                        local name = UnitName('party' .. i)
                        lfdebug('checking ' .. name)
                        if name == LFT.group[LFT.LFMDungeonCode].tank or name == LFT.group[LFT.LFMDungeonCode].healer or
                                name == LFT.group[LFT.LFMDungeonCode].damage1 or name == LFT.group[LFT.LFMDungeonCode].damage2 or
                                name == LFT.group[LFT.LFMDungeonCode].damage3 then
                            fromQueue = true
                        end
                        if not fromQueue then newName = name someoneJoinedManually = true end
                    end
                    if someoneJoinedManually then --joined manually, dont know his role
                        lfdebug('player ' .. newName .. ' joined manually')
                        --needs role check check
                        leaveQueue()
                        findMore()
                    else --joined from the queue, we know his role, check if group is full
                        lfdebug('player ' .. newName .. ' joined from queue')
                        if LFT.checkLFMGroupReady(LFT.LFMDungeonCode) then
                            SendAddonMessage(LFT_ADDON_CHANNEL, "LFMPartyReady:" .. LFT.LFMDungeonCode, "PARTY")
                        else
                            SendAddonMessage(LFT_ADDON_CHANNEL, "weInQueue:" .. LFT.LFMDungeonCode, "PARTY")
                        end
                    end
                end
            end
            if someoneLeft then
                -- find who left and update virtual group
                if LFT.findingMore and LFT.isLeader then

                    --inc some getto code
                    --
                    local leftName = ''
                    local stillInParty = false
                    if LFT.group[LFT.LFMDungeonCode].tank ~= '' and LFT.group[LFT.LFMDungeonCode].tank ~= me then
                        leftName = LFT.group[LFT.LFMDungeonCode].tank
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFT.group[LFT.LFMDungeonCode].tank = ''
                            LFT.LFMGroup.tank = ''
                            lfprint(leftName .. ' (' .. COLOR_TANK .. 'Tank' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFT.group[LFT.LFMDungeonCode].healer ~= '' and LFT.group[LFT.LFMDungeonCode].healer ~= me then
                        leftName = LFT.group[LFT.LFMDungeonCode].healer
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFT.group[LFT.LFMDungeonCode].healer = ''
                            LFT.LFMGroup.healer = ''
                            lfprint(leftName .. ' (' .. COLOR_HEALER .. 'Healer' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFT.group[LFT.LFMDungeonCode].damage1 ~= '' and LFT.group[LFT.LFMDungeonCode].damage1 ~= me then
                        leftName = LFT.group[LFT.LFMDungeonCode].damage1
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFT.group[LFT.LFMDungeonCode].damage1 = ''
                            LFT.LFMGroup.damage1 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFT.group[LFT.LFMDungeonCode].damage2 ~= '' and LFT.group[LFT.LFMDungeonCode].damage2 ~= me then
                        leftName = LFT.group[LFT.LFMDungeonCode].damage2
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFT.group[LFT.LFMDungeonCode].damage2 = ''
                            LFT.LFMGroup.damage2 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFT.group[LFT.LFMDungeonCode].damage3 ~= '' and LFT.group[LFT.LFMDungeonCode].damage3 ~= me then
                        leftName = LFT.group[LFT.LFMDungeonCode].damage3
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFT.group[LFT.LFMDungeonCode].damage3 = ''
                            LFT.LFMGroup.damage3 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been remove from the queue group.')
                        end
                    end
                end
            end
            LFT.sendMinimapDataToParty(LFT.LFMDungeonCode)
            LFT.fillAvailableDungeons()
        end
        if event == 'PLAYER_LEVEL_UP' then
            LFT.level = arg1
            LFT.fillAvailableDungeons()
        end
    end
end)

function LFT.init()

    local _, uClass = UnitClass('player')
    LFT.class = string.lower(uClass)

    if not LFT_TYPE then
        LFT_TYPE = 1
    end
    UIDropDownMenu_SetText(LFT.types[LFT_TYPE], getglobal('LFTTypeSelect'));
    getglobal('LFTDungeonsText'):SetText(LFT.types[LFT_TYPE])
    if not LFT_ROLE then
        LFT_ROLE = LFT.GetPossibleRoles()
    else
        LFT.GetPossibleRoles()
        LFTsetRole(LFT_ROLE)
    end

    if not LFT_FORMED_GROUPS then
        LFT.resetFormedGroups()
    end

    LFT.channel = 'LFT'
    LFT.channelIndex = 0
    LFT.level = UnitLevel('player')
    LFT.findingGroup = false
    LFT.findingMore = false
    LFT:RegisterEvent("ADDON_LOADED")
    LFT.availableDungeons = {}
    LFT.group = {}
    LFT.oneGroupFull = false
    LFT.groupFullCode = ''
    LFT.acceptNextInvite = false
    LFT.minimapFrameIndex = 0
    LFT.currentGroupSize = GetNumPartyMembers() + 1

    LFT.isLeader = LFT.playerIsPartyLeader()
    LFT.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0
    LFT.fixMainButton()

    LFT.fillAvailableDungeons()

    LFTChannelJoinDelay:Show()

    lfprint(COLOR_HUNTER .. 'Looking For Turtles v' .. addonVer .. COLOR_WHITE .. ' - LFG Addon for Turtle WoW loaded.')
end

LFTQueue:SetScript("OnShow", function()
    this.startTime = GetTime()
    this.lastTime = {
        tank = 0,
        damage = 0,
        heal = 0,
        reset = 0,
        checkGroupFull = 0
    }
end)

LFTQueue:SetScript("OnHide", function()
    getglobal('LFT_MinimapEye'):SetTexture('Interface\\Addons\\LFT\\images\\eye\\battlenetworking0')
end)

LFTQueue:SetScript("OnUpdate", function()
    local plus = 0.15 --seconds
    local gt = GetTime() * 1000 --22.123 -> 22123
    local st = (this.startTime + plus) * 1000 -- (22.123 + 0.1) * 1000 =  22.223 * 1000 = 22223
    if gt >= st and LFT.findingGroup then
        this.startTime = GetTime()

        local cSecond = tonumber(date("%S", time()))

        getglobal('LFTTitleTime'):SetText(cSecond)
        getglobal('LFTGroupStatusTimeInQueue'):SetText('Time in Queue: ' .. SecondsToTime(time() - LFT.queueStartTime))

        if (cSecond == LFT.RESET_TIME or cSecond == LFT.RESET_TIME + LFT.TIME_MARGIN) and this.lastTime.reset ~= time() then
            if not LFT.inGroup then -- dont reset group if we're LFM
                LFT.resetGroup()
                this.lastTime.reset = time()
            end
        end

        if (cSecond == LFT.TANK_TIME or cSecond == LFT.TANK_TIME + LFT.TIME_MARGIN) and LFT_ROLE == 'tank' and this.lastTime.tank ~= time() then
            if not LFT.inGroup then -- only start forming group if im not already grouped
                for dungeon, data in next, LFT.dungeons do
                    if data.queued then
                        LFT.group[data.code].tank = me
                    end
                end
                --new: but do send lfg message if im a tank, to be picked up by LFM party leader
                LFT.sendLFMessage()
                this.lastTime.tank = time()
            end
        end

        if (cSecond == LFT.HEALER_TIME + LFT.myRandomTime or cSecond == LFT.HEALER_TIME + LFT.TIME_MARGIN + LFT.myRandomTime) and LFT_ROLE == 'healer' and this.lastTime.heal ~= time() then
            if not LFT.inGroup then -- dont spam lfm if im already in a group, because leader will pick up new players
                LFT.sendLFMessage()
                this.lastTime.heal = time()
            end
        end

        if (cSecond == LFT.DAMAGE_TIME + LFT.myRandomTime or cSecond == LFT.DAMAGE_TIME + LFT.TIME_MARGIN + LFT.myRandomTime) and LFT_ROLE == 'damage' and this.lastTime.damage ~= time() then
            if not LFT.inGroup then -- dont spam lfm if im already in a group, because leader will pick up new players
                LFT.sendLFMessage()
                this.lastTime.damage = time()
            end
        end

        if (cSecond == LFT.FULLCHECK_TIME or cSecond == LFT.FULLCHECK_TIME + LFT.TIME_MARGIN) and LFT_ROLE == 'tank' and this.lastTime.checkGroupFull ~= time() then
            if not LFT.inGroup then
                lfdebug('==== check group full --')
                local groupFull, code, healer, damage1, damage2, damage3 = LFT.checkGroupFull()

                if groupFull then
                    LFT.groupFullCode = code

                    SendChatMessage("[LFT]:" .. code .. ":party:ready:" .. healer .. ":" .. damage1 .. ":" .. damage2 .. ":" .. damage3,
                        "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))

                    SendChatMessage("[LFT]:lft_group_formed:" .. code, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))

                    --untick everything
                    for dungeon, data in next, LFT.dungeons do
                        if getglobal("Dungeon_" .. data.code) then
                            getglobal("Dungeon_" .. data.code):SetChecked(false)
                        end
                        LFT.dungeons[dungeon].queued = false
                    end

                    LFT.findingGroup = false
                    LFT.findingMore = false

                    local background = ''
                    local dungeonName = 'unknown'
                    for d, data in next, LFT.dungeons do
                        if data.code == code then
                            background = data.background
                            dungeonName = d
                        end
                    end
                    getglobal('LFTGroupReadyBackground'):SetTexture('Interface\\addons\\LFT\\images\\background\\ui-lfg-background-' .. background)
                    getglobal('LFTGroupReadyRole'):SetTexture('Interface\\addons\\LFT\\images\\' .. LFT_ROLE .. '2')
                    getglobal('LFTGroupReadyMyRole'):SetText(LFT.ucFirst(LFT_ROLE))
                    getglobal('LFTGroupReadyDungeonName'):SetText(dungeonName)
                    getglobal('LFTGroupReady'):Show()
                    getglobal('LFTRoleCheck'):Hide()

                    PlaySound("ReadyCheck")
                    LFTQueue:Hide()
                    getglobal('LFT_MinimapEye'):SetTexture('Interface\\Addons\\LFT\\images\\eye\\battlenetworking0')

                    LFT.fixMainButton()
                    getglobal('LFTMain'):Hide()
                    LFTInvite:Show()
                end
            end

            this.lastTime.checkGroupFull = time()
        end

        getglobal('LFT_MinimapEye'):SetTexture('Interface\\Addons\\LFT\\images\\eye\\battlenetworking' .. LFT.minimapFrameIndex)

        if LFT.minimapFrameIndex < 28 then
            LFT.minimapFrameIndex = LFT.minimapFrameIndex + 1
        else
            LFT.minimapFrameIndex = 0
        end
    end
end)

function LFT.checkLFTChannel()
    lfdebug('checl LFT channel')
    local lastVal = 0
    local chanList = { GetChannelList() }

    for index, value in next, chanList do
        if value == LFT.channel then
            LFT.channelIndex = lastVal
            break
        end
        lastVal = value
    end

    if LFT.channelIndex == 0 then
        JoinChannelByName(LFT.channel)
    end
end

function LFT.GetPossibleRoles()

    local tankCheck = getglobal('RoleTank')
    local healerCheck = getglobal('RoleHealer')
    local damageCheck = getglobal('RoleDamage')

    --ready check window
    local readyCheckTank = getglobal('roleCheckTank')
    local readyCheckHealer = getglobal('roleCheckHealer')
    local readyCheckDamage = getglobal('roleCheckDamage')

    tankCheck:Disable()
    tankCheck:SetChecked(false)
    healerCheck:Disable()
    healerCheck:SetChecked(false)
    damageCheck:Disable()
    damageCheck:SetChecked(false)

    readyCheckTank:Disable()
    readyCheckTank:SetChecked(false)
    readyCheckHealer:Disable()
    readyCheckHealer:SetChecked(false)
    readyCheckDamage:Disable()
    readyCheckDamage:SetChecked(false)

    if LFT.class == 'warrior' then
        readyCheckTank:Enable();
        tankCheck:Enable();

        readyCheckTank:SetChecked(true)
        tankCheck:SetChecked(true)

        readyCheckDamage:Enable()
        damageCheck:Enable()

        readyCheckDamage:SetChecked(false)
        damageCheck:SetChecked(false)
        return 'tank'
    end
    if LFT.class == 'paladin' or LFT.class == 'druid' or LFT.class == 'shaman' then
        readyCheckTank:Enable();
        tankCheck:Enable();
        readyCheckTank:SetChecked(false)
        tankCheck:SetChecked(false)

        readyCheckHealer:Enable()
        healerCheck:Enable()
        readyCheckHealer:SetChecked(true)
        healerCheck:SetChecked(true)

        readyCheckDamage:Enable()
        damageCheck:Enable()
        readyCheckDamage:SetChecked(false)
        damageCheck:SetChecked(false)
        return 'healer'
    end
    if LFT.class == 'priest' then
        readyCheckHealer:Enable()
        healerCheck:Enable()
        readyCheckHealer:SetChecked(true)
        healerCheck:SetChecked(true)

        readyCheckDamage:Enable()
        damageCheck:Enable()
        readyCheckDamage:SetChecked(false)
        damageCheck:SetChecked(false)
        return 'healer'
    end
    if LFT.class == 'warlock' or LFT.class == 'hunter' or LFT.class == 'mage' or LFT.class == 'rogue' then
        readyCheckDamage:Enable()
        damageCheck:Enable()
        readyCheckDamage:SetChecked(true)
        damageCheck:SetChecked(true)
        return 'damage'
    end
    return 'damage'
end

function LFT.getAvailableDungeons(level, type, mine)
    if level == 0 then return {} end
    local dungeons = {}
    for dungeon, data in next, LFT.dungeons do
        if level >= data.minLevel and (level <= data.maxLevel or (not mine)) and type ~= 3 then
            dungeons[data.code] = true
        end
        if level >= data.minLevel and type == 3 then --all available
            dungeons[data.code] = true
        end
    end
    return dungeons
end

function LFT.fillAvailableDungeons(offset)
    if not offset then offset = 0 end

    --unqueue queued
    for dungeon, data in next, LFT.dungeons do
        LFT.dungeons[dungeon].canQueue = true
        if data.queued and (LFT.level < data.minLevel or LFT.level > data.maxLevel) then
            LFT.dungeons[dungeon].queued = false
        end
    end

    --hide all
    for i, frame in next, LFT.availableDungeons do
        getglobal("Dungeon_" .. frame.code):Hide()
    end

    -- if grouped fill only dungeons that can be joined by EVERYONE
    if LFT.inGroup then
        --        lfdebug('in group')
        local groupAvailableDungeons = {}
        local party = {
            [0] = {
                level = LFT.level,
                dungeons = LFT.getAvailableDungeons(LFT.level, LFT_TYPE, true)
            }
        }
        for i = 1, 4 do
            party[i] = {
                level = UnitLevel('party' .. i),
                dungeons = LFT.getAvailableDungeons(UnitLevel('party' .. i), LFT_TYPE, false)
            }
        end

        for dungeonCode in next, LFT.getAvailableDungeons(LFT.level, LFT_TYPE, true) do
            local canAdd = false
            for i = 1, 4 do
                for code in next, party[i].dungeons do
                    if dungeonCode == code then
                        canAdd = true
                    end
                end
            end
            if canAdd then
            else
                LFT.dungeons[LFT.dungeonNameFromCode(dungeonCode)].canQueue = canAdd
                --                lfdebug('d ' .. dungeonCode .. ' disabled')
            end
        end
    end

    local dungeonIndex = 0

    for dungeon, data in LFT.fuckingSortAlready(LFT.dungeons) do
        if LFT.level >= data.minLevel and LFT.level <= data.maxLevel and LFT_TYPE ~= 3 then

            dungeonIndex = dungeonIndex + 1
            if dungeonIndex > offset and dungeonIndex <= offset + LFT.maxDungeonsList then
                if not LFT.availableDungeons[data.code] then
                    LFT.availableDungeons[data.code] = CreateFrame("CheckButton", "Dungeon_" .. data.code, getglobal("LFTMain"), "LFT_DungeonCheck")
                end

                LFT.availableDungeons[data.code]:Show()

                local color = COLOR_GREEN
                if LFT.level == data.minLevel or LFT.level == data.minLevel + 1 then color = COLOR_RED end
                if LFT.level == data.minLevel + 2 or LFT.level == data.minLevel + 3 then color = COLOR_ORANGE end
                if LFT.level == data.minLevel + 4 or LFT.level == data.maxLevel + 5 then color = COLOR_GREEN end

                if LFT.level > data.maxLevel then color = COLOR_GREEN end

                getglobal('Dungeon_' .. data.code):Enable()

                if not data.canQueue then
                    color = COLOR_DISABLED
                    data.queued = false
                    LFT.addOnEnterTooltip(getglobal('Dungeon_' .. data.code .. '_Button'), dungeon .. ' is unavailable',
                        'Members in your party do not meet ', 'minimum level requirement (' .. data.minLevel .. ').')
                    getglobal('Dungeon_' .. data.code):Disable()
                end

                getglobal('Dungeon_' .. data.code .. 'Text'):SetText(color .. dungeon)
                getglobal('Dungeon_' .. data.code .. 'Levels'):SetText(color .. '(' .. data.minLevel .. ' - ' .. data.maxLevel .. ')')
                getglobal('Dungeon_' .. data.code .. '_Button'):SetID(dungeonIndex)

                LFT.availableDungeons[data.code]:SetPoint("TOP", getglobal("LFTMain"), "TOP", -145, -165 - 20 * (dungeonIndex - offset))
                LFT.availableDungeons[data.code].code = data.code

                LFT.dungeons[dungeon].queued = data.queued
                getglobal('Dungeon_' .. data.code):SetChecked(data.queued)


                if LFT_TYPE == 2 and not LFT.inGroup then
                    LFT.dungeons[dungeon].queued = true
                    getglobal('Dungeon_' .. data.code):SetChecked(true)
                end
            end
        end

        if LFT.level >= data.minLevel and LFT_TYPE == 3 then --all available
            dungeonIndex = dungeonIndex + 1
            if dungeonIndex > offset and dungeonIndex <= offset + LFT.maxDungeonsList then
                if not LFT.availableDungeons[data.code] then
                    LFT.availableDungeons[data.code] = CreateFrame("CheckButton", "Dungeon_" .. data.code, getglobal("LFTMain"), "LFT_DungeonCheck")
                end

                LFT.availableDungeons[data.code]:Show()

                local color = COLOR_GREEN
                if LFT.level == data.minLevel or LFT.level == data.minLevel + 1 then color = COLOR_RED end
                if LFT.level == data.minLevel + 2 or LFT.level == data.minLevel + 3 then color = COLOR_ORANGE end
                if LFT.level == data.minLevel + 4 or LFT.level == data.maxLevel + 5 then color = COLOR_GREEN end

                if LFT.level > data.maxLevel then color = COLOR_GREEN end

                getglobal('Dungeon_' .. data.code .. 'Text'):SetText(color .. dungeon)
                getglobal('Dungeon_' .. data.code .. 'Levels'):SetText(color .. '(' .. data.minLevel .. ' - ' .. data.maxLevel .. ')')
                getglobal('Dungeon_' .. data.code .. '_Button'):SetID(dungeonIndex)

                LFT.availableDungeons[data.code]:SetPoint("TOP", getglobal("LFTMain"), "TOP", -145, -165 - 20 * (dungeonIndex - offset))
                LFT.availableDungeons[data.code].code = data.code

                --                LFT.dungeons[dungeon].queued = data.queued
                --                getglobal('Dungeon_' .. data.code):SetChecked(data.queued)
            end
        end
    end

    LFT.fixMainButton()

    FauxScrollFrame_Update(getglobal('DungeonListScrollFrame'), dungeonIndex, LFT.maxDungeonsList, 20)
end

function LFT.enableDungeonCheckbuttons()
    for i, frame in next, LFT.availableDungeons do
        getglobal("Dungeon_" .. frame.code):Enable()
    end
end

function LFT.disableDungeonCheckbuttons(except)
    for i, frame in next, LFT.availableDungeons do
        if except and except == frame.code then
            --dont disable
        else
            getglobal("Dungeon_" .. frame.code):Disable()
        end
    end
end

function LFT.resetGroup()
    --    lfdebug('resetGroup()')
    LFT.group = {};
    if not LFT.oneGroupFull then
        LFT.groupFullCode = ''
        LFT.oneGroupFull = false
    end
    LFT.acceptNextInvite = false
    LFT.onlyAcceptFrom = ''
    LFT.foundGroup = false

    LFT.isLeader = LFT.playerIsPartyLeader()

    LFT.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0


    for dungeon, data in next, LFT.dungeons do
        if data.queued then
            local tank = ''
            if LFT_ROLE == 'tank' then tank = me end
            LFT.group[data.code] = {
                tank = tank,
                healer = '',
                damage1 = '',
                damage2 = '',
                damage3 = '',
            }
        end
    end
    LFT.myRandomTime = math.random(LFT.random_min, LFT.random_max)
    LFT.LFMGroup = {
        tank = '',
        healer = '',
        damage1 = '',
        damage2 = '',
        damage3 = '',
    }
end

function LFT.addTank(dungeon, name)
    if LFT.group[dungeon].tank == '' then
        LFT.group[dungeon].tank = name
        --SendChatMessage('found:tank:' .. dungeon, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        --no send message needed cause the tank gets insta invited in a lfm group and tank invites in a lfg group
        return true
    end
    return false
end

function LFT.addHealer(dungeon, name, faux)
    if LFT.group[dungeon].healer == '' then
        LFT.group[dungeon].healer = name
        if not faux then
            SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
        return true
    end
    return false
end

function LFT.remHealerOrDamage(dungeon, name)
    --    lfdebug('rem healer or damage, name : ' .. name)
    --    lfdebug('dungeon : ' .. dungeon)
    if LFT.group[dungeon].healer == name then
        LFT.group[dungeon].healer = ''
    end
    if LFT.group[dungeon].damage1 == name then
        LFT.group[dungeon].damage1 = ''
    end
    if LFT.group[dungeon].damage2 == name then
        LFT.group[dungeon].damage2 = ''
    end
    if LFT.group[dungeon].damage3 == name then
        LFT.group[dungeon].damage3 = ''
    end
end

function LFT.addDamage(dungeon, name, faux)

    if LFT.group[dungeon].damage1 == '' then
        LFT.group[dungeon].damage1 = name
        if not faux then
            SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
        return true
    elseif LFT.group[dungeon].damage2 == '' then
        LFT.group[dungeon].damage2 = name
        if not faux then
            SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
        return true
    elseif LFT.group[dungeon].damage3 == '' then
        LFT.group[dungeon].damage3 = name
        if not faux then
            SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
        return true
    end
    return false --group full on damage
end

function LFT.checkGroupFull()

    for dungeon, data in next, LFT.dungeons do
        if data.queued then
            local members = 0
            if LFT.group[data.code].tank ~= '' then members = members + 1 end
            if LFT.group[data.code].healer ~= '' then members = members + 1 end
            if LFT.group[data.code].damage1 ~= '' then members = members + 1 end
            if LFT.group[data.code].damage2 ~= '' then members = members + 1 end
            if LFT.group[data.code].damage3 ~= '' then members = members + 1 end

            if members == DEV_GROUP_SIZE then
                LFT.oneGroupFull = true
                LFT.group[data.code].full = true

                return true, data.code, LFT.group[data.code].healer, LFT.group[data.code].damage1, LFT.group[data.code].damage2, LFT.group[data.code].damage3
            else
                LFT.group[data.code].full = false
                LFT.oneGroupFull = false
            end
        end
    end

    return false, false, nil, nil, nil, nil
end

function LFT.dungeonNameFromCode(code)
    for name, data in next, LFT.dungeons do
        if data.code == code then return name end
    end
    return 'Unknown'
end

function LFT.dungeonFromCode(code)
    for name, data in next, LFT.dungeons do
        if data.code == code then return data end
    end
    return false
end

function LFT.AcceptGroupInvite()
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
    PlaySoundFile("Sound\\Doodad\\BellTollNightElf.wav")
    UIErrorsFrame:AddMessage("[LFT] Group Auto Accept")
end

function LFT.DeclineGroupInvite()
    DeclineGroup()
    StaticPopup_Hide("PARTY_INVITE")
end

function LFT.fuckingSortAlready(t, f)
    local a = {}
    for n, l in pairs(t) do table.insert(a, { ['code'] = l.code, ['minLevel'] = l.minLevel, ['name'] = n })
    end
    table.sort(a, function(a, b) return a['minLevel'] < b['minLevel']
    end)
    local i = 0 -- iterator variable
    local iter = function() -- iterator function
        i = i + 1
        if a[i] == nil then return nil
            --        else return a[i]['code'], t[a[i]['name']]
        else return a[i]['name'], t[a[i]['name']]
        end
    end
    return iter
end

function LFT.tableSize(t)
    local size = 0
    for _, _ in next, t do size = size + 1 end return size
end

function LFT.checkLFMgroup(someoneDeclined)
    if someoneDeclined then
        if someoneDeclined ~= me then
            lfprint(someoneDeclined .. ' declined role check.')
        end
        return false
    end

    if not LFT.isLeader then return end

    local currentGroupSize = GetNumPartyMembers() + 1
    local readyNumber = 0
    if LFT.LFMGroup.tank ~= '' then readyNumber = readyNumber + 1 end
    if LFT.LFMGroup.healer ~= '' then readyNumber = readyNumber + 1 end
    if LFT.LFMGroup.damage1 ~= '' then readyNumber = readyNumber + 1 end
    if LFT.LFMGroup.damage2 ~= '' then readyNumber = readyNumber + 1 end
    if LFT.LFMGroup.damage3 ~= '' then readyNumber = readyNumber + 1 end

    if currentGroupSize == readyNumber then
        --everyone is ready / confirmed roles
        LFT.group[LFT.LFMDungeonCode] = {
            tank = LFT.LFMGroup.tank,
            healer = LFT.LFMGroup.healer,
            damage1 = LFT.LFMGroup.damage1,
            damage2 = LFT.LFMGroup.damage2,
            damage3 = LFT.LFMGroup.damage3,
        }
        SendAddonMessage(LFT_ADDON_CHANNEL, "weInQueue:" .. LFT.LFMDungeonCode, "PARTY")
    end
end

function LFT.weInQueue(code)
    --lfdebug('exec we in queue ' .. code)
    local dungeonName = LFT.dungeonNameFromCode(code)
    LFT.dungeons[dungeonName].queued = true

    lfprint('Your group is in the queue for |cff69ccf0' .. dungeonName)

    LFT.findingGroup = true
    LFT.findingMore = true
    LFT.disableDungeonCheckbuttons()

    getglobal('RoleTank'):Disable()
    getglobal('RoleHealer'):Disable()
    getglobal('RoleDamage'):Disable()

    PlaySound('PvpEnterQueue')

    if LFT.isLeader then
        LFT.sendMinimapDataToParty(code)
    else
        LFT.group[code] = {
            tank = '',
            healer = '',
            damage1 = '',
            damage2 = '',
            damage3 = ''
        }
    end

    LFT.oneGroupFull = false
    LFT.queueStartTime = time()
    LFTQueue:Show()
    getglobal('LFTMain'):Hide()
end

function LFT.fixMainButton()

    local lfgButton = getglobal('findGroupButton')
    local lfmButton = getglobal('findMoreButton')
    local leaveQueueButton = getglobal('leaveQueueButton')

    lfgButton:Hide()
    lfmButton:Hide()
    leaveQueueButton:Hide()

    lfgButton:Disable()
    lfmButton:Disable()
    leaveQueueButton:Disable()

    LFT.isLeader = LFT.playerIsPartyLeader()
    LFT.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

    local queues = 0
    for dungeon, data in next, LFT.dungeons do
        if data.queued then queues = queues + 1 end
    end

    if queues > 0 then
        lfgButton:Enable()
    end

    if LFT.inGroup then
        lfmButton:Show()
        --GetNumPartyMembers() returns party size-1, doesnt count myself
        if GetNumPartyMembers() < (DEV_GROUP_SIZE - 1) and LFT.isLeader and queues > 0 then
            lfmButton:Enable()
        end
        if GetNumPartyMembers() == (DEV_GROUP_SIZE - 1) and LFT.isLeader then --group full
            lfmButton:Disable()
            lfdebug('aici')
            LFT.disableDungeonCheckbuttons()
        end
        if not LFT.isLeader then
            lfmButton:Disable()
            LFT.disableDungeonCheckbuttons()
        end
    else
        lfgButton:Show()
    end

    if LFT.findingGroup then
        leaveQueueButton:Show()
        leaveQueueButton:Enable()
        if LFT.inGroup then
            if not LFT.isLeader then leaveQueueButton:Disable() end
        end
        lfgButton:Hide()
        lfmButton:Hide()
    end
end

function LFT.sendCancelMeMessage()
    SendChatMessage('leftQueue:' .. LFT_ROLE, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
end

function LFT.sendLFMessage()

    local keyset = {}
    for k in pairs(LFT.group) do
        table.insert(keyset, k)
    end

    local added = {}

    for _, _ in next, LFT.group do
        local newD = keyset[math.random(LFT.tableSize(keyset))]
        if not added[newD] then
            added[newD] = true
            SendChatMessage('LFG:' .. newD .. ':' .. LFT_ROLE, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        else
            --            lfdebug('skipping ' .. newD .. ' already sent')
        end
    end
end

function LFT.isNeededInLFMGroup(role, name, code)
    --lfdebug('need in lfm ' .. code .. ' ' .. role .. ' ' .. name)
    if role == 'tank' and LFT.group[code].tank == '' then
        LFT.group[code].tank = name
        return true
    end
    if role == 'healer' and LFT.group[code].healer == '' then
        LFT.group[code].healer = name
        return true
    end
    if role == 'damage' then
        if LFT.group[code].damage1 == '' then
            LFT.group[code].damage1 = name
            return true
        end
        if LFT.group[code].damage2 == '' then
            LFT.group[code].damage2 = name
            return true
        end
        if LFT.group[code].damage3 == '' then
            LFT.group[code].damage3 = name
            return true
        end
    end
    return false
end

function LFT.inviteInLFMGroup(name)
    SendChatMessage("[LFT]:" .. LFT.LFMDungeonCode .. ":(LFM):" .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
    InviteByName(name)
end

function LFT.checkLFMGroupReady(code)
    if not LFT.isLeader then return end

    local members = 0

    if LFT.group[code].tank ~= '' then members = members + 1 end
    if LFT.group[code].healer ~= '' then members = members + 1 end
    if LFT.group[code].damage1 ~= '' then members = members + 1 end
    if LFT.group[code].damage2 ~= '' then members = members + 1 end
    if LFT.group[code].damage3 ~= '' then members = members + 1 end

    return members == DEV_GROUP_SIZE
end

function LFT.sendMinimapDataToParty(code)
    if code == '' then return false end
    local tank, healer, damage = 0, 0, 0
    if LFT.group[code].tank ~= '' then tank = tank + 1 end
    if LFT.group[code].healer ~= '' then healer = healer + 1 end
    if LFT.group[code].damage1 ~= '' then damage = damage + 1 end
    if LFT.group[code].damage2 ~= '' then damage = damage + 1 end
    if LFT.group[code].damage3 ~= '' then damage = damage + 1 end
    SendAddonMessage(LFT_ADDON_CHANNEL, "minimap:" .. code .. ":" .. tank .. ":" .. healer .. ":" .. damage, "PARTY")
end

function LFT.addOnEnterTooltip(frame, title, text1, text2)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT", -200, -5)
        GameTooltip:AddLine(title)
        if text1 then GameTooltip:AddLine(text1, 1, 1, 1) end
        if text2 then GameTooltip:AddLine(text2, 1, 1, 1) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function LFT.sendMyVersion()
    SendAddonMessage(LFT_ADDON_CHANNEL, "LFTVersion:" .. addonVer, "PARTY")
    SendAddonMessage(LFT_ADDON_CHANNEL, "LFTVersion:" .. addonVer, "GUILD")
    SendAddonMessage(LFT_ADDON_CHANNEL, "LFTVersion:" .. addonVer, "RAID")
    SendAddonMessage(LFT_ADDON_CHANNEL, "LFTVersion:" .. addonVer, "BATTLEGROUND")
end

function LFT.removePlayerFromVirtualParty(name, mRole)
    if not mRole then mRole = 'unknown' end
    for dungeonCode, data in next, LFT.group do
        if data.tank == name and (mRole == 'tank' or mRole == 'unknown') then LFT.group[dungeonCode].tank = '' end
        if data.healer == name and (mRole == 'healer' or mRole == 'unknown') then LFT.group[dungeonCode].healer = '' end
        if data.damage1 == name and (mRole == 'damage' or mRole == 'unknown') then LFT.group[dungeonCode].damage1 = '' end
        if data.damage2 == name and (mRole == 'damage' or mRole == 'unknown') then LFT.group[dungeonCode].damage2 = '' end
        if data.damage3 == name and (mRole == 'damage' or mRole == 'unknown') then LFT.group[dungeonCode].damage3 = '' end
    end
end

function LFT.deQueueAll()
    for dungeon, data in next, LFT.dungeons do
        if data.queued then
            LFT.dungeons[data.code].queued = false
        end
    end
end

function LFT.resetFormedGroups()
    LFT_FORMED_GROUPS = {}
    for dungeon, data in next, LFT.dungeons do
        LFT_FORMED_GROUPS[data.code] = 0
    end
end

-- XML called methods

function lft_replace(s, c, cc)
    return (string.gsub(s, c, cc))
end

function acceptRole()
    SendAddonMessage(LFT_ADDON_CHANNEL, "acceptRole:" .. LFT_ROLE, "PARTY")
    getglobal('LFTRoleCheck'):Hide()
    LFTRoleCheck:Hide()
end

function declineRole()
    SendAddonMessage(LFT_ADDON_CHANNEL, "declineRole:", "PARTY")
    getglobal('LFTRoleCheck'):Hide()
    LFTRoleCheck:Hide()
end

function LFT_Toggle()
    if LFT.level == 0 then
        LFT.level = UnitLevel('player')
    end
    if getglobal('LFTMain'):IsVisible() then
        getglobal('LFTMain'):Hide()
    else
        LFT.checkLFTChannel()
        if not LFT.findingGroup then
            LFT.fillAvailableDungeons()
        end

        getglobal('LFTMain'):Show()
        DungeonListFrame_Update()
    end
end

function sayReady()
    if LFT.inGroup then
        getglobal('LFTGroupReady'):Hide()
        SendChatMessage('Ready as ' .. LFT_ROLE, "PARTY");
        getglobal('LFT_MinimapEye'):SetTexture('Interface\\Addons\\LFT\\images\\eye\\battlenetworking0')
    end
end

function LFTsetRole(role, status, readyCheck)
    local tankCheck = getglobal('RoleTank')
    local healerCheck = getglobal('RoleHealer')
    local damageCheck = getglobal('RoleDamage')

    --ready check window
    local readyCheckTank = getglobal('roleCheckTank')
    local readyCheckHealer = getglobal('roleCheckHealer')
    local readyCheckDamage = getglobal('roleCheckDamage')

    if role == 'tank' then
        readyCheckHealer:SetChecked(false)
        healerCheck:SetChecked(false)

        readyCheckDamage:SetChecked(false)
        damageCheck:SetChecked(false)
        if not status and not readyCheck then tankCheck:SetChecked(true) end
    end
    if role == 'healer' then
        readyCheckTank:SetChecked(false)
        tankCheck:SetChecked(false)

        readyCheckDamage:SetChecked(false)
        damageCheck:SetChecked(false)
        if not status and not readyCheck then healerCheck:SetChecked(true) end
    end
    if role == 'damage' then
        readyCheckTank:SetChecked(false)
        tankCheck:SetChecked(false)

        readyCheckHealer:SetChecked(false)
        healerCheck:SetChecked(false)
        if not status and not readyCheck then damageCheck:SetChecked(true) end
    end

    if readyCheck then
        tankCheck:SetChecked(readyCheckTank:GetChecked())
        healerCheck:SetChecked(readyCheckHealer:GetChecked())
        damageCheck:SetChecked(readyCheckDamage:GetChecked())
    else
        readyCheckTank:SetChecked(tankCheck:GetChecked())
        readyCheckHealer:SetChecked(healerCheck:GetChecked())
        readyCheckDamage:SetChecked(damageCheck:GetChecked())
    end
    LFT_ROLE = role
end

function DungeonListFrame_Update()
    local offset = FauxScrollFrame_GetOffset(getglobal('DungeonListScrollFrame'));
    LFT.fillAvailableDungeons(offset)
end

function DungeonType_OnLoad()
    UIDropDownMenu_Initialize(this, DungeonType_Initialize);
    UIDropDownMenu_SetWidth(160, LFTTypeSelect);
end

function DungeonType_OnClick(a)
    LFT_TYPE = a
    UIDropDownMenu_SetText(LFT.types[LFT_TYPE], getglobal('LFTTypeSelect'))
    getglobal('LFTDungeonsText'):SetText(LFT.types[LFT_TYPE])
    LFT.fillAvailableDungeons()
end

function DungeonType_Initialize()
    for id, type in pairs(LFT.types) do
        local info = {}
        info.text = type
        info.value = id
        info.arg1 = id
        info.checked = LFT_TYPE == id
        info.func = DungeonType_OnClick
        if not LFT.findingGroup then
            UIDropDownMenu_AddButton(info)
        end
    end
end

function LFT_HideMinimap()
    for i, f in LFT.minimapFrames do
        LFT.minimapFrames[i]:Hide()
    end
    getglobal('LFTGroupStatus'):Hide()
end

function LFT_ShowMinimap()

    if LFT.findingGroup or LFT.findingMore then
        local dungeonIndex = 0
        for dungeonCode, data in next, LFT.group do
            local tank = 0
            local healer = 0
            local damage = 0

            if LFT.group[dungeonCode].tank ~= '' then tank = tank + 1 end
            if LFT.group[dungeonCode].healer ~= '' then healer = healer + 1 end
            if LFT.group[dungeonCode].damage1 ~= '' then damage = damage + 1 end
            if LFT.group[dungeonCode].damage2 ~= '' then damage = damage + 1 end
            if LFT.group[dungeonCode].damage3 ~= '' then damage = damage + 1 end

            if not LFT.minimapFrames[dungeonCode] then
                LFT.minimapFrames[dungeonCode] = CreateFrame('Frame', "LFTMinimap_" .. dungeonCode, UIParent, "LFTMinimapDungeonTemplate")
            end

            local background = ''
            local dungeonName = 'unknown'
            for d, data2 in next, LFT.dungeons do
                if data2.code == dungeonCode then
                    background = data2.background
                    dungeonName = d
                end
            end

            LFT.minimapFrames[dungeonCode]:Show()
            LFT.minimapFrames[dungeonCode]:SetPoint("TOP", getglobal("LFTGroupStatus"), "TOP", 0, -25 - 46 * (dungeonIndex))
            getglobal('LFTMinimap_' .. dungeonCode .. 'Background'):SetTexture('Interface\\addons\\LFT\\images\\background\\ui-lfg-background-' .. background)
            getglobal('LFTMinimap_' .. dungeonCode .. 'DungeonName'):SetText(dungeonName)

            getglobal('LFTMinimap_' .. dungeonCode .. 'NrTank'):SetText(tank .. '/1')
            getglobal('LFTMinimap_' .. dungeonCode .. 'NrHealer'):SetText(healer .. '/1')
            getglobal('LFTMinimap_' .. dungeonCode .. 'NrDamage'):SetText(damage .. '/3')

            dungeonIndex = dungeonIndex + 1
        end

        getglobal('LFTGroupStatus'):SetPoint("TOPRIGHT", getglobal("LFT_Minimap"), "BOTTOMLEFT", 8, 8)
        getglobal('LFTGroupStatus'):SetHeight(dungeonIndex * 46 + 80)
        getglobal('LFTGroupStatusTimeInQueue'):SetText('Time in Queue: ' .. SecondsToTime(time() - LFT.queueStartTime))
        getglobal('LFTGroupStatus'):Show()
    else

        GameTooltip:SetOwner(this, "ANCHOR_LEFT", 0, -90)
        GameTooltip:AddLine('Looking For Turtles - LFT', 1, 1, 1)
        GameTooltip:AddLine('Left-click to toggle frame')
        GameTooltip:AddLine('Not queued for any dungeons.')
        GameTooltip:Show()
    end
end

function queueForFromButton(Bcode)

    if true then return false end --dev, disabled for now

    local codeEx = string.split(Bcode, '_')
    local Qcode = codeEx[2]
    for code, data in next, LFT.availableDungeons do
        if code == Qcode and not LFT.findingGroup then
            getglobal('Dungeon_' .. data.code):SetChecked(not getglobal('Dungeon_' .. data.code):GetChecked())
            queueFor(Bcode, getglobal('Dungeon_' .. data.code):GetChecked())
        end
    end
end

function queueFor(name, status)
    local dugeonCode = ''
    for dungeon, data in next, LFT.dungeons do
        local dung = string.split(name, '_')
        dugeonCode = dung[2]
        if dugeonCode == data.code then
            if status then
                LFT.dungeons[dungeon].queued = true
            else
                LFT.dungeons[dungeon].queued = false
            end
        end
    end

    local queues = 0
    for dungeon, data in next, LFT.dungeons do
        if data.queued then queues = queues + 1 end
    end

    if queues == 1 and LFT.inGroup then
        LFT.disableDungeonCheckbuttons(dugeonCode)
    else
        LFT.enableDungeonCheckbuttons()
    end

    LFT.fixMainButton()
end

function findMore()

    -- find queueing dungeon
    local qDungeon = ''
    for i, frame in next, LFT.availableDungeons do
        if getglobal("Dungeon_" .. frame.code):GetChecked() then
            qDungeon = frame.code
        end
    end

    LFT.LFMDungeonCode = qDungeon
    LFT.findingMore = true
    SendAddonMessage(LFT_ADDON_CHANNEL, "roleCheck:" .. qDungeon, "PARTY")

    LFT.fixMainButton()
end

function findGroup()

    LFT.resetGroup()
    LFT.findingGroup = true
    LFTQueue:Show()

    LFT.disableDungeonCheckbuttons()

    getglobal('RoleTank'):Disable()
    getglobal('RoleHealer'):Disable()
    getglobal('RoleDamage'):Disable()

    PlaySound('PvpEnterQueue')

    local dungeonsText = ''

    local roleColor = ''
    if LFT_ROLE == 'tank' then roleColor = COLOR_TANK end
    if LFT_ROLE == 'healer' then roleColor = COLOR_HEALER end
    if LFT_ROLE == 'damage' then roleColor = COLOR_DAMAGE end

    for dungeon, data in next, LFT.dungeons do
        if data.queued then
            dungeonsText = dungeonsText .. dungeon .. ', '
            SendChatMessage('LFG:' .. data.code .. ':' .. LFT_ROLE, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
    end
    dungeonsText = string.sub(dungeonsText, 1, string.len(dungeonsText) - 2)
    lfprint('You are in the queue for |cff69ccf0' .. dungeonsText ..
            COLOR_WHITE .. ' as: ' .. roleColor .. LFT.ucFirst(LFT_ROLE))

    LFT.oneGroupFull = false
    LFT.queueStartTime = time()

    LFT.fixMainButton()
end

function leaveQueue()

    LFTQueue:Hide()

    local dungeonsText = ''

    for dungeon, data in next, LFT.dungeons do
        if data.queued then
            if LFT_TYPE == 2 then --random dungeon, dont uncheck if it comes here from the button
                getglobal("Dungeon_" .. data.code):SetChecked(false)
                LFT.dungeons[dungeon].queued = false
            end
            if LFT.inGroup then
                LFT.enableDungeonCheckbuttons()
                LFT.disableDungeonCheckbuttons(data.code)

                if LFT.findingGroup or LFT.findingMore then
                    dungeonsText = dungeonsText .. dungeon .. ', '
                end
            else
                if LFT.findingGroup or LFT.findingMore then
                    dungeonsText = dungeonsText .. dungeon .. ', '
                end
            end
        end
    end

    dungeonsText = string.sub(dungeonsText, 1, string.len(dungeonsText) - 2)
    if LFT.findingGroup or LFT.findingMore then
        if LFT.inGroup then
            lfprint('Your group has left the queue for |cff69ccf0' .. dungeonsText .. COLOR_WHITE .. '.')
        else
            lfprint('You have left the queue for |cff69ccf0' .. dungeonsText .. COLOR_WHITE .. '.')
        end
    end

    if not LFT.inGroup then
        LFT.enableDungeonCheckbuttons()
    end

    LFT.GetPossibleRoles()
    LFTsetRole(LFT_ROLE)

    LFT.findingGroup = false
    LFT.findingMore = false

    LFT.LFMDungeonCode = ''

    --    LFT.deQueueAll()

    if LFT.isLeader then
        SendAddonMessage(LFT_ADDON_CHANNEL, "leaveQueue:now", "PARTY")
    end

    LFT.sendCancelMeMessage()

    LFT.fixMainButton()
end

-- slash commands

SLASH_LFT1 = "/lft"
SlashCmdList["LFT"] = function(cmd)
    if cmd then
        if string.sub(cmd, 1, 3) == 'who' then
            if LFT.channelIndex == 0 then
                lfdebug('LFT.channelIndex = 0, please try again in 10 seconds')
                return false
            end
            LFTWhoCounter:Show()
            SendChatMessage('whoLFT:' .. addonVer, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFT.channel))
        end
        if string.sub(cmd, 1, 17) == 'resetformedgroups' then
            LFT.resetFormedGroups()
            lfprint('Formed groups history reset.')
        end
        if string.sub(cmd, 1, 12) == 'formedgroups' then
            for code, number in next, LFT_FORMED_GROUPS do
                if number ~= 0 then lfprint(number .. ' - ' .. LFT.dungeonNameFromCode(code)) end
            end
        end
    end
end

-- dungeons

LFT.dungeons = {
    ['Ragefire Chasm'] = { minLevel = 13, maxLevel = 18, code = 'rfc', queued = false, canQueue = true, background = 'ragefirechasm' },
    ['Wailing Caverns'] = { minLevel = 17, maxLevel = 24, code = 'wc', queued = false, canQueue = true, background = 'wailingcaverns' },
    ['The Deadmines'] = { minLevel = 19, maxLevel = 24, code = 'dm', queued = false, canQueue = true, background = 'deadmines' },
    ['Shadowfang Keep'] = { minLevel = 22, maxLevel = 30, code = 'sfk', queued = false, canQueue = true, background = 'shadowfangkeep' },
    ['The Stockade'] = { minLevel = 22, maxLevel = 30, code = 'stocks', queued = false, canQueue = true, background = 'stormwindstockades' },
    ['Blackfathom Deeps'] = { minLevel = 23, maxLevel = 32, code = 'bfd', queued = false, canQueue = true, background = 'blackfathomdeeps' },
    ['Scarlet Monastery Graveyard'] = { minLevel = 27, maxLevel = 36, code = 'smgy', queued = false, canQueue = true, background = 'scarletmonastery' },
    ['Scarlet Monastery Library'] = { minLevel = 28, maxLevel = 39, code = 'smlib', queued = false, canQueue = true, background = 'scarletmonastery' },
    ['Gnomeregan'] = { minLevel = 29, maxLevel = 38, code = 'gnomer', queued = false, canQueue = true, background = 'gnomeregan' },
    ['Razorfen Kraul'] = { minLevel = 29, maxLevel = 38, code = 'rfk', queued = false, canQueue = true, background = 'razorfenkraul' },
    ['Scarlet Monastery Armory'] = { minLevel = 32, maxLevel = 41, code = 'smarmory', queued = false, canQueue = true, background = 'scarletmonastery' },
    ['Scarlet Monastery Cathedral'] = { minLevel = 35, maxLevel = 45, code = 'smcath', queued = false, canQueue = true, background = 'scarletmonastery' },
    ['Razorfen Downs'] = { minLevel = 36, maxLevel = 46, code = 'rfd', queued = false, canQueue = true, background = 'razorfendowns' },
    ['Zul\'Farrak'] = { minLevel = 44, maxLevel = 54, code = 'zf', queued = false, canQueue = true, background = 'zulfarak' },
    ['Maraudon'] = { minLevel = 47, maxLevel = 55, code = 'mara', queued = false, canQueue = true, background = 'maraudon' },
    ['Uldaman'] = { minLevel = 50, maxLevel = 51, code = 'ulda', queued = false, canQueue = true, background = 'uldaman' },
    ['Temple of Atal\'Hakkar'] = { minLevel = 50, maxLevel = 60, code = 'st', queued = false, canQueue = true, background = 'sunkentemple' },
    ['Blackrock Depths'] = { minLevel = 52, maxLevel = 60, code = 'brd', queued = false, canQueue = true, background = 'blackrockdepths' },
    ['Lower Blackrock Spire'] = { minLevel = 55, maxLevel = 60, code = 'lbrs', queued = false, canQueue = true, background = 'blackrockspire' },
    ['Dire Maul East'] = { minLevel = 55, maxLevel = 60, code = 'dme', queued = false, canQueue = true, background = 'diremaul' },
    ['Dire Maul North'] = { minLevel = 57, maxLevel = 60, code = 'dmn', queued = false, canQueue = true, background = 'diremaul' },
    ['Dire Maul West'] = { minLevel = 57, maxLevel = 60, code = 'dmw', queued = false, canQueue = true, background = 'diremaul' },
    ['Scholomance'] = { minLevel = 58, maxLevel = 60, code = 'scholo', queued = false, canQueue = true, background = 'scholomance' },
    ['Stratholme UD'] = { minLevel = 58, maxLevel = 60, code = 'stratud', queued = false, canQueue = true, background = 'stratholme' },
    ['Stratholme Live'] = { minLevel = 58, maxLevel = 60, code = 'stratlive', queued = false, canQueue = true, background = 'stratholme' },
}

-- utils

function LFT.ver(ver)
    return tonumber(string.sub(ver, 1, 1)) * 1000 +
            tonumber(string.sub(ver, 3, 3)) * 100 +
            tonumber(string.sub(ver, 5, 5)) * 10 +
            tonumber(string.sub(ver, 7, 7)) * 1
end

function LFT.playerIsPartyLeader()
    return GetPartyLeaderIndex() == 0 and GetNumPartyMembers() > 0
end

function LFT.ucFirst(a)
    return string.upper(string.sub(a, 1, 1)) .. string.lower(string.sub(a, 2, string.len(a)))
end

function string:split(delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(self, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(self, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(self, delimiter, from)
    end
    table.insert(result, string.sub(self, from))
    return result
end
