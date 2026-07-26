--[[
  @description AutoGradientConfig - Edit color and icon rules
  @version 1.1.0
  @noindex
  @about
    Edits the ordered, case-insensitive color and track-icon rules used by
    AutoGradient. Requires ReaImGui 0.10 or newer.
]]

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local script_directory = script_path:match("^(.*[/\\])") or ""
local Settings = dofile(script_directory .. "Settings.lua")

if type(reaper.ImGui_GetBuiltinPath) ~= "function" then
    reaper.MB(
        "ReaImGui is not installed or REAPER has not been restarted "
            .. "since it was installed.\n\n"
            .. "Install ReaImGui through Extensions > ReaPack > "
            .. "Browse packages, restart REAPER, and run this editor again.",
        "AutoGradientConfig",
        0
    )
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path

local loaded, ImGui = pcall(function()
    return require("imgui")("0.10")
end)

if not loaded then
    reaper.MB(
        "ReaImGui was found, but API version 0.10 could not be loaded.\n\n"
            .. tostring(ImGui),
        "AutoGradientConfig",
        0
    )
    return
end

local ctx = ImGui.CreateContext("AutoGradient Rules")
local rules = Settings.load_rules()
local window_open = true
local is_dirty = false
local status_message = ""
local track_icon_directory =
    reaper.GetResourcePath() .. "/Data/track_icons"
local icon_catalog = {}
local icon_image_cache = {}
local icon_picker_rule = nil
local icon_picker_filter = ""
local icon_picker_window_open = false

local ICON_SCAN_MAX_DEPTH = 8
local ICON_THUMBNAIL_SIZE = 52
local ICON_CELL_WIDTH = 68

local function join_path(directory, name)
    return directory .. "/" .. name
end

local function is_absolute_path(path)
    return path:match("^[/\\]") ~= nil
        or path:match("^%a:[/\\]") ~= nil
end

local function get_icon_full_path(icon_path)
    if not icon_path or icon_path == "" then
        return nil
    end

    if is_absolute_path(icon_path) then
        return icon_path
    end

    return join_path(track_icon_directory, icon_path)
end

local function is_supported_icon_file(file_name)
    local lower_name = string.lower(file_name or "")

    return lower_name:match("%.png$") ~= nil
        or lower_name:match("%.jpe?g$") ~= nil
end

local function scan_icon_directory(
    absolute_directory,
    relative_directory,
    depth
)
    if depth > ICON_SCAN_MAX_DEPTH then
        return
    end

    reaper.EnumerateFiles(absolute_directory, -1)

    local file_index = 0

    while true do
        local file_name = reaper.EnumerateFiles(
            absolute_directory,
            file_index
        )

        if not file_name then
            break
        end

        if is_supported_icon_file(file_name) then
            local relative_path = relative_directory .. file_name

            icon_catalog[#icon_catalog + 1] = {
                name = file_name,
                relative_path = relative_path,
                full_path = join_path(
                    absolute_directory,
                    file_name
                ),
            }
        end

        file_index = file_index + 1
    end

    reaper.EnumerateSubdirectories(absolute_directory, -1)

    local directory_index = 0

    while true do
        local directory_name = reaper.EnumerateSubdirectories(
            absolute_directory,
            directory_index
        )

        if not directory_name then
            break
        end

        scan_icon_directory(
            join_path(absolute_directory, directory_name),
            relative_directory .. directory_name .. "/",
            depth + 1
        )

        directory_index = directory_index + 1
    end
end

local function refresh_icon_catalog()
    icon_catalog = {}
    scan_icon_directory(track_icon_directory, "", 0)

    table.sort(icon_catalog, function(first, second)
        return string.lower(first.relative_path)
            < string.lower(second.relative_path)
    end)
end

local function clear_icon_image_cache()
    for _, image in pairs(icon_image_cache) do
        if image then
            ImGui.Detach(ctx, image)
        end
    end

    icon_image_cache = {}
end

