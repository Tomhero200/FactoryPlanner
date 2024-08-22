local generator = require("backend.handlers.generator")

prototyper = {
    util = {},
    defaults = {}
}

-- The purpose of the prototyper is to recreate the global tables containing all relevant data types.
-- It also handles some other things related to prototypes, such as updating preferred ones, etc.
-- Its purpose is to not lose any data, so if a dataset of a factory doesn't exist anymore
-- in the newly loaded global tables, it saves the name in string-form instead and makes the
-- concerned factory-dataset invalid. This accomplishes that invalid data is only permanently
-- removed when the user tells the factory to repair itself, giving him a chance to re-add the
-- missing mods. It is also a better separation of responsibilities and avoids some redundant code.

-- Load order is important here: machines->recipes->items->fuels
-- The boolean indicates whether this prototype has categories or not
---@type { [DataType]: boolean }
prototyper.data_types = {machines = true, recipes = false, items = true, fuels = true,
                         belts = false, wagons = true, modules = true, beacons = false,
                         locations = false, qualities = false}

---@alias DataType "machines" | "recipes" | "items" | "fuels" | "belts" | "wagons" | "modules" | "beacons" | "locations" | "qualities"

---@alias NamedPrototypes<T> { [string]: T }
---@alias NamedPrototypesWithCategory<T> { [string]: { name: string, members: { [string]: T } } } }
---@alias NamedCategory { name: string, members: { [string]: table } }
---@alias AnyNamedPrototypes NamedPrototypes | NamedPrototypesWithCategory

---@alias IndexedPrototypes<T> { [integer]: T }
---@alias IndexedPrototypesWithCategory<T> { [integer]: { id: integer, name: string, members: { [integer]: T } } }
---@alias IndexedCategory { id: integer, name: string, members: { [integer]: table } }
---@alias AnyIndexedPrototypes IndexedPrototypes | IndexedPrototypesWithCategory

---@class PrototypeLists: { [DataType]: table }
---@field machines IndexedPrototypesWithCategory<FPMachinePrototype>
---@field recipes IndexedPrototypes<FPRecipePrototype>
---@field items IndexedPrototypesWithCategory<FPItemPrototype>
---@field fuels IndexedPrototypesWithCategory<FPFuelPrototype>
---@field belts IndexedPrototypes<FPBeltPrototype>
---@field wagons IndexedPrototypesWithCategory<FPWagonPrototype>
---@field modules IndexedPrototypesWithCategory<FPModulePrototype>
---@field beacons IndexedPrototypes<FPBeaconPrototype>
---@field locations IndexedPrototypes<FPLocationPrototype>
---@field qualities IndexedPrototypes<FPQualityPrototype>

---@alias SortingFunction fun(a: table, b: table): boolean


-- Converts given prototype list to use ids as keys, and sorts it if desired
---@param data_type DataType
---@param prototype_sorting_function SortingFunction
---@return AnyIndexedPrototypes
local function convert_and_sort(data_type, prototype_sorting_function)
    local final_list = {}

    ---@param list AnyNamedPrototypes[]
    ---@param sorting_function SortingFunction
    ---@param category_id integer?
    ---@return AnyIndexedPrototypes
    local function apply(list, sorting_function, category_id)
        local new_list = {}  ---@type (IndexedPrototypes | IndexedCategory)[]

        for _, member in pairs(list) do table.insert(new_list, member) end
        if sorting_function then table.sort(new_list, sorting_function) end

        for id, member in pairs(new_list) do
            member.id = id
            member.category_id = category_id  -- can be nil
            member.data_type = data_type
        end

        return new_list
    end

    ---@param a NamedCategory
    ---@param b NamedCategory
    ---@return boolean
    local function category_sorting_function(a, b)
        if a.name < b.name then return true
        elseif a.name > b.name then return false end
        return false
    end

    if prototyper.data_types[data_type] == false then
        final_list = apply(global.prototypes[data_type], prototype_sorting_function, nil)
        ---@cast final_list IndexedPrototypes<FPPrototype>
    else
        final_list = apply(global.prototypes[data_type], category_sorting_function, nil)
        ---@cast final_list IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        for id, category in pairs(final_list) do
            category.members = apply(category.members, prototype_sorting_function, id)
        end
    end

    return final_list
end


---@alias ProductivityRecipes { [string]: boolean }

---@return ProductivityRecipes
local function generate_productivity_recipes()
    local productivity_recipes = {}
    for _, technology in pairs(game.technology_prototypes) do
        for _, effect in pairs(technology.effects or {}) do
            if effect.type == "mining-drill-productivity-bonus" then
                productivity_recipes["custom-mining"] = true
            elseif effect.type == "change-recipe-productivity" then
                productivity_recipes[effect.recipe] = true
            end
        end
    end
    return productivity_recipes
end


