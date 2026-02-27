--[[
╔══════════════════════════════════════════════════════╗
║          JinHub v3 — Garden Horizons                 ║
║       SCRIPT NG MGA TANGA  ★  God Jin               ║
╠══════════════════════════════════════════════════════╣
║  UI: Rayfield (all tabs visible, resizable)          ║
║  Anti-Detection: Jitter delays, rate limiter,        ║
║                  teleport noise, batch firing        ║
║  VALUE FORMULA (wiki-accurate):                      ║
║  Final = Base × Weight² × Ripening × (Mut+Variant)  ║
║  Starstruck 6.5× | Meteoric 10× | Gold ×5           ║
╚══════════════════════════════════════════════════════╝
]]

-- ══════════════════════════════════
-- SERVICES
-- ══════════════════════════════════
local HttpService      = game:GetService("HttpService")
local Players          = game:GetService("Players")
local VirtualUser      = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

-- ══════════════════════════════════
-- ANTI-DETECTION
-- ══════════════════════════════════
local AntiDetectMode = "Normal" -- Conservative | Normal | Aggressive

local RATE = {Conservative={max=8,base=0.15},Normal={max=14,base=0.07},Aggressive={max=20,base=0.03}}

local function SmartWait(base, var)
    var = var or base * 0.3
    local m = RATE[AntiDetectMode] or RATE.Normal
    local j = (math.random()-0.5)*2*var
    task.wait(math.max(m.base, base+j))
end

local _rc, _rw = 0, os.clock()
local function RateLim()
    if os.clock()-_rw >= 1 then _rc=0; _rw=os.clock() end
    _rc += 1
    local m = RATE[AntiDetectMode] or RATE.Normal
    if _rc > m.max then task.wait(0.06) end
end

local function SafeFire(r, ...)
    if not r then return end
    RateLim(); pcall(r.FireServer, r, ...)
end
local function SafeInvoke(r, ...)
    if not r then return nil end
    RateLim()
    local ok, v = pcall(r.InvokeServer, r, ...)
    return ok and v or nil
end

local function SmartTP(hrp, cf)
    if not hrp then return end
    local noise = CFrame.new((math.random()-.5)*.6, 0, (math.random()-.5)*.6)
    hrp.CFrame = cf * noise
    SmartWait(0.32, 0.07)
end

-- ══════════════════════════════════
-- MUTATION/VALUE DATA (wiki-accurate)
-- ══════════════════════════════════
local MUT = {
    -- Weather mutations (additive to mutation sum)
    Soaked=1.2, Flooded=1.5, Foggy=1.2, Misty=1.2,
    Chilled=1.5, Snowy=2.0, Sandy=2.5,
    Shocked=4.5, Starstruck=6.5, Meteoric=10.0,
    Galactic=3.0, Stormy=3.5, Tidal=3.0,
    Frostbit=3.5, Muddy=5.0, Mossy=3.5,
    -- Variants (multiplicative)
    Gold=5.0, Silver=2.0,
    -- Ripening (multiplicative)
    Lush=3.0, Ripened=2.0, Unripe=1.0,
}
-- Value = Base × Ripening × (MutSum + VariantBonus)
local function CalcValue(basePrice, ripe, var, muts, weightKg)
    local rM = MUT[ripe] or 1
    local vB = MUT[var]  or 0
    local mSum = 0
    if type(muts)=="table" then
        for _,m in ipairs(muts) do mSum += (MUT[m] or 0) end
    end
    local wMult = weightKg and (weightKg^0.5) or 1
    return math.floor(basePrice * rM * (math.max(1,mSum) + vB) * wMult)
end

local ALL_MUT  = {"Any","None","Meteoric","Starstruck","Muddy","Shocked",
                  "Frostbit","Mossy","Stormy","Tidal","Galactic",
                  "Sandy","Snowy","Chilled","Flooded","Soaked","Foggy","Misty"}
local ALL_VAR  = {"Any","None","Gold","Silver"}
local ALL_RIPE = {"Any","Lush","Ripened","Unripe"}
local ALL_WEA  = {"Any","Clear","Rain","Storm","Sandstorm","Snow","Fog","Starfall","Meteor","Night"}

-- ══════════════════════════════════
-- CONFIG SYSTEM
-- ══════════════════════════════════
local CF="JinHub_Data"; local CFG=CF.."/Settings.json"
if isfolder and not isfolder(CF) then makefolder(CF) end

local DEF = {
    WalkSpeed=16, JumpPower=50, AntiAFK=true, AutoSave=false, AutoLoad=false,
    AntiDetect="Normal", FlyEnabled=false, FlySpeed=50, Noclip=false,
    -- Harvest
    HarvestRipeness={"Any"}, HarvestMutation={"Any"},
    HarvestVariant={"Any"}, HarvestWeather={"Any"}, AutoHarvest=false,
    -- Shovel
    ShovelMode="Remove Junk",
    ShovelKeepRipeness={"Lush"}, ShovelKeepVariant={"Gold","Silver"},
    ShovelKeepMutation={"Any"}, ShovelMinKg="0", ShovelMaxKg="999",
    AutoShovelFruit=false, AutoShovelTree=false,
    -- Farm
    AutoWater=false, AutoSprinkler=false,
    SeedSelect={"Carrot"}, PlantMode="Random",
    CustomPlantX="0", CustomPlantZ="0", AutoPlant=false,
    AutoGrowAll=false, AutoFavorite=false,
    -- Sell
    AutoSellDelay="10", AutoSell=false,
    ForceSellOnFull=true, BackpackFullThresh="35",
    -- Shop
    BuyMode="Buy Best Seed", TargetBuySeed={"Carrot Seed"}, AutoBuySeeds=false,
    TargetBuyGear={"Watering Can"}, AutoBuyGears=false,
    AutoBuyBestSeed=false, AutoBuyBestGear=false,
    -- Quest/Codes
    AutoQuest=false, RedeemCodes={}, AutoRedeem=false,
    -- ESP
    PlantESP=false, ESPShowMult=true, RareMutNotify=true,
    WeatherNotify=true,
    -- Stats
    TotalHarvested=0, TotalEstEarned=0,
}

local JC = {}
local function LoadCFG()
    if isfile and isfile(CFG) then
        local ok,d=pcall(HttpService.JSONDecode,HttpService,readfile(CFG))
        if ok and type(d)=="table" then
            for k,v in pairs(DEF) do if d[k]==nil then d[k]=v end end
            return d
        end
    end
    return DEF
end
local saved=LoadCFG()
JC = saved.AutoLoad and saved or DEF
JC.AutoLoad=saved.AutoLoad; JC.AutoSave=saved.AutoSave

local function Save()
    if writefile then
        local ok,s=pcall(HttpService.JSONEncode,HttpService,JC)
        if ok then writefile(CFG,s) end
    end
end
local function CS() if JC.AutoSave then Save() end end

-- ══════════════════════════════════
-- GAME REFERENCES
-- ══════════════════════════════════
local RE = ReplicatedStorage:WaitForChild("RemoteEvents",15)
local function WR(n) return RE and (RE:FindFirstChild(n)) or nil end

local rHarvest  = WR("HarvestFruit")
local rPlant    = WR("PlantSeed")
local rPurchase = WR("PurchaseShopItem")
local rSell     = WR("SellItems")
local rWater    = WR("WaterPlant")
local rShovel   = WR("ShovelPlant") or WR("RemovePlant") or WR("DeletePlant")
local rSprinkler= WR("UseSprinkler") or WR("ActivateSprinkler")
local rRedeem   = WR("RedeemCode")  or WR("UseCode")
local rGrowAll  = WR("GrowAll")     or WR("InstantGrow")
local rFavorite = WR("FavoritePlant") or WR("UseFavoriteTool")

local clientPlants = workspace:WaitForChild("ClientPlants",15)
local plotsFolder  = workspace:WaitForChild("Plots",15)

