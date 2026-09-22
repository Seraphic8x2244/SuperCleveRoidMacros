--[[
    Immunity testing/management UI
    Framework-stage inspection surface only.  No immunity inference lives here.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local DATA_VERSION = 1
local MAIN_WIDTH = 710
local MAIN_HEIGHT = 690
local TARGET_WIDTH = 300
local COLUMN_WIDTH = 138
local COLUMN_GAP = 6
local SECTION_WIDTH = 670
local HEADER_ICON_SIZE = 18
local MODAL_FRAME_LEVEL_OFFSET = 50
local TARGET_MODEL_WIDTH = 118
local TARGET_MODEL_HEIGHT = 126
local TARGET_MODEL_REVOLUTION_SECONDS = 12

local widgetCounter = 0
local mainFrame
local targetFrame
local clearDialog
local historyDialog
local ccSection
local spellSection
local legacyTitle
local legacyList
local targetNameText
local targetInfoText
local targetModel
local targetModelRotation = 0
local targetModelRotating = false
local targetCCList
local targetSpellList
local targetLiveList

local CC_COLUMNS = {
    { key = "cc", type = "cc", label = "CC", broad = true, iconSpellID = 853 }, -- Hammer of Justice
    { key = "cc_charm", type = "charm", mechanicID = 1, label = "Charm", iconSpellID = 6358 }, -- Seduction
    { key = "cc_disorient", type = "disorient", mechanicID = 2, label = "Disorient", iconSpellID = 1776 }, -- Gouge
    { key = "cc_fear", type = "fear", mechanicID = 5, label = "Fear", iconSpellID = 5782 }, -- Fear
    { key = "cc_root", type = "root", mechanicID = 7, label = "Root", iconSpellID = 339 }, -- Entangling Roots
    { key = "cc_silence", type = "silence", mechanicID = 9, label = "Silence", iconSpellID = 15487 }, -- Silence
    { key = "cc_sleep", type = "sleep", mechanicID = 10, label = "Sleep", iconSpellID = 2637 }, -- Hibernate
    { key = "cc_snare", type = "snare", mechanicID = 11, label = "Snare", iconSpellID = 1715 }, -- Hamstring
    { key = "cc_stun", type = "stun", mechanicID = 12, label = "Stun", iconSpellID = 853 }, -- Hammer of Justice
    { key = "cc_freeze", type = "freeze", mechanicID = 13, label = "Freeze", iconSpellID = 122 }, -- Frost Nova
    { key = "cc_knockout", type = "knockout", mechanicID = 14, label = "Knockout (Sap)", iconSpellID = 6770 }, -- Sap
    { key = "cc_polymorph", type = "polymorph", mechanicID = 17, label = "Polymorph", iconSpellID = 118 }, -- Polymorph
    { key = "cc_banish", type = "banish", mechanicID = 18, label = "Banish", iconSpellID = 710 }, -- Banish
    { key = "cc_shackle", type = "shackle", mechanicID = 20, label = "Shackle", iconSpellID = 9484 }, -- Shackle Undead
    { key = "cc_horror", type = "horror", mechanicID = 24, label = "Horror", iconSpellID = 6789 }, -- Death Coil
    { key = "cc_daze", type = "daze", mechanicID = 27, label = "Daze", iconSpellID = 5116 }, -- Concussive Shot
}

local SPELL_COLUMNS = {
    { key = "all", type = "all", label = "All", iconSpellID = 642 }, -- Divine Shield
    { key = "spell", type = "spell", label = "Spell", iconSpellID = 7121 }, -- Anti-Magic Shield
    { key = "physical", type = "physical", label = "Physical", iconSpellID = 1022 }, -- Blessing of Protection
    { key = "holy", type = "holy", label = "Holy", iconSpellID = 879 }, -- Exorcism
    { key = "fire", type = "fire", label = "Fire", iconSpellID = 133 }, -- Fireball
    { key = "nature", type = "nature", label = "Nature", iconSpellID = 403 }, -- Lightning Bolt
    { key = "frost", type = "frost", label = "Frost", iconSpellID = 116 }, -- Frostbolt
    { key = "shadow", type = "shadow", label = "Shadow", iconSpellID = 686 }, -- Shadow Bolt
    { key = "arcane", type = "arcane", label = "Arcane", iconSpellID = 5143 }, -- Arcane Missiles
    { key = "bleed", type = "bleed", label = "Bleed", iconSpellID = 772 }, -- Rend
}

local TYPE_LABELS = {
    cc = "CC",
    charm = "Charm",
    disorient = "Disorient",
    fear = "Fear",
    root = "Root",
    silence = "Silence",
    sleep = "Sleep",
    snare = "Snare",
    stun = "Stun",
    freeze = "Freeze",
    knockout = "Knockout (Sap)",
    polymorph = "Polymorph",
    banish = "Banish",
    shackle = "Shackle",
    horror = "Horror",
    daze = "Daze",
    all = "All",
    spell = "Spell",
    physical = "Physical",
    holy = "Holy",
    fire = "Fire",
    nature = "Nature",
    frost = "Frost",
    shadow = "Shadow",
    arcane = "Arcane",
    bleed = "Bleed",
    unknown = "Unknown",
}

local SPELL_GENERAL_KEYS = {
    all = true,
    spell = true,
    physical = true,
    holy = true,
    fire = true,
    nature = true,
    frost = true,
    shadow = true,
    arcane = true,
    bleed = true,
    unknown = true,
}

local CLASSIFICATION_LABELS = {
    normal = "Normal",
    trivial = "Trivial",
    elite = "Elite",
    rare = "Rare",
    rareelite = "Rare Elite",
    worldboss = "Boss",
}

local function StopTargetModelRotation()
    if targetModel then
        targetModel:SetScript("OnUpdate", nil)
    end
    targetModelRotating = false
end

local function StartTargetModelRotation()
    if not targetModel or targetModelRotating then return end

    targetModelRotating = true
    targetModel:SetScript("OnUpdate", function()
        local elapsed = arg1 or 0
        local speed = (2 * math.pi) / TARGET_MODEL_REVOLUTION_SECONDS
        targetModelRotation = targetModelRotation + (elapsed * speed)
        if targetModelRotation >= (2 * math.pi) then
            targetModelRotation = targetModelRotation - (2 * math.pi)
        end
        targetModel:SetRotation(targetModelRotation)
    end)
end

local function HideTargetModel()
    StopTargetModelRotation()
    if targetModel then
        targetModel:Hide()
    end
end

local function RefreshTargetModel()
    if not targetModel or not mainFrame or not mainFrame:IsShown() or not UnitExists("target") then
        HideTargetModel()
        return
    end

    targetModelRotation = 0
    local ok = pcall(function()
        targetModel:SetUnit("target")
        targetModel:SetRotation(targetModelRotation)
    end)

    if not ok then
        HideTargetModel()
        return
    end

    targetModel:Show()
    StartTargetModelRotation()
end


local function NewWidgetName(prefix)
    widgetCounter = widgetCounter + 1
    return "CleveRoidsImmunity" .. prefix .. tostring(widgetCounter)
end

local function ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", NewWidgetName("Button"), parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 90)
    button:SetHeight(height or 22)
    button:SetText(text or "")
    return button
end

local function CreateMessageList(parent)
    local list = CreateFrame("ScrollingMessageFrame", NewWidgetName("List"), parent)
    list:SetFont("Fonts\\FRIZQT__.TTF", 10)
    list:SetJustifyH("LEFT")
    list:SetMaxLines(1000)
    list:SetFading(false)
    if list.SetTimeVisible then
        list:SetTimeVisible(999999)
    end
    if list.EnableMouseWheel then
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function()
            local delta = arg1 or 0
            if delta > 0 then
                list:ScrollUp()
            elseif delta < 0 then
                list:ScrollDown()
            end
        end)
    end
    return list
end

local function ClearMessageList(list)
    if list and list.Clear then
        list:Clear()
    end
end

local function TableCount(t)
    local count = 0
    if type(t) ~= "table" then return 0 end
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function CountAllRecords(data)
    local count = 0
    if type(data) ~= "table" then return 0 end
    for _, bucket in pairs(data) do
        if type(bucket) == "table" then
            count = count + TableCount(bucket)
        end
    end
    return count
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[DeepCopy(key)] = DeepCopy(child)
    end
    return copy
end

local function FormatStoredLine(npcName, data)
    if data == true then
        return npcName
    end
    if type(data) == "table" then
        local suffix = ""
        if data.spell then
            suffix = suffix .. " [" .. tostring(data.spell) .. "]"
        end
        if data.buff then
            suffix = suffix .. " [buff: " .. tostring(data.buff) .. "]"
        end
        if suffix == "" then
            suffix = " [legacy]"
        end
        return npcName .. suffix
    end
    return npcName .. " [" .. tostring(data) .. "]"
end

local function SortedBucketLines(bucket)
    local names = {}
    local lines = {}
    if type(bucket) ~= "table" then
        return lines
    end
    for npcName in pairs(bucket) do
        table.insert(names, npcName)
    end
    table.sort(names)
    for _, npcName in ipairs(names) do
        table.insert(lines, FormatStoredLine(npcName, bucket[npcName]))
    end
    return lines
end

local function AddLines(list, lines)
    ClearMessageList(list)
    if table.getn(lines) == 0 then
        list:AddMessage("|cff777777(none)|r")
        return
    end
    for _, line in ipairs(lines) do
        list:AddMessage(line)
    end
end

local function ColumnHeader(column, count)
    if column.mechanicID then
        return tostring(column.mechanicID) .. " " .. column.label .. " (" .. tostring(count) .. ")"
    end
    return column.label .. " (" .. tostring(count) .. ")"
end

local function CreateHorizontalSlider(parent)
    local slider = CreateFrame("Slider", NewWidgetName("HSlider"), parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(12)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(0, 1)
    slider:SetValue(0)
    if slider.SetValueStep then
        slider:SetValueStep(12)
    end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 0)
    track:SetTexture("Interface\\Buttons\\WHITE8x8")
    track:SetVertexColor(0.18, 0.18, 0.18, 0.9)

    return slider
end

local function SetHorizontalSectionOffset(section, offset)
    offset = offset or 0
    if offset < 0 then offset = 0 end
    if offset > (section.maxScroll or 0) then
        offset = section.maxScroll or 0
    end

    section.offset = offset
    section.viewport:SetHorizontalScroll(0)
    section.child:ClearAllPoints()
    section.child:SetPoint("TOPLEFT", section.viewport, "TOPLEFT", -offset, 0)
end

local function CreateDataColumn(parent, column, height)
    local frame = CreateFrame("Frame", NewWidgetName("Column"), parent)
    frame:SetWidth(COLUMN_WIDTH)
    frame:SetHeight(height)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(HEADER_ICON_SIZE)
    icon:SetHeight(HEADER_ICON_SIZE)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -3)
    icon:SetTexture(
        (column.iconSpellID and C_Spell.GetSpellTexture(column.iconSpellID)) or
        CleveRoids.unknownTexture or
        "Interface\\Icons\\INV_Misc_QuestionMark"
    )
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    header:SetHeight(30)
    header:SetJustifyH("LEFT")
    header:SetJustifyV("TOP")
    header:SetText(column.label)

    local list = CreateMessageList(frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -34)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 22)

    local up = CreateButton(frame, "^", 22, 18)
    up:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 1)
    up:SetScript("OnClick", function()
        list:ScrollUp()
    end)

    local down = CreateButton(frame, "v", 22, 18)
    down:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 1)
    down:SetScript("OnClick", function()
        list:ScrollDown()
    end)

    column.frame = frame
    column.header = header
    column.list = list
