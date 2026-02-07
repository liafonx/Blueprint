--------------------------------------------------
--------- Incredible mod configuration -----------
--------------------------------------------------

local copy_when_highlighted
-- Blueprint will stop copying texture when highlighted (by clicking on it)
-- Remove -- in front of next line to disable this behaviour
-- copy_when_highlighted = true

local inverted_colors = false
-- Blueprint shader normally inverts sprite colors
-- Remove -- in front of next line to disable this behaviour
-- inverted_colors = false

local use_debuff_logic = true
-- Dont change sprite for debuffed jokers

local use_brainstorm_logic = true
-- Normally blueprint copying brainstorm will show sprite of joker copied by brainstorm
-- Remove -- in front of next line to disable this behaviour
-- use_brainstorm_logic = false

-- Decreasing this value makes blueprinted sprites darker, going above 0.28 is not recommended.
local lightness_offset = 0.131

-- Change coloring mode
-- 1 = linear (1 or less)
-- 2 = exponent
-- 3 = parabola
-- 4 = sin
local coloring_mode = 1

-- Change pow for exponent and parabola modes
local power = 1



--------------------------------------------------

-- Blueprint border color (used as canvas background)
local canvas_background_color = {76 / 255, 108 / 255, 216 / 255, 0}


local function is_blueprint(card)
    return card and card.config and card.config.center and card.config.center.key == 'j_blueprint'
end

local function is_brainstorm(card)
    return card and card.config and card.config.center and card.config.center.key == 'j_brainstorm'
end

-- Check to show original blueprint texture when it's dragged or highlighted
local function show_texture(current_joker)
    return current_joker.facing == 'front' and not current_joker.states.drag.is and (copy_when_highlighted or not current_joker.highlighted)
end

Blueprint.is_blueprint = is_blueprint
Blueprint.is_brainstorm = is_brainstorm

-- Cache for scaled background images (avoids recreating for same h_scale)
local scaled_bg_cache = {}

-- Flag to track if shader uniforms have been initialized
local shader_uniforms_initialized = false

-- Flag to track if background images have been pre-loaded
local bg_images_preloaded = false

-- Flag to track if shader-processed atlases have been pre-loaded
local atlases_preloaded = false

-- Initialize constant shader uniforms (called once during init, not every frame)
function Blueprint.init_shader_uniforms()
    if shader_uniforms_initialized then return end

    -- Blueprint shader constants
    if G.SHADERS['blueprint_shader'] then
        G.SHADERS['blueprint_shader']:send('inverted', inverted_colors)
        G.SHADERS['blueprint_shader']:send('lightness_offset', lightness_offset)
        G.SHADERS['blueprint_shader']:send('mode', coloring_mode)
        G.SHADERS['blueprint_shader']:send('expo', power)
    end

    -- Brainstorm shader constants
    if G.SHADERS['brainstorm_shader'] then
        G.SHADERS['brainstorm_shader']:send('greyscale_weights', {0.299, 0.587, 0.114})
        G.SHADERS['brainstorm_shader']:send('blur_amount', 1)
        G.SHADERS['brainstorm_shader']:send('margin', {5, 5})
        G.SHADERS['brainstorm_shader']:send('blue_low', {60.0/255.0, 100.0/255.0, 200.0/255.0, 0.4})
        G.SHADERS['brainstorm_shader']:send('blue_high', {60.0/255.0, 100.0/255.0, 200.0/255.0, 0.8})
        G.SHADERS['brainstorm_shader']:send('red_low', {200.0/255.0, 60.0/255.0, 60.0/255.0, 0.4})
        G.SHADERS['brainstorm_shader']:send('red_high', {200.0/255.0, 60.0/255.0, 60.0/255.0, 0.8})
        G.SHADERS['brainstorm_shader']:send('blue_threshold', 0.75)
        G.SHADERS['brainstorm_shader']:send('red_threshold', 0.2)
    end

    shader_uniforms_initialized = true
end

-- Clear caches when graphics settings change
-- Note: Does NOT reset shader uniforms - they remain valid across graphics changes
function Blueprint.clear_caches()
    scaled_bg_cache = {}
    bg_images_preloaded = false
    atlases_preloaded = false
end

