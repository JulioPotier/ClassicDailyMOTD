-- SavedVariables
CMOTD_Saved = CMOTD_Saved or {}
CMOTD_Saved.motdByDay = CMOTD_Saved.motdByDay or { "", "", "", "", "", "", "" }
CMOTD_Saved.motdList = nil
CMOTD_Saved.lastDate = nil

local ADDON_TAG = "ClassicDailyMOTD"
local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local MOTD_MAX_LEN = 128

-- date("%w") returns 0..6 with Sunday = 0. We want 1 = Monday ... 7 = Sunday.
local function GetTodayIndex()
    local w = tonumber(date("%w"))
    if w == 0 then return 7 end
    return w
end

local function GetMOTDForToday()
    return CMOTD_Saved.motdByDay[GetTodayIndex()] or ""
end

-- Idempotent apply: only calls GuildSetMOTD when current != target.
-- This makes the addon safe to run on multiple officer clients.
local function ApplyDailyMOTD()
    if not IsInGuild() or not CanEditMOTD() then
        return
    end

    local target = GetMOTDForToday()
    if target == "" then
        print(ADDON_TAG .. ": no MOTD defined for " .. DAYS[GetTodayIndex()] .. ".")
        return
    end

    local current = GetGuildRosterMOTD() or ""
    if current == target then
        return
    end

    GuildSetMOTD(target)
    print(ADDON_TAG .. ": MOTD updated for " .. DAYS[GetTodayIndex()] .. ".")
end

local function CreateGUI()
    local frame = CreateFrame("Frame", "CDMOTD_Frame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(460, 320)
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
    frame.numTabs = 7

    -- Scrollable multi-line edit area
    local scrollFrame = CreateFrame("ScrollFrame", "CDMOTD_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 46)

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

    local counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    counter:SetPoint("BOTTOMRIGHT", -14, 34)
    local function UpdateCounter()
        counter:SetText(string.format("%d / %d", #editBox:GetText(), MOTD_MAX_LEN))
    end

    -- Forward declaration; the real function is defined once applyBtn exists.
    local UpdateApplyButton

    editBox:SetScript("OnTextChanged", function()
        UpdateCounter()
        if UpdateApplyButton then UpdateApplyButton() end
    end)

    local function PersistCurrent()
        CMOTD_Saved.motdByDay[frame.selectedDay] = editBox:GetText()
    end

    -- Native Blizzard tabs hanging under the frame.
    -- Names must follow "<frameName>Tab<i>" for PanelTemplates_SetTab to find them.
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

    local function SelectDay(idx)
        if idx ~= frame.selectedDay then
            PersistCurrent()
            frame.selectedDay = idx
            editBox:SetText(CMOTD_Saved.motdByDay[idx] or "")
            UpdateCounter()
        end
        PanelTemplates_SetTab(frame, idx)
        if UpdateApplyButton then UpdateApplyButton() end
    end

    for i = 1, 7 do
        tabs[i]:SetScript("OnClick", function(self)
            SelectDay(self:GetID())
        end)
    end

    editBox:SetText(CMOTD_Saved.motdByDay[frame.selectedDay] or "")
    UpdateCounter()
    PanelTemplates_SetTab(frame, frame.selectedDay)

    local applyBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    applyBtn:SetPoint("BOTTOMLEFT", 14, 10)
    applyBtn:SetSize(130, 24)
    applyBtn:SetText("Apply for Today")
    applyBtn:SetScript("OnClick", function()
        PersistCurrent()
        ApplyDailyMOTD()
        UpdateApplyButton()
    end)

    -- Real definition (was forward-declared above).
    -- Enabled only when the would-be-applied target differs from the current guild MOTD.
    function UpdateApplyButton()
        if not IsInGuild() or not CanEditMOTD() then
            applyBtn:Disable()
            return
        end

        local target
        if frame.selectedDay == GetTodayIndex() then
            target = editBox:GetText()
        else
            target = CMOTD_Saved.motdByDay[GetTodayIndex()] or ""
        end

        local current = GetGuildRosterMOTD() or ""

        if target == "" or target == current then
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
        print(ADDON_TAG .. ": MOTDs saved.")
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
    if not gui then
        gui = CreateGUI()
    end
    gui:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    C_Timer.After(5, ApplyDailyMOTD)
end)
