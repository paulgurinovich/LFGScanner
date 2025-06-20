local version = GetAddOnMetadata("LFGScanner", "Version")
local seenAuthors = {}
local HandleIncomingMessage



local dungeonKeywords = {
    icc = "Icecrown Citadel",
    toc = "Trial of the Crusader",
    rs = "The Ruby Sanctum",
    voa = "Vault of Archavon",
    naxx = "Naxxramas",
    ulduar = "Ulduar",
    os = "Obsidian Sanctum",
    ony = "Onyxia's Lair",
    togc = "Trial of the Grand Crusader"
}

local validChannels = {
    ["LookingForGroup"] = true,
    ["General"] = true,
    ["Trade"] = true,
    ["LocalDefense"] = true,
    ["Global"] = true,
    ["guildRecruitment"] = true
}

LFGScannerSettings = LFGScannerSettings or {
    width = 500,
    height = 600,
    posX = 500,
    posY = 500,
    font = "GameFontNormal",
    enableSound = true
}


LFGScannerFilters = LFGScannerFilters or {
    guildRecruitment = true,
    nonFiltered = true,
    dungeons = {},
    size10 = true,
    size25 = true,
}

for shortname in pairs(dungeonKeywords) do
    if LFGScannerFilters.dungeons[shortname] == nil then
        LFGScannerFilters.dungeons[shortname] = true
    end
end

if LFGScannerFilters.guildRecruitment == nil then
    LFGScannerFilters.guildRecruitment = true
end


local LFGScannerDB = {}
local collapsed = {}

local function CreateClickableText(parent, font, text, x, y, width, author, color, wrap)

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local size = LFGScannerSettings.fontSize or 12
    fs:SetFont("Fonts\\FRIZQT__.TTF", size)

    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if color then
        fs:SetTextColor(color.r, color.g, color.b, 1)
    else
        fs:SetTextColor(1, 1, 1, 1) -- Default white
    end
    fs:SetWidth(width)
    fs:SetWordWrap(wrap or false)
    fs:SetText(text)

    local button = CreateFrame("Button", nil, parent)
    button:SetAllPoints(fs)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function()
        ChatFrame1EditBox:SetText("/w " .. author .. " ")
        ChatFrame1EditBox:Show()
        ChatFrame1EditBox:SetFocus()
    end)

    return fs
end


local function formatElapsedTime(timestamp)
    local elapsed = time() - timestamp
    if elapsed < 60 then
        return string.format("%ds ago", elapsed)
    elseif elapsed < 3600 then
        return string.format("%dm ago", math.floor(elapsed / 60))
    else
        return string.format("%dh ago", math.floor(elapsed / 3600))
    end
end

local function ContainsKeyword(message)
    message = string.lower(message)
    for shortName, fullName in pairs(dungeonKeywords) do
        if string.find(message, shortName:lower()) or string.find(message, fullName:lower()) then
            return shortName
        end
    end
    return nil
end


local function IsGuildRecruitment(message)
    message = message:lower()

    local keywords = {
        "recruit", "recruiting", "looking for members", "guild",
        "progress", "progression", "apply", "individuals",
        "raiding", "core team", "roster", "lineup",
        "expansion", "social", "friendly", "active",
        "casual", "hardcore", "semi%-hardcore", -- use %- for dash
        "raid days", "weekend", "weekday",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "server time", "start time", "invites", "pull", "form up", "arena"
    }

    for _, word in ipairs(keywords) do
        if message:find("%f[%a]" .. word .. "%f[%A]") then
            return true
        end
    end

    return false
end


local function DetectSize(message)
    message = string.lower(message)
    if message:find("25") then
        return "25"
    elseif message:find("10") then
        return "10"
    else
        return "10"
    end
end


-- Create Hide/Show Toggle Button
local toggleButton = CreateFrame("Button", "LFGScannerToggleButton", UIParent, "UIPanelButtonTemplate")
toggleButton:SetSize(80, 25) -- small button
toggleButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10) -- top-left corner
toggleButton:SetText("LFG Scan")
toggleButton:SetMovable(true)
toggleButton:EnableMouse(true)
toggleButton:RegisterForDrag("LeftButton")
toggleButton:SetScript("OnDragStart", toggleButton.StartMoving)
toggleButton:SetScript("OnDragStop", toggleButton.StopMovingOrSizing)