function prototyper.build()
    for data_type, _ in pairs(prototyper.data_types) do
        ---@type AnyNamedPrototypes
        global.prototypes[data_type] = generator[data_type].generate()
    end

    -- Second pass to do some things that can't be done in the first pass due to the strict sequencing
    for data_type, _ in pairs(prototyper.data_types) do
        local second_pass = generator[data_type].second_pass  ---@type fun(prototypes: NamedPrototypes)
        if second_pass ~= nil then second_pass(global.prototypes[data_type]) end
    end

    -- Finish up generation by converting lists to use ids as keys, and sort if desired
    for data_type, _ in pairs(prototyper.data_types) do
        local sorting_function = generator[data_type].sorting_function  ---@type SortingFunction
        global.prototypes[data_type] = convert_and_sort(data_type, sorting_function)  ---@type AnyIndexedPrototypes
    end

    global.productivity_recipes = generate_productivity_recipes()
end


-- ** UTIL **
---@param data_type DataType
---@param prototype (integer | string)?
---@param category (integer | string)?
---@return (AnyFPPrototype | NamedCategory)?
function prototyper.util.find(data_type, prototype, category)
    local prototypes, prototype_map = global.prototypes[data_type], PROTOTYPE_MAPS[data_type]

    if util.xor((category ~= nil), (prototype ~= nil)) then  -- either category or prototype provided
        local identifier = category or prototype
        local relevant_map = (type(identifier) == "string") and prototype_map or prototypes
        return relevant_map[identifier]  -- can be nil

    else  -- category and prototype provided
        local category_map = (type(category) == "string") and prototype_map or prototypes
        local category_table = category_map[category]  ---@type MappedCategory
        if category_table == nil then return nil end

        if type(prototype) == type(category) then
            return category_table.members[prototype]  -- can be nil
        else  -- If types don't match, we need to use the opposite map for the category
            if type(prototype) == "string" then
                return prototype_map[category_table.name].members[prototype]  -- can be nil
            else
                return prototypes[category_table.id].members[prototype]  -- can be nil
            end
        end
    end
end


---@class FPPackedPrototype
---@field name string
---@field category string
---@field data_type DataType
---@field simplified boolean

---@alias CategoryDesignation ("category" | "type")

-- Returns a new table that only contains the given prototypes' identifiers
---@param prototype AnyFPPrototype
---@param category_designation CategoryDesignation?
---@return FPPackedPrototype?
function prototyper.util.simplify_prototype(prototype, category_designation)
    if not prototype then return nil end
    return { name = prototype.name, category = prototype[category_designation],
        data_type = prototype.data_type, simplified = true }
end

---@param prototypes FPPrototype[]
---@param category_designation CategoryDesignation?
---@return FPPackedPrototype[]?
function prototyper.util.simplify_prototypes(prototypes, category_designation)
    if not prototypes then return nil end

    local simplified_prototypes = {}
    for index, proto in pairs(prototypes) do
        simplified_prototypes[index] = prototyper.util.simplify_prototype(proto, category_designation)
    end
    return simplified_prototypes
end


---@alias AnyPrototype (AnyFPPrototype | FPPackedPrototype)

-- Validates given object with prototype, which includes trying to find the correct
-- new reference for its prototype, if able. Returns valid-status at the end.
---@param prototype AnyPrototype
---@param category_designation CategoryDesignation?
---@return AnyPrototype
function prototyper.util.validate_prototype_object(prototype, category_designation)
    local updated_proto = prototype

    if prototype.simplified then  -- try to unsimplify, otherwise it stays that way
        ---@cast prototype FPPackedPrototype
        local new_proto = prototyper.util.find(prototype.data_type, prototype.name, prototype.category)
        if new_proto then updated_proto = new_proto end
    else
        ---@cast prototype AnyFPPrototype
        local category = prototype[category_designation]  ---@type string
        local new_proto = prototyper.util.find(prototype.data_type, prototype.name, category)
        updated_proto = new_proto or prototyper.util.simplify_prototype(prototype, category)
    end

    return updated_proto
end

---@param prototypes AnyPrototype[]?
---@param category_designation CategoryDesignation
---@return AnyPrototype[]?
---@return boolean valid
function prototyper.util.validate_prototype_objects(prototypes, category_designation)
    if not prototypes then return nil, true end

    local validated_prototypes, valid = {}, true
    for index, proto in pairs(prototypes) do
        validated_prototypes[index] = prototyper.util.validate_prototype_object(proto, category_designation)
        valid = (not validated_prototypes[index].simplified) and valid
    end
    return validated_prototypes, valid
end


-- Build the necessary RawDictionaries for translation
function prototyper.util.build_translation_dictionaries()
    for _, item_category in ipairs(global.prototypes.items) do
        translator.new(item_category.name)
        for _, proto in pairs(item_category.members) do
            translator.add(item_category.name, proto.name, proto.localised_name)
        end
    end

    translator.new("recipe")
    for _, proto in pairs(global.prototypes.recipes) do
        translator.add("recipe", proto.name, proto.localised_name)
    end
end

