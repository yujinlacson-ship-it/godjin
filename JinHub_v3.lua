--[[
╔═══════════════════════════════════════════════════╗
║           JinHub v3 — Garden Horizons             ║
║                  ★ God Jin ★                      ║
╠═══════════════════════════════════════════════════╣
║  HARVEST: Teleports TO each plant zone so the     ║
║  server's proximity check always passes — instant ║
║  SELL: TPs to Sell Stand before calling sell      ║
║  ANTI-DETECT: Jitter delays, rate limiter,        ║
║               noise on all teleports              ║
╚═══════════════════════════════════════════════════╝
]]

-- ════════════════════════════════════
-- SERVICES
-- ════════════════════════════════════
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local VirtualUser       = game:GetService("VirtualUser")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer

-- ════════════════════════════════════
-- ANTI-DETECTION
-- ════════════════════════════════════
local function SmartWait(base, var)
    var = var or base * 0.25
    task.wait(math.max(0.03, base + (math.random()-0.5)*2*var))
end

local _rc, _rw = 0, os.clock()
local function RateLimit()
    if os.clock()-_rw >= 1 then _rc=0; _rw=os.clock() end
    _rc+=1; if _rc>14 then task.wait(0.07) end
end
local function SafeFire(r,...) RateLimit(); pcall(r.FireServer,r,...) end
local function SafeInvoke(r,...) RateLimit(); local ok,v=pcall(r.InvokeServer,r,...); return ok and v or nil end

-- Teleport with small noise so coords are never pixel-perfect
local function SmartTP(hrp, cf)
    if not hrp then return end
    hrp.CFrame = cf * CFrame.new(
        (math.random()-0.5)*0.5, 0, (math.random()-0.5)*0.5)
    SmartWait(0.35, 0.08)
end

-- ════════════════════════════════════
-- MUTATION DATA (wiki-accurate)
-- ════════════════════════════════════
local MUT = {
    Soaked=1.2, Flooded=1.5, Foggy=1.2, Misty=1.2,
    Chilled=1.5, Snowy=2.0, Sandy=2.5,
    Shocked=4.5, Starstruck=6.5, Meteoric=10.0,
    Galactic=3.0, Stormy=3.5, Tidal=3.0,
    Frostbit=3.5, Muddy=5.0, Mossy=3.5,
    Gold=5.0, Silver=2.0, None=0,
    Lush=3.0, Ripened=2.0, Unripe=1.0,
}

local ALL_MUT  = {"Any","None","Meteoric","Starstruck","Muddy","Shocked",
                  "Frostbit","Mossy","Stormy","Tidal","Galactic",
                  "Sandy","Snowy","Chilled","Flooded","Soaked","Foggy","Misty"}
local ALL_VAR  = {"Any","None","Gold","Silver"}
local ALL_RIPE = {"Any","Lush","Ripened","Unripe"}
local ALL_WEA  = {"Any","Clear","Rain","Storm","Sandstorm",
                  "Snow","Fog","Starfall","Meteor","Night"}

-- ════════════════════════════════════
-- CONFIG
-- ════════════════════════════════════
local CF = "JinHub_Data"
local CFG_FILE = CF.."/Settings.json"

local DEF = {
    -- System
    WalkSpeed=16, JumpPower=50, AntiAFK=true,
    AutoSave=false, AutoLoad=false,
    -- Harvest
    HarvestRipeness={"Any"}, HarvestMutation={"Any"},
    HarvestVariant={"Any"},  HarvestWeather={"Any"},
    AutoHarvest=false,
    -- Smart Shovel Fruit
    ShovelMode="Remove Junk",
    ShovelKeepRipeness={"Lush"},
    ShovelKeepVariant={"Gold","Silver"},
    ShovelKeepMutation={"Any"},
    ShovelMinKg="0", ShovelMaxKg="999",
    AutoShovelFruit=false, AutoShovelTree=false,
    -- Water / Sprinkler
    AutoWater=false, AutoSprinkler=false,
    -- ESP
    PlantESP=false, ESPShowMult=true,
    -- Planting
    SeedSelect={"Carrot"}, PlantMode="Random",
    CustomPlantX="0", CustomPlantZ="0", AutoPlant=false,
    -- Selling
    AutoSellDelay="10", AutoSell=false,
    ForceSellOnFull=true, BackpackFullThresh="35",
    -- Shop
    BuyMode="Buy Best Seed",
    TargetBuySeed={"Carrot Seed"}, AutoBuySeeds=false,
    TargetBuyGear={"Watering Can"}, AutoBuyGears=false,
    AutoBuyBestSeed=false, AutoBuyBestGear=false,
    -- Quest / Codes
    AutoQuest=false, RedeemCodes={}, AutoRedeem=false,
}

local JC = {}  -- JinConfig

if isfolder and not isfolder(CF) then makefolder(CF) end

local function LoadCFG()
    if isfile and isfile(CFG_FILE) then
        local ok,d = pcall(HttpService.JSONDecode, HttpService, readfile(CFG_FILE))
        if ok and type(d)=="table" then
            for k,v in pairs(DEF) do if d[k]==nil then d[k]=v end end
            return d
        end
    end
    return DEF
end

local saved = LoadCFG()
if saved.AutoLoad then JC=saved
else
    JC=DEF; JC.AutoLoad=saved.AutoLoad; JC.AutoSave=saved.AutoSave