local function UpdateToggleButtonIndicator(state)
    if not toggleButton.indicator then
        toggleButton.indicator = toggleButton:CreateFontString(nil, "OVERLAY")
        toggleButton.indicator:SetFont("Fonts\\FRIZQT__.TTF", 30, "OUTLINE") -- size 20, outline for visibility
        toggleButton.indicator:SetPoint("LEFT", toggleButton, "LEFT", -10, -1)
        toggleButton.indicator:SetText("!")
        toggleButton.indicator:SetTextColor(1, 1, 0, 1)
        toggleButton.indicator:Hide()
    end

    if state then
        toggleButton.indicator:Show()
        if LFGScannerSettings.enableSound then
            PlaySoundFile("Interface\\AddOns\\LFGScanner\\Whisper.ogg")
        end 
    else
        toggleButton.indicator:Hide()
    end
end

toggleButton:SetScript("OnClick", function()
    if LFGScannerUI:IsShown() then
        LFGScannerUI:Hide()
    else
        LFGScannerUI:Show()
        UpdateToggleButtonIndicator(false) -- Clear new message indicator
    end
end)


local function AddMessage(messageKey, size, author, msg, class)
    local baseKey = messageKey  -- Preserve raw dungeon name

    local lowerMsg = msg:lower()
    if lowerMsg:find("wts") or lowerMsg:find("sell") then
        messageKey = "nonFiltered"
        size = nil
        baseKey = nil
    end

    if messageKey ~= "guildRecruitment" and messageKey ~= "nonFiltered" then
        messageKey = messageKey .. "-" .. size
    end

    if not LFGScannerDB[messageKey] then
        LFGScannerDB[messageKey] = {}
    end

    for _, entry in ipairs(LFGScannerDB[messageKey]) do
        if entry.author == author then
            entry.message = msg
            entry.time = time()
            entry.class = class
            return
        end
    end

    table.insert(LFGScannerDB[messageKey], { author = author, message = msg, time = time(), class = class })

    if not seenAuthors[author] then
        seenAuthors[author] = true

        if messageKey == "guildRecruitment" and LFGScannerFilters.guildRecruitment then
            UpdateToggleButtonIndicator(true)
        elseif baseKey and LFGScannerFilters.dungeons[baseKey] and
               ((size == "10" and LFGScannerFilters.size10) or (size == "25" and LFGScannerFilters.size25)) then
            UpdateToggleButtonIndicator(true)
        end
    end
end



local uiFrame = CreateFrame("Frame", "LFGScannerUI", UIParent)
uiFrame:SetSize(LFGScannerSettings.width, LFGScannerSettings.height)
uiFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", LFGScannerSettings.posX, LFGScannerSettings.posY)
uiFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
uiFrame:SetBackdropColor(0, 0, 0, 1)
uiFrame:SetMovable(true)
uiFrame:EnableMouse(true)
uiFrame:RegisterForDrag("LeftButton")
uiFrame:SetResizable(true)
uiFrame:SetMinResize(300, 300)
uiFrame:SetScript("OnDragStart", uiFrame.StartMoving)
uiFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    LFGScannerSettings.posX = x
    LFGScannerSettings.posY = y
end)
uiFrame:Hide() 

local resizeButton = CreateFrame("Button", nil, uiFrame)
resizeButton:SetSize(16, 16)
resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeButton:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        uiFrame:StartSizing("BOTTOMRIGHT")
    end
end)
resizeButton:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        uiFrame:StopMovingOrSizing()
        LFGScannerSettings.width = uiFrame:GetWidth()
        LFGScannerSettings.height = uiFrame:GetHeight()
        local point, _, _, x, y = uiFrame:GetPoint()
        LFGScannerSettings.posX = x
        LFGScannerSettings.posY = y
    end
end)

local scrollFrame = CreateFrame("ScrollFrame", "LFGScrollFrame", uiFrame)
scrollFrame:SetPoint("TOPLEFT", 10, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local scrollbar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
scrollbar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 20, -20)
scrollbar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 20, 20)
scrollbar:SetMinMaxValues(0, 1)
scrollbar:SetValueStep(1)
scrollbar:SetValue(0)
scrollbar:SetWidth(16)
scrollbar:SetScript("OnValueChanged", function(self, value)
    scrollFrame:SetVerticalScroll(value)
end)

