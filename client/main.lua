-- main.lua

local TARGET = Config.Target
local locInfos = false
local inRob = false
local FRAMEWORK = Config.Framework
local activeRobs = {}
local target1 = nil
local target2 = nil
local evidenceTargets = {}
local currentTombs = {}
local isInteracting = {}
local robbedBodies = {} -- Tracks NPCs that have already been searched

local isSearching = false -- Global interaction lock: prevents spamming any target while an action is in progress

local coordsList = {}
local startIndex = 1

RegisterCommand('addcoord', function()
    TriggerServerEvent('sf_cemetery:requestLastIndex')
end, false)

RegisterNetEvent('sf_cemetery:setLastIndex')
AddEventHandler('sf_cemetery:setLastIndex', function(lastIndex)
    startIndex = lastIndex + 1
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    coordsList["loc" .. startIndex] = vector3(coords.x, coords.y, coords.z)
    startIndex = startIndex + 1
end)

RegisterCommand('closecoord', function()
    TriggerServerEvent('sf_cemetery:saveCoords', coordsList)
end, false)

local ESX, QB
if FRAMEWORK == 'ESX' then
    ESX = exports["es_extended"]:getSharedObject()
else
    QBCore = exports["qb-core"]:GetCoreObject()
end

if FRAMEWORK == 'QB' then
    playerJob = QBCore.Functions.GetPlayerData().job
end

local evidenceAnalysisCoords = Config.CheckEvidenceCoords

function ApplyEvidenceTargetsToPolice()
    TriggerServerEvent('sf_cemetery:sendPoliceTargets')
end

local function getPlayerData()
    local firstname, secondname
    if FRAMEWORK == 'ESX' then
        if ESX.PlayerData and ESX.PlayerData.firstName and ESX.PlayerData.lastName then
            firstname = ESX.PlayerData.firstName
            secondname = ESX.PlayerData.lastName
        else
            return
        end
    else
        local PlayerData = QBCore.Functions.GetPlayerData()
        firstname = PlayerData.charinfo.firstname
        secondname = PlayerData.charinfo.lastname
    end

    assailantName = firstname .. " " .. secondname
end

if FRAMEWORK == 'QB' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        getPlayerData()
    end)
elseif FRAMEWORK == 'ESX' then
    RegisterNetEvent('esx:playerLoaded', function()
        getPlayerData()
    end)
end

RegisterNetEvent('sf_cemetery:createPoliceTarget', function()
    if evidenceTargets['analyzeEvidence'] then
        if TARGET == 'OX' then
            if evidenceTargets['analyzeEvidence'] then
                exports.ox_target:removeZone(evidenceTargets['analyzeEvidence'])
            end
        else
            if evidenceTargets['analyzeEvidence'] then
                exports['qb-target']:RemoveZone(evidenceTargets['analyzeEvidence'])
            end
        end
    end

    if TARGET == 'OX' then
        evidenceTargets['analyzeEvidence'] = exports.ox_target:addSphereZone({
            coords = vector3(evidenceAnalysisCoords.x, evidenceAnalysisCoords.y, evidenceAnalysisCoords.z),
            radius = 2.0,
            options = {
                name = 'sf_cemetery:analyzeEvidence',
                icon = 'fas fa-microscope',
                label = _t('target.analyze_evidence'),
                onSelect = function ()
                    TriggerServerEvent('sf_cemetery:analyzeEvidence')
                end
            }
        })
    else
        evidenceTargets['analyzeEvidence'] = exports['qb-target']:AddCircleZone('analyzeEvidence', vector3(evidenceAnalysisCoords.x, evidenceAnalysisCoords.y, evidenceAnalysisCoords.z), 2.0, {
            name = 'analyzeEvidence',
            debugPoly = false,
            useZ = true}, {
            options = {
                {
                    action = function ()
                        TriggerServerEvent('sf_cemetery:analyzeEvidence')
                    end,
                    icon = "fas fa-microscope",
                    label = _t('target.analyze_evidence'),
                }
            },
            distance = 2.0
        })
    end
end)

Citizen.CreateThread(function ()
    TriggerServerEvent('sf_cemetery:randomLocInfos')
    ApplyEvidenceTargetsToPolice()
end)

RegisterNetEvent('sf_cemetery:locInfosGenerated')
AddEventHandler('sf_cemetery:locInfosGenerated', function(graves)
    gravesBackup = graves
    locInfos = true
    if Config.typeOfRobbery == 'target' then
        TriggerServerEvent('sf_cemetery:checkPoliceTarget', graves)
    end
end)

