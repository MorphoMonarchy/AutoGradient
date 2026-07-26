--[[
  @description AutoGradientConfig - Edit color rules
  @version 1.0.0
  @noindex
  @about
    Edits the ordered, case-insensitive color rules used by AutoGradient.
    Requires ReaImGui 0.10 or newer.
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

local ctx = ImGui.CreateContext("AutoGradient Color Rules")
local rules = Settings.load_rules()
local window_open = true
local is_dirty = false
local status_message = ""

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

local function clone_rule_color(rule_index)
    local source = rules[rule_index]

    table.insert(rules, rule_index + 1, {
        name = "",
        color = {
            red = source.color.red,
            green = source.color.green,
            blue = source.color.blue,
        },
    })

    is_dirty = true
end

local function add_rule()
    rules[#rules + 1] = {
        name = "",
        color = {red = 160, green = 160, blue = 160},
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

local function draw_rule_table()
    local table_flags = ImGui.TableFlags_BordersInnerH
        | ImGui.TableFlags_RowBg
        | ImGui.TableFlags_Resizable
        | ImGui.TableFlags_SizingStretchProp

    if not ImGui.BeginTable(ctx, "ColorRules", 5, table_flags) then
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

        ImGui.TableSetColumnIndex(ctx, 4)

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
        clone_rule_color(pending_action[2])
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
            .. "rule wins, so rules near the top have higher priority."
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
        820,
        460,
        ImGui.Cond_FirstUseEver
    )

    local visible
    visible, window_open = ImGui.Begin(
        ctx,
        "AutoGradient Color Rules",
        window_open
    )

    if visible then
        draw_editor()
    end

    ImGui.End(ctx)

    if window_open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)