scrollFrame.scrollBar = scrollbar  -- link scrollbar
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local min, max = self.scrollBar:GetMinMaxValues()
    local step = 30  -- How much to scroll per wheel tick

    if delta > 0 then
        local newVal = math.max(current - step, min)
        self:SetVerticalScroll(newVal)
        self.scrollBar:SetValue(newVal)
    else
        local newVal = math.min(current + step, max)
        self:SetVerticalScroll(newVal)
        self.scrollBar:SetValue(newVal)
    end
end)


local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(460, 400)
scrollFrame:SetScrollChild(content)

local function UpdateUI()

    local sectionSpacing = 30 -- spacing between section header and messages

    content:Hide()
    content:SetParent(nil)

    content = CreateFrame("Frame", nil, scrollFrame)
    local frameWidth = uiFrame:GetWidth()
    local contentWidth = frameWidth - 30 -- adjust for scrollbar width
    content:SetSize(contentWidth, 400)
    scrollFrame:SetScrollChild(content)

    local authorWidth = 80
    local timeWidth = 40
    local messageWidth = math.floor(frameWidth - authorWidth - timeWidth - 100)

    local yOffset = -10
    local rowCount = 0 -- Global row counter for zebra stripes


    for key, entries in pairs(LFGScannerDB) do
        if key == "guildRecruitment" and LFGScannerFilters.guildRecruitment then
            -- Render Guild Recruitment Section
            local headerSeparator = content:CreateTexture(nil, "OVERLAY")
            headerSeparator:SetTexture(1, 1, 1, 0.15)
            headerSeparator:SetPoint("TOPLEFT", content, "TOPLEFT", 5, yOffset + 5)
            headerSeparator:SetPoint("TOPRIGHT", content, "TOPRIGHT", -5, yOffset + 5)
            headerSeparator:SetHeight(1)

            local header = CreateFrame("Button", nil, content)
            header:SetSize(frameWidth - 20, 20)
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)

            local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerTitle:SetFont("Fonts\\FRIZQT__.TTF", (LFGScannerSettings.fontSize or 12) + 1)
            headerTitle:SetPoint("LEFT", header, "LEFT", 10, 5)
            headerTitle:SetText("|cffffcc00Guild Recruitment|r")

            header:SetScript("OnClick", function()
                collapsed[key] = not collapsed[key]
                UpdateUI()
            end)

            yOffset = yOffset - 20

            if not collapsed[key] then
                for _, entry in ipairs(entries) do
                    local authorText = CreateClickableText(content, LFGScannerSettings.font, entry.author, 10, yOffset, authorWidth, entry.author, RAID_CLASS_COLORS[entry.class] or {r=1, g=1, b=1}, false)
                    local messageText = CreateClickableText(content, LFGScannerSettings.font, entry.message, 15 + authorWidth , yOffset, messageWidth, entry.author, nil, true)

                    local lineTime = content:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
                    lineTime:SetPoint("TOPLEFT", content, "TOPLEFT", frameWidth - 125, yOffset)
                    lineTime:SetWidth(timeWidth)
                    lineTime:SetWordWrap(false)
                    lineTime:SetJustifyH("RIGHT")
                    lineTime:SetText("|cFFFFFFFF" .. formatElapsedTime(entry.time) .. "|r")

                    local lineHeight = math.max(authorText:GetStringHeight(), messageText:GetStringHeight(), 20)

                    if rowCount % 2 == 1 then
                        local stripe = content:CreateTexture(nil, "BACKGROUND")
                        stripe:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset + 3)
                        stripe:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset + 3)
                        stripe:SetHeight(lineHeight + 6)
                        stripe:SetTexture(0.4, 0.4, 0.4, 0.3)
                        stripe:SetDrawLayer("BACKGROUND", -1)
                    end

                    yOffset = yOffset - lineHeight - 8
                    rowCount = rowCount + 1
                end
            end

            yOffset = yOffset - 20

        elseif key == "nonFiltered" and LFGScannerFilters.nonFiltered then
            local headerSeparator = content:CreateTexture(nil, "OVERLAY")
            headerSeparator:SetTexture(1, 1, 1, 0.15)
            headerSeparator:SetPoint("TOPLEFT", content, "TOPLEFT", 5, yOffset + 5)
            headerSeparator:SetPoint("TOPRIGHT", content, "TOPRIGHT", -5, yOffset + 5)
            headerSeparator:SetHeight(1)

            local header = CreateFrame("Button", nil, content)
            header:SetSize(frameWidth - 20, 20)
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)

            local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerTitle:SetFont("Fonts\\FRIZQT__.TTF", (LFGScannerSettings.fontSize or 12) + 1)
            headerTitle:SetPoint("LEFT", header, "LEFT", 10, 5)
            headerTitle:SetText("|cffffcc99Non-Filtered|r")

            header:SetScript("OnClick", function()
                collapsed[key] = not collapsed[key]
                UpdateUI()
            end)

            yOffset = yOffset - 20

            if not collapsed[key] then
                for _, entry in ipairs(entries) do
                    local authorText = CreateClickableText(content, LFGScannerSettings.font, entry.author, 10, yOffset, authorWidth, entry.author, RAID_CLASS_COLORS[entry.class] or {r=1, g=1, b=1}, false)
                    local messageText = CreateClickableText(content, LFGScannerSettings.font, entry.message, 15 + authorWidth , yOffset, messageWidth, entry.author, nil, true)

                    local lineTime = content:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
                    lineTime:SetPoint("TOPLEFT", content, "TOPLEFT", frameWidth - 125, yOffset)
                    lineTime:SetWidth(timeWidth)
                    lineTime:SetWordWrap(false)
                    lineTime:SetJustifyH("RIGHT")
                    lineTime:SetText("|cFFFFFFFF" .. formatElapsedTime(entry.time) .. "|r")

                    local lineHeight = math.max(authorText:GetStringHeight(), messageText:GetStringHeight(), 20)

                    if rowCount % 2 == 1 then
                        local stripe = content:CreateTexture(nil, "BACKGROUND")
                        stripe:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset + 3)
                        stripe:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset + 3)
                        stripe:SetHeight(lineHeight + 6)
                        stripe:SetTexture(0.4, 0.4, 0.4, 0.3)
                        stripe:SetDrawLayer("BACKGROUND", -1)
                    end

                    yOffset = yOffset - lineHeight - 8
                    rowCount = rowCount + 1
                end
            end

            yOffset = yOffset - 20

            else
                    local dungeon, size = string.match(key, "^(.-)%-(%d+)$")
                    if dungeon and size and LFGScannerFilters.dungeons[dungeon] and
                       ((size == "10" and LFGScannerFilters.size10) or (size == "25" and LFGScannerFilters.size25)) then

                        -- (Optional) Top separator before dungeon header
                        local headerSeparator = content:CreateTexture(nil, "OVERLAY")
                        headerSeparator:SetTexture(1, 1, 1, 0.15)
                        headerSeparator:SetPoint("TOPLEFT", content, "TOPLEFT", 5, yOffset + 5)
                        headerSeparator:SetPoint("TOPRIGHT", content, "TOPRIGHT", -5, yOffset + 5)
                        headerSeparator:SetHeight(1)

                        -- Create Dungeon Header
                        local dungeonButton = CreateFrame("Button", nil, content)
                        dungeonButton:SetSize(frameWidth - 20, 20)
                        dungeonButton:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)

                        local dungeonTitle = dungeonButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        dungeonTitle:SetFont("Fonts\\FRIZQT__.TTF", (LFGScannerSettings.fontSize or 12) + 1)
                        dungeonTitle:SetPoint("LEFT", dungeonButton, "LEFT", 10, 5)
                        dungeonTitle:SetText("|cff00ff00" .. (dungeonKeywords[dungeon] or dungeon) .. " " .. size .. "|r")

                        dungeonButton:SetScript("OnClick", function()
                            collapsed[key] = not collapsed[key]
                            UpdateUI()
                        end)

                        yOffset = yOffset - 20

                        if not collapsed[key] then
                            for _, entry in ipairs(entries) do
                                local authorText = CreateClickableText(content, LFGScannerSettings.font, entry.author, 10, yOffset, authorWidth, entry.author, RAID_CLASS_COLORS[entry.class] or { r = 1, g = 1, b = 1 }, false)
                                local messageText = CreateClickableText(content, LFGScannerSettings.font, entry.message, 15 + authorWidth, yOffset, messageWidth, entry.author, nil, true)

                                local lineTime = content:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
                                lineTime:SetPoint("TOPLEFT", content, "TOPLEFT", frameWidth - 125, yOffset)
                                lineTime:SetWidth(timeWidth)
                                lineTime:SetWordWrap(false)
                                lineTime:SetJustifyH("RIGHT")
                                lineTime:SetText("|cFFFFFFFF" .. formatElapsedTime(entry.time) .. "|r")

                                local lineHeight = math.max(authorText:GetStringHeight(), messageText:GetStringHeight(), 20)

                                if rowCount % 2 == 1 then
                                    local stripe = content:CreateTexture(nil, "BACKGROUND")
                                    stripe:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset + 3)
                                    stripe:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset + 3)
                                    stripe:SetHeight(lineHeight + 6)
                                    stripe:SetTexture(0.4, 0.4, 0.4, 0.3)
                                    stripe:SetDrawLayer("BACKGROUND", -1)
                                end

                                yOffset = yOffset - lineHeight - 8
                                rowCount = rowCount + 1
                            end
                        end

                        yOffset = yOffset - 20
                    end
                end
            end
                



    local height = math.abs(yOffset)
    content:SetHeight(height)
    scrollbar:SetMinMaxValues(0, math.max(0, height - 400))
    content:Show()