end

local function Save()
    if writefile then
        local ok,s=pcall(HttpService.JSONEncode,HttpService,JC)
        if ok then writefile(CFG_FILE,s) end
    end
end
local function CS() if JC.AutoSave then Save() end end

-- ════════════════════════════════════
-- GAME REMOTES  (wait for them safely)
-- ════════════════════════════════════
local function WaitRemote(parent, name, timeout)
    timeout = timeout or 10
    local t = 0
    while t < timeout do
        local r = parent:FindFirstChild(name)
        if r then return r end
        task.wait(0.5); t+=0.5
    end
    return nil
end

local RE = ReplicatedStorage:WaitForChild("RemoteEvents", 15)
if not RE then warn("[JinHub] RemoteEvents not found") end

local rHarvest  = RE and WaitRemote(RE,"HarvestFruit")
local rPlant    = RE and WaitRemote(RE,"PlantSeed")
local rPurchase = RE and WaitRemote(RE,"PurchaseShopItem")
local rSell     = RE and WaitRemote(RE,"SellItems")
local rWater    = RE and (RE:FindFirstChild("WaterPlant"))
local rShovel   = RE and (RE:FindFirstChild("ShovelPlant") or RE:FindFirstChild("RemovePlant") or RE:FindFirstChild("DeletePlant"))
local rSprinkler= RE and (RE:FindFirstChild("UseSprinkler") or RE:FindFirstChild("ActivateSprinkler"))
local rRedeem   = RE and (RE:FindFirstChild("RedeemCode") or RE:FindFirstChild("UseCode"))

local clientPlants = workspace:WaitForChild("ClientPlants",15)
local plotsFolder  = workspace:WaitForChild("Plots",15)

-- Weather check
local function GetWeather()
    for _,c in ipairs({workspace,ReplicatedStorage}) do
        for _,name in ipairs({"Weather","WeatherSystem","GameManager","WeatherData"}) do
            local obj = c:FindFirstChild(name)
            if obj then
                local a = obj:GetAttribute("CurrentWeather")
                    or obj:GetAttribute("Weather")
                    or obj:GetAttribute("ActiveWeather")
                if a then return tostring(a) end
            end
        end
    end
    return "Any"
end

-- ════════════════════════════════════
-- SEED / GEAR SHOP DATA
-- ════════════════════════════════════
local SEEDS = {
    {N="Carrot Seed",   K="Carrot",     P=20,      O=10},
    {N="Corn Seed",     K="Corn",       P=100,     O=20},
    {N="Onion Seed",    K="Onion",      P=200,     O=30},
    {N="Strawberry Seed",K="Strawberry",P=800,     O=40},
    {N="Mushroom Seed", K="Mushroom",   P=1500,    O=50},
    {N="Beetroot Seed", K="Beetroot",   P=2500,    O=60},
    {N="Tomato Seed",   K="Tomato",     P=4000,    O=70},
    {N="Apple Seed",    K="Apple",      P=7000,    O=80},
    {N="Rose Seed",     K="Rose",       P=10000,   O=90},
    {N="Wheat Seed",    K="Wheat",      P=12000,   O=100},
    {N="Banana Seed",   K="Banana",     P=30000,   O=110},
    {N="Plum Seed",     K="Plum",       P=60000,   O=120},
    {N="Potato Seed",   K="Potato",     P=100000,  O=130},
    {N="Cabbage Seed",  K="Cabbage",    P=150000,  O=140},
    {N="Cherry Seed",   K="Cherry",     P=1000000, O=150},
}
local GEARS = {
    {N="Watering Can",   P=5000,   O=10},
    {N="Basic Sprinkler",P=15000,  O=20},
    {N="Harvest Bell",   P=35000,  O=30},
    {N="Turbo Sprinkler",P=60000,  O=40},
    {N="Favorite Tool",  P=80000,  O=45},
    {N="Super Sprinkler",P=100000, O=50},
}
table.sort(SEEDS,function(a,b)return a.O<b.O end)
table.sort(GEARS,function(a,b)return a.O<b.O end)

local seedDDL,gearDDL={},{}
for _,d in ipairs(SEEDS) do table.insert(seedDDL,d.N) end
for _,d in ipairs(GEARS) do table.insert(gearDDL,d.N) end

local plantSeeds = {}
local mf = ReplicatedStorage:FindFirstChild("Plants") and ReplicatedStorage.Plants:FindFirstChild("Models")
if mf then for _,m in ipairs(mf:GetChildren()) do table.insert(plantSeeds,m.Name) end
else plantSeeds={"Carrot","Corn","Tomato","Mushroom","Strawberry","Beetroot","Apple","Rose","Wheat","Banana","Plum","Potato","Cabbage","Cherry"} end
table.sort(plantSeeds)

-- ════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════
local function ToSet(t)
    if type(t)=="string" then return {[t]=true} end
    if type(t)=="table" then
        if t[1] then local s={} for _,v in ipairs(t) do s[v]=true end return s end
        return t
    end
    return {}
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
local function CalcMult(ripe,var,muts)
    local rM=MUT[ripe] or 1; local vM=MUT[var] or 0; local sum=0
    if type(muts)=="table" then for _,m in ipairs(muts) do sum+=(MUT[m] or 0) end
    elseif type(muts)=="string" and muts~="None" then sum=MUT[muts] or 0 end
    return math.floor(rM*(math.max(1,sum)+vM)*10)/10
