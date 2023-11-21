ped = {}
peds = {}
local resourceName = GetCurrentResourceName()
local context = IsDuplicityVersion() and 'server' or 'client'
local pedIndex = 1
local netPeds = 0

local NetworkDoesEntityExistWithNetworkId = NetworkDoesEntityExistWithNetworkId
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local DoesEntityExist = DoesEntityExist
local SetEntityAlpha = SetEntityAlpha

if context == 'client' then
    AddEventHandler('onClientResourceStart', function(resource)
        if resource ~= resourceName then return end
        local syncedPeds = lib.callback.await(resourceName..':server:loadPeds', false)
        ped.loadPeds(syncedPeds)
    end)

    AddEventHandler('onClientResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        for k, v in pairs(Plants) do
            if v.isRendered == true then
                if DoesEntityExist(v.object) then
                    DeleteObject(v.object)
                    exports.ox_target:removeLocalEntity(v.object)
                end
            end
        end
    end)

    AddEventHandler('onResourceStop', function(resource)
        if resource ~= resourceName then return end
        for _, v in pairs (peds) do
            if DoesEntityExist(v.ped) then
                DeletePed(v.ped)
                exports.ox_target:removeLocalEntity(v.ped)
            end
        end
    end)

    function ped.addPed(ped)
        CreateThread(function()
            if peds[ped.name] ~= nil then return end
            if ped.options and type(ped.options) == 'table' then
                for i = 1, #ped.options do
                    ped.options[i].data = ped.name
                end
            end

            if not ped.name then 
                ped.name = 'ped_'..resourceName..'_'..pedIndex
                pedIndex = pedIndex + 1
            end

            peds[ped.name] = {
                model = joaat(ped.model),
                coords = ped.coords,
                heading = ped.heading,
                gender = ped.gender,
                scenario = ped.scenario,
                animDict = ped.animDict,
                animName = ped.animName,
                options = ped.options,
                distance = ped.options and ped.optionsDistance or 3.5,
                source = ped.source or 'client',
                ped = nil,
                zone = nil,
            }

            local pedData = peds[ped.name]
            pedData.zone = lib.zones.sphere({
                coords = vec3(pedData.coords.x, pedData.coords.y, pedData.coords.z),
                radius = 100,
                -- debug = true,
                onEnter = function()
                    lib.requestModel(pedData.model)
                    local genderInt = pedData.gender == 'male' and 4 or 5
                    pedData.ped = CreatePed(genderInt, pedData.model, pedData.coords.x, pedData.coords.y, pedData.coords.z - 1, pedData.heading, false, true)
                    SetEntityAlpha(pedData.ped, 0, false)
                    -- SetEntityHeading(pedData.ped, pedData.coords.w)
                    PlaceObjectOnGroundProperly(pedData.ped)
                    FreezeEntityPosition(pedData.ped, true)
                    SetEntityInvincible(pedData.ped, true)
                    SetBlockingOfNonTemporaryEvents(pedData.ped, true)

                    if pedData.animDict and pedData.animName then
                        lib.requestAnimDict(pedData.animDict)
                        TaskPlayAnim(pedData.ped, pedData.animDict, pedData.animName, 8.0, 0, -1, 1, 0, 0, 0)
                    elseif pedData.scenario then
                        TaskStartScenarioInPlace(pedData.ped, pedData.scenario, 0, true)
                    end

                    for i = 0, 255, 51 do
                        Wait(50)
                        SetEntityAlpha(pedData.ped, i, false)
                    end
                    if pedData.options and pedData.distance then
                        exports.ox_target:addLocalEntity(pedData.ped, pedData.options)
                    end
                end,
                onExit = function()
                    exports.ox_target:removeLocalEntity(pedData.ped)
                    if DoesEntityExist(pedData.ped) then
                        for i = 255, 0, -51 do
                            Wait(50)
                            SetEntityAlpha(pedData.ped, i, false)
                        end
                        ClearPedTasksImmediately(pedData.ped)
                        DeletePed(pedData.ped)
                    end
                    pedData.ped = nil
                end,
            })
        end)
    end

    local function netPedThread()
        CreateThread(function()
            local globalInterval = 2000
            while true  do
                local waitInterval = (8000 / netPeds) - globalInterval
                for _, v in pairs(peds) do
                    if v.source == 'server' then
                        if NetworkDoesEntityExistWithNetworkId(v.netId) and not v.ped then
                            v.ped = NetToPed(v.netId)
                            v.owner = NetworkGetEntityOwner(v.ped)
                            exports.ox_target:addLocalEntity(v.ped , v.options)
                            if v.owner == cache.playerId then
                                if v.task == 'wander' and not v.tasked then
                                    TaskWanderStandard(v.ped, 10.0, 10)
                                    v.tasked = true
                                elseif v.task == 'scenario' and not v.tasked then
                                    TaskStartScenarioInPlace(v.ped, v.taskData, 0, true)
                                    v.tasked = true
                                end
                                SetBlockingOfNonTemporaryEvents(v.ped, true)
                            end
                        elseif not NetworkDoesEntityExistWithNetworkId(v.netId) and v.ped then
                            for i=1, #v.options do
                                local s = v.options[i]
                                exports.ox_target:removeLocalEntity(v.ped, s.name)
                            end
                            v.ped = nil
                            v.tasked = false
                        end
                        Wait(waitInterval)
                    end
                end
                Wait(globalInterval)
            end
        end)
    end

    function ped.addNetworkedPed(ped)
        if ped.options and type(ped.options) == 'table' then
            for i = 1, #ped.options do
                ped.options[i].data = ped.name
            end
        end
        peds[ped.name] = {
            model = joaat(ped.model),
            coords = ped.coords,
            heading = ped.heading,
            gender = ped.gender,
            source = ped.source,
            ped = nil,
            netId = ped.netId,
            options = ped.options,
            distance = ped.options and ped.optionsDistance or 3.5,
            task = ped.task,
            taskData = ped.taskData
        }
        netPeds += 1
    end

    function ped.loadPeds(table)
        for _, pedData in pairs(table) do
            if pedData.source ~= 'server' then
                ped.addPed(pedData)
            elseif pedData.source == 'server' then
                ped.addNetworkedPed(pedData)
            end
        end
        if netPeds > 0 then
            netPedThread()
        end
    end

    RegisterNetEvent(resourceName..':client:modifyAnim', function(name, anim)
        if source == '' then return end
        if peds[name] == nil then return end
        local pedData = peds[name]
        if DoesEntityExist(pedData.ped) then
            if anim.scenario ~= nil then
                peds[name].animDict = nil
                peds[name].animName = nil
                peds[name].scenario = anim.scenario
                ClearPedTasksImmediately(pedData.ped)
                TaskStartScenarioInPlace(pedData.ped, anim, 0, true)
            elseif anim.dict ~= nil then
                lib.requestAnimDict(anim.dict)
                peds[name].scenario = nil
                peds[name].animDict = anim.dict
                peds[name].animName = anim.anim
                ClearPedTasksImmediately(pedData.ped)
                TaskPlayAnim(pedData.ped, pedData.animDict, pedData.animName, 7.0, 1.0, -1, 50, 0, false, false, false)
            elseif anim.dict == nil and anim.anim == nil and anim.scenario == nil then
                peds[name].scenario = nil
                peds[name].animDict = nil
                peds[name].animName = nil
                ClearPedTasksImmediately(pedData.ped)
            end
        end
    end)

    RegisterNetEvent(resourceName..':client:removePed', function(name, removeType)
        if source == '' then return end
        if peds[name] == nil then return end
        local pedData = peds[name]
        pedData.zone:remove()
        if DoesEntityExist(pedData['ped']) then
            if removeType == 'ghost' then
                ClearPedTasksImmediately(pedData['ped'])
                FreezeEntityPosition(pedData['ped'], false)
                for i = 255, 0, -51 do
                    Wait(50)
                    SetEntityAlpha(pedData.ped, i, false)
                end
                DeletePed(pedData['ped'])
            elseif removeType == 'flee' then
                FreezeEntityPosition(pedData['ped'], false)
                -- SetEntityInvincible(pedData['ped'], true)
                ClearPedTasksImmediately(pedData['ped'])
                TaskSmartFleePed(pedData['ped'], cache.ped, 100.0, -1, false, true)
                CreateThread(function()
                    Wait(8000)
                    if DoesEntityExist(pedData['ped']) then
                        for i = 255, 0, -51 do
                            Wait(50)
                            SetEntityAlpha(pedData.ped, i, false)
                        end
                        DeletePed(pedData['ped'])
                    end
                end)
            elseif removeType == 'wander' then
                FreezeEntityPosition(pedData['ped'], false)
                ClearPedTasksImmediately(pedData['ped'])
                TaskWanderStandard(pedData['ped'], 100.0, 100)
            end
            exports.ox_target:removeLocalEntity(pedData["ped"])
        end
        peds[name] = nil
    end)

    RegisterNetEvent(resourceName..':client:respawnPed', function(data)
        if source == '' then return end
        ped.addPed(data)
    end)