local function get_icon_image(icon_path)
    local full_path = get_icon_full_path(icon_path)

    if not full_path then
        return nil
    end

    local cached_image = icon_image_cache[full_path]

    if cached_image ~= nil then
        return cached_image or nil
    end

    local image = ImGui.CreateImage(
        full_path,
        ImGui.ImageFlags_NoErrors
    )

    if image then
        ImGui.Attach(ctx, image)
        icon_image_cache[full_path] = image
        return image
    end

    icon_image_cache[full_path] = false
    return nil
end

local function icon_matches_filter(icon)
    local filter = string.lower(icon_picker_filter or "")

    if filter == "" then
        return true
    end

    return string.find(
        string.lower(icon.relative_path),
        filter,
        1,
        true
    ) ~= nil
end

refresh_icon_catalog()

local function pack_rgb(color)
    return ((color.red & 0xFF) << 16)
        | ((color.green & 0xFF) << 8)
        | (color.blue & 0xFF)
end

local function unpack_rgb(packed_color)
    return {
        red = (packed_color >> 16) & 0xFF,
        green = (packed_color >> 8) & 0xFF,
        blue = packed_color & 0xFF,
    }
end

local function move_rule(rule_index, offset)
    local destination = rule_index + offset

    if destination < 1 or destination > #rules then
        return
    end

    rules[rule_index], rules[destination] =
        rules[destination], rules[rule_index]
    is_dirty = true
end

local function clone_rule(rule_index)
    local source = rules[rule_index]

    table.insert(rules, rule_index + 1, {
        name = "",
        color = {
            red = source.color.red,
            green = source.color.green,
            blue = source.color.blue,
        },
        icon = source.icon or "",
    })

    is_dirty = true
end

local function add_rule()
    rules[#rules + 1] = {
        name = "",
        color = {red = 160, green = 160, blue = 160},
        icon = "",
    }
    is_dirty = true
end

local function save_rules(close_after_save)
    local saved, result = Settings.save_rules(rules)

    if not saved then
        status_message = result
        return
    end

    rules = Settings.copy_rules(result)
    is_dirty = false
    status_message = "Rules saved. AutoGradient will refresh automatically."

    if close_after_save then
        window_open = false
    end
end

local function open_icon_picker(rule)
    icon_picker_rule = rule
    icon_picker_filter = ""
    icon_picker_window_open = true
end

local function mark_icon_changed()
    is_dirty = true
    status_message = ""
end

local function draw_rule_icon_control(rule)
    local icon_path = rule.icon or ""
    local image = get_icon_image(icon_path)

    if image then
        if ImGui.ImageButton(
            ctx,
            "##CurrentRuleIcon",
            image,
            30,
            30
        ) then
            open_icon_picker(rule)
        end

        if ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(ctx, icon_path)
        end

        ImGui.SameLine(ctx)
    end

    local choose_label = icon_path == ""
        and "Choose..."
        or "Change..."

    if ImGui.SmallButton(ctx, choose_label) then
        open_icon_picker(rule)
    end

    if icon_path ~= "" then
        ImGui.SameLine(ctx)

        if ImGui.SmallButton(ctx, "None") then
            rule.icon = ""
            mark_icon_changed()
        end

        if ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(
                ctx,
                "Stop automatically assigning an icon. "
                    .. "Existing track icons are left unchanged."
            )
        end
    end
end