end

local function CreateHorizontalSection(parent, topOffset, height, columns, namePrefix)
    local section = {}

    section.viewport = CreateFrame("ScrollFrame", NewWidgetName(namePrefix .. "Scroll"), parent)
    section.viewport:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, topOffset)
    section.viewport:SetWidth(SECTION_WIDTH)
    section.viewport:SetHeight(height)

    section.child = CreateFrame("Frame", NewWidgetName(namePrefix .. "Child"), section.viewport)
    section.child:SetHeight(height)
    section.child:SetWidth(SECTION_WIDTH)
    section.child:SetPoint("TOPLEFT", section.viewport, "TOPLEFT", 0, 0)
    section.viewport:SetScrollChild(section.child)

    for _, column in ipairs(columns) do
        CreateDataColumn(section.child, column, height - 18)
    end

    section.slider = CreateHorizontalSlider(parent)
    section.slider:SetPoint("TOPLEFT", section.viewport, "BOTTOMLEFT", 0, -2)
    section.slider:SetWidth(SECTION_WIDTH)
    section.columns = columns
    section.maxScroll = 0
    section.offset = 0
    section.slider:SetScript("OnValueChanged", function()
        SetHorizontalSectionOffset(section, arg1 or 0)
    end)
    return section
end

local function RefreshHorizontalSection(section)
    local x = 0
    local visibleCount = 0
    local data = CleveRoids_ImmunityData or {}

    for _, column in ipairs(section.columns) do
        local bucket = data[column.key]
        local count = TableCount(bucket)
        local visible = true
        if column.broad and count == 0 then
            visible = false
        end

        if visible then
            column.frame:ClearAllPoints()
            column.frame:SetPoint("TOPLEFT", section.child, "TOPLEFT", x, 0)
            column.frame:Show()
            column.header:SetText(ColumnHeader(column, count))
            AddLines(column.list, SortedBucketLines(bucket))
            x = x + COLUMN_WIDTH + COLUMN_GAP
            visibleCount = visibleCount + 1
        else
            column.frame:Hide()
        end
    end

    local previousOffset = section.offset or 0

    local contentWidth = x
    if contentWidth < SECTION_WIDTH then
        contentWidth = SECTION_WIDTH
    end
    section.child:SetWidth(contentWidth)

    local maxScroll = contentWidth - SECTION_WIDTH
    if maxScroll < 0 then maxScroll = 0 end
    section.maxScroll = maxScroll

    if maxScroll == 0 then
        section.slider:Hide()
        section.slider:SetValue(0)
        SetHorizontalSectionOffset(section, 0)
    else
        section.slider:Show()
        section.slider:SetMinMaxValues(0, maxScroll)

        if previousOffset > maxScroll then
            previousOffset = maxScroll
        end

        -- Leftmost columns are the initial state. Moving the thumb right increases
        -- the offset and physically moves the column strip left, revealing the
        -- additional columns on the right.
        section.slider:SetValue(previousOffset)
        SetHorizontalSectionOffset(section, previousOffset)
    end