-- Weather detection
local _lastWeather = "Any"
local function GetWeather()
    for _,p in ipairs({workspace,ReplicatedStorage}) do
        for _,n in ipairs({"Weather","WeatherSystem","GameManager","WeatherData"}) do
            local obj=p:FindFirstChild(n)
            if obj then
                local a=obj:GetAttribute("CurrentWeather") or obj:GetAttribute("Weather") or obj:GetAttribute("ActiveWeather")
                if a then return tostring(a) end
            end
        end
    end
    return "Any"
end

-- ══════════════════════════════════
-- SEED / GEAR DATA
-- ══════════════════════════════════
local SEEDS={
    {N="Carrot Seed",   K="Carrot",     P=20,      O=10,  Base=30},
    {N="Corn Seed",     K="Corn",       P=100,     O=20,  Base=50},
    {N="Onion Seed",    K="Onion",      P=200,     O=30,  Base=75},
    {N="Strawberry Seed",K="Strawberry",P=800,     O=40,  Base=150},
    {N="Mushroom Seed", K="Mushroom",   P=1500,    O=50,  Base=300},
    {N="Beetroot Seed", K="Beetroot",   P=2500,    O=60,  Base=500},
    {N="Tomato Seed",   K="Tomato",     P=4000,    O=70,  Base=800},
    {N="Apple Seed",    K="Apple",      P=7000,    O=80,  Base=1500},
    {N="Rose Seed",     K="Rose",       P=10000,   O=90,  Base=2000},
    {N="Wheat Seed",    K="Wheat",      P=12000,   O=100, Base=2500},
    {N="Banana Seed",   K="Banana",     P=30000,   O=110, Base=5000},
    {N="Plum Seed",     K="Plum",       P=60000,   O=120, Base=10000},
    {N="Potato Seed",   K="Potato",     P=100000,  O=130, Base=15000},
    {N="Cabbage Seed",  K="Cabbage",    P=150000,  O=140, Base=25000},
    {N="Cherry Seed",   K="Cherry",     P=1000000, O=150, Base=50000},
}
local GEARS={
    {N="Watering Can",   P=5000,  O=10},
    {N="Basic Sprinkler",P=15000, O=20},
    {N="Harvest Bell",   P=35000, O=30},
    {N="Turbo Sprinkler",P=60000, O=40},
    {N="Favorite Tool",  P=80000, O=45},
    {N="Super Sprinkler",P=100000,O=50},
}
table.sort(SEEDS,function(a,b)return a.O<b.O end)
table.sort(GEARS,function(a,b)return a.O<b.O end)
local seedDDL,gearDDL={},{}
for _,d in ipairs(SEEDS) do table.insert(seedDDL,d.N) end
for _,d in ipairs(GEARS) do table.insert(gearDDL,d.N) end

local plantSeeds={}
local mf=ReplicatedStorage:FindFirstChild("Plants") and ReplicatedStorage.Plants:FindFirstChild("Models")
if mf then for _,m in ipairs(mf:GetChildren()) do table.insert(plantSeeds,m.Name) end
else plantSeeds={"Carrot","Corn","Tomato","Mushroom","Strawberry","Beetroot","Apple","Rose","Wheat","Banana","Plum","Potato","Cabbage","Cherry"} end
table.sort(plantSeeds)

-- ══════════════════════════════════
-- HELPERS
-- ══════════════════════════════════
local function ToSet(t)
    if type(t)=="string" then return{[t]=true}end
    if type(t)=="table" then
        if t[1] then local s={} for _,v in ipairs(t) do s[v]=true end return s end
        return t
    end
    return{}
end
local function GetMyPlot()
    if not plotsFolder then return end
    for _,p in ipairs(plotsFolder:GetChildren()) do
        local id=p:GetAttribute("Owner") or p:GetAttribute("OwnerUserId")
        if not id and p:FindFirstChild("Owner") then id=p.Owner.Value end
        if id and tonumber(id)==LocalPlayer.UserId then return p end
    end
end
local function HRP() return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") end
local function HUM() return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") end
local function Shillings() local ls=LocalPlayer:FindFirstChild("leaderstats"); return ls and ls:FindFirstChild("Shillings") end
local function BPCount()
    local n=0
    local bp=LocalPlayer:FindFirstChild("Backpack")
    local ch=LocalPlayer.Character
    if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then n+=1 end end end
    if ch then for _,v in ipairs(ch:GetChildren()) do if v:IsA("Tool") then n+=1 end end end
    return n
end
local function RandInPart(p)
    local s=p.Size
    return p.CFrame:PointToWorldSpace(Vector3.new((math.random()-.5)*s.X, s.Y/2, (math.random()-.5)*s.Z))
end
local function GetFruitMuts(obj)
    local raw=obj:GetAttribute("Mutations") or obj:GetAttribute("MutationList")
    if raw then
        local t={} for m in tostring(raw):gmatch("[^,]+") do table.insert(t,m:match("^%s*(.-)%s*$")) end return t
    end
    return {obj:GetAttribute("Mutation") or "None"}
end
local function SeedStock(key)
    local gui=LocalPlayer:FindFirstChild("PlayerGui")
    local base=gui and gui:FindFirstChild("SeedShop") and gui.SeedShop:FindFirstChild("Frame")
        and gui.SeedShop.Frame:FindFirstChild("ScrollingFrame")
        and gui.SeedShop.Frame.ScrollingFrame:FindFirstChild(key)
    local st=base and base:FindFirstChild("MainInfo") and base.MainInfo:FindFirstChild("StockText")
    if st then
        if st.Text:upper()=="NO STOCK" then return 0 end
        return tonumber(st.Text:match("%d+")) or 0
    end
    return 99
end
local function GearStock(name)
    local gui=LocalPlayer:FindFirstChild("PlayerGui")
    local base=gui and gui:FindFirstChild("GearShop") and gui.GearShop:FindFirstChild("Frame")
        and gui.GearShop.Frame:FindFirstChild("ScrollingFrame")
        and gui.GearShop.Frame.ScrollingFrame:FindFirstChild(name)
    local st=base and base:FindFirstChild("MainInfo") and base.MainInfo:FindFirstChild("StockText")
    if st then
        if st.Text:upper()=="NO STOCK" then return 0 end
        return tonumber(st.Text:match("%d+")) or 0
    end
    return 99
end
local function FindShop(name)
    local shops=workspace:FindFirstChild("MapPhysical") and workspace.MapPhysical:FindFirstChild("Shops")
    if shops then local s=shops:FindFirstChild(name) if s then return s end end
    for _,c in ipairs(workspace:GetDescendants()) do
        if c.Name==name and (c:IsA("Model") or c:IsA("BasePart")) then return c end
    end
end
local function TPToShop(name)
    local hrp=HRP(); if not hrp then return false end
    local stand=FindShop(name)
    if stand then SmartTP(hrp, stand:IsA("Model") and stand:GetPivot() or stand.CFrame); return true end
    return false
end

-- ══════════════════════════════════
-- TASK MANAGER
-- ══════════════════════════════════
local Tasks={}
local function StartTask(name,fn,interval,var)
    if Tasks[name] then return end
    Tasks[name]=true
    task.spawn(function()
        while Tasks[name] do pcall(fn); SmartWait(interval,var or interval*.2) end
    end)
end
local function StopTask(name) Tasks[name]=nil end

-- ══════════════════════════════════
-- STATS TRACKER
-- ══════════════════════════════════
local Stats={harvested=0, estimated=0, shoveled=0, planted=0, sold=0}

