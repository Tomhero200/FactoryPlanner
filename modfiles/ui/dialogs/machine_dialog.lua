require("ui.elements.module_configurator")

-- ** LOCAL UTIL **
local function add_checkbox(modal_elements, checkbox_type, localised_name, identifier, event_name)
    local caption, tooltip = {"fp." .. checkbox_type}, {"fp." .. checkbox_type .. "_tt", localised_name}
    local tags = (event_name) and {mod="fp", on_gui_checked_state_changed=event_name} or nil
    local checkbox = modal_elements.defaults_panel.add{type="checkbox", state=false,
        caption=caption, tooltip=tooltip, tags=tags}
    modal_elements[identifier] = checkbox
end

local function refresh_defaults_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local machine = modal_data.object  --[[@as Machine]]

    -- Machine
    local default_machine = prototyper.defaults.get(player, "machines", machine.proto.category)
    local all_machines = modal_elements.machine_all.state
    modal_elements.machine.enabled = (default_machine.id ~= machine.proto.id and not all_machines)
    modal_elements.machine.state = (default_machine.id == machine.proto.id or all_machines)

    -- Fuel
    local fuel_required, default_fuel = (machine.proto.burner ~= nil), nil
    if fuel_required then
        local machine_category = next(machine.proto.burner.categories, nil)
        default_fuel = prototyper.defaults.get(player, "fuels", machine_category)
    end  ---@cast default_fuel FPFuelPrototype
    local all_fuels = modal_elements.fuel_all.state
    modal_elements.fuel.enabled = fuel_required and (default_fuel.id ~= machine.fuel.proto.id and not all_fuels)
    modal_elements.fuel.state = fuel_required and (default_fuel.id == machine.fuel.proto.id or all_fuels)
    modal_elements.fuel_all.enabled = fuel_required
end

local function add_defaults_panel(parent_frame, player)
    local modal_elements = util.globals.modal_elements(player)

    local bordered_frame = parent_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    bordered_frame.style.vertically_stretchable = true
    bordered_frame.style.right_padding = 24
    modal_elements.defaults_panel = bordered_frame

    bordered_frame.add{type="label", caption={"fp.pu_machine", 1}, style="caption_label"}
    add_checkbox(modal_elements, "save_as_default", {"fp.pl_machine", 1}, "machine")
    add_checkbox(modal_elements, "save_for_all", {"fp.pl_machine", 1}, "machine_all", "toggle_checkbox_all")

    local fuel_label = bordered_frame.add{type="label", caption={"fp.pu_fuel", 1}, style="caption_label"}
    fuel_label.style.top_margin = 8
    add_checkbox(modal_elements, "save_as_default", {"fp.pl_fuel", 1}, "fuel")
    add_checkbox(modal_elements, "save_for_all", {"fp.pl_fuel", 1}, "fuel_all", "toggle_checkbox_all")

    refresh_defaults_frame(player)
end

local function set_defaults(player, machine)
    local modal_elements = util.globals.modal_elements(player)
    if modal_elements.machine_all.state then
        prototyper.defaults.set_all(player, "machines", machine.proto.name)
    elseif modal_elements.machine.state then
        prototyper.defaults.set(player, "machines", machine.proto.id, machine.proto.category)
    end

    if modal_elements.fuel_all.state then
        prototyper.defaults.set_all(player, "fuels", machine.fuel.proto.name)
    elseif modal_elements.fuel.state then
        prototyper.defaults.set(player, "fuels", machine.fuel.proto.id, next(machine.proto.burner.categories, nil))
    end
end