end

local function RefreshLegacyUnknown()
    local bucket = CleveRoids_ImmunityData and CleveRoids_ImmunityData.unknown
    local count = TableCount(bucket)
    legacyTitle:SetText("Legacy / diagnostic unknown (" .. tostring(count) .. ")")
    AddLines(legacyList, SortedBucketLines(bucket))
end

local function ImmunityLabel(entry)
    local label = TYPE_LABELS[entry.immunityType] or tostring(entry.immunityType or "Unknown")
    if entry.mechanicID then
        return tostring(entry.mechanicID) .. " " .. label
    end
    return label
end

local function FormatRecordedTargetEntry(entry)
    local text = ImmunityLabel(entry)
    if entry.buff then
        text = text .. " [buff: " .. tostring(entry.buff) .. "]"
        if entry.active == false then
            text = text .. " (inactive)"
        end
    end
    if entry.spell then
        text = text .. " [" .. tostring(entry.spell) .. "]"
    end
    return text
end

local function FormatLiveDetail(detail)
    if detail == nil then return nil end
    if type(detail) == "number" then
        local spellName = C_Spell.GetSpellName(detail)
        if spellName then
            return spellName .. " " .. tostring(detail)
        end
        return "SpellID:" .. tostring(detail)
    end
    return tostring(detail)