-- ══════════════════════════════════
-- ★ INSTANT BATCH HARVEST
-- Collect all UUIDs → TP to plot center ONCE
-- → fire all events in rapid bursts of 10
-- ══════════════════════════════════
local function DoAutoHarvest()
    if not rHarvest then return end
    local ripS=ToSet(JC.HarvestRipeness)
    local mutS=ToSet(JC.HarvestMutation)
    local varS=ToSet(JC.HarvestVariant)
    local wetS=ToSet(JC.HarvestWeather)
    local weather=GetWeather()
    if not(wetS["Any"] or wetS[weather]) then return end

    local payloads={}
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local fruits={}
        for _,c in ipairs(plant:GetChildren()) do
            if c.Name:lower():find("fruit") then table.insert(fruits,c) end
        end
        local processObj=function(obj,uuid)
            local ripe=obj:GetAttribute("RipenessStage") or "Unripe"
            local var =obj:GetAttribute("Variant")       or "None"
            local muts=GetFruitMuts(obj)
            local idx =obj:GetAttribute("GrowthAnchorIndex")
            if not(ripS["Any"] or ripS[ripe]) then return end
            if not(varS["Any"] or varS[var])  then return end
            local mp=mutS["Any"]
            if not mp then for _,m in ipairs(muts) do if mutS[m] then mp=true break end end end
            if not mp then return end
            local pl={Uuid=uuid}; if idx then pl.GrowthAnchorIndex=idx end
            table.insert(payloads,pl)
            Stats.harvested+=1
            -- Rare mutation notifier
            if JC.RareMutNotify then
                for _,m in ipairs(muts) do
                    if (MUT[m] or 0)>=4.5 then
                        task.spawn(function()
                            if _Rayfield then
                                _Rayfield:Notify({
                                    Title="🔥 RARE MUTATION!",
                                    Content=m.." detected on "..plant.Name,
                                    Duration=5
                                })
                            end
                        end)
                    end
                end
            end
        end
        if #fruits>0 then
            local uuid=plant:GetAttribute("Uuid") or plant:GetAttribute("UUID")
            if uuid then for _,f in ipairs(fruits) do processObj(f,uuid) end end
        else
            local uuid=plant:GetAttribute("Uuid") or plant:GetAttribute("UUID")
            if uuid then processObj(plant,uuid) end
        end
    end
    if #payloads==0 then return end

    -- TP to plot center once
    local hrp=HRP(); local savedCF=hrp and hrp.CFrame
    local myPlot=GetMyPlot()
    if hrp and myPlot then
        local cf=myPlot:IsA("Model") and myPlot:GetPivot()
            or (myPlot:FindFirstChildWhichIsA("BasePart") and myPlot:FindFirstChildWhichIsA("BasePart").CFrame)
        if cf then SmartTP(hrp,cf) end
    end

    -- Batch fire
    for i=1,#payloads,10 do
        local chunk={}
        for j=i,math.min(i+9,#payloads) do table.insert(chunk,payloads[j]) end
        SafeFire(rHarvest,chunk)
        SmartWait(0.03,0.01)
    end

    -- Return
    if hrp and savedCF then
        task.delay(0.4,function() if hrp and hrp.Parent then hrp.CFrame=savedCF end end)
    end
end

-- ══════════════════════════════════
-- ★ SMART SHOVEL FRUIT (5 filters)
-- ══════════════════════════════════
local function FruitKeep(obj)
    local mode=JC.ShovelMode or "Remove Junk"
    if mode=="Remove All" then return false end
    local weight=tonumber(obj:GetAttribute("Weight") or obj:GetAttribute("Kg") or obj:GetAttribute("Size")) or 0
    local minKg=tonumber(JC.ShovelMinKg) or 0
    local maxKg=tonumber(JC.ShovelMaxKg) or 999
    if weight>0 and weight<minKg then return false end
    if maxKg>0 and weight>maxKg  then return true  end
    local ripe=obj:GetAttribute("RipenessStage") or "Unripe"
    local var =obj:GetAttribute("Variant")       or "None"
    local muts=GetFruitMuts(obj)
    if mode=="Keep Valuable" then
        if var=="Gold" then return true end
        if ripe=="Lush" then return true end
        for _,m in ipairs(muts) do if(MUT[m] or 0)>=3 then return true end end
        return false
    end
    local kR=ToSet(JC.ShovelKeepRipeness)
    local kV=ToSet(JC.ShovelKeepVariant)
    local kM=ToSet(JC.ShovelKeepMutation)
    if not(kR["Any"] or kR[ripe]) then return false end
    if not(kV["Any"] or kV[var])  then return false end
    local mp=kM["Any"]
    if not mp then
        for _,m in ipairs(muts) do if kM[m] then mp=true break end end
        if not mp and muts[1]=="None" and kM["None"] then mp=true end
    end
    return mp
end

local function DoAutoShovelFruit()
    if not rShovel then return end
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local uuid=plant:GetAttribute("Uuid") or plant:GetAttribute("UUID")
        if not uuid then continue end
        local fruits={}
        for _,c in ipairs(plant:GetChildren()) do
            if c.Name:lower():find("fruit") then table.insert(fruits,c) end
        end
        if #fruits>0 then
            for _,f in ipairs(fruits) do
                if not FruitKeep(f) then
                    local idx=f:GetAttribute("GrowthAnchorIndex")
                    local pl={Uuid=uuid,Type="Fruit"}
                    if idx then pl.GrowthAnchorIndex=idx end
                    SafeInvoke(rShovel,pl); SmartWait(0.07,0.02); Stats.shoveled+=1
                end
            end
        else
            if not FruitKeep(plant) then
                SafeInvoke(rShovel,{Uuid=uuid,Type="Fruit"}); SmartWait(0.07,0.02); Stats.shoveled+=1
            end
        end
    end
end

local function DoAutoShovelTree()
    if not rShovel then return end
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local uuid=plant:GetAttribute("Uuid") or plant:GetAttribute("UUID")
        local dead=plant:GetAttribute("IsDead") or plant:GetAttribute("Dead")
            or plant:GetAttribute("Finished") or plant:GetAttribute("FullyGrown")
        if uuid and dead then
            SafeInvoke(rShovel,{Uuid=uuid,Type="Tree"}); SmartWait(0.1,0.03)
        end
    end
end

-- ══════════════════════════════════
-- WATER / SPRINKLER
-- ══════════════════════════════════
local function DoAutoWater()
    if not rWater then return end
    for _,p in ipairs(clientPlants:GetChildren()) do
        local uuid=p:GetAttribute("Uuid") or p:GetAttribute("UUID")
        local thirsty=p:GetAttribute("NeedsWater") or p:GetAttribute("Thirsty")
        if uuid and thirsty then SafeFire(rWater,{Uuid=uuid}); SmartWait(0.1,0.03) end
    end
end
local function DoAutoSprinkler()
    if not rSprinkler then return end
    local myPlot=GetMyPlot()
    if myPlot then SafeFire(rSprinkler,{PlotId=myPlot:GetAttribute("PlotId") or myPlot.Name}) end
end

-- ══════════════════════════════════
-- AUTO GROW ALL
-- ══════════════════════════════════
local function DoAutoGrowAll()
    if not rGrowAll then return end
    local myPlot=GetMyPlot()
    if myPlot then SafeInvoke(rGrowAll,{PlotId=myPlot:GetAttribute("PlotId") or myPlot.Name}) end
end

-- ══════════════════════════════════
-- AUTO FAVORITE (uses Favorite Tool
-- on Gold/Meteoric/Starstruck plants)
-- ══════════════════════════════════
local function DoAutoFavorite()
    if not rFavorite then return end
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local uuid=plant:GetAttribute("Uuid") or plant:GetAttribute("UUID")
        if not uuid then continue end
        local var=plant:GetAttribute("Variant") or "None"
        local muts=GetFruitMuts(plant)
        local isValuable=var=="Gold"
        if not isValuable then
            for _,m in ipairs(muts) do if(MUT[m] or 0)>=6 then isValuable=true break end end
        end
        if isValuable then
            SafeInvoke(rFavorite,{Uuid=uuid}); SmartWait(0.2,0.05)
        end
    end
end

-- ══════════════════════════════════
-- AUTO PLANT
-- ══════════════════════════════════
local function DoAutoPlant()
    local ss=ToSet(JC.SeedSelect); local seeds={}
    for k,v in pairs(ss) do if v then table.insert(seeds,k) end end
    if #seeds==0 then return end
    local seedName=seeds[math.random(1,#seeds)]
    local char=LocalPlayer.Character
    local human=char and char:FindFirstChild("Humanoid")
    local bp=LocalPlayer:FindFirstChild("Backpack")
    local kw=seedName.." Seed"; local tool=nil
    if char then
        for _,c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") and c.Name:find(kw) then tool=c break end
        end
    end
    if not tool and bp and human then
        for _,c in ipairs(bp:GetChildren()) do
            if c:IsA("Tool") and c.Name:find(kw) then
                human:EquipTool(c); SmartWait(0.2,0.05); tool=c; break
            end
        end
    end
    if not tool then return end
    local pos; local mode=JC.PlantMode
    if mode=="Player Position" then
        local hrp=HRP(); if hrp then pos=hrp.Position end
    elseif mode=="Custom Position" then
        pos=Vector3.new(tonumber(JC.CustomPlantX) or 0, 0, tonumber(JC.CustomPlantZ) or 0)
    else
        local myPlot=GetMyPlot()
        if myPlot and myPlot:FindFirstChild("PlantableArea") then
            local parts={}
            for _,p in ipairs(myPlot.PlantableArea:GetChildren()) do if p:IsA("BasePart") then table.insert(parts,p) end end
            if #parts>0 then pos=RandInPart(parts[math.random(1,#parts)]) end
        end
    end
    if pos then SafeInvoke(rPlant,seedName,pos); Stats.planted+=1 end
end

-- ══════════════════════════════════
-- ★ INSTANT SELL (always TPs)
-- ══════════════════════════════════
local function DoAutoSell(force)
    if not rSell then return end
    if not force then
        if JC.ForceSellOnFull and BPCount()>=(tonumber(JC.BackpackFullThresh) or 35) then force=true end
    end
    local hrp=HRP(); local savedCF=hrp and hrp.CFrame
    -- Try all sell stand name variants
    for _,name in ipairs({"Sell Stand","SellStand","Sell_Stand","ShopSell","Sell Shop","SellShop","Merchant"}) do
        local stand=FindShop(name)
        if stand and hrp then SmartTP(hrp,stand:IsA("Model") and stand:GetPivot() or stand.CFrame); break end
    end
    SafeInvoke(rSell,"SellAll"); Stats.sold+=1; SmartWait(0.35,0.08)
    if hrp and savedCF then
        task.delay(0.5,function() if hrp and hrp.Parent then hrp.CFrame=savedCF end end)
    end
end

-- ══════════════════════════════════
-- AUTO BUY SEEDS / GEARS
-- ══════════════════════════════════
local function DoAutoBuySeeds()
    local sh=Shillings(); if not sh then return end
    local didTP=false
    if JC.AutoBuyBestSeed or JC.BuyMode=="Buy Best Seed" then
        for i=#SEEDS,1,-1 do
            local d=SEEDS[i]
            if sh.Value>=d.P and SeedStock(d.K)>0 then
                if not didTP then didTP=TPToShop("Seed Shop") end
                local b=0
                while JC.AutoBuySeeds and sh.Value>=d.P and SeedStock(d.K)>0 and b<10 do
                    SafeInvoke(rPurchase,"SeedShop",d.N); SmartWait(0.12,0.03); b+=1
                end
                break
            end
        end
    else
        local sel=ToSet(JC.TargetBuySeed)
        for sN,on in pairs(sel) do
            if not on then continue end
            local price,key=0,""
            for _,d in ipairs(SEEDS) do if d.N==sN then price=d.P; key=d.K; break end end
            if sh.Value>=price and SeedStock(key)>0 then
                if not didTP then didTP=TPToShop("Seed Shop") end
                local b=0
                while JC.AutoBuySeeds and sh.Value>=price and SeedStock(key)>0 and b<10 do
                    SafeInvoke(rPurchase,"SeedShop",sN); SmartWait(0.12,0.03); b+=1
                end
            end
            if not JC.AutoBuySeeds then break end
        end
    end
end

local function DoAutoBuyGears()
    local sh=Shillings(); if not sh then return end
    local didTP=false
    if JC.AutoBuyBestGear then
        for i=#GEARS,1,-1 do
            local d=GEARS[i]
            if sh.Value>=d.P and GearStock(d.N)>0 then
                if not didTP then didTP=TPToShop("Gear Shop") end
                SafeInvoke(rPurchase,"GearShop",d.N); SmartWait(0.2,0.05); break
            end
        end
    else
        local sel=ToSet(JC.TargetBuyGear)
        for gN,on in pairs(sel) do
            if not on then continue end
            local price=0
            for _,d in ipairs(GEARS) do if d.N==gN then price=d.P break end end
            if sh.Value>=price and GearStock(gN)>0 then
                if not didTP then didTP=TPToShop("Gear Shop") end
                local b=0
                while JC.AutoBuyGears and sh.Value>=price and GearStock(gN)>0 and b<5 do
                    SafeInvoke(rPurchase,"GearShop",gN); SmartWait(0.15,0.04); b+=1
                end
            end
            if not JC.AutoBuyGears then break end
        end
    end
end

-- ══════════════════════════════════
-- REDEEM / QUEST
-- ══════════════════════════════════
local function DoAutoRedeem()
    if not rRedeem then return end
    for _,c in ipairs(JC.RedeemCodes or {}) do
        SafeInvoke(rRedeem,tostring(c)); SmartWait(0.6,0.15)
    end
end
local function DoAutoQuest()
    DoAutoBuySeeds(); SmartWait(0.5)
    DoAutoPlant(); SmartWait(1,0.3)
    DoAutoHarvest(); SmartWait(0.5)
    DoAutoSell(false)
end

-- ══════════════════════════════════
-- FLY / NOCLIP
-- ══════════════════════════════════
local flyConn, noclipConn
local bodyVel, bodyGyro

local function StartFly()
    local hrp=HRP(); local hum=HUM()
    if not hrp or not hum then return end
    hum.PlatformStand=true
    bodyVel=Instance.new("BodyVelocity"); bodyVel.Velocity=Vector3.zero
    bodyVel.MaxForce=Vector3.new(1e5,1e5,1e5); bodyVel.P=1e4; bodyVel.Parent=hrp
    bodyGyro=Instance.new("BodyGyro"); bodyGyro.MaxTorque=Vector3.new(4e5,4e5,4e5)
    bodyGyro.D=100; bodyGyro.Parent=hrp
    local cam=workspace.CurrentCamera
    flyConn=RunService.Heartbeat:Connect(function()
        local spd=JC.FlySpeed or 50
        local dir=Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then dir+=Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir-=Vector3.yAxis end
        if dir.Magnitude>0 then dir=dir.Unit end
        if bodyVel then bodyVel.Velocity=dir*spd end
        if bodyGyro then bodyGyro.CFrame=cam.CFrame end
    end)
end
local function StopFly()
    if flyConn then flyConn:Disconnect(); flyConn=nil end
    if bodyVel then bodyVel:Destroy(); bodyVel=nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro=nil end
    local hum=HUM(); if hum then hum.PlatformStand=false end
end
local function StartNoclip()
    noclipConn=RunService.Stepped:Connect(function()
        local char=LocalPlayer.Character
        if char then
            for _,p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide=false
                end
            end
        end
    end)
end
local function StopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    local char=LocalPlayer.Character
    if char then
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=true end
        end
    end
end

-- Re-apply on character respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    local h=HUM(); if h then h.WalkSpeed=JC.WalkSpeed; h.JumpPower=JC.JumpPower end
    if JC.FlyEnabled then StartFly() end
    if JC.Noclip then StartNoclip() end
end)

-- ══════════════════════════════════
-- PLANT ESP
-- ══════════════════════════════════
local ESPF=Instance.new("Folder"); ESPF.Name="JinHub_ESP"; ESPF.Parent=workspace
local RCLR={Lush=Color3.fromRGB(0,255,90),Ripened=Color3.fromRGB(255,210,0),Unripe=Color3.fromRGB(155,155,155)}
local VCLR={Gold=Color3.fromRGB(255,215,0),Silver=Color3.fromRGB(190,190,255),None=Color3.fromRGB(200,200,200)}

local function ClearESP() for _,v in ipairs(ESPF:GetChildren()) do v:Destroy() end end
local function DoPlantESP()
    ClearESP(); if not JC.PlantESP then return end
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local root=plant:FindFirstChild("HumanoidRootPart") or plant:FindFirstChildWhichIsA("BasePart")
        if not root then continue end
        local ripe =plant:GetAttribute("RipenessStage") or "Unripe"
        local var  =plant:GetAttribute("Variant")       or "None"
        local muts =GetFruitMuts(plant)
        local wgt  =tonumber(plant:GetAttribute("Weight") or plant:GetAttribute("Kg")) or 0
        local wStr =wgt>0 and string.format("%.2fkg",wgt) or "?kg"
        local mutStr=table.concat(muts,"+")

        local bb=Instance.new("BillboardGui")
        bb.Size=UDim2.new(0,160,0,65); bb.StudsOffset=Vector3.new(0,4.5,0)
        bb.AlwaysOnTop=true; bb.Adornee=root; bb.Parent=ESPF

        local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0)
        bg.BackgroundColor3=Color3.fromRGB(5,5,5); bg.BackgroundTransparency=0.3
        bg.BorderSizePixel=0; bg.Parent=bb
        local uc=Instance.new("UICorner",bg); uc.CornerRadius=UDim.new(0,6)

        -- Colored accent bar
        local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,1,0)
        bar.BackgroundColor3=VCLR[var] or RCLR[ripe] or Color3.new(1,1,1)
        bar.BorderSizePixel=0; bar.Parent=bg
        Instance.new("UICorner",bar).CornerRadius=UDim.new(0,6)

        local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-8,1,-4)
        lbl.Position=UDim2.new(0,6,0,2); lbl.BackgroundTransparency=1
        lbl.Font=Enum.Font.GothamBold; lbl.TextScaled=true
        lbl.TextColor3=VCLR[var] or RCLR[ripe] or Color3.new(1,1,1)

        -- Value estimate
        local valStr=""
        if JC.ESPShowMult then
            local mult=0
            for _,m in ipairs(muts) do mult+=(MUT[m] or 0) end
            local vB=MUT[var] or 0; local rM=MUT[ripe] or 1
            local est=math.floor(rM*(math.max(1,mult)+vB)*10)/10
            valStr=" [×"..est.."]"
        end

        lbl.Text=string.format("[%s] %s\n%s | %s%s",ripe,var,mutStr,wStr,valStr)
        lbl.Parent=bg
    end
