--[[
  @version 1.1.0
  @noindex
]]

local Settings = {}

local EXTSTATE_SECTION = "AutoGradient"
local LEGACY_EXTSTATE_SECTION = "AutoGradiant"
local SETTINGS_VERSION = "2"
local MAX_RULE_COUNT = 200

local DEFAULT_RULES = {
    {
        name = "best",
        color = {red = 142, green = 91, blue = 91},
        icon = "",
    },
    {
        name = "vox",
        color = {red = 71, green = 122, blue = 122},
        icon = "mic.png",
    },
    {
        name = "perc",
        color = {red = 146, green = 120, blue = 90},
        icon = "drums.png",
    },
    {
        name = "guitar",
        color = {red = 140, green = 100, blue = 133},
        icon = "ac_guitar.png",
    },
    {
        name = "bass",
        color = {red = 91, green = 126, blue = 100},
        icon = "bass4.png",
    },
    {
        name = "synth",
        color = {red = 120, green = 117, blue = 117},
        icon = "drumbox.png",
    },
}

local function clamp_color_channel(value)
    value = tonumber(value) or 0
    return math.max(0, math.min(255, math.floor(value + 0.5)))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function copy_color(color)
    color = color or {}

    return {
        red = clamp_color_channel(color.red),
        green = clamp_color_channel(color.green),
        blue = clamp_color_channel(color.blue),
    }
end

local function copy_rule(rule)
    return {
        name = tostring(rule.name or ""),
        color = copy_color(rule.color),
        icon = trim(rule.icon),
    }
end

function Settings.copy_rules(rules)
    local copy = {}

    for _, rule in ipairs(rules or {}) do
        copy[#copy + 1] = copy_rule(rule)
    end

    return copy
end

function Settings.get_default_rules()
    return Settings.copy_rules(DEFAULT_RULES)
end

function Settings.color_to_hex(color)
    color = copy_color(color)

    return string.format(
        "#%02X%02X%02X",
        color.red,
        color.green,
        color.blue
    )
end

function Settings.hex_to_color(hex_color)
    local hex = tostring(hex_color or ""):match(
        "^#?([%x][%x][%x][%x][%x][%x])$"
    )

    if not hex then
        return nil
    end

    return {
        red = tonumber(hex:sub(1, 2), 16),
        green = tonumber(hex:sub(3, 4), 16),
        blue = tonumber(hex:sub(5, 6), 16),
    }
end

function Settings.validate_rules(rules)
    if #(rules or {}) > MAX_RULE_COUNT then
        return false,
            "AutoGradient supports up to "
                .. MAX_RULE_COUNT
                .. " rules."
    end

    local names = {}

    for rule_index, rule in ipairs(rules or {}) do
        local name = trim(rule.name)

        if name == "" then
            return false, "Rule " .. rule_index .. " needs a name."
        end

        local normalized_name = string.lower(name)

        if names[normalized_name] then
            return false,
                "Rules "
                    .. names[normalized_name]
                    .. " and "
                    .. rule_index
                    .. " use the same name."
        end

        names[normalized_name] = rule_index
    end

    return true
end

function Settings.get_revision()
    local revision = reaper.GetExtState(EXTSTATE_SECTION, "rules_revision")

    if revision == "" then
        revision = reaper.GetExtState(
            LEGACY_EXTSTATE_SECTION,
            "rules_revision"
        )
    end

    return revision ~= "" and revision or "0"
end

function Settings.load_rules()
    local settings_section = EXTSTATE_SECTION
    local saved_version = reaper.GetExtState(
        settings_section,
        "settings_version"
    )

    if saved_version == "" then
        settings_section = LEGACY_EXTSTATE_SECTION
        saved_version = reaper.GetExtState(
            settings_section,
            "settings_version"
        )

        if saved_version == "" then
            return Settings.get_default_rules()
        end
    end

    local rule_count = tonumber(
        reaper.GetExtState(settings_section, "rule_count")
    ) or 0

    rule_count = math.max(
        0,
        math.min(MAX_RULE_COUNT, math.floor(rule_count))
    )

    local rules = {}

    for rule_index = 1, rule_count do
        local name = reaper.GetExtState(
            settings_section,
            "rule_" .. rule_index .. "_name"
        )
        local color = Settings.hex_to_color(
            reaper.GetExtState(
                settings_section,
                "rule_" .. rule_index .. "_color"
            )
        )
        local icon = reaper.GetExtState(
            settings_section,
            "rule_" .. rule_index .. "_icon"
        )

        if name ~= "" and color then
            rules[#rules + 1] = {
                name = name,
                color = color,
                icon = icon,
            }
        end
    end

    if settings_section == LEGACY_EXTSTATE_SECTION then
        Settings.save_rules(rules)
    end

    return rules
end

function Settings.save_rules(rules)
    local valid, validation_message = Settings.validate_rules(rules)

    if not valid then
        return false, validation_message
    end

    local clean_rules = {}

    for _, rule in ipairs(rules or {}) do
        clean_rules[#clean_rules + 1] = {
            name = trim(rule.name),
            color = copy_color(rule.color),
            icon = trim(rule.icon),
        }
    end

    reaper.SetExtState(
        EXTSTATE_SECTION,
        "settings_version",
        SETTINGS_VERSION,
        true
    )
    reaper.SetExtState(
        EXTSTATE_SECTION,
        "rule_count",
        tostring(#clean_rules),
        true
    )

    for rule_index, rule in ipairs(clean_rules) do
        reaper.SetExtState(
            EXTSTATE_SECTION,
            "rule_" .. rule_index .. "_name",
            rule.name,
            true
        )
        reaper.SetExtState(
            EXTSTATE_SECTION,
            "rule_" .. rule_index .. "_color",
            Settings.color_to_hex(rule.color),
            true
        )
        reaper.SetExtState(
            EXTSTATE_SECTION,
            "rule_" .. rule_index .. "_icon",
            rule.icon,
            true
        )
    end

    local revision = tonumber(Settings.get_revision()) or 0
    revision = revision + 1

    reaper.SetExtState(
        EXTSTATE_SECTION,
        "rules_revision",
        tostring(revision),
        true
    )

    return true, clean_rules
end

return Settings