end

local function AddLiveTargetEntries(list, heading, entries)
    if table.getn(entries) == 0 then return end
    list:AddMessage("|cffffcc00" .. heading .. "|r")
    for _, entry in ipairs(entries) do
        local text = ImmunityLabel(entry)
        local detail = FormatLiveDetail(entry.detail)
        if detail then
            text = text .. " - " .. detail
        end
        if entry.source then
            text = text .. " [" .. tostring(entry.source) .. "]"
        end
        list:AddMessage(text)
    end
end

local function RefreshTargetPanel()
    if not targetNameText then return end

    ClearMessageList(targetCCList)
    ClearMessageList(targetSpellList)
    ClearMessageList(targetLiveList)

    if not CleveRoids.GetImmunityDebugSnapshot then
        targetNameText:SetText("Framework debug state unavailable")
        if targetInfoText then targetInfoText:SetText("") end
        HideTargetModel()
        return
    end

    local snapshot = CleveRoids.GetImmunityDebugSnapshot("target")
    if not snapshot or not snapshot.exists then
        targetNameText:SetText("No current target")
        if targetInfoText then targetInfoText:SetText("") end
        HideTargetModel()
        targetCCList:AddMessage("|cff777777(none)|r")
        targetSpellList:AddMessage("|cff777777(none)|r")
        targetLiveList:AddMessage("|cff777777No live immunity state|r")
        return
    end

    targetNameText:SetText(snapshot.name or "Unknown")

    local creatureID = snapshot.creatureEntry and tostring(snapshot.creatureEntry) or "-"
    local level = UnitLevel("target")
    local levelText = level and level > 0 and tostring(level) or "??"
    local creatureType = UnitCreatureType("target") or "Unknown"
    local classification = UnitClassification("target")
    local classificationText = CLASSIFICATION_LABELS[classification] or tostring(classification or "Unknown")

    if targetInfoText then
        targetInfoText:SetText(
            "Mob ID: " .. creatureID ..
            "\nLevel: " .. levelText ..
            "\nType: " .. creatureType ..
            "\nClass: " .. classificationText
        )
    end

    RefreshTargetModel()

    if table.getn(snapshot.recordedCC) == 0 then
        targetCCList:AddMessage("|cff777777(none)|r")
    else
        for _, entry in ipairs(snapshot.recordedCC) do
            targetCCList:AddMessage(FormatRecordedTargetEntry(entry))
        end
    end

    if table.getn(snapshot.recordedSpell) == 0 then
        targetSpellList:AddMessage("|cff777777(none)|r")
    else
        for _, entry in ipairs(snapshot.recordedSpell) do
            targetSpellList:AddMessage(FormatRecordedTargetEntry(entry))
        end
    end

    AddLiveTargetEntries(targetLiveList, "LIVE CC", snapshot.liveCC)
    AddLiveTargetEntries(targetLiveList, "LIVE SPELL", snapshot.liveSpell)

    if table.getn(snapshot.explanations) > 0 then
        targetLiveList:AddMessage("|cff66ccffEXPLANATION (not immunity)|r")
        for _, entry in ipairs(snapshot.explanations) do
            local detail = FormatLiveDetail(entry.detail)
            local text = "Reflection"
            if detail then
                text = text .. " - " .. detail
            end
            text = text .. " [reflection]"
            targetLiveList:AddMessage(text)
        end
    end

    if table.getn(snapshot.legacy) > 0 then
        targetLiveList:AddMessage("|cffaaaaaaLEGACY UNKNOWN|r")
        for _, entry in ipairs(snapshot.legacy) do
            targetLiveList:AddMessage(FormatRecordedTargetEntry(entry))
        end
    end

    if table.getn(snapshot.liveCC) == 0 and
       table.getn(snapshot.liveSpell) == 0 and
       table.getn(snapshot.explanations) == 0 and
       table.getn(snapshot.legacy) == 0 then
        targetLiveList:AddMessage("|cff777777No live immunity/explanation state|r")
    end