end

HandleIncomingMessage = function(msg, author, class)
    local dungeon = ContainsKeyword(msg)

    if IsGuildRecruitment(msg) then
        AddMessage("guildRecruitment", nil, author, msg, class)
        UpdateUI()
    elseif dungeon then
        local size = DetectSize(msg)
        AddMessage(dungeon, size, author, msg, class)
        UpdateUI()
    elseif LFGScannerFilters.nonFiltered then
        AddMessage("nonFiltered", nil, author, msg, class)
        UpdateUI()
    end
end

-- Buttons

local filterButton = CreateFrame("Button", nil, uiFrame, "UIPanelButtonTemplate")
filterButton:SetSize(60, 20)
filterButton:SetPoint("TOPLEFT", uiFrame, "TOPLEFT", 10, -10)
filterButton:SetText("Filters")

local refreshButton = CreateFrame("Button", nil, uiFrame, "UIPanelButtonTemplate")
refreshButton:SetSize(60, 20)
refreshButton:SetPoint("LEFT", filterButton, "RIGHT", 5, 0)
refreshButton:SetText("Refresh")
refreshButton:SetScript("OnClick", function() UpdateUI() end)

local clearButton = CreateFrame("Button", nil, uiFrame, "UIPanelButtonTemplate")
clearButton:SetSize(60, 20)
clearButton:SetPoint("LEFT", refreshButton, "RIGHT", 5, 0)
clearButton:SetText("Clear")
clearButton:SetScript("OnClick", function()
    LFGScannerDB = {}
    seenAuthors = {}
    toggleButton.indicator:Hide()
    UpdateUI()
end)