local function scaled_bg_image(h_scale)
    local cache_key = string.format("%.3f", h_scale)

    if scaled_bg_cache[cache_key] then
        return scaled_bg_cache[cache_key]
    end

    local base_image = G.ASSET_ATLAS["blue_brainstorm_single"].image
    local width, height = base_image:getDimensions()

    -- Use canvas directly as texture with GPU-side mipmaps (no CPU roundtrip)
    local canvas = love.graphics.newCanvas(width, height, {type = '2d', mipmaps = 'auto', dpiscale = base_image:getDPIScale()})
    love.graphics.push("all")

    love.graphics.setCanvas(canvas)
    love.graphics.scale(1, h_scale)
    love.graphics.draw(base_image)

    love.graphics.pop()

    canvas:generateMipmaps()
    scaled_bg_cache[cache_key] = canvas
    return canvas
end

-- Common h_scale values based on vanilla joker aspect ratios
local common_h_scales = {
    1.0,                    -- Normal jokers, Wee Joker (uniform scaling)
    1.0 / 1.7,              -- Half Joker: H/1.7 → h_scale ≈ 0.588
    1.0 / 1.2,              -- Photograph: H/1.2 → h_scale ≈ 0.833
    0.745,                  -- Square Joker: H=W (empirically measured)
}

-- Pre-load scaled background images for common joker aspect ratios
function Blueprint.preload_scaled_backgrounds()
    if bg_images_preloaded then return end
    if not G.ASSET_ATLAS or not G.ASSET_ATLAS["blue_brainstorm_single"] then return end

    for _, h_scale in ipairs(common_h_scales) do
        scaled_bg_image(h_scale)
    end
    bg_images_preloaded = true
end

local function process_texture_blueprint(image)
    Blueprint.init_shader_uniforms()

    local width, height = image:getDimensions()
    -- Use canvas directly as texture with GPU-side mipmaps (no CPU roundtrip)
    local canvas = love.graphics.newCanvas(width, height, {type = '2d', mipmaps = 'auto', dpiscale = image:getDPIScale()})

    love.graphics.push("all")

    love.graphics.setCanvas(canvas)
    love.graphics.clear(canvas_background_color)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(G.SHADERS['blueprint_shader'])

    -- Draw image with blueprint shader on new canvas
    love.graphics.draw(image)

    love.graphics.pop()

    canvas:generateMipmaps()
    return canvas
end

local function process_texture_brainstorm(image, px, py, floating_image, offset, h_scale)
    Blueprint.init_shader_uniforms()

    local width, height = image:getDimensions()
    -- Temporary canvas for compositing (no mipmaps needed)
    local temp_canvas = love.graphics.newCanvas(width, height, {type = '2d', dpiscale = image:getDPIScale()})

    love.graphics.push("all")
    love.graphics.setCanvas(temp_canvas)
    love.graphics.clear(canvas_background_color)
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.draw(image)
    if floating_image and offset then
        love.graphics.draw(floating_image, -offset.x, -offset.y)
    end

    love.graphics.pop()

    -- Final canvas with GPU-side mipmaps (no CPU roundtrip)
    local result_canvas = love.graphics.newCanvas(width, height, {type = '2d', mipmaps = 'auto', dpiscale = image:getDPIScale()})
    love.graphics.push("all")
    love.graphics.setCanvas(result_canvas)
    love.graphics.clear(canvas_background_color)
    love.graphics.setColor(1, 1, 1, 1)

    local bgImage = scaled_bg_image(h_scale)
    bgImage:setWrap("repeat", "repeat")
    local bgQuad = love.graphics.newQuad(0, 0, width, height, bgImage)
    love.graphics.setShader()
    love.graphics.draw(bgImage, bgQuad)

    -- Only send per-call uniforms (texture_size and card_size vary per joker)
    G.SHADERS['brainstorm_shader']:send('texture_size', {width, height})
    G.SHADERS['brainstorm_shader']:send('card_size', {px, py})

    love.graphics.setShader(G.SHADERS['brainstorm_shader'])
    love.graphics.draw(temp_canvas)

    love.graphics.pop()

    -- Release temporary canvas immediately to free GPU memory
    temp_canvas:release()

    result_canvas:generateMipmaps()
    return result_canvas
end


local function pre_blueprinted(a)
    local atlas = a.name or a.key
    local name = atlas.."_blueprinted"
    if G.ASSET_ATLAS[name] then
        return {
            old_name = atlas,
            new_name = name,
            atlas = G.ASSET_ATLAS[name],
        }
    else
        return {
            old_name = atlas,
            new_name = name,
            atlas = nil
        }
    end
end