end

-- ══════════════════════════════════
-- WEATHER WATCHER
-- ══════════════════════════════════
local function WeatherWatcher()
    local w=GetWeather()
    if w~=_lastWeather and JC.WeatherNotify then
        _lastWeather=w
        if _Rayfield then
            _Rayfield:Notify({
                Title="🌦 Weather Changed!",
                Content="Current weather: "..w,
                Duration=5
            })
        end
    end
end

-- ══════════════════════════════════
-- FORCE SELL WATCHER
-- ══════════════════════════════════
task.spawn(function()
    while true do
        SmartWait(3,0.5)
        if JC.ForceSellOnFull then
            if BPCount()>=(tonumber(JC.BackpackFullThresh) or 35) then
                pcall(DoAutoSell,true)
            end
        end
    end
end)

-- ══════════════════════════════════
-- LOAD RAYFIELD UI
-- ══════════════════════════════════
local Rayfield=loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
_Rayfield=Rayfield -- global ref for notifications from functions above

local Window=Rayfield:CreateWindow({
    Name            = "JinHub v3  ★  God Jin",
    LoadingTitle    = "SCRIPT NG MGA TANGA",
    LoadingSubtitle = "Pinakamagandang script sa Garden Horizons",
    Theme           = "Dark",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings   = true,
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "JinHub_Data",
        FileName   = "JinHub_v3"
    },
    Discord = { Enabled=false },
    KeySystem = false,
})

