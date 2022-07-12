local Accounts = {}
local QBCore = exports['qb-core']:GetCoreObject()

CreateThread(function()
    Wait(500)
    local result = json.decode(LoadResourceFile(GetCurrentResourceName(), "./accounts.json"))
    if not result then
        return
    end
    for k,v in pairs(result) do
        local k = tostring(k)
        local v = tonumber(v)
        if k and v then
            Accounts[k] = v
        end
    end
end)

QBCore.Functions.CreateCallback('qb-bossmenu:server:GetAccount', function(source, cb, jobname)
    local result = GetAccount(jobname)
    cb(result)
end)

-- Export
function GetAccount(account)
    return Accounts[account] or 0
end

-- Withdraw Money
RegisterServerEvent("qb-bossmenu:server:withdrawMoney")
AddEventHandler("qb-bossmenu:server:withdrawMoney", function(amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local job = Player.PlayerData.job.name

    if not Accounts[job] then
        Accounts[job] = 0
    end

    if Accounts[job] >= amount and amount > 0 then
        Accounts[job] = Accounts[job] - amount
        Player.Functions.AddMoney("cash", amount)
    else
        TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Not Enough Money"}, 'error')
        return
    end
    SaveResourceFile(GetCurrentResourceName(), "./accounts.json", json.encode(Accounts), -1)
    TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Withdraw Money', 'lightgreen', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' successfully withdrew $' .. amount .. ' (' .. job .. ')', false)
end)

-- Deposit Money
RegisterServerEvent("qb-bossmenu:server:depositMoney")
AddEventHandler("qb-bossmenu:server:depositMoney", function(amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local job = Player.PlayerData.job.name

    if not Accounts[job] then
        Accounts[job] = 0
    end

    if Player.Functions.RemoveMoney("cash", amount) then
        Accounts[job] = Accounts[job] + amount
    else
        TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Not Enough Money"}, "error")
        return
    end
    SaveResourceFile(GetCurrentResourceName(), "./accounts.json", json.encode(Accounts), -1)
    TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Deposit Money', 'lightgreen', "Successfully deposited $" .. amount .. ' (' .. job .. ')', false)
end)

RegisterServerEvent("qb-bossmenu:server:addAccountMoney")
AddEventHandler("qb-bossmenu:server:addAccountMoney", function(account, amount)
    if not Accounts[account] then
        Accounts[account] = 0
    end

    Accounts[account] = Accounts[account] + amount
    TriggerClientEvent('qb-bossmenu:client:refreshSociety', -1, account, Accounts[account])
    SaveResourceFile(GetCurrentResourceName(), "./accounts.json", json.encode(Accounts), -1)
end)

RegisterServerEvent("qb-bossmenu:server:removeAccountMoney")
AddEventHandler("qb-bossmenu:server:removeAccountMoney", function(account, amount)
    if not Accounts[account] then
        Accounts[account] = 0
    end

    if Accounts[account] >= amount then
        Accounts[account] = Accounts[account] - amount
    end

    TriggerClientEvent('qb-bossmenu:client:refreshSociety', -1, account, Accounts[account])
    SaveResourceFile(GetCurrentResourceName(), "./accounts.json", json.encode(Accounts), -1)
end)

-- Get Employees
QBCore.Functions.CreateCallback('qb-bossmenu:server:GetEmployees', function(source, cb, jobname)
    local src = source
    local employees = {}
    if not Accounts[jobname] then
        Accounts[jobname] = 0
    end
    local players = exports.oxmysql:executeSync("SELECT * FROM `players` WHERE `job` LIKE '%".. jobname .."%'")
    if players[1] ~= nil then
        for key, value in pairs(players) do
            local isOnline = QBCore.Functions.GetPlayerByCitizenId(value.citizenid)

            if isOnline then
                employees[#employees+1] = {
                    empSource = isOnline.PlayerData.citizenid,
                    grade = isOnline.PlayerData.job.grade,
                    level = isOnline.PlayerData.job.grade.level,
                    isboss = isOnline.PlayerData.job.isboss,
                    name = isOnline.PlayerData.charinfo.firstname .. ' ' .. isOnline.PlayerData.charinfo.lastname
                }
            else
                employees[#employees+1] = {
                    empSource = value.citizenid,
                    grade =  json.decode(value.job).grade,
                    level = json.decode(value.job).grade.level,
                    isboss = json.decode(value.job).isboss,
                    name = json.decode(value.charinfo).firstname .. ' ' .. json.decode(value.charinfo).lastname
                }
            end
        end
    end
    cb(employees)
end)

-- Grade Change
RegisterServerEvent('qb-bossmenu:server:updateGrade')
AddEventHandler('qb-bossmenu:server:updateGrade', function(target, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local Employee = QBCore.Functions.GetPlayerByCitizenId(target)
    if grade == nil then
        TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Invalid grade. Numbers only, with 0 being the lowest grade. What is this, amateur hour?"}, "error", 6000)
        return
    end
    if Player.PlayerData.job.grade.level >= grade and grade <= Player.PlayerData.job.grade.level then
        if Employee then
            if Employee.Functions.SetJob(Player.PlayerData.job.name, grade) then
                TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Grade Changed', 'lightgreen', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' changed grade to ' .. grade .. ' for ' .. Employee.PlayerData.charinfo.firstname .. ' ' .. Employee.PlayerData.charinfo.lastname .. ' (' .. Player.PlayerData.job.name .. ')', false)
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Grade Changed Successfully!"}, "success")
                TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source, {text="Boss Menu", caption="Your new job grade is now [" ..grade.."]."}, "success")
            else
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Grade Does Not Exist"}, "error")
            end
        else
            local playerJob = '%' .. Player.PlayerData.job.name .. '%'
            local result = exports.oxmysql:scalarSync('SELECT job FROM players WHERE citizenid = ? AND job LIKE ?', {target, playerJob})
            if result then
                jobFinal = checkJob(Player.PlayerData.job.name, grade)
                if jobFinal ~= false then
                    TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Grade Changed', 'lightgreen', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' changed grade to ' .. jobFinal.grade.name .. ' for '  .. target .. ' (' .. Player.PlayerData.job.name .. ')', false)
                    TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Grade Changed Successfully!"}, "success")
                    exports.oxmysql:execute('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(jobFinal), target })
                else
                    TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Invalid grade. Numbers only, with 0 being the lowest grade. What is this, amateur hour?"}, "error", 6000)
                end
            else
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="This person is not on your payroll"}, "error", 5000)
            end
        end
    else
        TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Unfair Job Change', 'lightgreen', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' tried to changed grade to ' .. checkJob(Player.PlayerData.job.name, grade).grade.name .. ' ('.. grade ..') for '  .. target .. ' (' .. Player.PlayerData.job.name .. ') but failed because they are lower rank than the person or are trying to give themselves a promotion.', true)
        TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu",caption="You are not authorized to do this. This has been reported."}, "error", 8000)
    end
end)

-- Fire Employee
RegisterServerEvent('qb-bossmenu:server:fireEmployee')
AddEventHandler('qb-bossmenu:server:fireEmployee', function(target)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local Employee = QBCore.Functions.GetPlayerByCitizenId(target)
    if Employee then
        if Player.PlayerData.job.grade.level >= Employee.PlayerData.job.grade.level then
            if Employee.Functions.SetJob("unemployed", '0') then
                TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Fire', 'red', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. Employee.PlayerData.charinfo.firstname .. ' ' .. Employee.PlayerData.charinfo.lastname .. ' (' .. Player.PlayerData.job.name .. ')', false)
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu",caption="You have fired your employee. We will be sending the records to " .. Player.PlayerData.job.label .. " and government."}, "error", 5000)
                TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source , {text="Boss Menu", caption="You Were Fired. Please look for a new job at the courthouse (City Services) and pick up your belongings."}, "error", 10000)
            else
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Mail in a video raffle ticket with full details regarding this error."}, "error")
            end
        else
            TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Unfair Firing', 'red', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' tried to fire ('.. target .. ') at (' .. Player.PlayerData.job.name .. ') but failed because they are lower rank than the person. Something amiss is afoot.', true)
            TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu",caption="You are not authorized to do this. This has been reported to " .. Player.PlayerData.job.label .. " and government."}, "error", 15000)
        end
    else
        local playerJob = '%' .. Player.PlayerData.job.name .. '%'
        local result = exports.oxmysql:scalarSync('SELECT job FROM players WHERE citizenid = ? AND job LIKE ?', {target, playerJob})
        if result then
            jobFinal = checkJob('unemployed', 0)
            if jobFinal ~= false then
                exports.oxmysql:execute('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(jobFinal), target })
                TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Fired Employee', 'red', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' fired ('.. target .. ') at (' .. Player.PlayerData.job.name .. ')', false)
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu",caption="You have fired your employee. We will be sending the records to " .. Player.PlayerData.job.label .. " and government."}, "error", 5000)
            else
                TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="Something failed. Did you try turning it off and on again?"}, "error")
            end
        else
            TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="This person is not on your payroll."}, "error", 4000)
        end




    end