local function refresh_fuel_frame(player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local modal_elements = modal_data.modal_elements
    local machine = modal_data.object

    local machine_burner = machine.proto.burner
    modal_elements.fuel_label.visible = (machine_burner == nil)
    modal_elements.fuel_button.visible = (machine_burner ~= nil)

    if machine_burner == nil then return end
    local fuel_proto = machine.fuel.proto

    modal_elements.fuel_button.elem_value = fuel_proto.name
    modal_elements.fuel_button.elem_filters = machine:compile_fuel_filter()
end


local function create_choice_frame(parent_frame, label_caption)
    local frame_choices = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_bordered_stretch"}
    frame_choices.style.width = (MAGIC_NUMBERS.module_dialog_element_width / 2) - 2

    local flow_choices = frame_choices.add{type="flow", direction="horizontal"}
    flow_choices.style.vertical_align = "center"

    flow_choices.add{type="label", caption=label_caption, style="semibold_label"}
    flow_choices.add{type="empty-widget", style="flib_horizontal_pusher"}

    return flow_choices
end

local function add_machine_frame(parent_frame, player, line)
    local modal_elements = util.globals.modal_data(player).modal_elements
    local flow_choices = create_choice_frame(parent_frame, {"fp.pu_machine", 1})

    local button_machine = flow_choices.add{type="choose-elem-button", elem_type="entity-with-quality",
        tags={mod="fp", on_gui_elem_changed="choose_machine"}, style="fp_sprite-button_inset",
        elem_filters=line:compile_machine_filter()}
    button_machine.elem_value = line.machine:elem_value()
    modal_elements["machine_button"] = button_machine
end

local function add_fuel_frame(parent_frame, player)
    local modal_elements = util.globals.modal_data(player).modal_elements
    local flow_choices = create_choice_frame(parent_frame, {"fp.pu_fuel", 1})

    local label_fuel = flow_choices.add{type="label", caption={"fp.machine_no_fuel_required"}}
    label_fuel.style.padding = {6, 4}
    modal_elements["fuel_label"] = label_fuel

    local button_fuel = flow_choices.add{type="choose-elem-button", elem_type="item",
        tags={mod="fp", on_gui_elem_changed="choose_fuel"}, style="fp_sprite-button_inset"}
    -- Need to set elem filters dynamically depending on the machine
    modal_elements["fuel_button"] = button_fuel

    refresh_fuel_frame(player)
end


local function add_limit_frame(parent_frame, player)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine = modal_data.object

    local frame_limit = parent_frame.add{type="frame", direction="horizontal", style="fp_frame_module"}
    frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_limit"}},
        tooltip={"fp.machine_limit_tt"}, style="semibold_label"}

    local textfield_width = 45
    local textfield_limit = frame_limit.add{type="textfield", tags={mod="fp", on_gui_text_changed="machine_limit",
        on_gui_confirmed="machine_limit", width=textfield_width}, tooltip={"fp.expression_textfield"},
        text=machine.limit}
    textfield_limit.style.width = textfield_width
    modal_data.modal_elements["limit_textfield"] = textfield_limit

    local label_force = frame_limit.add{type="label", caption={"fp.info_label", {"fp.machine_force_limit"}},
        tooltip={"fp.machine_force_limit_tt"}, style="semibold_label"}
    label_force.style.left_margin = 12

    local state =  util.gui.switch.convert_to_state(machine.force_limit)
    local switch_force_limit = util.gui.switch.add_on_off(frame_limit, nil, {}, state)
    modal_data.modal_elements["force_limit_switch"] = switch_force_limit
end


local function handle_machine_choice(player, _, event)
    local machine = util.globals.modal_data(player).object  --[[@as Machine]]
    local elem_value = event.element.elem_value

    if not elem_value then
        event.element.elem_value = machine:elem_value()  -- reset the machine so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_machine", 1}})
        return  -- nothing changed
    end

    local new_machine_proto = prototyper.util.find("machines", elem_value.name, machine.proto.category)
    local new_quality_proto = prototyper.util.find("qualities", elem_value.quality, nil)

    -- Can't use Line:change_machine_to_proto() as that modifies the line, which we can't do
    machine.proto = new_machine_proto
    machine.quality_proto = new_quality_proto
    machine.parent.surface_compatibility = nil  -- reset since the machine changed
    machine:normalize_fuel(player)
    machine.module_set:normalize({compatibility=true, trim=true, effects=true})

    -- Make sure the line's beacon is removed if this machine no longer supports it
    if not machine:uses_effects() then machine.parent:set_beacon(nil) end

    refresh_fuel_frame(player)
    module_configurator.refresh_modules_flow(player, false)
    refresh_defaults_frame(player)
end

local function handle_fuel_choice(player, _, event)
    local machine = util.globals.modal_data(player).object
    local elem_value = event.element.elem_value

    if not elem_value then
        event.element.elem_value = machine.fuel.proto.name  -- reset the fuel so it can't be nil
        util.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_fuel", 1}})
        return  -- nothing changed
    end

    for category_name, _ in pairs(machine.proto.burner.categories) do
        local new_proto = prototyper.util.find("fuels", elem_value, category_name)
        if new_proto then machine.fuel.proto = new_proto; break end
    end

    refresh_defaults_frame(player)