end

local function RefreshAll()
    if not mainFrame then return end
    RefreshHorizontalSection(ccSection)
    RefreshHorizontalSection(spellSection)
    RefreshLegacyUnknown()
    RefreshTargetPanel()
end

local function EnsureBackupTable()
    CleveRoidMacros = CleveRoidMacros or {}
    CleveRoidMacros.immunityBackups = CleveRoidMacros.immunityBackups or {}
    return CleveRoidMacros.immunityBackups
end

local function BackupCurrent(reason)
    local backups = EnsureBackupTable()
    local stamp = time and time() or 0
    local label

    if date then
        if stamp and stamp > 0 then
            label = date("%Y-%m-%d %H:%M:%S", stamp)
        else
            label = date("%Y-%m-%d %H:%M:%S")
        end
    end
    if not label then
        label = "Backup " .. tostring(table.getn(backups) + 1)
    end

    table.insert(backups, {
        timestamp = stamp,
        label = label,
        immunityDataVersion = DATA_VERSION,
        reason = reason,
        data = DeepCopy(CleveRoids_ImmunityData or {}),
    })

    CleveRoids.Print("Immunity backup created: " .. label)
    if historyDialog and historyDialog:IsShown() then
        historyDialog.index = table.getn(backups)
        historyDialog.Refresh()
    end
end

local function NotifyDataChanged()
    if CleveRoids.NotifyImmunityDataChanged then
        CleveRoids.NotifyImmunityDataChanged()
    else
        RefreshAll()
    end
end

local function ClearCCStorage(key)
    CleveRoids_ImmunityData = CleveRoids_ImmunityData or {}
    if key == "*" then
        for storageKey in pairs(CleveRoids_ImmunityData) do
            if storageKey == "cc" or string.sub(storageKey, 1, 3) == "cc_" then
                CleveRoids_ImmunityData[storageKey] = nil
            end
        end
        CleveRoids.Print("Cleared all CC immunity data")
    else
        CleveRoids_ImmunityData[key] = nil
        CleveRoids.Print("Cleared " .. tostring(key) .. " immunity data")
    end
    NotifyDataChanged()
end

local function ClearSpellStorage(key)
    CleveRoids_ImmunityData = CleveRoids_ImmunityData or {}
    if key == "*" then
        for storageKey in pairs(SPELL_GENERAL_KEYS) do
            CleveRoids_ImmunityData[storageKey] = nil
        end
        CleveRoids.Print("Cleared all spell/school immunity data")
    else
        CleveRoids_ImmunityData[key] = nil
        CleveRoids.Print("Cleared " .. tostring(key) .. " immunity data")
    end
    NotifyDataChanged()
end

local function ClearAllStorage()
    CleveRoids_ImmunityData = {}
    CleveRoids.Print("Cleared all learned immunity data")
    NotifyDataChanged()
end