elseif context == 'server' then
    AddEventHandler("onResourceStop", function(resource)
        if resource ~= resourceName then return end
        for k, v in pairs(peds) do
            if v.source == 'server' then
                ped.removeNetworkedPed(k)
            end
        end
    end)

    function ped.addPed(pedData)
        peds[pedData.name] = pedData
        peds[pedData.name].source = 'serverLocal'
        peds[pedData.name].model = joaat(pedData.model)
    end

    function ped.loadPeds(table)
        for i = 1, #table do
            ped.addPed(table[i])
        end
    end

    function ped.respawnPed(pedData)
        ped.addPed(pedData)
        TriggerClientEvent(resourceName..':client:respawnPed', -1, peds[pedData.name])
    end

    function ped.modifyAnim(name, anim)
        if peds[name] == nil then return end
        peds[name].animDict = anim and anim.dict or nil
        peds[name].animName =  anim and anim.anim or nil
        peds[name].scenario =  anim and anim.scenario or nil
        TriggerClientEvent(resourceName..':client:modifyAnim', -1, name, anim)
    end

    function ped.removePed(name, removeType)
        if peds[name] == nil then return end
        -- if peds[name].source == 'server' then
        --     if DoesEntityExist(peds[name].ped) then
        --         DeleteEntity(peds[name].ped)
        --     end
        -- end
        peds[name] = nil
        TriggerClientEvent(resourceName..':client:removePed', -1, name, removeType)
    end

    RegisterNetEvent(resourceName..':server:modifyAnim', function(name, anim)
        if peds[name] == nil then return end
        peds[name].animDict = anim and anim.dict or nil
        peds[name].animName =  anim and anim.anim or nil
        peds[name].scenario =  anim and anim.scenario or nil
        TriggerClientEvent(resourceName..':client:modifyAnim', -1, name, anim)
    end)

    RegisterNetEvent(resourceName..':server:removePed', function(name, removeType)
        if peds[name] == nil then return end
        peds[name] = nil
        TriggerClientEvent(resourceName..':client:removePed', -1, name, removeType)
    end)

    RegisterNetEvent(resourceName..':server:taskPed', function(name, tasked)
        if peds[name] == nil then return end
        peds[name].animDict = anim and anim.dict or nil
        peds[name].animName =  anim and anim.anim or nil
        peds[name].scenario =  anim and anim.scenario or nil
        TriggerClientEvent(resourceName..':client:taskPed', -1, name, tasked)
    end)

    lib.callback.register(resourceName..':server:loadPeds', function(source)
        -- local sentPeds = {}
        -- for _, v in pairs(peds) do
        --     sentPeds[#sentPeds+1] = v
        -- end
        return peds
    end)

    function ped.addNetworkedPed(pedData)
        CreateThread(function()
            peds[pedData.name] = pedData
            peds[pedData.name].source = 'server'
            peds[pedData.name].model = joaat(pedData.model)
            local ped = CreatePed(4, peds[pedData.name].model, peds[pedData.name].coords.x, peds[pedData.name].coords.y, peds[pedData.name].coords.z - 1, peds[pedData.name].heading, true, true)
            while not DoesEntityExist(ped) do Wait(10) end
            peds[pedData.name].ent = ped
            peds[pedData.name].netId = NetworkGetNetworkIdFromEntity(ped)
        end)
    end

    function ped.removeNetworkedPed(name)
        local ent = peds[name].ent
        if DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end

    function ped.getPedInfo(name)
        print(json.encode(peds[name], {indent=true}))
    end
end