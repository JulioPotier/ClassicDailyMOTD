-- SavedVariables (defaults completed in EnsureCMOTDDefaults; merge order can leave fields nil)
CMOTD_Saved = CMOTD_Saved or {}
CMOTD_Saved.motdList = nil
CMOTD_Saved.lastDate = nil
CMOTD_Saved.lastDayProcessedKey = CMOTD_Saved.lastDayProcessedKey or nil

local ADDON_FOLDER = "ClassicDailyMOTD"

local function EnsureCMOTDDefaults()
    CMOTD_Saved = CMOTD_Saved or {}
    local motd = CMOTD_Saved.motdByDay
    if type(motd) ~= "table" then
        CMOTD_Saved.motdByDay = { "", "", "", "", "", "", "" }
    else
        for i = 1, 7 do
            if motd[i] == nil then
                motd[i] = ""
            end
        end
    end
    local auto = CMOTD_Saved.autoByDay
    if type(auto) ~= "table" then
        CMOTD_Saved.autoByDay = { false, false, false, false, false, false, false }
    else
        for i = 1, 7 do
            auto[i] = auto[i] and true or false
        end
    end
    if type(CMOTD_Saved.ideas) ~= "string" then
        CMOTD_Saved.ideas = ""
    end
end

local ADDON_TAG = "ClassicDailyMOTD"
local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local DAYS_FULL_EN = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local MOTD_MAX_LEN = 128
local IDEAS_MAX_LEN = 4000
local EXPORT_SEP = "<<<CDMOTD>>>"
local EXPORT_HEADER = "CDMOTD_EXPORT_V1"

-- date("%w") returns 0..6 with Sunday = 0. We want 1 = Monday ... 7 = Sunday.
local function GetTodayIndex()
    local w = tonumber(date("%w"))
    if w == 0 then return 7 end
    return w
end

local function GetMOTDForToday()
    return CMOTD_Saved.motdByDay[GetTodayIndex()] or ""
end

local function EscapeExportChunk(s)
    if not s then return "" end
    return (tostring(s):gsub(EXPORT_SEP, "<<<CDMOTDESC>>>"))
end

local function UnescapeExportChunk(s)
    if not s then return "" end
    return (tostring(s):gsub("<<<CDMOTDESC>>>", EXPORT_SEP))
end