local function BuildClearOptions(mode)
    local options = {}

    if mode == "cc" then
        table.insert(options, { key = "*", label = "All CC immunity data" })
        if TableCount(CleveRoids_ImmunityData and CleveRoids_ImmunityData.cc) > 0 then
            table.insert(options, { key = "cc", label = "Broad CC" })
        end
        for _, column in ipairs(CC_COLUMNS) do
            if not column.broad then
                table.insert(options, {
                    key = column.key,
                    label = (column.mechanicID and (tostring(column.mechanicID) .. " ") or "") .. column.label,
                })
            end
        end
    elseif mode == "spell" then
        table.insert(options, { key = "*", label = "All spell/school immunity data" })
        for _, column in ipairs(SPELL_COLUMNS) do
            table.insert(options, { key = column.key, label = column.label })
        end
        if TableCount(CleveRoids_ImmunityData and CleveRoids_ImmunityData.unknown) > 0 then
            table.insert(options, { key = "unknown", label = "Legacy unknown" })
        end
    else
        table.insert(options, { key = "*", label = "ALL learned immunity data" })
    end

    return options
end

local function CreateClearDialog(parent)
    local frame = CreateFrame("Frame", "CleveRoidsImmunityClearDialog", parent)
    frame:SetWidth(430)
    frame:SetHeight(180)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + MODAL_FRAME_LEVEL_OFFSET)
    ApplyBackdrop(frame)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetText("Clear Immunity Data")
    frame.title = title

    local selected = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selected:SetPoint("TOP", title, "BOTTOM", 0, -28)
    selected:SetWidth(280)
    selected:SetHeight(32)
    selected:SetJustifyH("CENTER")
    frame.selected = selected

    local prev = CreateButton(frame, "<", 35, 22)
    prev:SetPoint("RIGHT", selected, "LEFT", -8, 0)
    prev:SetScript("OnClick", function()
        if not frame.options then return end
        frame.index = frame.index - 1
        if frame.index < 1 then frame.index = table.getn(frame.options) end
        frame.Refresh()
    end)

    local nextButton = CreateButton(frame, ">", 35, 22)
    nextButton:SetPoint("LEFT", selected, "RIGHT", 8, 0)
    nextButton:SetScript("OnClick", function()
        if not frame.options then return end
        frame.index = frame.index + 1
        if frame.index > table.getn(frame.options) then frame.index = 1 end
        frame.Refresh()
    end)

    local backup = CreateButton(frame, "Backup", 90, 24)
    backup:SetPoint("BOTTOM", frame, "BOTTOM", -105, 20)
    backup:SetScript("OnClick", function()
        BackupCurrent("Manual backup from clear dialog")
    end)

    local clear = CreateButton(frame, "Clear", 90, 24)
    clear:SetPoint("LEFT", backup, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        local option = frame.options and frame.options[frame.index]
        if not option then return end

        if frame.mode == "cc" then
            ClearCCStorage(option.key)
        elseif frame.mode == "spell" then
            ClearSpellStorage(option.key)
        else
            ClearAllStorage()
        end
        frame:Hide()
    end)

    local cancel = CreateButton(frame, "Cancel", 90, 24)
    cancel:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        frame:Hide()
    end)

    function frame.Refresh()
        local option = frame.options and frame.options[frame.index]
        if option then
            frame.selected:SetText(option.label)
        else
            frame.selected:SetText("(none)")
        end
    end

    return frame
end

local function ShowClearDialog(mode)
    clearDialog.mode = mode
    clearDialog.options = BuildClearOptions(mode)
    clearDialog.index = 1
    if mode == "cc" then
        clearDialog.title:SetText("Clear CC Immunity Data")
    elseif mode == "spell" then
        clearDialog.title:SetText("Clear Spell Immunity Data")
    else
        clearDialog.title:SetText("Clear ALL Learned Immunity Data")
    end
    clearDialog.Refresh()
    clearDialog:Show()
end