end
local function GetFruitMuts(fruit)
    local raw=fruit:GetAttribute("Mutations") or fruit:GetAttribute("MutationList")
    if raw then
        local t={}
        for m in tostring(raw):gmatch("[^,]+") do table.insert(t,(m:match("^%s*(.-)%s*$"))) end
        return t
    end
    return {fruit:GetAttribute("Mutation") or "None"}
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

-- Find a named shop stand in workspace
local function FindShop(name)
    local shops = workspace:FindFirstChild("MapPhysical")
        and workspace.MapPhysical:FindFirstChild("Shops")
    if shops then
        local s=shops:FindFirstChild(name)
        if s then return s end
    end
    -- fallback: search workspace directly
    for _,c in ipairs(workspace:GetDescendants()) do
        if (c:IsA("Model") or c:IsA("BasePart")) and c.Name==name then return c end
    end
end

local function TPToShop(name)
    local hrp=HRP(); if not hrp then return false end
    local stand=FindShop(name)
    if stand then
        SmartTP(hrp, stand:IsA("Model") and stand:GetPivot() or stand.CFrame)
        return true
    end
    return false
end

-- ════════════════════════════════════
-- TASK MANAGER
-- ════════════════════════════════════
local Tasks={}
local function StartTask(name,fn,interval,var)
    if Tasks[name] then return end
    Tasks[name]=true
    task.spawn(function()
        while Tasks[name] do
            pcall(fn); SmartWait(interval,var or interval*.2)
        end
    end)
end
local function StopTask(name) Tasks[name]=nil end