local function pre_brainstormed(a, f, offset, h_scale)
    local atlas = a.name or a.key
    local floating_atlas = f and (f.name or f.key) or "nil"
    -- Round floating-point values to avoid cache misses from precision differences
    local offset_x = offset and string.format("%.1f", offset.x) or "nil"
    local offset_y = offset and string.format("%.1f", offset.y) or "nil"
    local h_scale_key = string.format("%.3f", h_scale)
    local name = string.format("%s_(%s_%s_%s_%s)_brainstormed", atlas, floating_atlas, offset_x, offset_y, h_scale_key)
    if G.ASSET_ATLAS[name] then
        return {
            old_name = atlas,
            old_floating_name = floating_atlas,
            new_name = name,
            atlas = G.ASSET_ATLAS[name],
        }
    else
        return {
            old_name = atlas,
            old_floating_name = floating_atlas,
            new_name = name,
            atlas = nil
        }
    end
end

local function blueprint_atlas(a)
    local blueprinted = pre_blueprinted(a)

    if not blueprinted.atlas then
        G.ASSET_ATLAS[blueprinted.new_name] = {}
        G.ASSET_ATLAS[blueprinted.new_name].blueprint = true
        G.ASSET_ATLAS[blueprinted.new_name].name = G.ASSET_ATLAS[blueprinted.old_name].name
        G.ASSET_ATLAS[blueprinted.new_name].type = G.ASSET_ATLAS[blueprinted.old_name].type
        G.ASSET_ATLAS[blueprinted.new_name].px = G.ASSET_ATLAS[blueprinted.old_name].px
        G.ASSET_ATLAS[blueprinted.new_name].py = G.ASSET_ATLAS[blueprinted.old_name].py
        G.ASSET_ATLAS[blueprinted.new_name].image = process_texture_blueprint(G.ASSET_ATLAS[blueprinted.old_name].image)
    end

    return G.ASSET_ATLAS[blueprinted.new_name]
end

local function brainstorm_atlas(a, f, offset, h_scale)
    local brainstormed = pre_brainstormed(a, f, offset, h_scale)

    if not brainstormed.atlas then
        G.ASSET_ATLAS[brainstormed.new_name] = {}
        G.ASSET_ATLAS[brainstormed.new_name].blueprint = true
        G.ASSET_ATLAS[brainstormed.new_name].name = brainstormed.new_name
        G.ASSET_ATLAS[brainstormed.new_name].type = G.ASSET_ATLAS[brainstormed.old_name].type
        G.ASSET_ATLAS[brainstormed.new_name].px = G.ASSET_ATLAS[brainstormed.old_name].px
        G.ASSET_ATLAS[brainstormed.new_name].py = G.ASSET_ATLAS[brainstormed.old_name].py
        G.ASSET_ATLAS[brainstormed.new_name].image = process_texture_brainstorm(G.ASSET_ATLAS[brainstormed.old_name].image, G.ASSET_ATLAS[brainstormed.new_name].px, G.ASSET_ATLAS[brainstormed.new_name].py, f and G.ASSET_ATLAS[brainstormed.old_floating_name].image or nil, offset, h_scale)
    end

    return G.ASSET_ATLAS[brainstormed.new_name]
end

-- Pre-cache shader-processed atlases for common joker atlas
function Blueprint.preload_atlases()
    if atlases_preloaded then return end
    if not G.ASSET_ATLAS or not G.ASSET_ATLAS["Joker"] then return end

    local joker_atlas = G.ASSET_ATLAS["Joker"]

    -- Pre-cache Blueprint version of Joker atlas
    local bp_name = "Joker_blueprinted"
    if not G.ASSET_ATLAS[bp_name] then
        G.ASSET_ATLAS[bp_name] = {
            blueprint = true,
            name = joker_atlas.name,
            type = joker_atlas.type,
            px = joker_atlas.px,
            py = joker_atlas.py,
            image = process_texture_blueprint(joker_atlas.image)
        }
    end

    -- Pre-cache Brainstorm versions for each common h_scale
    for _, h_scale in ipairs(common_h_scales) do
        local h_scale_key = string.format("%.3f", h_scale)
        local bs_name = string.format("Joker_(nil_nil_nil_%s)_brainstormed", h_scale_key)
        if not G.ASSET_ATLAS[bs_name] then
            G.ASSET_ATLAS[bs_name] = {
                blueprint = true,
                name = bs_name,
                type = joker_atlas.type,
                px = joker_atlas.px,
                py = joker_atlas.py,
                image = process_texture_brainstorm(joker_atlas.image, joker_atlas.px, joker_atlas.py, nil, nil, h_scale)
            }
        end
    end

    atlases_preloaded = true
end