-- ══════════════════════════════════
-- TAB 1: 🌾 HARVEST
-- ══════════════════════════════════
local T1=Window:CreateTab("Harvest",4483362458)
T1:CreateSection("SCRIPT NG MGA TANGA — Harvest Settings")

T1:CreateParagraph({
    Title="How it works",
    Content="Instant batch harvest: TPs to your plot center ONCE, then fires ALL fruit harvest events in rapid batches of 10. Way faster than per-plant TP. Filters apply before collecting."
})

T1:CreateDropdown({
    Name="Ripeness Filter",Info="Which ripeness stages to harvest",
    Options=ALL_RIPE, CurrentOption=JC.HarvestRipeness,
    Flag="HarvestRipeness", MultipleOptions=true,
    Callback=function(v) JC.HarvestRipeness=v; CS() end
})
T1:CreateDropdown({
    Name="Required Mutation",Info="Only harvest fruits with these mutations (Any = all)",
    Options=ALL_MUT, CurrentOption=JC.HarvestMutation,
    Flag="HarvestMutation", MultipleOptions=true,
    Callback=function(v) JC.HarvestMutation=v; CS() end
})
T1:CreateDropdown({
    Name="Required Variant",Info="Gold/Silver/None or Any",
    Options=ALL_VAR, CurrentOption=JC.HarvestVariant,
    Flag="HarvestVariant", MultipleOptions=true,
    Callback=function(v) JC.HarvestVariant=v; CS() end
})
T1:CreateDropdown({
    Name="Weather Filter",Info="Only harvest during these weather conditions",
    Options=ALL_WEA, CurrentOption=JC.HarvestWeather,
    Flag="HarvestWeather", MultipleOptions=true,
    Callback=function(v) JC.HarvestWeather=v; CS() end
})
T1:CreateToggle({
    Name="Auto Harvest",Info="Continuously harvests using all filters above",
    CurrentValue=JC.AutoHarvest, Flag="AutoHarvest",
    Callback=function(v)
        JC.AutoHarvest=v; CS()
        if v then StartTask("harvest",DoAutoHarvest,0.8) else StopTask("harvest") end
    end
})
T1:CreateButton({
    Name="⚡ Harvest All NOW",Info="Instant one-shot harvest",
    Callback=function() task.spawn(DoAutoHarvest) end
})

-- ══════════════════════════════════
-- TAB 2: 🪛 SHOVEL
-- ══════════════════════════════════
local T2=Window:CreateTab("Shovel",4483362458)
T2:CreateSection("Smart Shovel Fruit — 5 Filters")
T2:CreateParagraph({
    Title="Modes Explained",
    Content="Remove Junk = shovel fruits NOT matching your keep-filters. Keep Valuable = auto-keep Gold/Lush/Mutation≥3×. Remove All = shovel everything no matter what."
})
T2:CreateDropdown({
    Name="Shovel Mode",Info="Choose how the shovel logic decides what to remove",
    Options={"Remove Junk","Keep Valuable","Remove All"},
    CurrentOption={JC.ShovelMode}, Flag="ShovelMode", MultipleOptions=false,
    Callback=function(v) JC.ShovelMode=v[1] or v; CS() end
})
T2:CreateSection("Keep Filters — fruits matching ALL of these are SAVED")
T2:CreateDropdown({
    Name="Keep Ripeness",Info="Save fruits with this ripeness (Lush recommended)",
    Options={"Any","Lush","Ripened","Unripe"},
    CurrentOption=JC.ShovelKeepRipeness, Flag="ShovelKeepRipeness", MultipleOptions=true,
    Callback=function(v) JC.ShovelKeepRipeness=v; CS() end
})
T2:CreateDropdown({
    Name="Keep Variant",Info="Save Gold/Silver by default, shovel Normal",
    Options={"Any","Gold","Silver","None"},
    CurrentOption=JC.ShovelKeepVariant, Flag="ShovelKeepVariant", MultipleOptions=true,
    Callback=function(v) JC.ShovelKeepVariant=v; CS() end
})
T2:CreateDropdown({
    Name="Keep Mutation",Info="Save fruits with these mutations",
    Options=ALL_MUT, CurrentOption=JC.ShovelKeepMutation,
    Flag="ShovelKeepMutation", MultipleOptions=true,
    Callback=function(v) JC.ShovelKeepMutation=v; CS() end
})
T2:CreateSection("Weight Gate (kg)")
T2:CreateInput({
    Name="Min Kg to Keep",Info="Fruits LIGHTER than this get shoveled. Set 0 to disable",
    PlaceholderText="0", NumbersOnly=true, Flag="ShovelMinKg",
    Callback=function(v) JC.ShovelMinKg=v; CS() end
})
T2:CreateInput({
    Name="Max Kg to Shovel",Info="Fruits HEAVIER than this are always kept. Set 999 to disable",
    PlaceholderText="999", NumbersOnly=true, Flag="ShovelMaxKg",
    Callback=function(v) JC.ShovelMaxKg=v; CS() end
})
T2:CreateSection("Auto Shovel")
T2:CreateToggle({
    Name="Auto Shovel Fruit",Info="Continuously removes junk fruits using your filters",
    CurrentValue=JC.AutoShovelFruit, Flag="AutoShovelFruit",
    Callback=function(v)
        JC.AutoShovelFruit=v; CS()
        if v then StartTask("shovelFruit",DoAutoShovelFruit,1.2) else StopTask("shovelFruit") end
    end
})
T2:CreateButton({Name="🪛 Shovel Fruits NOW",Callback=function()task.spawn(DoAutoShovelFruit)end})
T2:CreateToggle({
    Name="Auto Shovel Dead Trees",Info="Clears dead/finished trees from plot automatically",
    CurrentValue=JC.AutoShovelTree, Flag="AutoShovelTree",
    Callback=function(v)
        JC.AutoShovelTree=v; CS()
        if v then StartTask("shovelTree",DoAutoShovelTree,2) else StopTask("shovelTree") end
    end
})
T2:CreateButton({Name="🪛 Shovel Dead Trees NOW",Callback=function()task.spawn(DoAutoShovelTree)end})