end)

-- Recruit Player
RegisterServerEvent('qb-bossmenu:server:giveJob')
AddEventHandler('qb-bossmenu:server:giveJob', function(recruit)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local Target = QBCore.Functions.GetPlayer(recruit)
    if Player.PlayerData.job.isboss == true and (Target.PlayerData.job.name == 'unemployed' or Target.PlayerData.job.name == 'garbage' or Target.PlayerData.job.name == 'taxi' or Target.PlayerData.job.name == 'reporter' or Target.PlayerData.job.name == 'trucker' or Target.PlayerData.job.name == 'tow' or Target.PlayerData.job.name == 'vineyard' or Target.PlayerData.job.name == 'hotdog' or Target.PlayerData.job.name == nil) then
        if Target and Target.Functions.SetJob(Player.PlayerData.job.name, 0) then
            TriggerClientEvent('QBCore:Notify', src, {text="Boss Menu", caption="You Recruited " .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) .. " To " .. Player.PlayerData.job.label .. ""}, "success")
            TriggerClientEvent('QBCore:Notify', Target.PlayerData.source , {text="Boss Menu", caption="You've Been Recruited To " .. Player.PlayerData.job.label .. "!"}, "success")
            TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Recruit', 'yellow', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' successfully recruited ' .. Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname .. ' (' .. Player.PlayerData.job.name .. ')', false)
        end
    end
end)

-- Functions
function checkJob(jobName, grade)
    job = {}
    grade = tostring(grade) or '0'
    if QBCore.Shared.Jobs[jobName] then
        job.name = jobName
        job.label = QBCore.Shared.Jobs[jobName].label
        job.onduty = QBCore.Shared.Jobs[jobName].defaultDuty
            if QBCore.Shared.Jobs[jobName].grades[grade] then
                local jobgrade = QBCore.Shared.Jobs[jobName].grades[grade]
                job.grade = {}
                job.grade.name = jobgrade.name
                job.grade.level = tonumber(grade)
                job.payment = jobgrade.payment or 30
                job.isboss = jobgrade.isboss or false
            else
                job.grade = {}
                job.grade.name = 'Invalid Grade'
                job.grade.level = 0
                job.payment = 30
                job.isboss = false
            end
        return job
    end
    return false
end
