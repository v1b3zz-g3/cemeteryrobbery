-- server.lua

local Graves = {}
GraveRobbers = {}

local FRAMEWORK = Config.Framework

local ESX, QB
if FRAMEWORK == 'ESX' then
    ESX = exports["es_extended"]:getSharedObject()
else
    QBCore = exports["qb-core"]:GetCoreObject()
end

local function getLastIndexFromFile()
    local configFile = LoadResourceFile(GetCurrentResourceName(), "config2.lua")
    if not configFile then
        return 0
    end

    local lastIndex = 0
    for loc in string.gmatch(configFile, "loc(%d+)") do
        local num = tonumber(loc)
        if num and num > lastIndex then
            lastIndex = num
        end
    end

    return lastIndex
end

RegisterNetEvent('sf_cemetery:requestLastIndex')
AddEventHandler('sf_cemetery:requestLastIndex', function()
    local source = source
    local lastIndex = getLastIndexFromFile()
    TriggerClientEvent('sf_cemetery:setLastIndex', source, lastIndex)
end)

RegisterNetEvent('sf_cemetery:saveCoords')
AddEventHandler('sf_cemetery:saveCoords', function(coordsList)
    local configFile = LoadResourceFile(GetCurrentResourceName(), "config2.lua")

    if not configFile then
        configFile = "Config.robloc = {\n"
    else
        configFile = configFile:gsub("%}\n$", "")
    end

    for loc, coords in pairs(coordsList) do
        configFile = configFile .. string.format("    %s = vec3(%.4f, %.4f, %.4f),\n", loc, coords.x, coords.y, coords.z)
    end

    configFile = configFile .. "}\n"

    SaveResourceFile(GetCurrentResourceName(), "config2.lua", configFile, -1)
end)

RegisterNetEvent('sf_cemetery:randomLocInfos')
AddEventHandler('sf_cemetery:randomLocInfos', function()
    Graves = {}
    local percentage = Config.Camp * 0.01
    local n = 0
    local body = false
    for _, location in pairs(Config.robloc) do
        local chance = math.random()
        if chance <= percentage then
            body = true
        else
            body = false
        end
        n = n + 1
        local grave = 'Grave' .. n
        Graves[grave] = {
            loc = location,
            body = body,
            open = false,
        }
    end
    TriggerClientEvent('sf_cemetery:locInfosGenerated', source, Graves)
end)

RegisterNetEvent('sf_cemetery:searchLocInfo')
AddEventHandler('sf_cemetery:searchLocInfo', function(index, loc)
    if loc == nil then
        print("[sf_cemetery] Error: loc is nil in searchLocInfo")
        return
    end

    for _, grave in pairs(Graves) do
        if grave.loc == loc then
            if grave.open == false then
                grave.open = true
                TriggerClientEvent('sf_cemetery:startDigging', source, index, loc, grave.body, grave)
            else
                TriggerClientEvent('sf_cemetery:graveOpen', source)
                return
            end
        end
    end
end)