-- ════════════════════════════════════
-- ★ INSTANT HARVEST
-- Strategy: collect ALL fruit UUIDs first,
-- then TP to plot center ONCE and fire all
-- harvest events in rapid bursts — no per-plant TP
-- needed because we're inside proximity range of
-- the whole plot at once.
-- ════════════════════════════════════
local function DoAutoHarvest()
    if not rHarvest then return end
    local ripSet=ToSet(JC.HarvestRipeness)
    local mutSet=ToSet(JC.HarvestMutation)
    local varSet=ToSet(JC.HarvestVariant)
    local wetSet=ToSet(JC.HarvestWeather)
    local weather=GetWeather()
    if not(wetSet["Any"] or wetSet[weather]) then return end

    -- Step 1: collect all payloads
    local payloads={}
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local fruits={}
        for _,c in ipairs(plant:GetChildren()) do
            if c.Name:lower():find("fruit") then table.insert(fruits,c) end
        end

        local processObj=function(obj, uuid)
            local ripe=obj:GetAttribute("RipenessStage") or "Unripe"
            local var =obj:GetAttribute("Variant")       or "None"
            local muts=GetFruitMuts(obj)
            local idx =obj:GetAttribute("GrowthAnchorIndex")
            if not(ripSet["Any"] or ripSet[ripe]) then return end
            if not(varSet["Any"] or varSet[var])  then return end
            local mp=mutSet["Any"]
            if not mp then
                for _,m in ipairs(muts) do if mutSet[m] then mp=true break end end
            end
            if not mp then return end
            local pl={Uuid=uuid}
            if idx then pl.GrowthAnchorIndex=idx end
            table.insert(payloads,pl)
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

    -- Step 2: TP to plot center ONCE so proximity checks pass
    local hrp=HRP()
    local savedCF = hrp and hrp.CFrame
    local myPlot=GetMyPlot()
    if hrp and myPlot then
        local center = myPlot:IsA("Model") and myPlot:GetPivot()
            or (myPlot:FindFirstChildWhichIsA("BasePart") and myPlot:FindFirstChildWhichIsA("BasePart").CFrame)
        if center then SmartTP(hrp, center) end
    end

    -- Step 3: Fire ALL harvest events in rapid batch (no per-item wait)
    -- Chunk into batches of 10 to avoid server overflow
    local BATCH=10
    for i=1,#payloads,BATCH do
        local chunk={}
        for j=i,math.min(i+BATCH-1,#payloads) do
            table.insert(chunk,payloads[j])
        end
        SafeFire(rHarvest, chunk)
        SmartWait(0.04, 0.01)
    end

    -- Step 4: Return to original position
    if hrp and savedCF then
        task.delay(0.3, function() if hrp and hrp.Parent then hrp.CFrame=savedCF end end)
    end
end

-- ════════════════════════════════════
-- ★ SMART SHOVEL FRUIT
-- 5-filter: ripeness, variant, mutation,
--           min kg (keep), max kg (keep)
-- ════════════════════════════════════
local function FruitKeep(obj)
    local mode=JC.ShovelMode or "Remove Junk"
    if mode=="Remove All" then return false end

    local weight=tonumber(obj:GetAttribute("Weight") or obj:GetAttribute("Kg") or obj:GetAttribute("Size")) or 0
    local minKg=tonumber(JC.ShovelMinKg) or 0
    local maxKg=tonumber(JC.ShovelMaxKg) or 999

    -- Weight gates
    if weight>0 and weight<minKg then return false end  -- too light → shovel
    if maxKg>0 and weight>maxKg  then return true  end  -- very heavy → always keep

    local ripe=obj:GetAttribute("RipenessStage") or "Unripe"
    local var =obj:GetAttribute("Variant")       or "None"
    local muts=GetFruitMuts(obj)

    if mode=="Keep Valuable" then
        if var=="Gold" then return true end
        if ripe=="Lush" then return true end
        for _,m in ipairs(muts) do if (MUT[m] or 0)>=3.0 then return true end end
        return false
    end

    -- "Remove Junk": keep only if matches ALL three keep-filters
    local kRipe=ToSet(JC.ShovelKeepRipeness)
    local kVar =ToSet(JC.ShovelKeepVariant)
    local kMut =ToSet(JC.ShovelKeepMutation)
    if not(kRipe["Any"] or kRipe[ripe]) then return false end
    if not(kVar["Any"]  or kVar[var])   then return false end
    local mp=kMut["Any"]
    if not mp then
        for _,m in ipairs(muts) do if kMut[m] then mp=true break end end
        if not mp and muts[1]=="None" and kMut["None"] then mp=true end
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
                    SafeInvoke(rShovel,pl); SmartWait(0.08,0.02)
                end
            end
        else
            if not FruitKeep(plant) then
                SafeInvoke(rShovel,{Uuid=uuid,Type="Fruit"}); SmartWait(0.08,0.02)
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

-- ════════════════════════════════════
-- WATER / SPRINKLER
-- ════════════════════════════════════
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

-- ════════════════════════════════════
-- AUTO PLANT
-- ════════════════════════════════════
local function DoAutoPlant()
    local s=ToSet(JC.SeedSelect); local seeds={}
    for k,v in pairs(s) do if v then table.insert(seeds,k) end end
    if #seeds==0 then return end
    local seedName=seeds[math.random(1,#seeds)]
    local char=LocalPlayer.Character
    local human=char and char:FindFirstChild("Humanoid")
    local bp=LocalPlayer:FindFirstChild("Backpack")
    local kw=seedName.." Seed"; local tool=nil
    if char then for _,c in ipairs(char:GetChildren()) do if c:IsA("Tool") and c.Name:find(kw) then tool=c break end end end
    if not tool and bp and human then
        for _,c in ipairs(bp:GetChildren()) do
            if c:IsA("Tool") and c.Name:find(kw) then human:EquipTool(c); SmartWait(0.2,0.05); tool=c; break end
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
    if pos then SafeInvoke(rPlant,seedName,pos) end
end

-- ════════════════════════════════════
-- ★ INSTANT SELL
-- Always TPs to Sell Stand first, then fires
-- ════════════════════════════════════
local function DoAutoSell(force)
    if not rSell then return end
    if not force then
        local thresh=tonumber(JC.BackpackFullThresh) or 35
        if JC.ForceSellOnFull and BPCount()>=thresh then force=true end
    end
    -- Always TP to sell stand so the server allows the sell
    local hrp=HRP(); local savedCF = hrp and hrp.CFrame
    local sold=false
    -- Try named sell stand variants
    for _,name in ipairs({"Sell Stand","SellStand","Sell_Stand","ShopSell","Sell Shop"}) do
        local stand=FindShop(name)
        if stand and hrp then
            SmartTP(hrp, stand:IsA("Model") and stand:GetPivot() or stand.CFrame)
            sold=true; break
        end
    end
    -- Fire sell
    SafeInvoke(rSell,"SellAll")
    SmartWait(0.4,0.1)
    -- Return
    if hrp and savedCF then
        task.delay(0.5, function() if hrp and hrp.Parent then hrp.CFrame=savedCF end end)
    end
end

-- ════════════════════════════════════
-- AUTO BUY SEEDS
-- ════════════════════════════════════
local function DoAutoBuySeeds()
    local sh=Shillings(); if not sh then return end
    local didTP=false
    local bestMode=JC.AutoBuyBestSeed or JC.BuyMode=="Buy Best Seed"
    if bestMode then
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

-- ════════════════════════════════════
-- AUTO BUY GEARS
-- ════════════════════════════════════
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

-- ════════════════════════════════════
-- AUTO REDEEM / QUEST
-- ════════════════════════════════════
local function DoAutoRedeem()
    if not rRedeem then return end
    for _,code in ipairs(JC.RedeemCodes or {}) do
        SafeInvoke(rRedeem,tostring(code)); SmartWait(0.6,0.15)
    end
end
local function DoAutoQuest()
    DoAutoBuySeeds(); SmartWait(0.5)
    DoAutoPlant(); SmartWait(1,0.3)
    DoAutoHarvest(); SmartWait(0.5)
    DoAutoSell(false)
end

-- ════════════════════════════════════
-- PLANT ESP
-- ════════════════════════════════════
local ESPF=Instance.new("Folder"); ESPF.Name="JinHub_ESP"; ESPF.Parent=workspace
local RCLR={Lush=Color3.fromRGB(0,255,80),Ripened=Color3.fromRGB(255,200,0),Unripe=Color3.fromRGB(160,160,160)}
local VCLR={Gold=Color3.fromRGB(255,215,0),Silver=Color3.fromRGB(180,180,255),None=Color3.fromRGB(200,200,200)}
local function ClearESP() for _,v in ipairs(ESPF:GetChildren()) do v:Destroy() end end
local function DoPlantESP()
    ClearESP(); if not JC.PlantESP then return end
    for _,plant in ipairs(clientPlants:GetChildren()) do
        local root=plant:FindFirstChild("HumanoidRootPart") or plant:FindFirstChildWhichIsA("BasePart")
        if not root then continue end
        local ripe=plant:GetAttribute("RipenessStage") or "Unripe"
        local var =plant:GetAttribute("Variant")       or "None"
        local muts=GetFruitMuts(plant)
        local wgt =plant:GetAttribute("Weight") or plant:GetAttribute("Kg")
        local wStr=wgt and string.format("%.2fkg",tonumber(wgt) or 0) or "?kg"
        local mult=JC.ESPShowMult and CalcMult(ripe,var,muts) or nil
        local mStr=mult and (" ×"..mult) or ""
        local mutStr=table.concat(muts,"+")

        local bb=Instance.new("BillboardGui")
        bb.Size=UDim2.new(0,150,0,58); bb.StudsOffset=Vector3.new(0,4,0)
        bb.AlwaysOnTop=true; bb.Adornee=root; bb.Parent=ESPF

        local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0)
        bg.BackgroundColor3=Color3.fromRGB(0,0,0); bg.BackgroundTransparency=0.35
        bg.BorderSizePixel=0; bg.Parent=bb
        Instance.new("UICorner",bg).CornerRadius=UDim.new(0,5)

        local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-6,1,-4)
        lbl.Position=UDim2.new(0,3,0,2); lbl.BackgroundTransparency=1
        lbl.Font=Enum.Font.GothamBold; lbl.TextScaled=true
        lbl.TextColor3=VCLR[var] or RCLR[ripe] or Color3.new(1,1,1)
        lbl.Text=string.format("[%s] %s\n%s | %s%s",ripe,var,mutStr,wStr,mStr)
        lbl.Parent=bg
    end
end

-- ════════════════════════════════════
-- FORCE SELL BACKGROUND WATCHER
-- ════════════════════════════════════
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

-- ════════════════════════════════════
-- LOAD UI
-- ════════════════════════════════════
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/x2zu/OPEN-SOURCE-UI-ROBLOX/refs/heads/main/X2ZU%20UI%20ROBLOX%20OPEN%20SOURCE/DummyUi-leak-by-x2zu/fetching-main/Tools/Framework.luau"
))()