RegisterNetEvent('sf_cemetery:startRob', function (count, graves)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped, false)
    local n = 0
    count = tonumber(count) or 0

    if count >= Config.minPolice then
        if inRob then
            TriggerEvent('sf_cemetery:robStarted')
        else
            for _, grave in pairs(gravesBackup) do
                n = n + 1
                local loc = grave.loc

                if Config.typeOfRobbery == 'item' then
                    local dist = #(loc.xy - pos.xy)
                    if dist < 1 then
                        if not locInfos then
                            TriggerServerEvent('sf_cemetery:randomLocInfos')
                        else
                            inRob = true
                            TriggerServerEvent('sf_cemetery:searchLocInfo', n, loc)
                            break
                        end
                    end
                end
            end
        end
    else
        TriggerEvent('sf_cemetery:notEnoughPolice')
    end

    if Config.typeOfRobbery == 'target' then
        for _, grave in pairs(gravesBackup) do
            n = n + 1
            local loc = grave.loc
            if TARGET == 'OX' then
                local targetTomb = exports.ox_target:addSphereZone({
                    coords = vector3(loc.x, loc.y, loc.z - 1),
                    radius = 1.5,
                    options = {
                        name = 'sf_cemetery:targetToRob',
                        icon = 'fas fa-user',
                        label = 'Rob Tomb',
                        onSelect = function ()
                            if count >= Config.minPolice then
                                if not isInteracting[n] and not isSearching then
                                    isSearching = true
                                    inRob = true
                                    -- Remove the zone immediately on click so it disappears right away
                                    if currentTombs[n] and currentTombs[n].target then
                                        exports.ox_target:removeZone(currentTombs[n].target)
                                        currentTombs[n].target = nil
                                    end
                                    TriggerServerEvent('sf_cemetery:searchLocInfo', n, loc)
                                end
                            else
                                TriggerEvent('sf_cemetery:notEnoughPolice')
                            end
                        end
                    }
                })
                currentTombs[n] = {target = targetTomb, coords = vector3(loc.x, loc.y, loc.z)}
                isInteracting[n] = false
            else
                local targetTomb = exports['qb-target']:AddCircleZone('targetrobTomb' .. n, vector3(loc.x, loc.y, loc.z - 1), 1.5, {
                    name = 'targetrobTomb' .. n,
                    debugPoly = false,
                    useZ = true
                }, {
                    options = {
                        {
                            action = function ()
                                if count >= Config.minPolice then
                                    if not isInteracting[n] and not isSearching then
                                        isSearching = true
                                        inRob = true
                                        -- Remove the zone immediately on click so it disappears right away
                                        if currentTombs[n] and currentTombs[n].targetName then
                                            exports['qb-target']:RemoveZone(currentTombs[n].targetName)
                                            currentTombs[n].targetName = nil
                                        end
                                        TriggerServerEvent('sf_cemetery:searchLocInfo', n, loc)
                                    end
                                else
                                    TriggerEvent('sf_cemetery:notEnoughPolice')
                                end
                            end,
                            icon = "fas fa-user",
                            label = 'Rob Tomb',
                        }
                    },
                    distance = 1.5
                })
                currentTombs[n] = {target = targetTomb, targetName = 'targetrobTomb' .. n, coords = vector3(loc.x, loc.y, loc.z)}
                isInteracting[n] = false
            end
        end
    end
end)