local function CreateHistoryDialog(parent)
    local frame = CreateFrame("Frame", "CleveRoidsImmunityBackupHistory", parent)
    frame:SetWidth(500)
    frame:SetHeight(250)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 15)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + MODAL_FRAME_LEVEL_OFFSET)
    ApplyBackdrop(frame)
    frame:Hide()
    frame.index = 1

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetText("Immunity Backup History")

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOP", title, "BOTTOM", 0, -12)
    frame.countText = countText

    local selected = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selected:SetPoint("TOP", countText, "BOTTOM", 0, -16)
    selected:SetWidth(360)
    selected:SetHeight(52)
    selected:SetJustifyH("CENTER")
    selected:SetJustifyV("TOP")
    frame.selected = selected

    local prev = CreateButton(frame, "< Prev", 70, 22)
    prev:SetPoint("TOPRIGHT", selected, "TOPLEFT", -6, 0)
    prev:SetScript("OnClick", function()
        local backups = EnsureBackupTable()
        if table.getn(backups) == 0 then return end
        frame.index = frame.index - 1
        if frame.index < 1 then frame.index = table.getn(backups) end
        frame.Refresh()
    end)

    local nextButton = CreateButton(frame, "Next >", 70, 22)
    nextButton:SetPoint("TOPLEFT", selected, "TOPRIGHT", 6, 0)
    nextButton:SetScript("OnClick", function()
        local backups = EnsureBackupTable()
        if table.getn(backups) == 0 then return end
        frame.index = frame.index + 1
        if frame.index > table.getn(backups) then frame.index = 1 end
        frame.Refresh()
    end)

    local backup = CreateButton(frame, "Backup Current", 110, 24)
    backup:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 24)
    backup:SetScript("OnClick", function()
        BackupCurrent("Manual backup from history")
    end)

    local restore = CreateButton(frame, "Restore", 90, 24)
    restore:SetPoint("LEFT", backup, "RIGHT", 8, 0)
    restore:SetScript("OnClick", function()
        local backups = EnsureBackupTable()
        local selectedBackup = backups[frame.index]
        if not selectedBackup then return end
        CleveRoids_ImmunityData = DeepCopy(selectedBackup.data or {})
        CleveRoids.Print("Restored immunity backup: " .. tostring(selectedBackup.label or frame.index))
        NotifyDataChanged()
        frame.Refresh()
    end)

    local deleteButton = CreateButton(frame, "Delete", 90, 24)
    deleteButton:SetPoint("LEFT", restore, "RIGHT", 8, 0)
    deleteButton:SetScript("OnClick", function()
        local backups = EnsureBackupTable()
        local selectedBackup = backups[frame.index]
        if not selectedBackup then return end
        local label = selectedBackup.label or tostring(frame.index)
        table.remove(backups, frame.index)
        if frame.index > table.getn(backups) then
            frame.index = table.getn(backups)
        end
        if frame.index < 1 then frame.index = 1 end
        CleveRoids.Print("Deleted immunity backup: " .. tostring(label))
        frame.Refresh()
    end)

    local close = CreateButton(frame, "Close", 90, 24)
    close:SetPoint("LEFT", deleteButton, "RIGHT", 8, 0)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    function frame.Refresh()
        local backups = EnsureBackupTable()
        local count = table.getn(backups)
        frame.countText:SetText(tostring(count) .. " saved backup" .. (count == 1 and "" or "s"))

        if count == 0 then
            frame.selected:SetText("No manual backups yet.")
            return
        end

        if frame.index > count then frame.index = count end
        if frame.index < 1 then frame.index = 1 end

        local selectedBackup = backups[frame.index]
        local label = selectedBackup.label or ("Backup " .. tostring(frame.index))
        local reason = selectedBackup.reason and ("\n" .. tostring(selectedBackup.reason)) or ""
        local recordCount = CountAllRecords(selectedBackup.data)
        frame.selected:SetText(
            tostring(frame.index) .. "/" .. tostring(count) .. "  " .. label ..
            "\nData v" .. tostring(selectedBackup.immunityDataVersion or "?") ..
            " - " .. tostring(recordCount) .. " records" .. reason
        )
    end

    frame:SetScript("OnShow", function()
        local backups = EnsureBackupTable()
        local count = table.getn(backups)
        frame.index = count > 0 and count or 1
        frame.Refresh()
    end)

    return frame
end

local function CreateTargetPanel(parent)
    local frame = CreateFrame("Frame", "CleveRoidsImmunityTargetPanel", parent)
    frame:SetWidth(TARGET_WIDTH)
    frame:SetHeight(MAIN_HEIGHT)
    frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    ApplyBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("Current Target")

    targetModel = CreateFrame("PlayerModel", "CleveRoidsImmunityTargetModel", frame)
    targetModel:SetWidth(TARGET_MODEL_WIDTH)
    targetModel:SetHeight(TARGET_MODEL_HEIGHT)
    targetModel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46)
    targetModel:SetFrameLevel(frame:GetFrameLevel() + 1)
    ApplyBackdrop(targetModel)
    targetModel:Hide()

    targetNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetNameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 148, -48)
    targetNameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -48)
    targetNameText:SetHeight(34)
    targetNameText:SetJustifyH("LEFT")
    targetNameText:SetJustifyV("TOP")
    targetNameText:SetText("No current target")

    targetInfoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetInfoText:SetPoint("TOPLEFT", frame, "TOPLEFT", 148, -84)
    targetInfoText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -84)
    targetInfoText:SetHeight(82)
    targetInfoText:SetJustifyH("LEFT")
    targetInfoText:SetJustifyV("TOP")
    targetInfoText:SetText("")

    local ccHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ccHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -190)
    ccHeader:SetText("Recorded CC")

    local spellHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 155, -190)
    spellHeader:SetText("Recorded Spell")

    targetCCList = CreateMessageList(frame)
    targetCCList:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -210)
    targetCCList:SetWidth(126)
    targetCCList:SetHeight(148)

    targetSpellList = CreateMessageList(frame)
    targetSpellList:SetPoint("TOPLEFT", frame, "TOPLEFT", 155, -210)
    targetSpellList:SetWidth(126)
    targetSpellList:SetHeight(148)

    local liveHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    liveHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -378)
    liveHeader:SetText("Live / current-state / explanations")

    targetLiveList = CreateMessageList(frame)
    targetLiveList:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -401)
    targetLiveList:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 28)

    targetFrame = frame
    return frame