local function equal_sprites(first, second)
    if not first and not second then
        return true
    end
    if not (first and second) then
        return false
    end

    -- Dynamically update sprite for animated jokers & multiple blueprint copies
    return first.atlas.name == second.atlas.name and first.sprite_pos.x == second.sprite_pos.x and first.sprite_pos.y == second.sprite_pos.y
end

-- Align card dimensions and calculate aspect ratio change
local function align_card(self, card, restore)
    if restore then
        -- Restore cached dimensions
        if self.blueprint_T then
            self.T.h = self.blueprint_T.h
            self.T.w = self.blueprint_T.w
            self.blueprint_T = nil
        end
        -- Restore cached scale.y on the restored original sprite
        if self.blueprint_scale_y then
            self.children.center.scale.y = self.blueprint_scale_y
            self.blueprint_scale_y = nil
        end
        return 1.0
    end

    -- Cache original dimensions and scale BEFORE any modifications
    if not self.blueprint_T then
        self.blueprint_T = {h = self.T.h, w = self.T.w}
        self.blueprint_scale_y = self.children.center.scale.y
    end

    -- Align to copied card's dimensions
    self.T.h = card.T.h
    self.T.w = card.T.w
    -- Note: scale.y is NOT set here - sprites get replaced, so caller handles it

    -- Calculate aspect ratio change, not raw height change
    -- This prevents double-scaling for uniformly-scaled jokers like Wee Joker
    -- Only scale the background pattern when aspect ratio actually changes (e.g., Cavendish)
    local original_aspect = self.blueprint_T.h / self.blueprint_T.w
    local new_aspect = card.T.h / card.T.w
    return new_aspect / original_aspect
end

-- Helper: Check if dimensions and scale match (for early return optimization)
local function dimensions_match(self, card)
    return self.T.h == card.T.h and self.T.w == card.T.w and
           self.children.center.scale.y == card.children.center.scale.y
end

-- Helper: Calculate floating sprite offset (used by brainstorm for texture baking)
local function get_floating_offset(card)
    if not card.children.floating_sprite then return nil end
    return {
        x = (card.children.floating_sprite.sprite_pos.x * card.children.floating_sprite.atlas.px) -
            (card.children.center.sprite_pos.x * card.children.center.atlas.px),
        y = (card.children.floating_sprite.sprite_pos.y * card.children.floating_sprite.atlas.py) -
            (card.children.center.sprite_pos.y * card.children.center.atlas.py)
    }
end

-- Helper: Calculate aspect ratio scale (for brainstorm background pattern)
local function get_aspect_scale(self, card)
    local original_h = self.blueprint_T and self.blueprint_T.h or self.T.h
    local original_w = self.blueprint_T and self.blueprint_T.w or self.T.w
    return (card.T.h / card.T.w) / (original_h / original_w)
end

-- Helper: Setup center sprite with common configuration
local function setup_center_sprite(self, card, atlas, sprite_pos)
    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, atlas, sprite_pos)
    self.children.center.states.hover = self.states.hover
    self.children.center.states.click = self.states.click
    self.children.center.states.drag = self.states.drag
    self.children.center.states.collide.can = false
    self.children.center:set_role({major = self, role_type = 'Glued', draw_major = self})
    self.children.center.scale.y = card.children.center.scale.y
end

-- Helper: Setup floating sprite (Blueprint only - Brainstorm bakes it into texture)
local function setup_floating_sprite(self, card, atlas)
    self.children.floating_sprite = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, atlas, card.children.floating_sprite.sprite_pos)
    self.children.floating_sprite.role.draw_major = self
    self.children.floating_sprite.states.hover.can = false
    self.children.floating_sprite.states.click.can = false
    self.children.floating_sprite.scale.y = card.children.floating_sprite.scale.y
end

-- Helper: Prepare for sprite update (cache, align, cleanup)
local function prepare_sprite_update(self, card)
    -- Cache original sprite BEFORE any modifications
    if not self.blueprint_sprite_copy then
        self.blueprint_sprite_copy = self.children.center
    end

    -- Align dimensions to copied card (caches original dimensions on first call)
    align_card(self, card)

    -- Remove floating sprite if exists
    if self.children.floating_sprite then
        self.children.floating_sprite:remove()
        self.children.floating_sprite = nil
    end

    -- Remove current sprite if we already cached the original
    if self.children.center ~= self.blueprint_sprite_copy then
        self.children.center:remove()
    end

    self.blueprint_copy_key = card.config.center.key
end