local Window = Library:Window({
    Title  = "JinHub",
    Desc   = "God Jin  ★  v3",
    Icon   = "zap",
    Theme  = "Midnight",
    Color  = Color3.fromRGB(8, 8, 8),
    Config = {
        Keybind = Enum.KeyCode.LeftControl,
        Size    = UDim2.new(0, 580, 0, 530),
    },
    CloseUIButton = { Enabled = false, Text = "" }
})

-- ════════════════════════════════════
-- DRAGGABLE TOGGLE BUTTON
-- ════════════════════════════════════
local tGui=(gethui and gethui()) or game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
local CG=Instance.new("ScreenGui"); CG.Name="JinHubToggle_v3"; CG.ResetOnSpawn=false; CG.Parent=tGui

-- Jin label button (replaces M icon)
local TBtn=Instance.new("TextButton"); TBtn.Name="JinBtn"; TBtn.Parent=CG
TBtn.Position=UDim2.new(0,15,0.5,-28); TBtn.Size=UDim2.new(0,56,0,56)
TBtn.BackgroundColor3=Color3.fromRGB(10,10,10)
TBtn.TextColor3=Color3.fromRGB(255,255,255)
TBtn.Font=Enum.Font.GothamBold; TBtn.TextScaled=true
TBtn.Text="Jin"; TBtn.BorderSizePixel=0
local UC=Instance.new("UICorner",TBtn); UC.CornerRadius=UDim.new(0,12)
local US=Instance.new("UIStroke",TBtn)
US.Color=Color3.fromRGB(80,80,80); US.Thickness=1.5

local dragging,dragInput,dragStart,startPos=false,nil,nil,nil
local isClick=false