-- Migrates the prototypes for default beacons and modules
---@param player_table PlayerTable
function prototyper.util.migrate_mb_defaults(player_table)
    local mb_defaults = player_table.preferences.mb_defaults
    local find = prototyper.util.find

    local machine = mb_defaults.machine
    if machine then
        mb_defaults.machine = find("modules", machine.name, machine.category)  --[[@as FPModulePrototype ]]
    end

    local second = mb_defaults.machine_secondary
    if second then
        mb_defaults.machine_secondary = find("modules", second.name, second.category)  --[[@as FPModulePrototype ]]
    end

    local beacon = mb_defaults.beacon
    if beacon then
        mb_defaults.beacon = find("modules", beacon.name, nil)  --[[@as FPModulePrototype ]]
    end
end


-- ** DEFAULTS **
---@class DefaultPrototype
---@field proto AnyFPPrototype
---@field beacon_amount integer?

---@class DefaultData
---@field prototype (integer | string)?
---@field beacon_amount integer?

---@alias AnyPrototypeDefault DefaultPrototype | { [integer]: DefaultPrototype }

-- Returns the default prototype for the given type, incorporating the category, if given
---@param player LuaPlayer
---@param data_type DataType
---@param category (integer | string)?
---@return DefaultPrototype
function prototyper.defaults.get(player, data_type, category)
    local default = util.globals.preferences(player)["default_" .. data_type]
    local category_table = prototyper.util.find(data_type, nil, category)
    return (category_table == nil) and default or default[category_table.id]
end

-- Sets the default for the given type, incorporating the category if given
---@param player LuaPlayer
---@param data_type DataType
---@param data DefaultData
---@param category (integer | string)?
function prototyper.defaults.set(player, data_type, data, category)
    local default = prototyper.defaults.get(player, data_type, category)

    if data.prototype then
        default.proto = prototyper.util.find(data_type, data.prototype, category)  --[[@as AnyFPPrototype]]
    end
    if data.beacon_amount then
        default.beacon_amount = data.beacon_amount
    end
end

-- Sets the default prototypem for all categories of the given type
---@param player LuaPlayer
---@param data_type DataType
---@param data DefaultData
function prototyper.defaults.set_all(player, data_type, data)
    -- Doesn't make sense for prototypes without categories, just use .set() instead
    if prototyper.data_types[data_type] == false then return end

    local defaults = util.globals.preferences(player)["default_" .. data_type]
    for _, category_data in pairs(global.prototypes[data_type]) do
        if table_size(category_data.members) > 1 then  -- don't change single-member categories
            local matched_prototype = prototyper.util.find(data_type, data.prototype, category_data.id)
            if matched_prototype then
                defaults[category_data.id].proto = matched_prototype
                defaults[category_data.id].beacon_amount = data.beacon_amount
            end
        end
    end
end

-- Returns the fallback default for the given type of prototype
---@param data_type DataType
---@return AnyPrototypeDefault
function prototyper.defaults.get_fallback(data_type)
    local prototypes = global.prototypes[data_type]  ---@type AnyIndexedPrototypes

    local fallback = nil
    if prototyper.data_types[data_type] == false then
        ---@cast prototypes IndexedPrototypes<FPPrototype>
        fallback = {proto=prototypes[1], beacon_amount=nil}
    else
        ---@cast prototypes IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        fallback = {}
        for _, category in pairs(prototypes) do
            fallback[category.id] = {proto=category.members[1], beacon_amount=nil}
        end
    end

    return fallback
end

-- Kinda unclean that I have to do this, but it's better than storing it elsewhere
local category_designations = {machines="category", items="type",
    fuels="combined_category", wagons="category", modules="category"}

-- Migrates the default prototype preferences, trying to preserve the users choices
-- When this is called, the loader cache will already exist
---@param player_table PlayerTable
function prototyper.defaults.migrate(player_table)
    local preferences = player_table.preferences

    for data_type, has_categories in pairs(prototyper.data_types) do
        local fallback = prototyper.defaults.get_fallback(data_type)
        local default = preferences["default_" .. data_type]
        if default == nil then goto skip end

        if not has_categories then
            -- Use the same prototype if an equivalent can be found, use fallback otherwise
            local equivalent_proto = prototyper.util.find(data_type, default.proto.name, nil)
            preferences["default_" .. data_type].proto = equivalent_proto or fallback.proto
        else
            local default_map = {}
            for _, default_data in pairs(default) do
                local category_name = default_data.proto[category_designations[data_type]]  ---@type string
                default_map[category_name] = default_data
            end

            local new_defaults = {}
            for _, category in pairs(global.prototypes[data_type]) do
                local previous_category = default_map[category.name]
                if previous_category then  -- category existed previously
                    local proto_name = previous_category.proto.name
                    new_defaults[category.id] = {
                        proto = prototyper.util.find(data_type, proto_name, category.name),
                        beacon_amount = previous_category.beacon_amount
                    }
                end
                new_defaults[category.id] = new_defaults[category.id] or fallback[category.id]
            end

            preferences["default_" .. data_type] = new_defaults
        end
        ::skip::
    end
end