-- Blueprint: Color-shifted copy of joker sprite
local function blueprint_sprite(self, card)
    -- Early return: skip if atlas exists and everything matches
    if pre_blueprinted(card.children.center.atlas).atlas then
        if equal_sprites(self.children.center, card.children.center) and
           equal_sprites(self.children.floating_sprite, card.children.floating_sprite) and
           dimensions_match(self, card) then
            return
        end
    end

    prepare_sprite_update(self, card)
    setup_center_sprite(self, card, blueprint_atlas(card.children.center.atlas), card.children.center.sprite_pos)

    if card.children.floating_sprite then
        setup_floating_sprite(self, card, blueprint_atlas(card.children.floating_sprite.atlas))
    end
end

-- Brainstorm: Edge-detected copy with scaled background pattern
local function brainstorm_sprite(self, card)
    local offset = get_floating_offset(card)
    local h_scale = get_aspect_scale(self, card)
    local needed_atlas = card.children.floating_sprite
        and brainstorm_atlas(card.children.center.atlas, card.children.floating_sprite.atlas, offset, h_scale)
        or brainstorm_atlas(card.children.center.atlas, nil, nil, h_scale)

    -- Early return: skip if atlas and everything matches
    if self.children.center.atlas.name == needed_atlas.name and
       card.children.center.sprite_pos.x == self.children.center.sprite_pos.x and
       card.children.center.sprite_pos.y == self.children.center.sprite_pos.y and
       dimensions_match(self, card) then
        return
    end

    prepare_sprite_update(self, card)
    setup_center_sprite(self, card, needed_atlas, card.children.center.sprite_pos)
end

-- Unified restore function for both Blueprint and Brainstorm
local function restore_sprite(card)
    if not card.blueprint_sprite_copy then
        return
    end

    card.children.center:remove()
    card.children.center = card.blueprint_sprite_copy
    card.blueprint_sprite_copy = nil
    card.blueprint_copy_key = nil

    if card.children.floating_sprite then
        card.children.floating_sprite:remove()
        card.children.floating_sprite = nil
    end

    -- Restore dimensions and scale.y using unified align_card
    align_card(card, nil, true)
end

local card_draw = Card.draw
function Card:draw(...)
    if self.blueprint_sprite_copy and self.children.center.atlas.released then
        restore_sprite(self)
    end

    return card_draw(self, ...)
end

local function find_brainstormed_joker()
    local index = 1
    local max = #G.jokers.cards
    while index <= max do
        local current = G.jokers.cards[index]
        if not current or current.debuff then
            return nil
        end

        if is_blueprint(current) then
            index = index + 1
        elseif is_brainstorm(current) then
            -- Looped back into brainstorm
            return nil
        else
            return current
        end
    end

    return nil
end

local function find_blueprinted_joker(current_joker, previous_joker)
    if not previous_joker then
        return nil
    end

    if use_brainstorm_logic and is_brainstorm(previous_joker) then
        if use_debuff_logic and previous_joker.debuff then
            -- Brainstorm is debuffed, so it isn't copying leftmost
            return nil
        else
            previous_joker = find_brainstormed_joker()
        end
    end
    if not previous_joker then
        return nil
    end

    if use_debuff_logic and (current_joker.debuff or previous_joker.debuff) then
        return nil
    end

    local should_copy = previous_joker.config.center.blueprint_compat
    if should_copy then
        return previous_joker
    end

    return nil
end

local cardarea_align_cards = CardArea.align_cards
function CardArea:align_cards()
    local ret = cardarea_align_cards(self)

    if self == G.jokers then
        local brainstormed_joker = find_brainstormed_joker()

        local previous_joker = nil
        local current_joker = nil
        for i = #G.jokers.cards, 1, -1  do
            current_joker = G.jokers.cards[i]
            if Blueprint.SETTINGS.brainstorm and is_brainstorm(current_joker) then
                local should_copy = brainstormed_joker and not (use_debuff_logic and (current_joker.debuff or brainstormed_joker.debuff)) and brainstormed_joker.config.center.blueprint_compat
                if Blueprint.brainstorm_enabled and should_copy and show_texture(current_joker) then
                    brainstorm_sprite(current_joker, brainstormed_joker)
                else
                    restore_sprite(current_joker)
                end

            elseif Blueprint.SETTINGS.blueprint and is_blueprint(current_joker) then
                previous_joker = find_blueprinted_joker(current_joker, previous_joker)

                if previous_joker and show_texture(current_joker) then
                    blueprint_sprite(current_joker, previous_joker)
                else
                    restore_sprite(current_joker)
                end
            end
            if not (current_joker.config.center.key == 'j_blueprint') then
                previous_joker = current_joker
            end
        end

    end

    return ret
end