RegisterNetEvent('sf_cemetery:robResult')
AddEventHandler('sf_cemetery:robResult', function (ped, loc, grave)
    local source = source
    local playerName

    if FRAMEWORK == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(source)
        playerName = xPlayer.getName()
    else
        local Player = QBCore.Functions.GetPlayer(source)
        playerName = Player.PlayerData.name
    end

    GraveRobbers[loc] = playerName

    local percentage = Config.Values * 0.01
    local chance = math.random()
    if chance <= percentage then
        local items = {}
        for key, value in pairs(Config.Items) do
            table.insert(items, value)
        end

        local randomItem = items[math.random(1, #items)]
        local quantity = math.random(randomItem.min, randomItem.max)

        if Config.Inventory == 'OX' then
            exports.ox_inventory:AddItem(source, randomItem.item, quantity)
        else
            exports['qb-inventory']:AddItem(source, randomItem.item, quantity)
        end
    else
        TriggerClientEvent('sf_cemetery:bodyHasNoValues', source)
    end

    TriggerClientEvent('sf_cemetery:deleteTarget', source, ped, loc, grave)
end)

RegisterNetEvent('sf_cemetery:receiveEvidence')
AddEventHandler('sf_cemetery:receiveEvidence', function(assailantName)
    local source = source

    if Config.Inventory == 'OX' then
        exports.ox_inventory:AddItem(source, 'blood_evidence', 1, {assailant = assailantName})
    else
        exports['qb-inventory']:AddItem(source, 'blood_evidence', 1, {assailant = assailantName})
    end

    local players = (FRAMEWORK == 'QB') and QBCore.Functions.GetQBPlayers() or ESX.GetPlayers()

    for _, player in pairs(players) do
        local playerData = (FRAMEWORK == 'QB') and player.PlayerData or ESX.GetPlayerData(player)

        if playerData and playerData.job.name == Config.PoliceJob then
            TriggerClientEvent('sf_cemetery:removeTargetAndPed', -1, source, assailantName)
        end
    end

    TriggerClientEvent('sf_cemetery:bloodEvidenceCollected', source, assailantName)
end)

RegisterNetEvent('sf_cemetery:analyzeEvidence')
AddEventHandler('sf_cemetery:analyzeEvidence', function()
    local source = source
    local hasEvidence = false
    local assailantName = nil

    if FRAMEWORK == 'ESX' then
        local xPlayer = ESX.GetPlayerFromId(source)
        local job = xPlayer.getJob()
        local inventory = xPlayer.getInventory()

        for _, item in pairs(inventory) do
            if item.name == 'blood_evidence' and item.count > 0 then
                hasEvidence = true
                assailantName = item.info.assailant
                break
            end
        end

        if job.name == Config.PoliceJob then
            if hasEvidence then
                TriggerClientEvent('sf_cemetery:evidenceAnalyzed', source, assailantName)
            else
                TriggerClientEvent('sf_cemetery:noEvidence', source)
            end
        end

    else
        local Player = QBCore.Functions.GetPlayer(source)
        local job = Player.PlayerData.job
        local evidenceItem = Player.Functions.GetItemByName('blood_evidence')

        if evidenceItem then
            hasEvidence = true
            assailantName = evidenceItem.info.assailant
        end

        if job.name == Config.PoliceJob then
            if hasEvidence then
                TriggerClientEvent('sf_cemetery:evidenceAnalyzed', source, assailantName)
            else
                TriggerClientEvent('sf_cemetery:noEvidence', source)
            end
        end
    end
end)

RegisterNetEvent('sf_cemetery:sendPoliceTargets')
AddEventHandler('sf_cemetery:sendPoliceTargets', function()
    local players = (FRAMEWORK == 'QB') and QBCore.Functions.GetQBPlayers() or ESX.GetPlayers()

    for _, player in pairs(players) do
        local playerData

        if FRAMEWORK == 'QB' then
            playerData = player.PlayerData
        else
            local esxPlayer = ESX.GetPlayerFromId(player)
            playerData = esxPlayer and esxPlayer.getJob()
        end

        if playerData and playerData.name == Config.PoliceJob then
            local playerSource = (FRAMEWORK == 'QB') and player.PlayerData.source or player
            TriggerClientEvent('sf_cemetery:createPoliceTarget', playerSource, evidenceAnalysisCoords)
        end
    end
end)

RegisterNetEvent('sf_cemetery:createTargetEvidenceServer')
AddEventHandler('sf_cemetery:createTargetEvidenceServer', function(ped, loc, assailantName, grave)
    local loc = grave

    local players = (FRAMEWORK == 'QB') and QBCore.Functions.GetQBPlayers() or ESX.GetPlayers()

    for _, player in pairs(players) do
        local playerData

        if FRAMEWORK == 'QB' then
            playerData = player.PlayerData
        else
            local esxPlayer = ESX.GetPlayerFromId(player)
            playerData = esxPlayer and esxPlayer.getJob()
        end

        if playerData and playerData.name == Config.PoliceJob then
            TriggerClientEvent('sf_cemetery:createTargetEvidenceClient', playerData.source, ped, loc, assailantName)
        end
    end
end)

RegisterNetEvent('sf_cemetery:checkPoliceTarget')
AddEventHandler('sf_cemetery:checkPoliceTarget', function(graves)
    local count = 0
    local jobName = Config.PoliceJob

    if FRAMEWORK == "ESX" then
        local policePlayers = ESX.GetExtendedPlayers('job', jobName)
        if type(policePlayers) == 'table' then
            count = #policePlayers
        else
            print("[sf_cemetery] Error: ESX.GetExtendedPlayers did not return a valid table")
        end
    else
        local players = QBCore.Functions.GetPlayers()
        if type(players) == 'table' then
            for i = 1, #players, 1 do
                local player = QBCore.Functions.GetPlayer(players[i])
                if player and player.PlayerData.job.name == jobName then
                    count = count + 1
                end
            end
        else
            print("[sf_cemetery] Error: QBCore.Functions.GetPlayers did not return a valid table")
        end
    end

    if type(count) ~= 'number' then
        count = 0
    end

    TriggerClientEvent('sf_cemetery:startRob', source, count, graves)
end)

RegisterNetEvent('sf_cemetery:checkPoliceServer')
AddEventHandler('sf_cemetery:checkPoliceServer', function()
    local count = 0
    local jobName = Config.PoliceJob

    if FRAMEWORK == "ESX" then
        local policePlayers = ESX.GetExtendedPlayers('job', jobName)
        if type(policePlayers) == 'table' then
            count = #policePlayers
        else
            print("[sf_cemetery] Error: ESX.GetExtendedPlayers did not return a valid table")
        end
    else
        local players = QBCore.Functions.GetPlayers()
        if type(players) == 'table' then
            for i = 1, #players, 1 do
                local player = QBCore.Functions.GetPlayer(players[i])
                if player and player.PlayerData.job.name == jobName then
                    count = count + 1
                end
            end
        else
            print("[sf_cemetery] Error: QBCore.Functions.GetPlayers did not return a valid table")
        end
    end

    if type(count) ~= 'number' or count == nil then
        print("[sf_cemetery] Warning: count was nil or non-numeric, defaulting to 0")
        count = 0
    end

    TriggerClientEvent('sf_cemetery:startRob', source, count, Graves)
end)