end


local function open_machine_dialog(player, modal_data)
    modal_data.object = OBJECT_INDEX[modal_data.machine_id]  --[[@as Machine]]
    modal_data.line = modal_data.object.parent  --[[@as Line]]

    modal_data.machine_backup = modal_data.object:clone()
    modal_data.beacon_backup = modal_data.line.beacon and modal_data.line.beacon:clone()
    modal_data.module_set = modal_data.object.module_set

    local flow_content = modal_data.modal_elements.dialog_flow.add{type="flow", direction="horizontal"}
    flow_content.style.horizontal_spacing = 12

    local left_frame = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    left_frame.style.vertically_stretchable = true

    local subheader_caption = {"fp.machine_dialog_description", modal_data.line.recipe_proto.localised_name}
    local subheader = util.gui.add_modal_subheader(left_frame, subheader_caption, nil)

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}
    local button_defaults = subheader.add{type="button", caption={"fp.defaults_open"}, style="fp_button_transparent",
        tags={mod="fp", on_gui_click="toggle_defaults_panel"}}
    modal_data.modal_elements["defaults_button"] = button_defaults

    local left_flow = left_frame.add{type="flow", direction="vertical"}
    left_flow.style.padding = 12

    -- Machine & Fuel
    local flow_machine = left_flow.add{type="flow", direction="horizontal"}
    add_machine_frame(flow_machine, player, modal_data.line)
    add_fuel_frame(flow_machine, player)

    -- Limit
    if modal_data.line.parent.parent.matrix_free_items == nil then
        add_limit_frame(left_flow, player)
    end

    -- Modules
    module_configurator.add_modules_flow(left_flow, modal_data)
    module_configurator.refresh_modules_flow(player, false)

    local right_frame = flow_content.add{type="frame", direction="vertical", visible=false, style="inside_shallow_frame"}
    right_frame.style.padding = 12
    right_frame.style.vertically_stretchable = true
    modal_data.modal_elements["defaults_box"] = right_frame

    -- Defaults
    add_defaults_panel(right_frame, player)
end

local function close_machine_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local machine, line = modal_data.object, modal_data.line

    if action == "submit" then
        machine.module_set:normalize({sort=true})
        machine.limit = util.gui.parse_expression_field(modal_data.modal_elements.limit_textfield)
        machine.force_limit = util.gui.switch.convert_to_state(modal_data.modal_elements.force_limit_switch)

        set_defaults(player, machine)  -- set defaults according to the checkboxes

        solver.update(player)
        util.raise.refresh(player, "factory")

    else  -- action == "cancel"
        line.machine = modal_data.machine_backup
        line.machine.module_set:normalize({effects=true})
        line:set_beacon(modal_data.beacon_backup)
        -- Need to refresh so the buttons have the 'new' backup machine for further actions
        util.raise.refresh(player, "production_detail")
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_elem_changed = {
        {
            name = "choose_machine",
            handler = handle_machine_choice
        },
        {
            name = "choose_fuel",
            handler = handle_fuel_choice
        }
    },
    on_gui_text_changed = {
        {
            name = "machine_limit",
            handler = (function(_, _, event)
                util.gui.update_expression_field(event.element)
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "machine_limit",
            handler = (function(player, _, event)
                local confirmed = util.gui.confirm_expression_field(event.element)
                if confirmed then util.raise.close_dialog(player, "submit") end
            end)
        }
    },
    on_gui_click = {
        {
            name = "toggle_defaults_panel",
            handler = (function(player, _, _)
                local modal_elements = util.globals.modal_elements(player)  --[[@as table]]
                local defaults_frame = modal_elements.defaults_box
                defaults_frame.visible = not defaults_frame.visible
                modal_elements.defaults_button.caption = (defaults_frame.visible)
                    and {"fp.defaults_close"} or {"fp.defaults_open"}
            end)
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "toggle_checkbox_all",
            handler = refresh_defaults_frame
        }
    }
}

listeners.dialog = {
    dialog = "machine",
    metadata = (function(modal_data)
        return {
            caption = {"", {"fp.edit"}, " ", {"fp.pl_machine", 1}},
            create_content_frame = false,
            show_submit_button = true
        }
    end),
    open = open_machine_dialog,
    close = close_machine_dialog
}

return { listeners }