RegisterNetEvent('sf_cemetery:startDigging', function (index, loc, bodyinfo, grave)
    isInteracting[index] = true
    local ped = PlayerPedId()
    RequestAnimDict('amb@world_human_gardener_plant@male@base')
    while not HasAnimDictLoaded('amb@world_human_gardener_plant@male@base') do
        Wait(0)
    end

    local shovelModel = GetHashKey('prop_cs_trowel')
    RequestModel(shovelModel)
    while not HasModelLoaded(shovelModel) do
        Wait(0)
    end

    if not HasModelLoaded(shovelModel) then
        return
    end

    local function removeTargetAndBlip(index)
        if currentTombs[index] then
            local tomb = currentTombs[index]

            if TARGET == 'OX' then
                if tomb.target then
                    exports.ox_target:removeZone(tomb.target)
                end
            else
                if tomb.targetName then
                    exports['qb-target']:RemoveZone(tomb.targetName)
                end
            end

            currentTombs[index] = nil
            isInteracting[index] = nil
        end
    end

    removeTargetAndBlip(index)

    local shovel = CreateObject(shovelModel, loc.x, loc.y, loc.z, true, true, false)
    AttachEntityToEntity(shovel, ped, GetPedBoneIndex(ped, 57005), 0.1, 0.0, 0.0, 0.0, 0.0, 100.0, true, true, false, true, 1, true)

    TaskPlayAnim(ped, 'amb@world_human_gardener_plant@male@base', 'base', 8.0, -8.0, 10000, 1, 0, false, false, false)
    local n = 0
    while n < 10 do
        Wait(1000)
        n = n + 1
        RequestNamedPtfxAsset("core")
        while not HasNamedPtfxAssetLoaded("core") do
            Wait(0)
        end
        UseParticleFxAssetNextCall("core")
        StartParticleFxNonLoopedOnEntity("ent_dst_rocks", shovel, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, false, false, false)
    end

    DeleteObject(shovel)
    SetModelAsNoLongerNeeded(shovelModel)

    if not activeRobs[loc] and bodyinfo then
        activeRobs[loc] = true
        TriggerEvent('sf_cemetery:spawnPed', loc, grave)
    elseif not activeRobs[loc] and not bodyinfo then
        TriggerEvent('sf_cemetery:noBodysFound')
        inRob = false
        isSearching = false
    end

    TriggerEvent('sf_cemetery:notifyPolice', loc)
end)

RegisterNetEvent('sf_cemetery:spawnPed', function(loc, grave)
    local model = GetHashKey('a_m_m_beach_02')

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    local _, groundZ = GetGroundZFor_3dCoord(loc.x, loc.y, loc.z, true)
    local offsetZ = 1.0

    ped = CreatePed(25, model, loc.x, loc.y, groundZ + offsetZ, 124.8383, true, true)

    if DoesEntityExist(ped) then
        local animDict = "dead"
        local animName = "dead_a"

        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(0)
        end

        SetEntityCoordsNoOffset(ped, loc.x, loc.y, groundZ + offsetZ, true, true, true)
        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        SetPedCanRagdoll(ped, false)

        TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)
        ApplyPedDamagePack(ped, "BigHitByVehicle", 1.0, 1.0)
        SetEntityHealth(ped, 0)
        TaskStartScenarioAtPosition(ped, "WORLD_HUMAN_BUM_SLUMPED", loc.x, loc.y, groundZ + offsetZ, 0.0, -1, true, false)

        Wait(1000)

        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        TriggerEvent('sf_cemetery:createTarget', ped, loc, grave)
    end
end)

RegisterNetEvent('sf_cemetery:createTarget', function (ped, loc, grave)
    -- Guard: if this NPC has already been robbed, do not create a new interact target
    if robbedBodies[ped] then
        return
    end

    if TARGET == 'OX' then
        target1 = exports.ox_target:addSphereZone({
            coords = vector3(loc.x, loc.y, loc.z - 1),
            radius = 2.0,
            options = {
                name = 'sf_cemetery:targetToRob',
                icon = 'fas fa-user',
                label = _t('target.rob'),
                onSelect = function ()
                    if robbedBodies[ped] or isSearching then return end
                    isSearching = true
                    robbedBodies[ped] = true
                    -- Remove the zone immediately so it cannot be triggered again
                    exports.ox_target:removeZone(target1)
                    target1 = nil
                    TriggerEvent('sf_cemetery:playSearchAnim', source, ped, loc, grave)
                end
            }
        })
    else
        exports['qb-target']:AddCircleZone('targetrob', vector3(loc.x, loc.y, loc.z - 1), 2.0, {
            name = 'targetrob',
            debugPoly = false,
            useZ = true}, {
            options = {
                {
                    action = function ()
                        if robbedBodies[ped] or isSearching then return end
                        isSearching = true
                        robbedBodies[ped] = true
                        -- Remove the zone immediately so it cannot be triggered again
                        exports['qb-target']:RemoveZone('targetrob')
                        target1 = nil
                        TriggerEvent('sf_cemetery:playSearchAnim', source, ped, loc, grave)
                    end,
                    icon = "fas fa-user",
                    label = _t('target.rob'),
                }
            },
            distance = 2.0
        })
    end
end)

