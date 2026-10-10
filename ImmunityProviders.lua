-- Optional, storage-independent immunity providers for Vanilla WoW (Lua 5.0).
-- RegisterImmunityProvider(id, displayName, check)
-- check(unitId, spellOrSchool): true = immune, false = vulnerable, nil = unknown.
-- Errors are reported separately; no legacy-data fallback.
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
    failed[id] = nil -- A late registration may restore a previously missing choice.
    table.insert(ORDER, id)
    if CR.UpdateImmunityProviderButton then CR.UpdateImmunityProviderButton() end
    return true
end

function CR.GetSelectedImmunityProvider()
    local saved = CleveRoidMacros and CleveRoidMacros.immunityProvider
    return type(saved) == "string" and saved or BUILTIN
end

-- The selected authority is independent of availability and health.
function CR.GetActiveImmunityProvider()
    return CR.GetSelectedImmunityProvider()
end

function CR.IsExternalImmunityActive()
    return CR.GetActiveImmunityProvider() ~= BUILTIN
end

function CR.QueryExternalImmunity(unitId, spellOrSchool)
    local id = CR.GetSelectedImmunityProvider()
    if id == BUILTIN then return false, nil end

    -- Handled remains true for an absent/failed provider. nil is unknown,
    -- never permission to consult the legacy learner or stored facts.
    if not failed[id] then
        local provider = providers[id]
        if not provider then
            failed[id] = true
            if CR.Print then
                CR.Print("|cffff9900Immunity provider '" .. id ..
                    "' unavailable. Select SCRM Built-in explicitly to restore legacy immunities.|r")
            end
        else
            local ok, answer = pcall(provider.check, unitId, spellOrSchool)
            if ok and (answer == nil or type(answer) == "boolean") then
                return true, answer
            end
            failed[id] = true
            if CR.Print then
                CR.Print("|cffff9900Immunity provider '" .. provider.name ..
                    "' failed. Immunity is unknown until the provider recovers or is changed.|r")
            end
        end
        if CR.UpdateImmunityProviderButton then CR.UpdateImmunityProviderButton() end
    end
    return true, nil
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

-- Use the standard Blizzard dropdown, not an extra macro tab.
-- This stays available when only SCRM Built-in is registered.
local providerRow
local providerDropdown

local function RefreshProviderSelection()
    if not providerDropdown then return end
    local id = CR.GetSelectedImmunityProvider()
    local item = providers[id]
    local name = id == BUILTIN and "SCRM Built-in" or
        (item and (item.name .. (failed[id] and " (error)" or ""))
            or (id .. " (unavailable)"))
    UIDropDownMenu_SetText(name, providerDropdown)
end

local function PopulateProviders()
    local entries = { BUILTIN }
    for _, id in ipairs(ORDER) do
        table.insert(entries, id)
    end
    -- Keep the chosen provider visible even if that addon did not register.
    local selected = CR.GetSelectedImmunityProvider()
    if selected ~= BUILTIN and not providers[selected] then
        table.insert(entries, selected)
    end
    for _, id in ipairs(entries) do
        local info = {} -- Vanilla 1.12 has no UIDropDownMenu_CreateInfo
        info.text = id == BUILTIN and "SCRM Built-in" or
            (providers[id] and providers[id].name or (id .. " (unavailable)"))
        info.checked = id == selected
        info.disabled = id ~= BUILTIN and not providers[id]
        info.func = function()
            CR.SelectImmunityProvider(id)
            RefreshProviderSelection()
        end
        UIDropDownMenu_AddButton(info)
    end
end

function CR.UpdateImmunityProviderButton()
    if not MacroFrame or not MacroDeleteButton or not UIDropDownMenu_Initialize then return end
    if not providerRow then
        providerRow = CreateFrame("Frame", "CleveRoidsImmunityProviderRow", MacroFrame)
        providerRow:SetWidth(450)
        providerRow:SetHeight(22)
        -- Follow the existing Delete button, including UI skin/layout changes.
        providerRow:SetPoint("BOTTOMLEFT", MacroDeleteButton, "TOPLEFT", 0, 2)

        local label = providerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", providerRow, "LEFT", 0, 0)
        label:SetText("Immunity Provider:")

        providerDropdown = CreateFrame("Frame", "CleveRoidsImmunityProviderDropdown",
            providerRow, "UIDropDownMenuTemplate")
        providerDropdown:SetPoint("LEFT", label, "RIGHT", -9, -2)
        UIDropDownMenu_SetWidth(230, providerDropdown)
        UIDropDownMenu_Initialize(providerDropdown, PopulateProviders)
    end
    RefreshProviderSelection()
    providerRow:Show()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function()
    CR.UpdateImmunityProviderButton()
end)