end

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "CleveRoidsImmunityManagementFrame", UIParent)
    frame:SetWidth(MAIN_WIDTH)
    frame:SetHeight(MAIN_HEIGHT)
    -- Center the combined main + attached target footprint. At 1024-wide UI scale
    -- this leaves a small margin on both sides instead of clipping the target border.
    frame:SetPoint("CENTER", UIParent, "CENTER", -152, 0)
    frame:SetFrameStrata("DIALOG")
    ApplyBackdrop(frame)
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("SCRM Immunities")

    local close = CreateFrame("Button", NewWidgetName("Close"), frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    local ccTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ccTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48)
    ccTitle:SetText("CC Immunities")

    ccSection = CreateHorizontalSection(frame, -70, 214, CC_COLUMNS, "CC")

    local spellTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -322)
    spellTitle:SetText("Spell Immunities")

    spellSection = CreateHorizontalSection(frame, -344, 190, SPELL_COLUMNS, "Spell")

    legacyTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legacyTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -574)
    legacyTitle:SetText("Legacy / diagnostic unknown (0)")

    legacyList = CreateMessageList(frame)
    legacyList:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -593)
    legacyList:SetWidth(670)
    legacyList:SetHeight(38)

    local backupCC = CreateButton(frame, "Backup", 70, 22)
    backupCC:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22)
    backupCC:SetScript("OnClick", function()
        BackupCurrent("Manual backup before/around CC management")
    end)

    local clearCC = CreateButton(frame, "Clear CC...", 90, 22)
    clearCC:SetPoint("LEFT", backupCC, "RIGHT", 4, 0)
    clearCC:SetScript("OnClick", function()
        ShowClearDialog("cc")
    end)

    local backupSpell = CreateButton(frame, "Backup", 70, 22)
    backupSpell:SetPoint("LEFT", clearCC, "RIGHT", 16, 0)
    backupSpell:SetScript("OnClick", function()
        BackupCurrent("Manual backup before/around spell management")
    end)

    local clearSpell = CreateButton(frame, "Clear Spell...", 100, 22)
    clearSpell:SetPoint("LEFT", backupSpell, "RIGHT", 4, 0)
    clearSpell:SetScript("OnClick", function()
        ShowClearDialog("spell")
    end)

    local backupAll = CreateButton(frame, "Backup", 70, 22)
    backupAll:SetPoint("LEFT", clearSpell, "RIGHT", 16, 0)
    backupAll:SetScript("OnClick", function()
        BackupCurrent("Manual backup before/around full immunity reset")
    end)

    local clearAll = CreateButton(frame, "Clear All...", 90, 22)
    clearAll:SetPoint("LEFT", backupAll, "RIGHT", 4, 0)
    clearAll:SetScript("OnClick", function()
        ShowClearDialog("all")
    end)

    local backups = CreateButton(frame, "Backups...", 90, 22)
    backups:SetPoint("LEFT", clearAll, "RIGHT", 16, 0)
    backups:SetScript("OnClick", function()
        historyDialog:Show()
    end)

    CreateTargetPanel(frame)
    clearDialog = CreateClearDialog(frame)
    historyDialog = CreateHistoryDialog(frame)

    local eventFrame = CreateFrame("Frame", "CleveRoidsImmunityUIEventFrame", frame)
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function()
        if not frame:IsShown() then return end
        if event == "UNIT_AURA" and arg1 and arg1 ~= "target" then
            return
        end
        RefreshTargetPanel()
    end)

    frame:SetScript("OnShow", function()
        RefreshAll()
    end)
    frame:SetScript("OnHide", function()
        StopTargetModelRotation()
    end)

    frame:Hide()
    mainFrame = frame
end

function CleveRoids.RefreshImmunityUI()
    if mainFrame and mainFrame:IsShown() then
        RefreshAll()
    end
end

function CleveRoids.ToggleImmunityUI()
    if not mainFrame then
        CreateMainFrame()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshAll()
    end
end

CreateMainFrame()