local optionsButton = CreateFrame("Button", nil, uiFrame, "UIPanelButtonTemplate")
optionsButton:SetSize(60, 20)
optionsButton:SetPoint("TOPRIGHT", uiFrame, "TOPRIGHT", -10, -10)
optionsButton:SetText("Options")


local fonts = {
    "GameFontNormalSmall",
    "GameFontNormal",
}



local dungeonCheckboxes = {}
local size10Checkbox, size25Checkbox

local function CreateFilterUI()
    filterFrame = CreateFrame("Frame", "LFGFilterFrame", uiFrame)  -- Parent is now uiFrame
    filterFrame:SetSize(200, 440)  -- narrower, but taller for vertical list
    filterFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    filterFrame:SetBackdropColor(0, 0, 0, 1)
    filterFrame:SetPoint("TOPLEFT", uiFrame, "TOPLEFT", -filterFrame:GetWidth(), 0)  -- Positioned to the right of the main frame
    filterFrame:SetMovable(false)  -- No longer movable manually
    filterFrame:EnableMouse(true)


    local title = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Filters")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")



    local startX, startY = 10, -35
    local rowHeight = 25  -- a bit tighter rows

    local yOffset = startY

    for dungeon, dungeonFullName in pairs(dungeonKeywords) do
        local cb = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", startX, yOffset)

        local label = filterFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
        label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
        label:SetText(dungeonFullName)

        cb:SetChecked(LFGScannerFilters.dungeons[dungeon])
        cb:SetScript("OnClick", function(self)
            LFGScannerFilters.dungeons[dungeon] = self:GetChecked()
        end)

        table.insert(dungeonCheckboxes, cb)

        yOffset = yOffset - rowHeight
    end

    -- Separator line
    local separator = filterFrame:CreateTexture(nil, "ARTWORK")
    separator:SetTexture(1, 1, 1, 0.2)
    separator:SetSize(160, 1)
    separator:SetPoint("TOPLEFT", startX, yOffset - 10)

    yOffset = yOffset - 20

    -- Size 10 and 25 checkboxes
    size10Checkbox = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    size10Checkbox:SetSize(20, 20)
    size10Checkbox:SetPoint("TOPLEFT", startX, yOffset)
    local label10 = filterFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
    label10:SetPoint("LEFT", size10Checkbox, "RIGHT", 5, 0)
    label10:SetText("10-man")

    size10Checkbox:SetChecked(LFGScannerFilters.size10)
    size10Checkbox:SetScript("OnClick", function(self)
        LFGScannerFilters.size10 = self:GetChecked()
    end)

    yOffset = yOffset - rowHeight

    size25Checkbox = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    size25Checkbox:SetSize(20, 20)
    size25Checkbox:SetPoint("TOPLEFT", startX, yOffset)
    local label25 = filterFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
    label25:SetPoint("LEFT", size25Checkbox, "RIGHT", 5, 0)
    label25:SetText("25-man")

    size25Checkbox:SetChecked(LFGScannerFilters.size25)
    size25Checkbox:SetScript("OnClick", function(self)
        LFGScannerFilters.size25 = self:GetChecked()
    end)

    yOffset = yOffset - 20

    -- Separator line
    local separator = filterFrame:CreateTexture(nil, "ARTWORK")
    separator:SetTexture(1, 1, 1, 0.2)
    separator:SetSize(160, 1)
    separator:SetPoint("TOPLEFT", startX, yOffset - 10)

    yOffset = yOffset - 20

    -- Guild Recruitment Checkbox
    local guildCB = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    guildCB:SetSize(20, 20)
    guildCB:SetPoint("TOPLEFT", startX, yOffset)
    local guildLabel = filterFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
    guildLabel:SetPoint("LEFT", guildCB, "RIGHT", 5, 0)
    guildLabel:SetText("Guild Recruitment")
    guildCB:SetChecked(LFGScannerFilters.guildRecruitment)
    guildCB:SetScript("OnClick", function(self)
        LFGScannerFilters.guildRecruitment = self:GetChecked()
    end)

    yOffset = yOffset - rowHeight

    -- Non-Filtered Checkbox
    local nonFilteredCB = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    nonFilteredCB:SetSize(20, 20)
    nonFilteredCB:SetPoint("TOPLEFT", startX, yOffset)
    local nonFilteredLabel = filterFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
    nonFilteredLabel:SetPoint("LEFT", nonFilteredCB, "RIGHT", 5, 0)
    nonFilteredLabel:SetText("Non-Filtered")
    nonFilteredCB:SetChecked(LFGScannerFilters.nonFiltered)
    nonFilteredCB:SetScript("OnClick", function(self)
        LFGScannerFilters.nonFiltered = self:GetChecked()
    end)
    yOffset = yOffset - rowHeight

    -- Buttons
    local applyButton = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
    applyButton:SetSize(70, 20)
    applyButton:SetPoint("BOTTOM", filterFrame, "BOTTOM", -45, 10)
    applyButton:SetText("Apply")
    applyButton:SetScript("OnClick", function()
        filterFrame:Hide()
        UpdateUI()
    end)

    local closeButton = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(70, 20)
    closeButton:SetPoint("BOTTOM", filterFrame, "BOTTOM", 45, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        filterFrame:Hide()
    end)