TBtn.InputBegan:Connect(function(inp)
    local m=inp.UserInputType==Enum.UserInputType.MouseButton1
    local t=inp.UserInputType==Enum.UserInputType.Touch
    if m or t then
        dragging=true; isClick=true
        dragStart=inp.Position; startPos=TBtn.Position
        inp.Changed:Connect(function()
            if inp.UserInputState==Enum.UserInputState.End then dragging=false end
        end)
    end
end)
TBtn.InputChanged:Connect(function(inp)
    local mm=inp.UserInputType==Enum.UserInputType.MouseMovement
    local tt=inp.UserInputType==Enum.UserInputType.Touch
    if mm or tt then dragInput=inp; if dragging then isClick=false end end
end)
UserInputService.InputChanged:Connect(function(inp)
    if inp==dragInput and dragging then
        local d=inp.Position-dragStart
        TBtn.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
local vim2=game:GetService("VirtualInputManager")
TBtn.InputEnded:Connect(function(inp)
    local m=inp.UserInputType==Enum.UserInputType.MouseButton1
    local t=inp.UserInputType==Enum.UserInputType.Touch
    if (m or t) and isClick then
        isClick=false
        pcall(function()
            vim2:SendKeyEvent(true,Enum.KeyCode.LeftControl,false,game)
            task.wait(0.05)
            vim2:SendKeyEvent(false,Enum.KeyCode.LeftControl,false,game)
        end)
    end
end)

-- ════════════════════════════════════
-- NOTE: Framework has limited tab slots
-- Tabs are combined into 6 max to keep all visible
-- ════════════════════════════════════

-- ════ TAB 1: HARVEST ════════════════
local T1=Window:Tab({Title="Harvest",Icon="leaf"})
T1:Section({Title="Harvest Filters"})
T1:Dropdown({Title="Ripeness",Multi=true,List=ALL_RIPE,Value=JC.HarvestRipeness,Callback=function(v)JC.HarvestRipeness=v;CS()end})
T1:Dropdown({Title="Mutation Required",Multi=true,List=ALL_MUT,Value=JC.HarvestMutation,Callback=function(v)JC.HarvestMutation=v;CS()end})
T1:Dropdown({Title="Variant Required",Multi=true,List=ALL_VAR,Value=JC.HarvestVariant,Callback=function(v)JC.HarvestVariant=v;CS()end})
T1:Dropdown({Title="Weather Filter",Multi=true,List=ALL_WEA,Value=JC.HarvestWeather,Callback=function(v)JC.HarvestWeather=v;CS()end})
T1:Section({Title="Auto Harvest (Instant Batch + Plot TP)"})
T1:Toggle({Title="Enable Auto Harvest",Desc="TPs to your plot center, fires all harvest events in rapid batch",Value=JC.AutoHarvest,Callback=function(v)
    JC.AutoHarvest=v;CS()
    if v then StartTask("harvest",DoAutoHarvest,0.8) else StopTask("harvest") end
end})
T1:Button({Title="Harvest All Now",Desc="One-shot instant harvest",Callback=function()task.spawn(DoAutoHarvest)end})
Window:Line()

-- ════ TAB 2: SHOVEL ═════════════════
local T2=Window:Tab({Title="Shovel",Icon="shovel"})
T2:Section({Title="Shovel Mode"})
T2:Dropdown({Title="Mode",Desc="Remove Junk=use keep-filters | Keep Valuable=auto Gold/Lush/Mut3× | Remove All=shovel everything",
    List={"Remove Junk","Keep Valuable","Remove All"},Value=JC.ShovelMode,Callback=function(v)JC.ShovelMode=v;CS()end})
T2:Section({Title="Keep Filters — fruits matching these are SAVED"})
T2:Dropdown({Title="Keep Ripeness",Multi=true,List={"Any","Lush","Ripened","Unripe"},Value=JC.ShovelKeepRipeness,Callback=function(v)JC.ShovelKeepRipeness=v;CS()end})
T2:Dropdown({Title="Keep Variant",Multi=true,List={"Any","Gold","Silver","None"},Value=JC.ShovelKeepVariant,Callback=function(v)JC.ShovelKeepVariant=v;CS()end})
T2:Dropdown({Title="Keep Mutation",Multi=true,List=ALL_MUT,Value=JC.ShovelKeepMutation,Callback=function(v)JC.ShovelKeepMutation=v;CS()end})
T2:Section({Title="Weight Gate (kg)"})
T2:Textbox({Title="Min Kg to Keep",Desc="Fruits lighter than this get shoveled  (0 = off)",Placeholder="0",Value=JC.ShovelMinKg,ClearTextOnFocus=false,Callback=function(v)JC.ShovelMinKg=v;CS()end})
T2:Textbox({Title="Max Kg to Shovel",Desc="Fruits heavier than this are always kept (999 = off)",Placeholder="999",Value=JC.ShovelMaxKg,ClearTextOnFocus=false,Callback=function(v)JC.ShovelMaxKg=v;CS()end})
T2:Section({Title="Auto Shovel"})
T2:Toggle({Title="Auto Shovel Fruit",Desc="Continuously removes junk fruits",Value=JC.AutoShovelFruit,Callback=function(v)
    JC.AutoShovelFruit=v;CS()
    if v then StartTask("shovelFruit",DoAutoShovelFruit,1.2) else StopTask("shovelFruit") end
end})
T2:Button({Title="Shovel Fruits Now",Callback=function()task.spawn(DoAutoShovelFruit)end})
T2:Toggle({Title="Auto Shovel Dead Trees",Value=JC.AutoShovelTree,Callback=function(v)
    JC.AutoShovelTree=v;CS()
    if v then StartTask("shovelTree",DoAutoShovelTree,2) else StopTask("shovelTree") end
end})
T2:Button({Title="Shovel Dead Trees Now",Callback=function()task.spawn(DoAutoShovelTree)end})
Window:Line()

-- ════ TAB 3: PLANT + WATER ══════════
local T3=Window:Tab({Title="Farm",Icon="sprout"})
T3:Section({Title="Auto Plant"})
T3:Dropdown({Title="Seeds to Plant",Multi=true,List=plantSeeds,Value=JC.SeedSelect,Callback=function(v)JC.SeedSelect=v;CS()end})
T3:Dropdown({Title="Plant Mode",List={"Random","Player Position","Custom Position"},Value=JC.PlantMode,Callback=function(v)JC.PlantMode=v;CS()end})
T3:Textbox({Title="Custom X",Placeholder="0",Value=JC.CustomPlantX,ClearTextOnFocus=false,Callback=function(v)JC.CustomPlantX=v;CS()end})
T3:Textbox({Title="Custom Z",Placeholder="0",Value=JC.CustomPlantZ,ClearTextOnFocus=false,Callback=function(v)JC.CustomPlantZ=v;CS()end})
T3:Button({Title="Capture My Position as Custom X/Z",Callback=function()
    local hrp=HRP()
    if hrp then
        JC.CustomPlantX=tostring(math.floor(hrp.Position.X))
        JC.CustomPlantZ=tostring(math.floor(hrp.Position.Z))
        JC.PlantMode="Custom Position"; CS()
        Window:Notify({Title="Position Saved",Desc="X="..JC.CustomPlantX.."  Z="..JC.CustomPlantZ,Time=3})
    end
end})
T3:Toggle({Title="Enable Auto Plant",Value=JC.AutoPlant,Callback=function(v)
    JC.AutoPlant=v;CS()
    if v then StartTask("plant",DoAutoPlant,0.45) else StopTask("plant") end
end})
T3:Section({Title="Water & Sprinkler"})
T3:Toggle({Title="Auto Water Plants",Value=JC.AutoWater,Callback=function(v)
    JC.AutoWater=v;CS()
    if v then StartTask("water",DoAutoWater,2) else StopTask("water") end
end})
T3:Toggle({Title="Auto Sprinkler",Value=JC.AutoSprinkler,Callback=function(v)
    JC.AutoSprinkler=v;CS()
    if v then StartTask("sprinkler",DoAutoSprinkler,5) else StopTask("sprinkler") end
end})
T3:Section({Title="Plant ESP"})
T3:Toggle({Title="Enable Plant ESP",Desc="Shows ripeness/variant/mutation/weight/mult on all plants",Value=JC.PlantESP,Callback=function(v)
    JC.PlantESP=v;CS()
    if v then StartTask("esp",DoPlantESP,2) else StopTask("esp");ClearESP() end
end})
T3:Toggle({Title="Show ×Multiplier on ESP",Value=JC.ESPShowMult,Callback=function(v)JC.ESPShowMult=v;CS()end})
Window:Line()

-- ════ TAB 4: SELL + SHOP ════════════
local T4=Window:Tab({Title="Sell/Shop",Icon="coins"})
T4:Section({Title="Auto Sell (TPs to Sell Stand)"})
T4:Textbox({Title="Sell Every (seconds)",Placeholder="10",Value=JC.AutoSellDelay,ClearTextOnFocus=false,Callback=function(v)
    JC.AutoSellDelay=v;CS()
    if JC.AutoSell then StopTask("sell"); StartTask("sell",function()DoAutoSell(false)end,tonumber(v) or 10) end
end})
T4:Toggle({Title="Enable Auto Sell",Desc="TPs to Sell Stand then fires SellAll",Value=JC.AutoSell,Callback=function(v)
    JC.AutoSell=v;CS()
    if v then StartTask("sell",function()DoAutoSell(false)end,tonumber(JC.AutoSellDelay) or 10)
    else StopTask("sell") end
end})
T4:Button({Title="Sell All Now",Callback=function()task.spawn(function()DoAutoSell(true)end)end})
T4:Toggle({Title="Force Sell When Backpack Full",Value=JC.ForceSellOnFull,Callback=function(v)JC.ForceSellOnFull=v;CS()end})
T4:Textbox({Title="Backpack Full Threshold",Placeholder="35",Value=JC.BackpackFullThresh,ClearTextOnFocus=false,Callback=function(v)JC.BackpackFullThresh=v;CS()end})
T4:Section({Title="Shop — Seeds"})
T4:Toggle({Title="Auto Buy Best Seed",Desc="Buys most expensive seed you can afford",Value=JC.AutoBuyBestSeed,Callback=function(v)
    JC.AutoBuyBestSeed=v;CS()
    if v then StartTask("buyBestSeed",DoAutoBuySeeds,3) else StopTask("buyBestSeed") end
end})
T4:Dropdown({Title="Manual Buy Mode",List={"Buy Best Seed","Select Mode"},Value=JC.BuyMode,Callback=function(v)JC.BuyMode=v;CS()end})
T4:Dropdown({Title="Seeds to Buy",Multi=true,List=seedDDL,Value=JC.TargetBuySeed,Callback=function(v)JC.TargetBuySeed=v;CS()end})
T4:Toggle({Title="Enable Auto Buy Seeds",Value=JC.AutoBuySeeds,Callback=function(v)
    JC.AutoBuySeeds=v;CS()
    if v then StartTask("buySeeds",DoAutoBuySeeds,3) else StopTask("buySeeds") end
end})
T4:Section({Title="Shop — Gears"})
T4:Toggle({Title="Auto Buy Best Gear",Value=JC.AutoBuyBestGear,Callback=function(v)
    JC.AutoBuyBestGear=v;CS()
    if v then StartTask("buyBestGear",DoAutoBuyGears,5) else StopTask("buyBestGear") end
end})
T4:Dropdown({Title="Gears to Buy",Multi=true,List=gearDDL,Value=JC.TargetBuyGear,Callback=function(v)JC.TargetBuyGear=v;CS()end})
T4:Toggle({Title="Enable Auto Buy Gears",Value=JC.AutoBuyGears,Callback=function(v)
    JC.AutoBuyGears=v;CS()
    if v then StartTask("buyGears",DoAutoBuyGears,5) else StopTask("buyGears") end
end})
Window:Line()

-- ════ TAB 5: QUEST + CODES ══════════
local T5=Window:Tab({Title="Quest",Icon="scroll-text"})
T5:Section({Title="Full Auto Quest"})
T5:Toggle({Title="Enable Auto Quest",Desc="Loop: Buy seeds → Plant → Harvest → Sell",Value=JC.AutoQuest,Callback=function(v)
    JC.AutoQuest=v;CS()
    if v then StartTask("quest",DoAutoQuest,2) else StopTask("quest") end
end})
T5:Section({Title="Redeem Codes"})
T5:Textbox({Title="Add Code (press Enter)",Placeholder="FREEGOLD",ClearTextOnFocus=true,Callback=function(v)
    if v and v~="" then
        JC.RedeemCodes=JC.RedeemCodes or {}
        table.insert(JC.RedeemCodes,v); CS()
        Window:Notify({Title="Code Added",Desc=v,Time=3})
    end
end})
T5:Button({Title="Redeem All Codes Now",Callback=function()task.spawn(DoAutoRedeem)end})
T5:Button({Title="Clear Saved Codes",Callback=function()JC.RedeemCodes={};CS();Window:Notify({Title="Codes Cleared",Time=2})end})
T5:Toggle({Title="Auto Redeem on Load",Value=JC.AutoRedeem,Callback=function(v)JC.AutoRedeem=v;CS()end})
Window:Line()

-- ════ TAB 6: PLAYER + SETTINGS ══════
local T6=Window:Tab({Title="Settings",Icon="wrench"})
T6:Section({Title="Player"})
T6:Slider({Title="WalkSpeed",Min=16,Max=250,Rounding=0,Value=JC.WalkSpeed,Callback=function(v)
    JC.WalkSpeed=v;CS(); local h=HUM(); if h then h.WalkSpeed=v end
end})
T6:Slider({Title="JumpPower",Min=50,Max=300,Rounding=0,Value=JC.JumpPower,Callback=function(v)
    JC.JumpPower=v;CS(); local h=HUM(); if h then h.JumpPower=v end
end})
T6:Section({Title="System"})
local AfkConn
T6:Toggle({Title="Anti-AFK",Value=JC.AntiAFK,Callback=function(v)
    JC.AntiAFK=v;CS()
    if v then AfkConn=LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end)
    else if AfkConn then AfkConn:Disconnect();AfkConn=nil end end
end})
if JC.AntiAFK then AfkConn=LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    task.wait(1); VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
end) end
T6:Button({Title="Copy Discord",Desc="discord.gg/k2wdyy8QMN",Callback=function()
    if setclipboard then setclipboard("https://discord.gg/k2wdyy8QMN") end
    Window:Notify({Title="Copied!",Time=2})
end})
T6:Section({Title="Config"})
T6:Toggle({Title="Auto Save",Value=JC.AutoSave,Callback=function(v)JC.AutoSave=v;Save();Window:Notify({Title="Auto Save "..(v and "ON" or "OFF"),Time=2})end})
T6:Toggle({Title="Auto Load",Value=JC.AutoLoad,Callback=function(v)JC.AutoLoad=v;Save();Window:Notify({Title="Auto Load "..(v and "ON" or "OFF"),Time=2})end})
T6:Button({Title="Save Now",Callback=function()Save();Window:Notify({Title="Saved!",Time=2})end})
T6:Button({Title="Reset Defaults",Callback=function()JC=DEF;Save();Window:Notify({Title="Reset",Desc="Rejoin for full effect",Time=4})end})