RegisterNetEvent('sf_cemetery:deleteTarget', function (ped, loc, grave)
    -- Zone was already removed the moment the player clicked, but clean up just in case
    if target1 then
        if TARGET == 'OX' then
            exports.ox_target:removeZone(target1)
        else
            exports['qb-target']:RemoveZone("targetrob")
        end
        target1 = nil
    end
    activeRobs[loc] = nil
    inRob = false
    isSearching = false -- Unlock so the player can interact with the next tomb
    TriggerServerEvent('sf_cemetery:createTargetEvidenceServer', ped, loc, assailantName, grave)
end)

RegisterNetEvent('sf_cemetery:notifyPolice', function(loc)
    local percentage = Config.PoliceNotify * 0.01
    local chance = math.random()
    if chance <= percentage then
        if Config.dispatch == 'PS' then
            exports["ps-dispatch"]:CustomAlert({
                coords = vector3(loc.x, loc.y, loc.z),
                message = "Criminal Activity - Tomb Robbery",
                dispatchCode = "10-4 Tomb Robbery",
                description = "Tomb Robbery",
                radius = 0,
                sprite = 64,
                color = 2,
                scale = 1.0,
                length = 3,
            })
        elseif Config.dispatch == 'ORIGEN' then
            exports['origen_police']:SendAlert({
                coords = vector3(loc.x, loc.y, loc.z),
                title = 'Tomb Robbery',
                type = 'GENERAL',
                message = 'Criminal Activity - Tomb Robbery',
                job = Config.PoliceJob,
            })
        end
    end
end)

RegisterNetEvent('sf_cemetery:createTargetEvidenceClient', function(ped, loc, assailantName)
    if target2 then
        if TARGET == 'OX' then
            exports.ox_target:removeZone(target2)
        else
            exports['qb-target']:RemoveZone('targetevidence')
        end
        target2 = nil
    end
    if TARGET == 'OX' then
        target2 = exports.ox_target:addSphereZone({
            coords = vector3(loc.x, loc.y, loc.z - 1),
            radius = 2.0,
            options = {
                name = 'sf_cemetery:createEvidence',
                icon = 'fas fa-user',
                label = _t('target.evidence'),
                onSelect = function ()
                    TriggerServerEvent('sf_cemetery:receiveEvidence', assailantName)
                end
            }
        })
    else
        exports['qb-target']:AddCircleZone('targetevidence', vector3(loc.x, loc.y, loc.z - 1), 2.0, {
            name = 'targetevidence',
            debugPoly = false,
            useZ = true}, {
            options = {
                {
                    action = function ()
                        TriggerServerEvent('sf_cemetery:receiveEvidence', assailantName)
                    end,
                    icon = "fas fa-user",
                    label = _t('target.evidence'),
                }
            },
            distance = 2.0
        })
        target2 = 'targetevidence'
    end
end)


RegisterNetEvent('sf_cemetery:playSearchAnim')
AddEventHandler('sf_cemetery:playSearchAnim', function(ped, loc, grave)
    local playerPed = PlayerPedId()

    RequestAnimDict('amb@medic@standing@kneel@base')
    while not HasAnimDictLoaded('amb@medic@standing@kneel@base') do
        Wait(0)
    end

    TaskPlayAnim(playerPed, 'amb@medic@standing@kneel@base', 'base', 8.0, -8.0, 5000, 1, 0, false, false, false)
    Wait(5000)

    ClearPedTasks(playerPed)

    -- isSearching stays true until deleteTarget fires; server response resets it.
    -- If the server never responds for any reason, reset here as a safety net.
    TriggerServerEvent('sf_cemetery:robResult', ped, loc, grave)
end)

RegisterNetEvent('sf_cemetery:removeTargetAndPed', function(source, assailantName)
    if target1 then
        if TARGET == 'OX' then
            exports.ox_target:removeZone(target1)
        else
            exports['qb-target']:RemoveZone('targetrob')
        end
        target1 = nil
    end

    if target2 then
        if TARGET == 'OX' then
            exports.ox_target:removeZone(target2)
        else
            exports['qb-target']:RemoveZone('targetevidence')
        end
        target2 = nil
    end

    -- Clean up the robbed body tracking entry and delete the NPC
    if ped then
        robbedBodies[ped] = nil
        DeleteEntity(ped)
    end
end)

RegisterNetEvent('sf_cemetery:checkPolice', function()
    TriggerServerEvent('sf_cemetery:checkPoliceServer')
end)