end

local function CreateOptionsUI()
    optionsFrame = CreateFrame("Frame", "LFGOptionsFrame", uiFrame)
    optionsFrame:SetSize(200, 200)
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    optionsFrame:SetBackdropColor(0, 0, 0, 1)
    optionsFrame:SetPoint("TOPRIGHT", uiFrame, "TOPRIGHT", 200, 0)

    local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Options")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")


    local soundCheckbox = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    soundCheckbox:SetSize(20, 20)
    soundCheckbox:SetPoint("TOPLEFT", 10, -35)

    local soundLabel = optionsFrame:CreateFontString(nil, "OVERLAY", LFGScannerSettings.font)
    soundLabel:SetPoint("LEFT", soundCheckbox, "RIGHT", 8, 0)
    soundLabel:SetJustifyH("LEFT")

    soundLabel:SetText("Enable Sound Alert")


    soundCheckbox:SetChecked(LFGScannerSettings.enableSound)
    soundCheckbox:SetScript("OnClick", function(self)
        LFGScannerSettings.enableSound = self:GetChecked()
    end)

    local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(70, 20)
    closeButton:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        optionsFrame:Hide()
    end)


    -- Font Dropdown inside Options
    -- Font Size Header
    local fontHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontHeader:SetPoint("TOPLEFT", soundCheckbox, "BOTTOMLEFT", 0, -15)
    fontHeader:SetText("Font Size")
    fontHeader:SetJustifyH("LEFT")

    -- Font Dropdown
    local fontSizes = {10, 11, 12, 13, 14, 15, 16}

    local fontDropdown = CreateFrame("Frame", "LFGFontDropdown", optionsFrame, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", fontHeader, "BOTTOMLEFT", -15, -5)
    UIDropDownMenu_SetWidth(fontDropdown, 80)

    UIDropDownMenu_Initialize(fontDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, size in ipairs(fontSizes) do
            info.text = tostring(size)
            info.checked = (LFGScannerSettings.fontSize == size)
            info.func = function()
                LFGScannerSettings.fontSize = size
                UIDropDownMenu_SetText(fontDropdown, tostring(size))
                UpdateUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetText(fontDropdown, tostring(LFGScannerSettings.fontSize or 12))

end

local optionsInitialized = false
local filterInitialized = false

filterButton:SetScript("OnClick", function()
    if not filterInitialized then
        CreateFilterUI()
        filterInitialized = true
        filterFrame:Show()
    else
        if filterFrame:IsShown() then
            filterFrame:Hide()
        else
            filterFrame:Show()
        end
    end
end)

optionsButton:SetScript("OnClick", function()
    if not optionsInitialized then
        CreateOptionsUI()
        optionsInitialized = true
        optionsFrame:Show()
    else
        if optionsFrame:IsShown() then
            optionsFrame:Hide()
        else
            optionsFrame:Show()
        end
    end
end)





-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_YELL")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not LFGScannerSettings.font then
            LFGScannerSettings.font = "GameFontNormal"
        end
        print("|cFF33FF99[LFGScanner]|r Loaded. Version " .. version)
    else
        local msg, author, language, channelName, _, _, _, _, _, _, _, guid = ...

        if event == "CHAT_MSG_CHANNEL" then

        local shortName = channelName:match("%d+%.%s*(.-)%s*%-") or channelName
        shortName = shortName:gsub("^%d+%.%s*", "")
        
        if validChannels[shortName] then
            local _, class = GetPlayerInfoByGUID(guid)
            HandleIncomingMessage(msg, author, class)
        end

        elseif event == "CHAT_MSG_YELL" then
            if language and (language == "Orcish" or language == "Thalassian") then
                return
            end
            local _, class = GetPlayerInfoByGUID(guid)
            HandleIncomingMessage(msg, author, class)
        end
    end
end)

-- Auto-refresh
local refreshTimer = CreateFrame("Frame")
refreshTimer:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed > 30 then
        UpdateUI()
        self.elapsed = 0
    end
end)

-- Slash command to toggle UI
SLASH_LFGSCANNER1 = '/lfgscanner'

SlashCmdList["LFGSCANNER"] = function(msg)
    if LFGScannerUI then
        if LFGScannerUI:IsShown() then
            LFGScannerUI:Hide()
            print("|cFF33FF99[LFGScanner]|r Hidden.")
        else
            LFGScannerUI:Show()
            print("|cFF33FF99[LFGScanner]|r Shown.")
        end
    else
        print("|cFFFF0000[LFGScanner]|r UI not loaded.")
    end
end


--font fix

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local font = LibStub("LibSharedMedia-3.0"):Fetch("font", "PT Sans Narrow")

    ChatFontNormal:SetFont(font, 14)
end)