-- ══════════════════════════════════
-- TAB 3: 🌱 PLANT
-- ══════════════════════════════════
local T3=Window:CreateTab("Plant",4483362458)
T3:CreateSection("Auto Plant Settings")
T3:CreateDropdown({
    Name="Seeds to Plant",Info="Which seeds to auto-plant (picks randomly if multiple)",
    Options=plantSeeds, CurrentOption=JC.SeedSelect,
    Flag="SeedSelect", MultipleOptions=true,
    Callback=function(v) JC.SeedSelect=v; CS() end
})
T3:CreateDropdown({
    Name="Plant Mode",Info="Where to place seeds",
    Options={"Random","Player Position","Custom Position"},
    CurrentOption={JC.PlantMode}, Flag="PlantMode", MultipleOptions=false,
    Callback=function(v) JC.PlantMode=v[1] or v; CS() end
})
T3:CreateSection("Custom Position")
T3:CreateInput({
    Name="Custom X",PlaceholderText="0",NumbersOnly=true,Flag="CustomPlantX",
    Callback=function(v) JC.CustomPlantX=v; CS() end
})
T3:CreateInput({
    Name="Custom Z",PlaceholderText="0",NumbersOnly=true,Flag="CustomPlantZ",
    Callback=function(v) JC.CustomPlantZ=v; CS() end
})
T3:CreateButton({
    Name="📍 Capture My Current Position",
    Info="Saves your current X/Z and switches mode to Custom",
    Callback=function()
        local hrp=HRP()
        if hrp then
            JC.CustomPlantX=tostring(math.floor(hrp.Position.X))
            JC.CustomPlantZ=tostring(math.floor(hrp.Position.Z))
            JC.PlantMode="Custom Position"; CS()
            Rayfield:Notify({Title="Position Saved",Content="X="..JC.CustomPlantX.."  Z="..JC.CustomPlantZ,Duration=3})
        end
    end
})
T3:CreateToggle({
    Name="Auto Plant",Info="Continuously plants seeds on your plot",
    CurrentValue=JC.AutoPlant, Flag="AutoPlant",
    Callback=function(v)
        JC.AutoPlant=v; CS()
        if v then StartTask("plant",DoAutoPlant,0.45) else StopTask("plant") end
    end
})
T3:CreateButton({Name="🌱 Plant Once NOW",Callback=function()task.spawn(DoAutoPlant)end})

T3:CreateSection("Grow All / Auto Favorite")
T3:CreateToggle({
    Name="Auto Grow All",Info="Instantly grows all plants on your plot (if Grow All is available)",
    CurrentValue=JC.AutoGrowAll, Flag="AutoGrowAll",
    Callback=function(v)
        JC.AutoGrowAll=v; CS()
        if v then StartTask("growAll",DoAutoGrowAll,5) else StopTask("growAll") end
    end
})
T3:CreateButton({Name="⚡ Grow All NOW",Callback=function()task.spawn(DoAutoGrowAll)end})
T3:CreateToggle({
    Name="Auto Favorite Tool",Info="Auto-uses Favorite Tool on Gold/Starstruck/Meteoric plants",
    CurrentValue=JC.AutoFavorite, Flag="AutoFavorite",
    Callback=function(v)
        JC.AutoFavorite=v; CS()
        if v then StartTask("favorite",DoAutoFavorite,3) else StopTask("favorite") end
    end
})

-- ══════════════════════════════════
-- TAB 4: 💧 WATER & SPRINKLER
-- ══════════════════════════════════
local T4=Window:CreateTab("Water",4483362458)
T4:CreateSection("Auto Water")
T4:CreateParagraph({
    Title="Sprinkler Strategy (wiki)",
    Content="Stack Basic + Turbo + Super Sprinklers in overlapping range for max fruit size. Different types stack! Same type does NOT stack. Best combo = one of each type."
})
T4:CreateToggle({
    Name="Auto Water Plants",Info="Automatically waters thirsty plants",
    CurrentValue=JC.AutoWater, Flag="AutoWater",
    Callback=function(v)
        JC.AutoWater=v; CS()
        if v then StartTask("water",DoAutoWater,2) else StopTask("water") end
    end
})
T4:CreateButton({Name="💧 Water All NOW",Callback=function()task.spawn(DoAutoWater)end})
T4:CreateSection("Auto Sprinkler")
T4:CreateToggle({
    Name="Auto Sprinkler",Info="Activates sprinkler on your plot automatically",
    CurrentValue=JC.AutoSprinkler, Flag="AutoSprinkler",
    Callback=function(v)
        JC.AutoSprinkler=v; CS()
        if v then StartTask("sprinkler",DoAutoSprinkler,5) else StopTask("sprinkler") end
    end
})
T4:CreateButton({Name="🌊 Use Sprinkler NOW",Callback=function()task.spawn(DoAutoSprinkler)end})

-- ══════════════════════════════════
-- TAB 5: 💰 SELL
-- ══════════════════════════════════
local T5=Window:CreateTab("Sell",4483362458)
T5:CreateSection("Auto Sell (Always TPs to Sell Stand)")
T5:CreateParagraph({
    Title="How Sell Works",
    Content="Always teleports to the Sell Stand before firing the sell event. Tries multiple name variants of the stand. Returns you after selling."
})
T5:CreateInput({
    Name="Sell Delay (seconds)",PlaceholderText="10",NumbersOnly=true,Flag="AutoSellDelay",
    Callback=function(v)
        JC.AutoSellDelay=v; CS()
        if JC.AutoSell then
            StopTask("sell"); StartTask("sell",function()DoAutoSell(false)end,tonumber(v) or 10)
        end
    end
})
T5:CreateToggle({
    Name="Auto Sell",Info="Teleports to Sell Stand and sells all items on a timer",
    CurrentValue=JC.AutoSell, Flag="AutoSell",
    Callback=function(v)
        JC.AutoSell=v; CS()
        if v then StartTask("sell",function()DoAutoSell(false)end,tonumber(JC.AutoSellDelay) or 10)
        else StopTask("sell") end
    end
})
T5:CreateButton({Name="💰 Sell All NOW",Callback=function()task.spawn(function()DoAutoSell(true)end)end})
T5:CreateSection("Force Sell on Full Backpack")
T5:CreateToggle({
    Name="Force Sell When Full",Info="Auto-sells when backpack count hits threshold",
    CurrentValue=JC.ForceSellOnFull, Flag="ForceSellOnFull",
    Callback=function(v) JC.ForceSellOnFull=v; CS() end
})
T5:CreateInput({
    Name="Backpack Threshold",PlaceholderText="35",NumbersOnly=true,Flag="BackpackFullThresh",
    Callback=function(v) JC.BackpackFullThresh=v; CS() end
})

