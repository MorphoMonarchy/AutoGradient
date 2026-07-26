--[[
  @description AutoGradient
  @version 1.1.0
  @author Morpho Monarchy Studios
  @changelog
    Added optional REAPER track-icon assignments to color rules.
  @link
    GitHub repository https://github.com/MorphoMonarchy/AutoGradient
  @provides
    [main] .
    [main] AutoGradientConfig.lua
    [nomain] Settings.lua
  @about
    Automatically assigns color gradients and optional track icons using
    ordered, case-insensitive name rules. Includes AutoGradientConfig, a
    ReaImGui editor for creating and prioritizing custom rules.
]]

----------------------------------- SETTINGS ----------------------------------

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local script_directory = script_path:match("^(.*[/\\])") or ""
local Settings = dofile(script_directory .. "Settings.lua")
local COLOR_RULES = Settings.load_rules()

-- Each additional track widens the light-to-dark range. The cap prevents
-- colors in large groups from becoming too close to pure white or black.
local GRADIENT_STEP_PER_TRACK = 0.05
local MAX_GRADIENT_AMOUNT = 0.45

-- How often the script checks for renamed, duplicated, added, removed, or
-- reordered tracks.
local TRACK_SCAN_INTERVAL_SECONDS = 0.25

local PROJECT = 0

----------------------------------- HELPERS -----------------------------------

local function clamp_color_channel(value)
    return math.max(0, math.min(255, math.floor(value)))
end

local function make_reaper_color(red, green, blue)
    red = clamp_color_channel(red)
    green = clamp_color_channel(green)
    blue = clamp_color_channel(blue)

    -- The high bit tells REAPER that this is a custom color.
    return reaper.ColorToNative(red, green, blue) | 0x1000000
end

local function string_contains(text, search_text)
    text = string.lower(text or "")
    search_text = string.lower(search_text or "")

    -- Plain-text matching avoids treating characters as Lua patterns.
    return string.find(text, search_text, 1, true) ~= nil
end

local function get_rule_for_track(track_name)
    for rule_index, rule in ipairs(COLOR_RULES) do
        if string_contains(track_name, rule.name) then
            return rule_index, rule
        end
    end

    return nil
end

local function blend_channel(channel, target, amount)
    return channel + ((target - channel) * amount)
end

local function get_gradient_color(base_color, position, group_size)
    if group_size == 1 then
        return make_reaper_color(
            base_color.red,
            base_color.green,
            base_color.blue
        )
    end

    local gradient_amount = math.min(
        MAX_GRADIENT_AMOUNT,
        (group_size - 1) * GRADIENT_STEP_PER_TRACK
    )

    -- 1 at the top of the group, 0 in the middle, and -1 at the bottom.
    local gradient_position = 1
        - (2 * (position - 1) / (group_size - 1))

    local target = gradient_position > 0 and 255 or 0
    local blend_amount = math.abs(gradient_position) * gradient_amount

    return make_reaper_color(
        blend_channel(base_color.red, target, blend_amount),
        blend_channel(base_color.green, target, blend_amount),
        blend_channel(base_color.blue, target, blend_amount)
    )
end

local function group_tracks_by_rule()
    local groups = {}

    for rule_index, rule in ipairs(COLOR_RULES) do
        groups[rule_index] = {
            rule = rule,
            tracks = {},
        }
    end

    local track_count = reaper.CountTracks(PROJECT)

    for track_index = 0, track_count - 1 do
        local track = reaper.GetTrack(PROJECT, track_index)

        if track then
            local _, track_name = reaper.GetTrackName(track)
            local rule_index = get_rule_for_track(track_name)

            if rule_index then
                local tracks = groups[rule_index].tracks
                tracks[#tracks + 1] = track
            end
        end
    end

    return groups
end

local function style_track_groups(groups)
    local styled_track_count = 0

    for _, group in ipairs(groups) do
        local group_size = #group.tracks

        for position, track in ipairs(group.tracks) do
            local color = get_gradient_color(
                group.rule.color,
                position,
                group_size
            )

            reaper.SetMediaTrackInfo_Value(
                track,
                "I_CUSTOMCOLOR",
                color
            )

            if group.rule.icon and group.rule.icon ~= "" then
                reaper.GetSetMediaTrackInfo_String(
                    track,
                    "P_ICON",
                    group.rule.icon,
                    true
                )
            end

            styled_track_count = styled_track_count + 1
        end
    end

    return styled_track_count
end

local function get_track_signature()
    local signature_parts = {}
    local track_count = reaper.CountTracks(PROJECT)

    for track_index = 0, track_count - 1 do
        local track = reaper.GetTrack(PROJECT, track_index)

        if track then
            local _, track_name = reaper.GetTrackName(track)
            local track_guid = reaper.GetTrackGUID(track)
            local _, track_icon = reaper.GetSetMediaTrackInfo_String(
                track,
                "P_ICON",
                "",
                false
            )

            signature_parts[#signature_parts + 1] =
                track_guid
                    .. "\31"
                    .. track_name
                    .. "\31"
                    .. (track_icon or "")
        end
    end

    return table.concat(signature_parts, "\30")
end

local function count_grouped_tracks(groups)
    local track_count = 0

    for _, group in ipairs(groups) do
        track_count = track_count + #group.tracks
    end

    return track_count
end

local function apply_track_styles()
    local groups = group_tracks_by_rule()
    local matched_track_count = count_grouped_tracks(groups)

    if matched_track_count == 0 then
        return
    end

    reaper.PreventUIRefresh(1)

    local success, error_message = xpcall(
        function()
            return style_track_groups(groups)
        end,
        debug.traceback
    )

    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    if not success then
        reaper.MB(error_message, "AutoGradient error", 0)
    end
end

------------------------------------ WATCHER ----------------------------------

local _, _, SECTION_ID, COMMAND_ID = reaper.get_action_context()
local last_track_signature = nil
local last_rules_revision = nil
local next_scan_time = 0

local function set_action_toggle_state(state)
    if SECTION_ID and COMMAND_ID and COMMAND_ID > 0 then
        reaper.SetToggleCommandState(SECTION_ID, COMMAND_ID, state)
        reaper.RefreshToolbar2(SECTION_ID, COMMAND_ID)
    end
end

local function stop_watcher()
    set_action_toggle_state(0)
end

local function watch_tracks()
    local current_time = reaper.time_precise()

    if current_time >= next_scan_time then
        next_scan_time = current_time + TRACK_SCAN_INTERVAL_SECONDS

        local current_rules_revision = Settings.get_revision()
        local rules_changed =
            current_rules_revision ~= last_rules_revision

        if rules_changed then
            COLOR_RULES = Settings.load_rules()
            last_rules_revision = current_rules_revision
        end

        local current_signature = get_track_signature()

        if rules_changed
            or current_signature ~= last_track_signature
        then
            last_track_signature = current_signature
            apply_track_styles()
            last_track_signature = get_track_signature()
        end
    end

    reaper.defer(watch_tracks)
end

set_action_toggle_state(1)
reaper.atexit(stop_watcher)
watch_tracks()
