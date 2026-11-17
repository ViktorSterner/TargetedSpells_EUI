-- Independent spell-target detector for EllesmereUI raid frames.
-- Uses unit spellcast events and the Forever target-query APIs; no TargetedSpells
-- addon code or floating display system is loaded.
local DEFAULTS = {
	size = 24,
	point = "CENTER",
	relativePoint = "CENTER",
	offsetX = 0,
	offsetY = 0,
}

local function GetSettings()
	if not TargetedSpellsEUISaved then
		TargetedSpellsEUISaved = {}
	end
	for key, value in pairs(DEFAULTS) do
		if TargetedSpellsEUISaved[key] == nil then
			TargetedSpellsEUISaved[key] = value
		end
	end
	return TargetedSpellsEUISaved
end

local function GetUnitMap()
	local modules = EllesmereUI and EllesmereUI._ModuleNS
	local module = modules and modules.EllesmereUIRaidFrames
	local internals = module and module._internals
	local raidMap = internals and internals.unitToButton
	local partyMap = module and module._partyUnitToButton
	return raidMap, partyMap
end

local function GetGroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, 40 do
			local unit = "raid" .. i
			if UnitExists(unit) then units[#units + 1] = unit end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then units[#units + 1] = unit end
		end
		if UnitExists("player") then units[#units + 1] = "player" end
	end
	return units
end

local icons = {}
local casts = {}
local debugEnabled = false

local function DebugLog(message)
	if debugEnabled then
		print("|cff66ccffTargetedSpells_EUI:|r " .. message)
	end
end

local function CreateIcon()
	local icon = CreateFrame("Frame", nil, UIParent)
	icon:SetSize(DEFAULTS.size, DEFAULTS.size)
	icon:SetFrameStrata("HIGH")
	icon:Hide()
	icon.Texture = icon:CreateTexture(nil, "ARTWORK")
	icon.Texture:SetAllPoints()
	icon.Texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon.Mask = icon:CreateMaskTexture()
	icon.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	icon.Mask:SetAllPoints(icon.Texture)
	icon.Texture:AddMaskTexture(icon.Mask)
	icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.Cooldown:SetAllPoints()
	icon.Cooldown:SetDrawEdge(true)
	icon.Cooldown:SetDrawBling(false)
	icon.Cooldown:SetDrawSwipe(true)
	icon.Cooldown:SetReverse(true)
	icon.Cooldown:SetSwipeColor(0, 0, 0, 0.7)
	return icon
end

local function GetIcon(caster, unit)
	icons[caster] = icons[caster] or {}
	if not icons[caster][unit] then icons[caster][unit] = CreateIcon() end
	return icons[caster][unit]
end

local function HideIcon(unit)
	local casterIcons = icons[unit]
	if casterIcons then
		for _, icon in pairs(casterIcons) do
			icon:Hide()
			icon:ClearAllPoints()
		end
	end
	-- Retain these hidden frames for reuse. Dropping the Lua references here
	-- would make every later cast allocate another set of member icons.
	casts[unit] = nil
end

local function GetCast(caster)
	local name, _, texture, _, _, _, castID, _, spellID = UnitCastingInfo(caster)
	local channel = false
	local duration
	if not name then
		name, _, texture, _, _, _, _, spellID = UnitChannelInfo(caster)
		channel = true
	end
	if not name then return nil end
	if channel and UnitChannelDuration then
		duration = UnitChannelDuration(caster)
	elseif UnitCastingDuration then
		duration = UnitCastingDuration(caster)
	end
	if not duration then return nil end
	if not texture and spellID and C_Spell and C_Spell.GetSpellTexture then
		texture = C_Spell.GetSpellTexture(spellID)
	end
	return {
		texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
		duration = duration,
		castID = castID,
		channel = channel,
	}
end

local function UpdateCaster(caster)
	if type(caster) ~= "string" or not caster:match("^nameplate%d+$") or not UnitExists(caster) then
		DebugLog("unit is not an active nameplate token")
		return
	end
	local cast = GetCast(caster)
	if not cast then
		DebugLog(caster .. ": no active cast reported")
		HideIcon(caster)
		return
	end
	DebugLog(caster .. ": active cast reported")

	if not UnitSpellTargetName or UnitSpellTargetName(caster) == nil then
		DebugLog(caster .. ": cast has no spell target")
		HideIcon(caster)
		return
	end

	local raidMap, partyMap = GetUnitMap()
	local settings = GetSettings()
	local units = GetGroupUnits()
	local shown = 0
	for _, unit in ipairs(units) do
		local button = (raidMap and raidMap[unit]) or (partyMap and partyMap[unit])
		if button then
			local icon = GetIcon(caster, unit)
			icon:SetParent(button)
			icon:ClearAllPoints()
			icon:SetPoint(settings.point, button, settings.relativePoint, settings.offsetX, settings.offsetY)
			icon:SetSize(settings.size, settings.size)
			icon:SetFrameLevel(button:GetFrameLevel() + 20)
			icon.Texture:SetTexture(cast.texture)
			icon.Cooldown:SetCooldownFromDurationObject(cast.duration)
			if UnitIsSpellTarget then
				-- Returns whether this cast's target matches this exact group token.
				icon:SetAlphaFromBoolean(UnitIsSpellTarget(caster, unit), 1, 0)
			elseif PlayerIsSpellTarget and UnitIsUnit(unit, "player") then
				-- PlayerIsSpellTarget has no target-unit argument; only use for self.
				icon:SetAlphaFromBoolean(PlayerIsSpellTarget(caster), 1, 0)
			else
				-- Fallback for clients without UnitIsSpellTarget.
				local target = caster .. "target"
				icon:SetAlpha(UnitExists(target) and UnitIsUnit(target, unit) and 1 or 0)
			end
			icon:Show()
			shown = shown + 1
		end
	end
	if shown == 0 then
		DebugLog("no EUI buttons found for current party/raid tokens")
		HideIcon(caster)
		return
	end
	casts[caster] = true
	DebugLog("cast icon attached to " .. shown .. " EUI frame(s); target visibility uses the client predicate")
end

local function ClearAll()
	for caster in pairs(icons) do HideIcon(caster) end
end

local eventFrame = CreateFrame("Frame")
local function ScheduleCasterUpdate(unit, delay)
	if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then
		DebugLog("event unit is not nameplateN: " .. (type(unit) == "string" and unit or "<missing>"))
		return
	end
	C_Timer.After(delay, function() UpdateCaster(unit) end)
end

for _, event in ipairs({
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_TARGET",
	"GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}) do
	eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
	DebugLog("event " .. event .. (type(unit) == "string" and (" (" .. unit .. ")") or ""))
	if event == "NAME_PLATE_UNIT_REMOVED" then
		HideIcon(unit)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		ScheduleCasterUpdate(unit, 0.2)
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_TARGET" then
		ScheduleCasterUpdate(unit, 0.2)
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		if type(unit) == "string" and unit:match("^nameplate%d+$") then UpdateCaster(unit) end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		for caster in pairs(casts) do UpdateCaster(caster) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		for caster in pairs(casts) do UpdateCaster(caster) end
	end
end)

SLASH_TARGETEDSPELLSEUI1 = "/tseui"
SlashCmdList.TARGETEDSPELLSEUI = function(message)
	local command = strlower((message or ""):match("^%s*(.-)%s*$"))
	if command == "debug" then
		debugEnabled = not debugEnabled
		print("|cff66ccffTargetedSpells_EUI:|r debug logging " .. (debugEnabled and "enabled" or "disabled"))
	elseif command == "status" then
		local raidMap, partyMap = GetUnitMap()
		print("|cff66ccffTargetedSpells_EUI:|r loaded; target API=" .. tostring(type(UnitSpellTargetName) == "function") .. ", UnitIsSpellTarget=" .. tostring(type(UnitIsSpellTarget) == "function") .. ", PlayerIsSpellTarget=" .. tostring(type(PlayerIsSpellTarget) == "function") .. ", EUI raid map=" .. tostring(raidMap ~= nil) .. ", party map=" .. tostring(partyMap ~= nil))
	else
		print("|cff66ccffTargetedSpells_EUI:|r use /tseui status or /tseui debug")
	end
end

-- EUI may repoint/rebuild buttons after roster and visibility transitions.
-- Refresh is event-driven and does not install a per-frame polling loop.
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

_G.TargetedSpells_EUI = {
	Refresh = function() for caster in pairs(casts) do UpdateCaster(caster) end end,
	Defaults = DEFAULTS,
}