-- ══════════════════════════════════
-- TAB 6: 🏪 SHOP
-- ══════════════════════════════════
local T6=Window:CreateTab("Shop",4483362458)
T6:CreateSection("Auto Buy Seeds")
T6:CreateToggle({
    Name="Auto Buy Best Seed",Info="Buys the most expensive seed you can currently afford",
    CurrentValue=JC.AutoBuyBestSeed, Flag="AutoBuyBestSeed",
    Callback=function(v)
        JC.AutoBuyBestSeed=v; CS()
        if v then StartTask("buyBestSeed",DoAutoBuySeeds,3) else StopTask("buyBestSeed") end
    end
})
T6:CreateDropdown({
    Name="Buy Mode",Options={"Buy Best Seed","Select Mode"},
    CurrentOption={JC.BuyMode}, Flag="BuyMode", MultipleOptions=false,
    Callback=function(v) JC.BuyMode=v[1] or v; CS() end
})
T6:CreateDropdown({
    Name="Seeds to Buy",Options=seedDDL,CurrentOption=JC.TargetBuySeed,
    Flag="TargetBuySeed", MultipleOptions=true,
    Callback=function(v) JC.TargetBuySeed=v; CS() end
})
T6:CreateToggle({
    Name="Auto Buy Seeds",Info="Buys selected seeds when affordable and in stock",
    CurrentValue=JC.AutoBuySeeds, Flag="AutoBuySeeds",
    Callback=function(v)
        JC.AutoBuySeeds=v; CS()
        if v then StartTask("buySeeds",DoAutoBuySeeds,3) else StopTask("buySeeds") end
    end
})
T6:CreateButton({Name="🌾 Buy Seeds NOW",Callback=function()task.spawn(DoAutoBuySeeds)end})
T6:CreateSection("Auto Buy Gears")
T6:CreateToggle({
    Name="Auto Buy Best Gear",Info="Buys the best gear you can currently afford",
    CurrentValue=JC.AutoBuyBestGear, Flag="AutoBuyBestGear",
    Callback=function(v)
        JC.AutoBuyBestGear=v; CS()
        if v then StartTask("buyBestGear",DoAutoBuyGears,5) else StopTask("buyBestGear") end
    end
})
T6:CreateDropdown({
    Name="Gears to Buy",Options=gearDDL,CurrentOption=JC.TargetBuyGear,
    Flag="TargetBuyGear", MultipleOptions=true,
    Callback=function(v) JC.TargetBuyGear=v; CS() end
})
T6:CreateToggle({
    Name="Auto Buy Gears",Info="Buys selected gears when affordable and in stock",
    CurrentValue=JC.AutoBuyGears, Flag="AutoBuyGears",
    Callback=function(v)
        JC.AutoBuyGears=v; CS()
        if v then StartTask("buyGears",DoAutoBuyGears,5) else StopTask("buyGears") end
    end
})
T6:CreateButton({Name="⚙️ Buy Gears NOW",Callback=function()task.spawn(DoAutoBuyGears)end})

-- ══════════════════════════════════
-- TAB 7: 🎯 QUEST & CODES
-- ══════════════════════════════════
local T7=Window:CreateTab("Quest",4483362458)
T7:CreateSection("Full Auto Quest")
T7:CreateParagraph({
    Title="Auto Quest Loop",
    Content="Automatically loops: Buy best seeds → Plant → Instant harvest → Sell. Completes quest objectives that require growing/selling crops."
})
T7:CreateToggle({
    Name="Enable Auto Quest",
    Info="Loops: Buy → Plant → Harvest → Sell",
    CurrentValue=JC.AutoQuest, Flag="AutoQuest",
    Callback=function(v)
        JC.AutoQuest=v; CS()
        if v then StartTask("quest",DoAutoQuest,2) else StopTask("quest") end
    end
})
T7:CreateSection("Code Redemption")
T7:CreateInput({
    Name="Add Code (press Enter)",PlaceholderText="FREEGOLD",Flag="AddCode",
    Callback=function(v)
        if v and v~="" then
            JC.RedeemCodes=JC.RedeemCodes or {}
            table.insert(JC.RedeemCodes,v); CS()
            Rayfield:Notify({Title="Code Added!",Content=v,Duration=3})
        end
    end
})
T7:CreateButton({
    Name="🎟️ Redeem All Codes NOW",
    Info="Tries all your saved codes immediately",
    Callback=function()task.spawn(DoAutoRedeem)end
})
T7:CreateButton({
    Name="🗑️ Clear All Codes",
    Callback=function()
        JC.RedeemCodes={}; CS()
        Rayfield:Notify({Title="Codes Cleared",Duration=2})
    end
})
T7:CreateToggle({
    Name="Auto Redeem on Load",Info="Redeems codes automatically when script loads",
    CurrentValue=JC.AutoRedeem, Flag="AutoRedeem",
    Callback=function(v) JC.AutoRedeem=v; CS() end
})

-- ══════════════════════════════════
-- TAB 8: 👁 ESP & ALERTS
-- ══════════════════════════════════
local T8=Window:CreateTab("ESP",4483362458)
T8:CreateSection("Plant ESP")
T8:CreateParagraph({
    Title="ESP Info",
    Content="Shows ripeness, variant, mutations, weight, and estimated ×multiplier on every plant. Color-coded: Gold=yellow, Silver=blue, Lush=green, Ripened=orange."
})
T8:CreateToggle({
    Name="Enable Plant ESP",
    Info="Overlay labels on all plants in ClientPlants",
    CurrentValue=JC.PlantESP, Flag="PlantESP",
    Callback=function(v)
        JC.PlantESP=v; CS()
        if v then StartTask("esp",DoPlantESP,2) else StopTask("esp"); ClearESP() end
    end
})
T8:CreateToggle({
    Name="Show ×Multiplier on ESP",Info="Displays estimated value multiplier on each plant label",
    CurrentValue=JC.ESPShowMult, Flag="ESPShowMult",
    Callback=function(v) JC.ESPShowMult=v; CS() end
})
T8:CreateSection("Alerts")
T8:CreateToggle({
    Name="Rare Mutation Notifier",
    Info="Pops a notification when Starstruck, Meteoric, or Shocked is detected",
    CurrentValue=JC.RareMutNotify, Flag="RareMutNotify",
    Callback=function(v) JC.RareMutNotify=v; CS() end
})
T8:CreateToggle({
    Name="Weather Change Notifier",Info="Notifies you when the weather changes",
    CurrentValue=JC.WeatherNotify, Flag="WeatherNotify",
    Callback=function(v)
        JC.WeatherNotify=v; CS()
        if v then StartTask("weatherWatch",WeatherWatcher,15) else StopTask("weatherWatch") end
    end
})
if JC.WeatherNotify then StartTask("weatherWatch",WeatherWatcher,15) end

-- ══════════════════════════════════
-- TAB 9: ✈️ UTILITY
-- ══════════════════════════════════
local T9=Window:CreateTab("Utility",4483362458)
T9:CreateSection("Fly (W/A/S/D + Q/E)")
T9:CreateToggle({
    Name="Enable Fly",Info="WASD to move, Q=down, E=up",
    CurrentValue=JC.FlyEnabled, Flag="FlyEnabled",
    Callback=function(v)
        JC.FlyEnabled=v; CS()
        if v then StartFly() else StopFly() end
    end
})
T9:CreateSlider({
    Name="Fly Speed",Info="How fast you fly",
    Range={10,300}, Increment=5,
    CurrentValue=JC.FlySpeed or 50, Flag="FlySpeed", Suffix=" stud/s",
    Callback=function(v) JC.FlySpeed=v; CS() end
})
T9:CreateSection("Noclip")
T9:CreateToggle({
    Name="Enable Noclip",Info="Walk through walls and objects",
    CurrentValue=JC.Noclip, Flag="Noclip",
    Callback=function(v)
        JC.Noclip=v; CS()
        if v then StartNoclip() else StopNoclip() end
    end
})
T9:CreateSection("Teleport Hub")
local shopTPs={
    {"🏪 TP to Seed Shop","Seed Shop"},
    {"⚙️ TP to Gear Shop","Gear Shop"},
    {"💰 TP to Sell Stand","Sell Stand"},
}
for _,entry in ipairs(shopTPs) do
    T9:CreateButton({
        Name=entry[1], Info="Teleport to "..entry[2],
        Callback=function() TPToShop(entry[2]) end
    })