local function draw_icon_grid()
    local available_width = ImGui.GetContentRegionAvail(ctx)
    local column_count = math.max(
        1,
        math.floor(available_width / ICON_CELL_WIDTH)
    )
    local table_flags = ImGui.TableFlags_SizingFixedFit
        | ImGui.TableFlags_ScrollY

    if not ImGui.BeginTable(
        ctx,
        "TrackIconGrid",
        column_count,
        table_flags,
        0,
        390
    ) then
        return
    end

    local visible_icon_count = 0

    for _, icon in ipairs(icon_catalog) do
        if icon_matches_filter(icon) then
            visible_icon_count = visible_icon_count + 1
            ImGui.TableNextColumn(ctx)

            local image = get_icon_image(icon.relative_path)

            if image then
                local is_selected = icon_picker_rule
                    and icon_picker_rule.icon
                        == icon.relative_path
                local background_color = is_selected
                    and 0x4C8ED9FF
                    or 0x00000000

                if ImGui.ImageButton(
                    ctx,
                    "##" .. icon.relative_path,
                    image,
                    ICON_THUMBNAIL_SIZE,
                    ICON_THUMBNAIL_SIZE,
                    0,
                    0,
                    1,
                    1,
                    background_color,
                    0xFFFFFFFF
                ) then
                    icon_picker_rule.icon = icon.relative_path
                    mark_icon_changed()
                    icon_picker_rule = nil
                    icon_picker_window_open = false
                end

                if ImGui.IsItemHovered(ctx) then
                    ImGui.SetTooltip(ctx, icon.relative_path)
                end
            end
        end
    end

    ImGui.EndTable(ctx)

    if visible_icon_count == 0 then
        ImGui.TextDisabled(ctx, "No matching track icons found.")
    end
end

local function draw_icon_picker()
    ImGui.SetNextWindowSize(
        ctx,
        720,
        520,
        ImGui.Cond_FirstUseEver
    )

    local visible
    visible, icon_picker_window_open = ImGui.Begin(
        ctx,
        "Choose REAPER Track Icon",
        icon_picker_window_open
    )

    if visible then
        ImGui.Text(
            ctx,
            "Icons from REAPER/Data/track_icons"
        )

        ImGui.SetNextItemWidth(ctx, -100)
        local _, new_filter = ImGui.InputText(
            ctx,
            "##IconFilter",
            icon_picker_filter,
            ImGui.InputTextFlags_AutoSelectAll
        )
        icon_picker_filter = new_filter

        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "Refresh") then
            clear_icon_image_cache()
            refresh_icon_catalog()
        end

        ImGui.TextDisabled(
            ctx,
            "Type part of a filename to filter, then click an icon."
        )
        ImGui.Separator(ctx)

        draw_icon_grid()

        ImGui.Separator(ctx)

        if ImGui.Button(ctx, "Cancel") then
            icon_picker_rule = nil
            icon_picker_window_open = false
        end
    end

    ImGui.End(ctx)

    if not icon_picker_window_open then
        icon_picker_rule = nil
    end
end