-- ════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════
if JC.AutoRedeem   then task.spawn(DoAutoRedeem) end
if JC.AutoHarvest  then StartTask("harvest",     DoAutoHarvest,   0.8) end
if JC.AutoShovelFruit then StartTask("shovelFruit",DoAutoShovelFruit,1.2) end
if JC.AutoShovelTree  then StartTask("shovelTree", DoAutoShovelTree, 2) end
if JC.AutoWater    then StartTask("water",        DoAutoWater,     2) end
if JC.AutoSprinkler then StartTask("sprinkler",   DoAutoSprinkler, 5) end
if JC.AutoPlant    then StartTask("plant",        DoAutoPlant,    0.45) end
if JC.AutoSell     then StartTask("sell",function()DoAutoSell(false)end,tonumber(JC.AutoSellDelay) or 10) end
if JC.AutoBuySeeds then StartTask("buySeeds",     DoAutoBuySeeds,  3) end
if JC.AutoBuyGears then StartTask("buyGears",     DoAutoBuyGears,  5) end
if JC.AutoBuyBestSeed then StartTask("buyBestSeed",DoAutoBuySeeds, 3) end
if JC.AutoBuyBestGear then StartTask("buyBestGear",DoAutoBuyGears, 5) end
if JC.AutoQuest    then StartTask("quest",        DoAutoQuest,     2) end
if JC.PlantESP     then StartTask("esp",          DoPlantESP,      2) end

Window:Notify({
    Title = "JinHub v3  ★  God Jin",
    Desc  = (JC.AutoLoad and "[Config Loaded] " or "")
          .."[CTRL] = toggle | All tabs visible",
    Time  = 5
})