local function BuildExportString()
    EnsureCMOTDDefaults()
    local parts = {}
    for i = 1, 7 do
        parts[#parts + 1] = EscapeExportChunk(CMOTD_Saved.motdByDay[i] or "")
    end
    local autoBits = {}
    for i = 1, 7 do
        autoBits[i] = CMOTD_Saved.autoByDay[i] and "1" or "0"
    end
    parts[#parts + 1] = table.concat(autoBits, "")
    parts[#parts + 1] = EscapeExportChunk(CMOTD_Saved.ideas or "")
    return EXPORT_HEADER .. EXPORT_SEP .. table.concat(parts, EXPORT_SEP)
end

local function ParseImportString(raw)
    if not raw or raw:match("^%s*$") then
        return false, "empty"
    end
    local trim = raw:match("^%s*(.-)%s*$")
    if not trim:find(EXPORT_HEADER, 1, true) then
        return false, "missing header"
    end
    local rest = trim:sub(#EXPORT_HEADER + 1)
    if rest:sub(1, #EXPORT_SEP) ~= EXPORT_SEP then
        return false, "bad header"
    end
    rest = rest:sub(#EXPORT_SEP + 1)
    local chunks = { strsplit(EXPORT_SEP, rest) }
    if #chunks < 9 then
        return false, "incomplete data"
    end
    local motds = {}
    for i = 1, 7 do
        motds[i] = UnescapeExportChunk(chunks[i] or "")
        if #motds[i] > MOTD_MAX_LEN then
            return false, "MOTD too long"
        end
    end
    local autoStr = chunks[8] or ""
    if #autoStr ~= 7 or not autoStr:match("^[01]+$") then
        return false, "invalid auto flags"
    end
    local auto = {}
    for i = 1, 7 do
        auto[i] = autoStr:sub(i, i) == "1"
    end
    local ideas = UnescapeExportChunk(table.concat(chunks, EXPORT_SEP, 9))
    if #ideas > IDEAS_MAX_LEN then
        return false, "ideas too long"
    end
    return true, motds, auto, ideas
end

-- If current guild MOTD equals target, clear then set so the message shows again in guild chat.
local function GuildSetMOTDForce(text)
    if not IsInGuild() or not CanEditMOTD() then
        return false
    end
    if text == "" then
        return false
    end
    local current = GetGuildRosterMOTD() or ""
    if current == text then
        GuildSetMOTD("")
        C_Timer.After(0.05, function()
            if IsInGuild() and CanEditMOTD() then
                GuildSetMOTD(text)
            end
        end)
    else
        GuildSetMOTD(text)
    end
    return true
end

local function ApplyDailyMOTDAuto()
    EnsureCMOTDDefaults()
    if not IsInGuild() or not CanEditMOTD() then
        return
    end
    local todayIdx = GetTodayIndex()
    if not CMOTD_Saved.autoByDay[todayIdx] then
        return
    end
    local target = GetMOTDForToday()
    if target == "" then
        print(ADDON_TAG .. ": no MOTD defined for " .. DAYS[todayIdx] .. ".")
        return
    end
    if GuildSetMOTDForce(target) then
        print(ADDON_TAG .. ": MOTD updated for " .. DAYS[todayIdx] .. ".")
    end
end

local function CreateGUI()
    EnsureCMOTDDefaults()
    local frame = CreateFrame("Frame", "CDMOTD_Frame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(460, 340)
    frame:SetPoint("CENTER")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -6)
    frame.title:SetText("Classic Daily MOTD")

    frame.selectedDay = GetTodayIndex()
    frame.inSettings = false
    frame.numTabs = 7

    local gearBtn = CreateFrame("Button", nil, frame)
    gearBtn:SetSize(26, 26)
    gearBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -2)
    gearBtn:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    gearBtn:SetPushedTexture("Interface\\Icons\\Trade_Engineering")
    gearBtn:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)
    gearBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(frame.inSettings and "Back to MOTDs" or "Settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", GameTooltip_Hide)

    local dayHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dayHeader:SetPoint("TOPLEFT", 18, -32)
    dayHeader:SetJustifyH("LEFT")
    dayHeader:SetWidth(260)

    local autoCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -30)
    autoCheck.Text:SetText("Auto")
    autoCheck.Text:SetFontObject("GameFontNormalSmall")

    local settingsPanel = CreateFrame("Frame", nil, frame)
    settingsPanel:SetPoint("TOPLEFT", 10, -30)
    settingsPanel:SetPoint("BOTTOMRIGHT", -10, 42)
    settingsPanel:Hide()

    local ideasLabel = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ideasLabel:SetPoint("TOPLEFT", 4, -8)
    ideasLabel:SetText("Ideas")

    local ideasScroll = CreateFrame("ScrollFrame", "CDMOTD_IdeasScroll", settingsPanel, "UIPanelScrollFrameTemplate")
    ideasScroll:SetPoint("TOPLEFT", 4, -28)
    ideasScroll:SetPoint("BOTTOMRIGHT", -28, 44)

    local ideasBg = ideasScroll:CreateTexture(nil, "BACKGROUND")
    ideasBg:SetAllPoints()
    ideasBg:SetColorTexture(0, 0, 0, 0.5)

    local ideasBox = CreateFrame("EditBox", "CDMOTD_IdeasBox", ideasScroll)
    ideasBox:SetMultiLine(true)
    ideasBox:SetMaxLetters(IDEAS_MAX_LEN)
    ideasBox:SetFontObject("ChatFontNormal")
    ideasBox:SetWidth(390)
    ideasBox:SetHeight(400)
    ideasBox:SetTextInsets(6, 6, 6, 6)
    ideasBox:SetAutoFocus(false)
    ideasBox:SetScript("OnEscapePressed", ideasBox.ClearFocus)
    ideasScroll:SetScrollChild(ideasBox)
    ideasScroll:EnableMouse(true)
    ideasScroll:SetScript("OnMouseDown", function() ideasBox:SetFocus() end)

    local ideasCounter = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ideasCounter:SetPoint("BOTTOMRIGHT", -8, 50)
    local function UpdateIdeasCounter()
        ideasCounter:SetText(string.format("%d / %d", #ideasBox:GetText(), IDEAS_MAX_LEN))
    end
    ideasBox:SetScript("OnTextChanged", function()
        UpdateIdeasCounter()
    end)

    local exportBtn = CreateFrame("Button", nil, settingsPanel, "GameMenuButtonTemplate")
    exportBtn:SetPoint("BOTTOMLEFT", 4, 10)
    exportBtn:SetSize(100, 24)
    exportBtn:SetText("Export")

    local importBtn = CreateFrame("Button", nil, settingsPanel, "GameMenuButtonTemplate")
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetSize(100, 24)
    importBtn:SetText("Import")

    -- Modal for export / import text
    local modal = CreateFrame("Frame", "CDMOTD_ExportModal", frame, "BackdropTemplate")
    modal:SetSize(420, 280)
    modal:SetPoint("CENTER", frame, "CENTER", 0, 0)
    modal:SetFrameStrata("DIALOG")
    modal:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    modal:SetBackdropColor(0, 0, 0, 1)
    modal:Hide()
    modal:EnableMouse(true)

    local modalTitle = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modalTitle:SetPoint("TOP", 0, -14)

    local modalScroll = CreateFrame("ScrollFrame", nil, modal, "UIPanelScrollFrameTemplate")
    modalScroll:SetPoint("TOPLEFT", 16, -36)
    modalScroll:SetPoint("BOTTOMRIGHT", -38, 44)

    local modalBg = modalScroll:CreateTexture(nil, "BACKGROUND")
    modalBg:SetAllPoints()
    modalBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    local modalEdit = CreateFrame("EditBox", nil, modalScroll)
    modalEdit:SetMultiLine(true)
    modalEdit:SetMaxLetters(120000)
    modalEdit:SetFontObject("ChatFontNormal")
    modalEdit:SetWidth(360)
    modalEdit:SetHeight(2000)
    modalEdit:SetTextInsets(6, 6, 6, 6)
    modalEdit:SetAutoFocus(true)
    modalEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        modal:Hide()
    end)
    modalScroll:SetScrollChild(modalEdit)

    local modalOk = CreateFrame("Button", nil, modal, "GameMenuButtonTemplate")
    modalOk:SetSize(100, 24)
    modalOk:SetPoint("BOTTOMRIGHT", -16, 12)
    modalOk:SetText("OK")

    local modalClose = CreateFrame("Button", nil, modal, "GameMenuButtonTemplate")
    modalClose:SetSize(100, 24)
    modalClose:SetPoint("BOTTOMLEFT", 16, 12)
    modalClose:SetText("Close")

    local modalMode = "export"

    modalClose:SetScript("OnClick", function()
        modal:Hide()
    end)

    modalOk:SetScript("OnClick", function()
        if modalMode == "import" then
            local ok, motds, auto, ideas = ParseImportString(modalEdit:GetText())
            if not ok then
                print(ADDON_TAG .. ": import failed (" .. tostring(motds) .. ").")
                return
            end
            CMOTD_Saved.motdByDay = motds
            CMOTD_Saved.autoByDay = auto
            for j = 1, 7 do
                CMOTD_Saved.autoByDay[j] = CMOTD_Saved.autoByDay[j] and true or false
            end
            CMOTD_Saved.ideas = ideas or ""
            ideasBox:SetText(CMOTD_Saved.ideas)
            UpdateIdeasCounter()
            if frame.selectedDay >= 1 and frame.selectedDay <= 7 then
                editBox:SetText(CMOTD_Saved.motdByDay[frame.selectedDay] or "")
                UpdateCounter()
                autoCheck:SetChecked(CMOTD_Saved.autoByDay[frame.selectedDay])
                dayHeader:SetText(DAYS_FULL_EN[frame.selectedDay])
            end
            print(ADDON_TAG .. ": import OK.")
            modal:Hide()
        else
            modal:Hide()
        end
    end)

    exportBtn:SetScript("OnClick", function()
        modalMode = "export"
        modalTitle:SetText("Export — copy text, then Close")
        modalOk:Hide()
        local exportText = BuildExportString()
        modalEdit:SetText(exportText)
        modalEdit:HighlightText(0, string.len(exportText))
        modal:Show()
    end)

    importBtn:SetScript("OnClick", function()
        modalMode = "import"
        modalTitle:SetText("Import — paste data, then OK")
        modalOk:Show()
        modalEdit:SetText("")
        modal:Show()
        modalEdit:SetFocus()
    end)

    local motdBlock = CreateFrame("Frame", nil, frame)
    motdBlock:SetPoint("TOPLEFT", 10, -30)
    motdBlock:SetPoint("BOTTOMRIGHT", -10, 42)

    dayHeader:SetParent(motdBlock)
    dayHeader:ClearAllPoints()
    dayHeader:SetPoint("TOPLEFT", motdBlock, "TOPLEFT", 8, -4)

    autoCheck:SetParent(motdBlock)
    autoCheck:ClearAllPoints()
    autoCheck:SetPoint("TOPRIGHT", motdBlock, "TOPRIGHT", -22, -2)

    local scrollFrame = CreateFrame("ScrollFrame", "CDMOTD_ScrollFrame", motdBlock, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -26)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    local editBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    editBg:SetAllPoints()
    editBg:SetColorTexture(0, 0, 0, 0.5)

    local editBox = CreateFrame("EditBox", "CDMOTD_EditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(MOTD_MAX_LEN)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(390)
    editBox:SetHeight(200)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    scrollFrame:SetScrollChild(editBox)

    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    local counter = motdBlock:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    counter:SetPoint("BOTTOMRIGHT", -4, 8)
    local function UpdateCounter()
        counter:SetText(string.format("%d / %d", #editBox:GetText(), MOTD_MAX_LEN))
    end

    local UpdateApplyButton

    editBox:SetScript("OnTextChanged", function()
        UpdateCounter()
        if UpdateApplyButton then UpdateApplyButton() end
    end)

    local function PersistMOTD()
        if frame.selectedDay >= 1 and frame.selectedDay <= 7 then
            CMOTD_Saved.motdByDay[frame.selectedDay] = editBox:GetText()
        end
    end

    local function PersistIdeas()
        CMOTD_Saved.ideas = ideasBox:GetText()
    end

    local function PersistCurrent()
        if frame.inSettings then
            PersistIdeas()
        else
            PersistMOTD()
        end
    end

    local function UpdateDayHeader()
        if frame.selectedDay >= 1 and frame.selectedDay <= 7 then
            dayHeader:SetText(DAYS_FULL_EN[frame.selectedDay])
            autoCheck:SetChecked(CMOTD_Saved.autoByDay[frame.selectedDay] and true or false)
            autoCheck:Show()
        end
    end

    autoCheck:SetScript("OnClick", function(self)
        if frame.selectedDay >= 1 and frame.selectedDay <= 7 then
            CMOTD_Saved.autoByDay[frame.selectedDay] = self:GetChecked() and true or false
        end
    end)

    -- Native Blizzard tabs
    local tabs = {}
    for i = 1, 7 do
        local tab = CreateFrame("Button", "CDMOTD_FrameTab" .. i, frame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        local label = DAYS[i]
        if i == GetTodayIndex() then
            label = "|cffffd200" .. label .. "|r"
        end
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 0)
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end
        tabs[i] = tab
    end

    PanelTemplates_SetNumTabs(frame, 7)

    local function ShowMOTDTab(show)
        if show then
            motdBlock:Show()
            settingsPanel:Hide()
        else
            motdBlock:Hide()
            settingsPanel:Show()
        end
    end

    local function SelectDay(idx)
        if idx < 1 or idx > 7 then
            return
        end
        if frame.inSettings then
            PersistIdeas()
            frame.inSettings = false
            frame.selectedDay = idx
            ShowMOTDTab(true)
            editBox:SetText(CMOTD_Saved.motdByDay[idx] or "")
            UpdateCounter()
            UpdateDayHeader()
            PanelTemplates_SetTab(frame, idx)
            if UpdateApplyButton then UpdateApplyButton() end
            return
        end
        if idx ~= frame.selectedDay then
            PersistMOTD()
            frame.selectedDay = idx
            editBox:SetText(CMOTD_Saved.motdByDay[idx] or "")
            UpdateCounter()
            UpdateDayHeader()
            PanelTemplates_SetTab(frame, idx)
            if UpdateApplyButton then UpdateApplyButton() end
        end
    end

    for i = 1, 7 do
        tabs[i]:SetScript("OnClick", function(self)
            SelectDay(self:GetID())
        end)
    end

    gearBtn:SetScript("OnClick", function()
        if frame.inSettings then
            PersistIdeas()
            frame.inSettings = false
            ShowMOTDTab(true)
            editBox:SetText(CMOTD_Saved.motdByDay[frame.selectedDay] or "")
            UpdateCounter()
            UpdateDayHeader()
            PanelTemplates_SetTab(frame, frame.selectedDay)
        else
            PersistMOTD()
            frame.inSettings = true
            ShowMOTDTab(false)
            ideasBox:SetText(CMOTD_Saved.ideas or "")
            UpdateIdeasCounter()
        end
        if UpdateApplyButton then UpdateApplyButton() end
    end)

    editBox:SetText(CMOTD_Saved.motdByDay[frame.selectedDay] or "")
    UpdateCounter()
    UpdateDayHeader()
    PanelTemplates_SetTab(frame, frame.selectedDay)

    local applyBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    applyBtn:SetPoint("BOTTOMLEFT", 14, 10)
    applyBtn:SetSize(130, 24)
    applyBtn:SetText("Apply now")
    applyBtn:SetScript("OnClick", function()
        PersistCurrent()
        if not IsInGuild() or not CanEditMOTD() then
            return
        end
        local target = CMOTD_Saved.motdByDay[GetTodayIndex()] or ""
        if target == "" then
            print(ADDON_TAG .. ": no MOTD defined for " .. DAYS[GetTodayIndex()] .. ".")
            return
        end
        if GuildSetMOTDForce(target) then
            print(ADDON_TAG .. ": MOTD applied for " .. DAYS[GetTodayIndex()] .. ".")
        end
        if UpdateApplyButton then UpdateApplyButton() end
    end)

    function UpdateApplyButton()
        if not IsInGuild() or not CanEditMOTD() then
            applyBtn:Disable()
        else
            applyBtn:Enable()
        end
    end

    local saveBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    saveBtn:SetPoint("BOTTOMRIGHT", -14, 10)
    saveBtn:SetSize(110, 24)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        PersistCurrent()
        print(ADDON_TAG .. ": saved.")
    end)

    frame:SetScript("OnHide", function()
        PersistCurrent()
    end)

    frame:RegisterEvent("GUILD_MOTD")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GUILD_MOTD" then
            UpdateApplyButton()
        end
    end)

    frame:HookScript("OnShow", function()
        UpdateApplyButton()
    end)

    UpdateApplyButton()

    return frame
end

local gui

SLASH_CDMOTD1 = "/cmotd"
SLASH_CDMOTD2 = "/cdmotd"
SlashCmdList["CDMOTD"] = function()
    EnsureCMOTDDefaults()
    if not gui then
        gui = CreateGUI()
    end
    gui:Show()
end

EnsureCMOTDDefaults()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_FOLDER then
        EnsureCMOTDDefaults()
    elseif event == "PLAYER_LOGIN" then
        EnsureCMOTDDefaults()
        C_Timer.After(5, function()
            EnsureCMOTDDefaults()
            local todayKey = date("%Y-%m-%d")
            CMOTD_Saved.lastDayProcessedKey = todayKey
            ApplyDailyMOTDAuto()
        end)
    end
end)