end
T9:CreateButton({
    Name="🏠 TP to My Plot Center",
    Callback=function()
        local hrp=HRP(); local myPlot=GetMyPlot()
        if hrp and myPlot then
            local cf=myPlot:IsA("Model") and myPlot:GetPivot()
                or (myPlot:FindFirstChildWhichIsA("BasePart") and myPlot:FindFirstChildWhichIsA("BasePart").CFrame)
            if cf then SmartTP(hrp,cf) end
        end
    end
})
T9:CreateSection("Value Calculator")
T9:CreateButton({
    Name="📊 Scan & Print Plant Values",
    Info="Prints estimated sell values for all plants to output",
    Callback=function()
        local results={}
        for _,plant in ipairs(clientPlants:GetChildren()) do
            local ripe=plant:GetAttribute("RipenessStage") or "Unripe"
            local var =plant:GetAttribute("Variant")       or "None"
            local muts=GetFruitMuts(plant)
            local wgt =tonumber(plant:GetAttribute("Weight") or plant:GetAttribute("Kg")) or 1
            local base=500 -- default base
            local mSum=0; for _,m in ipairs(muts) do mSum+=(MUT[m] or 0) end
            local vB=MUT[var] or 0; local rM=MUT[ripe] or 1
            local est=math.floor(base*rM*(math.max(1,mSum)+vB)*math.sqrt(wgt))
            table.insert(results,plant.Name.." ["..ripe.."/"..var.."] "..table.concat(muts,"+").." = ~"..tostring(est).." 💰")
        end
        print("=== JinHub Value Scan ===")
        for _,r in ipairs(results) do print(r) end
        Rayfield:Notify({Title="Scan Complete",Content=#results.." plants scanned. Check output.",Duration=4})
    end
})

-- ══════════════════════════════════
-- TAB 10: ⚙️ PLAYER & SETTINGS
-- ══════════════════════════════════
local T10=Window:CreateTab("Settings",4483362458)
T10:CreateSection("Player Stats")
T10:CreateSlider({
    Name="Walk Speed",Range={16,250},Increment=1,
    CurrentValue=JC.WalkSpeed,Flag="WalkSpeed",Suffix=" stud/s",
    Callback=function(v)
        JC.WalkSpeed=v; CS()
        local h=HUM(); if h then h.WalkSpeed=v end
    end
})
T10:CreateSlider({
    Name="Jump Power",Range={50,300},Increment=5,
    CurrentValue=JC.JumpPower,Flag="JumpPower",
    Callback=function(v)
        JC.JumpPower=v; CS()
        local h=HUM(); if h then h.JumpPower=v end
    end
})
T10:CreateSection("Anti-AFK")
local AfkConn
T10:CreateToggle({
    Name="Anti-AFK",Info="Prevents idle kick",
    CurrentValue=JC.AntiAFK,Flag="AntiAFK",
    Callback=function(v)
        JC.AntiAFK=v; CS()
        if v then
            AfkConn=LocalPlayer.Idled:Connect(function()
                VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
            end)
        else
            if AfkConn then AfkConn:Disconnect(); AfkConn=nil end
        end
    end
})
if JC.AntiAFK then
    AfkConn=LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end)
end
T10:CreateSection("Anti-Detection Mode")
T10:CreateDropdown({
    Name="Anti-Detect Level",
    Info="Conservative=safe slow | Normal=balanced | Aggressive=fast risky",
    Options={"Conservative","Normal","Aggressive"},
    CurrentOption={JC.AntiDetect or "Normal"},
    Flag="AntiDetect", MultipleOptions=false,
    Callback=function(v)
        local mode=type(v)=="table" and (v[1] or "Normal") or v
        JC.AntiDetect=mode; AntiDetectMode=mode; CS()
        Rayfield:Notify({Title="Anti-Detect: "..mode,Duration=2})
    end
})
T10:CreateSection("Session Stats")
T10:CreateButton({
    Name="📊 Show Session Stats",
    Callback=function()
        Rayfield:Notify({
            Title="JinHub Session Stats",
            Content=string.format(
                "Harvested: %d | Shoveled: %d | Planted: %d | Sold: %d",
                Stats.harvested, Stats.shoveled, Stats.planted, Stats.sold
            ),
            Duration=6
        })
    end
})
T10:CreateSection("Config")
T10:CreateToggle({
    Name="Auto Save Config",Info="Saves on every setting change",
    CurrentValue=JC.AutoSave,Flag="AutoSave",
    Callback=function(v) JC.AutoSave=v; Save(); Rayfield:Notify({Title="Auto Save "..(v and "ON" or "OFF"),Duration=2}) end
})
T10:CreateToggle({
    Name="Auto Load Config",Info="Loads saved config on inject",
    CurrentValue=JC.AutoLoad,Flag="AutoLoad",
    Callback=function(v) JC.AutoLoad=v; Save(); Rayfield:Notify({Title="Auto Load "..(v and "ON" or "OFF"),Duration=2}) end
})
T10:CreateButton({
    Name="💾 Save Config NOW",
    Callback=function() Save(); Rayfield:Notify({Title="Saved!",Duration=2}) end
})
T10:CreateButton({
    Name="🔄 Reset to Defaults",
    Callback=function()
        JC=DEF; Save()
        Rayfield:Notify({Title="Reset Done",Content="Rejoin for full effect",Duration=4})
    end
})
T10:CreateButton({
    Name="📋 Copy Discord",Info="discord.gg/k2wdyy8QMN",
    Callback=function()
        if setclipboard then setclipboard("https://discord.gg/k2wdyy8QMN") end
        Rayfield:Notify({Title="Discord Copied!",Duration=2})
    end
})

-- ══════════════════════════════════
-- STARTUP — Resume tasks
-- ══════════════════════════════════
AntiDetectMode = JC.AntiDetect or "Normal"

if JC.AutoRedeem    then task.spawn(DoAutoRedeem) end
if JC.AutoHarvest   then StartTask("harvest",    DoAutoHarvest,   0.8) end
if JC.AutoShovelFruit then StartTask("shovelFruit",DoAutoShovelFruit,1.2) end
if JC.AutoShovelTree  then StartTask("shovelTree", DoAutoShovelTree, 2) end
if JC.AutoWater     then StartTask("water",       DoAutoWater,     2) end
if JC.AutoSprinkler then StartTask("sprinkler",   DoAutoSprinkler, 5) end
if JC.AutoPlant     then StartTask("plant",       DoAutoPlant,     0.45) end
if JC.AutoSell      then StartTask("sell",function()DoAutoSell(false)end,tonumber(JC.AutoSellDelay) or 10) end
if JC.AutoBuySeeds  then StartTask("buySeeds",    DoAutoBuySeeds,  3) end
if JC.AutoBuyGears  then StartTask("buyGears",    DoAutoBuyGears,  5) end
if JC.AutoBuyBestSeed then StartTask("buyBestSeed",DoAutoBuySeeds, 3) end
if JC.AutoBuyBestGear then StartTask("buyBestGear",DoAutoBuyGears, 5) end
if JC.AutoQuest     then StartTask("quest",       DoAutoQuest,     2) end
if JC.AutoGrowAll   then StartTask("growAll",     DoAutoGrowAll,   5) end
if JC.AutoFavorite  then StartTask("favorite",    DoAutoFavorite,  3) end
if JC.PlantESP      then StartTask("esp",         DoPlantESP,      2) end
if JC.FlyEnabled    then StartFly() end
if JC.Noclip        then StartNoclip() end

Rayfield:Notify({
    Title = "✅ JinHub v3 Loaded!",
    Content = "SCRIPT NG MGA TANGA — 10 tabs, all features active\n[=] to toggle UI",
    Duration = 6
})
