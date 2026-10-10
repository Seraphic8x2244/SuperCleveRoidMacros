-- Optional, storage-independent immunity providers for Vanilla WoW (Lua 5.0).
-- RegisterImmunityProvider(id, displayName, check)
-- check(unitId, spellOrSchool) must return a boolean, matching CheckImmunity.
local CR = _G.CleveRoids
local providers = {}
local failed = {}
local ORDER = {}
local BUILTIN = "builtin"

function CR.RegisterImmunityProvider(id, name, check)
    if type(id) ~= "string" or id == "" or id == BUILTIN
        or type(name) ~= "string" or name == ""
        or type(check) ~= "function" or providers[id] then
        return false
    end
    providers[id] = { name = name, check = check }
    table.insert(ORDER, id)
    if CR.UpdateImmunityProviderButton then CR.UpdateImmunityProviderButton() end
    return true
end

function CR.GetSelectedImmunityProvider()
    local saved = CleveRoidMacros and CleveRoidMacros.immunityProvider
    return type(saved) == "string" and saved or BUILTIN
end

function CR.GetActiveImmunityProvider()
    local selected = CR.GetSelectedImmunityProvider()
    if selected ~= BUILTIN and providers[selected] and not failed[selected] then
        return selected
    end
    return BUILTIN
end

function CR.IsExternalImmunityActive()
    return CR.GetActiveImmunityProvider() ~= BUILTIN
end

function CR.QueryExternalImmunity(unitId, spellOrSchool)
    local id = CR.GetActiveImmunityProvider()
    if id == BUILTIN then return false, nil end
    local ok, answer = pcall(providers[id].check, unitId, spellOrSchool)
    if ok and type(answer) == "boolean" then return true, answer end
    failed[id] = true -- Fail closed for this session; never mix provider answers.
    if CR.Print then
        CR.Print("|cffff9900Immunity provider '" .. providers[id].name ..
          "' failed. Built-in immunity restored for this session; selection retained.|r")
    end
    return false, nil
end

function CR.SelectImmunityProvider(id)
    if id ~= BUILTIN and not providers[id] then return false end
    CleveRoidMacros = CleveRoidMacros or {}
    CleveRoidMacros.immunityProvider = id
    failed[id] = nil
    if CR.UpdateImmunityProviderButton then CR.UpdateImmunityProviderButton() end
    if CR.QueueActionUpdate then CR.QueueActionUpdate() end
    return true
end

-- The Blizzard MacroFrameTab2 is the character-specific macro tab.
-- Anchor on it rather than rearranging the existing tab strip.
local providerButton
local menu
local function ShowProviderMenu()
    if not menu then
        menu = CreateFrame("Frame", "CleveRoidsImmunityProviderMenu", UIParent)
        menu:SetFrameStrata("DIALOG")
        menu:SetWidth(190)
        menu:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true,
            tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
        menu:SetBackdropColor(0,0,0,0.95)
    end
    local ids = { BUILTIN }
    for _, id in ipairs(ORDER) do table.insert(ids, id) end
    for i, id in ipairs(ids) do
        local row = getglobal("CleveRoidsImmunityProviderRow"..i)
        if not row then
            row = CreateFrame("Button", "CleveRoidsImmunityProviderRow"..i, menu)
            row:SetHeight(20)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 8, 0)
            row.label = label
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -6-(i-1)*20)
        row:SetWidth(178)
        row.label:SetText((id == CR.GetSelectedImmunityProvider() and "|cff00ff00* |r" or "  ") ..
            (id == BUILTIN and "SCRM Built-in" or providers[id].name) ..
            (id ~= BUILTIN and failed[id] and " (failed)" or ""))
        row:SetScript("OnClick", function()
            CR.SelectImmunityProvider(id)
            menu:Hide()
        end)
        row:Show()
    end
    for i=table.getn(ids)+1,table.getn(ORDER)+1 do
        local row=getglobal("CleveRoidsImmunityProviderRow"..i)
        if row then row:Hide() end
    end
    menu:SetHeight(12+table.getn(ids)*20)
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOM", providerButton, "TOP", 0, 3)
    menu:Show()
end

function CR.UpdateImmunityProviderButton()
    if not MacroFrameTab2 then return end
    if not providerButton then
        providerButton = CreateFrame("Button", "CleveRoidsImmunityProviderButton", MacroFrame, "UIPanelButtonTemplate")
        providerButton:SetWidth(118)
        providerButton:SetHeight(22)
        providerButton:SetText("Immunity Provider")
        providerButton:SetPoint("RIGHT", MacroFrameTab2, "LEFT", -4, 0)
        providerButton:SetScript("OnClick", function()
            if menu and menu:IsShown() then menu:Hide() else ShowProviderMenu() end
        end)
    end
    providerButton:Show()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function()
    CR.UpdateImmunityProviderButton()
end)