local function draw_rule_table()
    local table_flags = ImGui.TableFlags_BordersInnerH
        | ImGui.TableFlags_RowBg
        | ImGui.TableFlags_Resizable
        | ImGui.TableFlags_SizingStretchProp

    if not ImGui.BeginTable(ctx, "ColorRules", 6, table_flags) then
        return
    end

    ImGui.TableSetupColumn(
        ctx,
        "Priority",
        ImGui.TableColumnFlags_WidthFixed,
        58
    )
    ImGui.TableSetupColumn(ctx, "Name contains")
    ImGui.TableSetupColumn(
        ctx,
        "Base color",
        ImGui.TableColumnFlags_WidthFixed,
        220
    )
    ImGui.TableSetupColumn(
        ctx,
        "Track icon",
        ImGui.TableColumnFlags_WidthFixed,
        174
    )
    ImGui.TableSetupColumn(
        ctx,
        "Order",
        ImGui.TableColumnFlags_WidthFixed,
        88
    )
    ImGui.TableSetupColumn(
        ctx,
        "Actions",
        ImGui.TableColumnFlags_WidthFixed,
        112
    )
    ImGui.TableHeadersRow(ctx)

    local pending_action = nil

    for rule_index, rule in ipairs(rules) do
        ImGui.PushID(ctx, rule_index)
        ImGui.TableNextRow(ctx)

        ImGui.TableSetColumnIndex(ctx, 0)
        ImGui.Text(ctx, tostring(rule_index))

        ImGui.TableSetColumnIndex(ctx, 1)
        ImGui.SetNextItemWidth(ctx, -1)
        local name_changed, new_name = ImGui.InputText(
            ctx,
            "##RuleName",
            rule.name
        )

        if name_changed then
            rule.name = new_name
            is_dirty = true
            status_message = ""
        end

        ImGui.TableSetColumnIndex(ctx, 2)
        ImGui.SetNextItemWidth(ctx, -1)
        local color_changed, packed_color = ImGui.ColorEdit3(
            ctx,
            "##RuleColor",
            pack_rgb(rule.color)
        )

        if color_changed then
            rule.color = unpack_rgb(packed_color)
            is_dirty = true
            status_message = ""
        end

        ImGui.TableSetColumnIndex(ctx, 3)
        draw_rule_icon_control(rule)

        ImGui.TableSetColumnIndex(ctx, 4)
        if rule_index == 1 then
            ImGui.BeginDisabled(ctx)
        end

        if ImGui.SmallButton(ctx, "Up") then
            pending_action = {"move", rule_index, -1}
        end

        if rule_index == 1 then
            ImGui.EndDisabled(ctx)
        end

        ImGui.SameLine(ctx)

        if rule_index == #rules then
            ImGui.BeginDisabled(ctx)
        end

        if ImGui.SmallButton(ctx, "Down") then
            pending_action = {"move", rule_index, 1}
        end

        if rule_index == #rules then
            ImGui.EndDisabled(ctx)
        end

        ImGui.TableSetColumnIndex(ctx, 5)

        if ImGui.SmallButton(ctx, "Clone") then
            pending_action = {"clone", rule_index}
        end

        ImGui.SameLine(ctx)

        if ImGui.SmallButton(ctx, "Delete") then
            pending_action = {"delete", rule_index}
        end

        ImGui.PopID(ctx)
    end

    ImGui.EndTable(ctx)

    if not pending_action then
        return
    end

    if pending_action[1] == "move" then
        move_rule(pending_action[2], pending_action[3])
    elseif pending_action[1] == "clone" then
        clone_rule(pending_action[2])
    elseif pending_action[1] == "delete" then
        table.remove(rules, pending_action[2])
        is_dirty = true
    end

    status_message = ""
end

local function draw_editor()
    ImGui.TextWrapped(
        ctx,
        "Rules are matched without regard to case. The first matching "
            .. "rule wins, so rules near the top have higher priority. "
            .. "A rule without an icon leaves existing track icons "
            .. "unchanged."
    )
    ImGui.Spacing(ctx)

    draw_rule_table()

    ImGui.Spacing(ctx)

    if ImGui.Button(ctx, "Add Rule") then
        add_rule()
        status_message = ""
    end

    ImGui.SameLine(ctx)

    if ImGui.Button(ctx, "Restore Defaults") then
        rules = Settings.get_default_rules()
        is_dirty = true
        status_message = "Defaults restored locally. Click Save to apply."
    end

    ImGui.Separator(ctx)

    if ImGui.Button(ctx, "Save") then
        save_rules(false)
    end

    ImGui.SameLine(ctx)

    if ImGui.Button(ctx, "Save and Close") then
        save_rules(true)
    end

    ImGui.SameLine(ctx)

    if ImGui.Button(ctx, "Cancel") then
        window_open = false
    end

    ImGui.SameLine(ctx)

    if status_message ~= "" then
        ImGui.TextWrapped(ctx, status_message)
    elseif is_dirty then
        ImGui.TextDisabled(ctx, "Unsaved changes")
    else
        ImGui.TextDisabled(ctx, "No unsaved changes")
    end
end

local function loop()
    ImGui.SetNextWindowSize(
        ctx,
        1080,
        520,
        ImGui.Cond_FirstUseEver
    )

    local visible
    visible, window_open = ImGui.Begin(
        ctx,
        "AutoGradient Color and Icon Rules",
        window_open
    )

    if visible then
        draw_editor()
    end

    ImGui.End(ctx)

    if icon_picker_rule then
        draw_icon_picker()
    end

    if window_open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)
