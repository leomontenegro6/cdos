
class EntityLayerItem < Qt::GraphicsRectItem
  attr_reader :entities
  
  VILLAGER_EVENT_FLAG_TO_NAME = {
    0x0D => "George",
    0x2A => "Jacob",
    0x2D => "Abram",
    0x32 => "Laura",
    0x38 => "Eugen",
    0x3C => "Aeon",
    0x40 => "Marcel",
    0x47 => "Serge",
    0x4B => "Anna",
    0x4F => "Monica",
    0x53 => "Irina",
    0x57 => "Daniela",
  }
  
  AOS_BREAKABLE_WALL_INDEX_TO_DATA = {
    # Graphic index, palette index, frame index
    0x00 => [0, 0, 0],
    0x01 => [0, 1, 1],
    0x02 => [0, 2, 2],
    0x03 => [1, 0, 0],
    0x04 => [1, 1, 1],
    0x05 => [1, 2, 1],
    0x06 => [2, 0, 0],
    0x07 => [2, 1, 1],
    0x08 => [5, 4, 0],
    0x09 => [3, 0, 0],
    0x0A => [3, 0, 1],
    0x0B => [4, 4, 3],
    0x0C => [4, 5, 4],
    0x0D => [4, 3, 5],
    0x0E => [1, 2, 3],
    0x0F => [6, 3, 1],
    0x10 => [6, 3, 0],
    0x11 => [7, 6, 6],
    0x12 => [2, 0, 0],
  }
  
  AOS_NPC_EVENT_INDEX_TO_NAME_AND_FRAME = {
    0x1A => ["Hammer event actor", 9],
    0x1B => ["Mina event actor", 0],
    0x1C => ["Yoko event actor", 0xF],
  }
  
  DOS_DESTRUCTIBLE_INDEX_TO_DATA = {
    # Graphic index, animation index
    0x00 => [0x00, 0x00],
    0x01 => [0x01, 0x01],
    0x02 => [0x01, 0x04],
    0x03 => [0x01, 0x04],
    0x04 => [0x01, 0x00],
    0x05 => [0x01, 0x03],
    0x06 => [0x01, 0x05],
    0x07 => [0x02, 0x02],
    0x08 => [0x02, 0x04],
    0x09 => [0x03, 0x00],
    0x0A => [0x03, 0x01],
    0x0B => [0x08, 0x00],
    0x0C => [0x08, 0x01],
    0x0D => [0x00, 0x01],
    0x0E => [0x02, 0x00],
    0x0F => [0x02, 0x01],
    0x10 => [0x01, 0x06],
    0x11 => [0x01, 0x07],
    0x12 => [0x00, 0x02],
    0x13 => [0x02, 0x03],
    0x14 => [0x05, 0x00],
    0x15 => [0x06, 0x00],
    0x16 => [0x07, 0x00],
  }
  
  def initialize(entities, main_window, game, renderer)
    super()
    
    @main_window = main_window
    @game = game
    @fs = game.fs
    @renderer = renderer
    
    entities.each do |entity|
      add_graphics_item_for_entity(entity)
    end
  end
  
  def add_graphics_item_for_entity(entity)
    if GAME == "hod" && entity.is_enemy? && entity.subtype == 0x6A # Enemy spawner
      enemy_id = entity.var_b
      if ENEMY_IDS.include?(enemy_id)
        sprite_info = @game.enemy_dnas[enemy_id].extract_gfx_and_palette_and_sprite_from_init_ai
        add_sprite_item_for_entity(entity, sprite_info,
          BEST_SPRITE_FRAME_FOR_ENEMY[enemy_id],
          sprite_offset: BEST_SPRITE_OFFSET_FOR_ENEMY[enemy_id]
        )
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif entity.is_enemy? && ENEMY_IDS.include?(entity.subtype)
      enemy_id = entity.subtype
      sprite_info = @game.enemy_dnas[enemy_id].extract_gfx_and_palette_and_sprite_from_init_ai
      add_sprite_item_for_entity(entity, sprite_info,
        BEST_SPRITE_FRAME_FOR_ENEMY[enemy_id],
        sprite_offset: BEST_SPRITE_OFFSET_FOR_ENEMY[enemy_id])
    elsif GAME == "aos" && entity.is_special_object? && [0x0A, 0x0B].include?(entity.subtype) # Conditional enemy
      enemy_id = entity.var_a
      if ENEMY_IDS.include?(enemy_id)
        sprite_info = @game.enemy_dnas[enemy_id].extract_gfx_and_palette_and_sprite_from_init_ai
        add_sprite_item_for_entity(entity, sprite_info,
          BEST_SPRITE_FRAME_FOR_ENEMY[enemy_id],
          sprite_offset: BEST_SPRITE_OFFSET_FOR_ENEMY[enemy_id]
        )
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif GAME == "dos" && entity.is_special_object? && entity.subtype == 0x01 # Destructible
      if DOS_DESTRUCTIBLE_INDEX_TO_DATA.include?(entity.var_a)
        graphic_index, anim_index = DOS_DESTRUCTIBLE_INDEX_TO_DATA[entity.var_a]
        pointer = OTHER_SPRITES.find{|spr| spr[:desc] == "Destructibles %d" % graphic_index}[:pointer]
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(pointer, @fs, nil, {})
        frame_index = sprite_info.sprite.animations[anim_index].frame_delays[0].frame_index
        add_sprite_item_for_entity(entity, sprite_info, frame_index)
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif entity.is_villager? && VILLAGER_EVENT_FLAG_TO_NAME.keys.include?(entity.var_a)
      villager_name = VILLAGER_EVENT_FLAG_TO_NAME[entity.var_a]
      villager_info = OTHER_SPRITES.find{|other| other[:desc] == "#{villager_name} event actor"}
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(nil, @fs, nil, villager_info)
      if villager_name == "George"
        best_frame_index = 2
      else
        best_frame_index = 0
      end
      add_sprite_item_for_entity(entity, sprite_info, best_frame_index)
    elsif GAME == "ooe" && entity.is_special_object? && entity.subtype == 0x36 # Transition room hider
      hider_index = entity.var_a
      hider_info = OTHER_SPRITES.find{|other| other[:desc] == "Transition room hider %02X" % hider_index}
      if hider_info
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(nil, @fs, nil, hider_info)
        frames_to_use = (0...sprite_info.sprite.number_of_frames).to_a.reverse
        if [0, 1].include?(hider_index)
          # Don't use the water layer
          frames_to_use.delete(1)
        end
        add_sprite_item_for_entity(entity, sprite_info, frames_to_use)
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif GAME == "aos" && entity.is_pickup? && (5..8).include?(entity.subtype) # soul candle
      soul_candle_sprite = COMMON_SPRITE.merge(palette_offset: 4)
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(soul_candle_sprite[:pointer], @fs, soul_candle_sprite[:overlay], soul_candle_sprite)
      add_sprite_item_for_entity(entity, sprite_info, 0x6B)
    elsif GAME == "aos" && entity.is_special_object? && entity.subtype == 0x20 && AOS_NPC_EVENT_INDEX_TO_NAME_AND_FRAME.include?(entity.var_a) # NPC
      other_sprite_name, frame_index = AOS_NPC_EVENT_INDEX_TO_NAME_AND_FRAME[entity.var_a]
      other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == other_sprite_name}
      
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:pointer], @fs, nil, other_sprite)
      add_sprite_item_for_entity(entity, sprite_info, frame_index)
    elsif GAME == "aos" && entity.is_special_object? && [8, 9].include?(entity.subtype) # Breakable wall
      if AOS_BREAKABLE_WALL_INDEX_TO_DATA.include?(entity.var_a)
        graphic_index, palette_index, frame_index = AOS_BREAKABLE_WALL_INDEX_TO_DATA[entity.var_a]
        breakable_wall_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Breakable wall graphics %d" % graphic_index}
        breakable_wall_sprite = breakable_wall_sprite.merge(palette_offset: palette_index)
      else
        breakable_wall_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Breakable wall graphics 0"}
        frame_index = 0
      end
      
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(breakable_wall_sprite[:pointer], @fs, nil, breakable_wall_sprite)
      add_sprite_item_for_entity(entity, sprite_info, frame_index)
    elsif GAME == "aos" && entity.is_special_object? && entity.subtype == 0xE # Destructible
      if entity.var_a <= 0xD
        graphic_index = entity.var_a
        destructible_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Destructible %X" % graphic_index}
        
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(
          destructible_sprite[:pointer],
          @fs, nil,
          destructible_sprite
        )
        frame_index = 0
        add_sprite_item_for_entity(entity, sprite_info, frame_index)
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif GAME == "aos" && entity.is_special_object? && [0x29, 0x2A].include?(entity.subtype) && [2, 3].include?(entity.var_b) # Moving platform that doesn't use the normal sprite
      case entity.var_b
      when 2
        other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Wet rock moving platform"}
      when 3
        other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Clock moving platform"}
      end
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:pointer], @fs, nil, other_sprite)
      add_sprite_item_for_entity(entity, sprite_info, 0)
    elsif GAME == "hod" && entity.is_pickup? && entity.subtype == 9 && (0..1).include?(entity.var_b) # max up
      chunky_image = @renderer.render_icon(0xB + entity.var_b, 1)
      
      graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
      graphics_item.setOffset(-8, -16)
      graphics_item.setPos(entity.x_pos, entity.y_pos)
      graphics_item.setParentItem(self)
    elsif entity.is_glyph_statue?
      pointer = OTHER_SPRITES.find{|spr| spr[:desc] == "Glyph statue"}[:pointer]
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(pointer, @fs, nil, {})
      add_sprite_item_for_entity(entity, sprite_info, 0)
    elsif entity.is_item_chest?
      item_global_id = entity.var_a - 1
      item = @game.items[item_global_id]
      if item
        item_icon_chunky_image = @renderer.render_icon_by_item(item)
        
        special_object_id = entity.subtype
        sprite_info = SpecialObjectType.new(special_object_id, @fs).extract_gfx_and_palette_and_sprite_from_create_code
        add_sprite_item_for_entity(entity, sprite_info,
          BEST_SPRITE_FRAME_FOR_SPECIAL_OBJECT[special_object_id],
          sprite_offset: BEST_SPRITE_OFFSET_FOR_SPECIAL_OBJECT[special_object_id],
          item_icon_image: item_icon_chunky_image
        )
      else
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
      end
    elsif entity.is_portrait? && (0..9).include?(entity.var_a)
      if entity.subtype == 0x75 # Portrait to the Throne Room
        other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Portrait painting 2"}
        frame_to_render = 0
        palette_offest = 0
        art_offset_x = 0
        art_offset_y = 0
      else
        other_sprite = case entity.var_a
        when 1, 3, 5, 7
          OTHER_SPRITES.find{|spr| spr[:desc] == "Portrait painting 0"}
        when 2, 4, 6, 8
          OTHER_SPRITES.find{|spr| spr[:desc] == "Portrait painting 1"}
        when 0, 9
          OTHER_SPRITES.find{|spr| spr[:desc] == "Portrait painting 3"}
        end
        frame_to_render = [0, 0, 0, 1, 1, 3, 2, 2, 3, 1][entity.var_a]
        palette_offset = case entity.var_a
        when 5 # Nation of Fools hardcodes the palette offset instead of having the sprite set a palette index normally.
          1
        else
          0
        end
        art_offset_x = 24
        art_offset_y = 24
      end
      
      reused_info = other_sprite.merge({palette_offset: palette_offset})
      painting_sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:pointer], @fs, nil, reused_info)
      sprite_filename = @renderer.ensure_sprite_exists("cache/#{GAME}/sprites/", painting_sprite_info, frame_to_render)
      portrait_art_image = ChunkyPNG::Image.from_file(sprite_filename)
      
      special_object_id = entity.subtype
      sprite_info = SpecialObjectType.new(special_object_id, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      add_sprite_item_for_entity(entity, sprite_info,
        BEST_SPRITE_FRAME_FOR_SPECIAL_OBJECT[special_object_id],
        sprite_offset: BEST_SPRITE_OFFSET_FOR_SPECIAL_OBJECT[special_object_id],
        portrait_art: [portrait_art_image, art_offset_x, art_offset_y])
    elsif GAME == "por" && entity.is_special_object? && [0x77, 0x8A].include?(entity.subtype)
      studio_portrait_frame_sprite_info = SpecialObjectType.new(0x5F, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      studio_portrait_art_sprite_info = SpecialObjectType.new(entity.subtype, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      
      frame_to_render = 0
      sprite_filename = @renderer.ensure_sprite_exists("cache/#{GAME}/sprites/", studio_portrait_art_sprite_info, frame_to_render)
      studio_portrait_art_image = ChunkyPNG::Image.from_file(sprite_filename)
      art_offset_x = 208
      art_offset_y = 40
      
      frame_num_for_studio_portrait_frame = 0x18
      special_object_id = entity.subtype
      sprite_info = SpecialObjectType.new(special_object_id, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      add_sprite_item_for_entity(entity, studio_portrait_frame_sprite_info,
        frame_num_for_studio_portrait_frame,
        sprite_offset: BEST_SPRITE_OFFSET_FOR_SPECIAL_OBJECT[special_object_id],
        portrait_art: [studio_portrait_art_image, art_offset_x, art_offset_y])
    elsif GAME == "por" && entity.is_special_object? && entity.subtype == 0x3A
      # Objects from the Behemoth chase room.
      special_object_id = entity.subtype
      sprite_info = SpecialObjectType.new(special_object_id, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      
      frame_index = entity.var_a
      add_sprite_item_for_entity(entity, sprite_info, frame_index)
    elsif entity.is_special_object? && SPECIAL_OBJECT_IDS.include?(entity.subtype)
      special_object_id = entity.subtype
      sprite_info = SpecialObjectType.new(special_object_id, @fs).extract_gfx_and_palette_and_sprite_from_create_code
      add_sprite_item_for_entity(entity, sprite_info,
        BEST_SPRITE_FRAME_FOR_SPECIAL_OBJECT[special_object_id],
        sprite_offset: BEST_SPRITE_OFFSET_FOR_SPECIAL_OBJECT[special_object_id])
    elsif entity.is_candle?
      if GAME == "hod"
        sprite_info, candle_frame = entity.get_hod_candle_sprite_info()
        if sprite_info.nil?
          graphics_item = EntityRectItem.new(entity, @main_window)
          graphics_item.setParentItem(self)
        else
          add_sprite_item_for_entity(entity, sprite_info, candle_frame)
        end
      elsif GAME == "aos"
        if entity.var_a <= 0xF
          gfx_page = GfxWrapper.new(CANDLE_SPRITE[:gfx_files][0], @fs)
          palette = @renderer.generate_palettes(CANDLE_SPRITE[:palette], 16)[3]
          x = (entity.var_a % 2) * 64
          y = (entity.var_a / 2) * 16
          width = 16
          height = 16
          chunky_image = @renderer.render_gfx_1_dimensional_mode(gfx_page, palette)
          chunky_image = chunky_image.crop(x, y, width, height)
          
          graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
          graphics_item.setOffset(-8, -8)
          graphics_item.setPos(entity.x_pos, entity.y_pos)
          graphics_item.setParentItem(self)
        else
          graphics_item = EntityRectItem.new(entity, @main_window)
          graphics_item.setParentItem(self)
        end
      else
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(CANDLE_SPRITE[:pointer], @fs, CANDLE_SPRITE[:overlay], CANDLE_SPRITE)
        add_sprite_item_for_entity(entity, sprite_info, CANDLE_FRAME_IN_COMMON_SPRITE)
      end
    elsif entity.is_magic_seal?
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(COMMON_SPRITE[:pointer], @fs, COMMON_SPRITE[:overlay], COMMON_SPRITE)
      add_sprite_item_for_entity(entity, sprite_info, 0xCE)
    elsif entity.is_item?
      if GAME == "ooe"
        item_global_id = entity.var_b - 1
        item = @game.items[item_global_id]
      else
        item_type = entity.subtype
        item_id = entity.var_b
        item = @game.get_item_by_type_and_index(item_type, item_id)
      end
      
      if item
        chunky_image = @renderer.render_icon_by_item(item)
      end
      
      if chunky_image.nil?
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
        return
      end
      
      graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
      graphics_item.setOffset(-8, -16)
      graphics_item.setPos(entity.x_pos, entity.y_pos)
      graphics_item.setParentItem(self)
    elsif entity.is_heart?
      case GAME
      when "dos"
        frame_id = 0xDA
      when "por", "ooe"
        frame_id = 0x11D
      end
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(COMMON_SPRITE[:pointer], @fs, COMMON_SPRITE[:overlay], COMMON_SPRITE)
      add_sprite_item_for_entity(entity, sprite_info, frame_id)
    elsif entity.is_money_bag?
      sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(MONEY_SPRITE[:pointer], @fs, MONEY_SPRITE[:overlay], MONEY_SPRITE)
      add_sprite_item_for_entity(entity, sprite_info, MONEY_FRAME_IN_COMMON_SPRITE)
    elsif entity.is_skill? && GAME == "por"
      case entity.var_b
      when 0x00..0x26
        chunky_image = @renderer.render_icon(64 + 0, 0)
      when 0x27..0x50
        chunky_image = @renderer.render_icon(64 + 2, 2)
      when 0x51..0x5B
        chunky_image = @renderer.render_icon(64 + 1, 0)
      else
        chunky_image = @renderer.render_icon(64 + 3, 0)
      end
      
      if chunky_image.nil?
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
        return
      end
      
      graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
      graphics_item.setOffset(-8, -16)
      graphics_item.setPos(entity.x_pos, entity.y_pos)
      graphics_item.setParentItem(self)
    elsif entity.is_glyph? && entity.var_b > 0
      glyph_id = entity.var_b - 1
      item = @game.items[glyph_id]
      
      if item
        icon_index = item["Icon"]
        if glyph_id <= 0x36
          palette_index = 2
        else
          palette_index = 1
        end
        chunky_image = @renderer.render_icon(icon_index, palette_index, mode=:glyph)
      end
      
      if chunky_image.nil?
        graphics_item = EntityRectItem.new(entity, @main_window)
        graphics_item.setParentItem(self)
        return
      end
      
      graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
      graphics_item.setOffset(-16, -16)
      graphics_item.setPos(entity.x_pos, entity.y_pos)
      graphics_item.setParentItem(self)
    else
      graphics_item = EntityRectItem.new(entity, @main_window)
      graphics_item.setParentItem(self)
    end
  rescue StandardError => e
    if DEBUG
      unless e.message =~ /has no sprite/
        Qt::MessageBox.warning(@main_window,
          "Sprite error",
          "#{e.message}\n\n#{e.backtrace.join("\n")}"
        )
      end
    end
    graphics_item = EntityRectItem.new(entity, @main_window)
    graphics_item.setParentItem(self)
  end
  
  def add_sprite_item_for_entity(entity, sprite_info, frames_to_render, sprite_offset: nil, item_icon_image: nil, portrait_art: nil)
    if frames_to_render == -1
      # Don't show this entity's sprite in the editor.
      graphics_item = EntityRectItem.new(entity, @main_window)
      graphics_item.setParentItem(self)
      return
    end
    
    sprite = sprite_info.sprite
    
    if frames_to_render.nil?
      frames_to_render = [0]
    elsif frames_to_render.is_a?(Integer)
      frames_to_render = [frames_to_render]
    end
    
    chunky_image = ChunkyPNG::Image.new(sprite.full_width, sprite.full_height, ChunkyPNG::Color::TRANSPARENT)
    frame_min_xs = []
    frame_min_ys = []
    frame_max_xs = []
    frame_max_ys = []
    frames_to_render.each do |frame_to_render|
      frame = sprite.frames[frame_to_render]
      if frame.nil?
        frame_to_render = 0
      end
      
      sprite_filename = @renderer.ensure_sprite_exists("cache/#{GAME}/sprites/", sprite_info, frame_to_render)
      chunky_frame = ChunkyPNG::Image.from_file(sprite_filename)
      
      chunky_image.compose!(chunky_frame, 0, 0)
      
      frame_min_xs << frame.min_x
      frame_min_ys << frame.min_y
      frame_max_xs << frame.max_x
      frame_max_ys << frame.max_y
    end
    
    crop_left_x   = frame_min_xs.min - sprite.min_x
    crop_top_y    = frame_min_ys.min - sprite.min_y
    crop_right_x  = frame_max_xs.max - sprite.min_x
    crop_bottom_y = frame_max_ys.max - sprite.min_y
    
    if item_icon_image
      chunky_image.compose!(item_icon_image, 6, 0)
      crop_top_y = 0
    end
    
    if portrait_art
      portrait_art_image, x_offset, y_offset = portrait_art
      chunky_image.compose!(portrait_art_image, x_offset, y_offset)
    end
    
    # Crop the image.
    # This is so the giant blank space around the image doesn't count as clickable.
    crop_x_offset = crop_left_x
    crop_y_offset = crop_top_y
    crop_width    = crop_right_x-crop_left_x
    crop_height   = crop_bottom_y-crop_top_y
    chunky_image.crop!(
      crop_x_offset,
      crop_y_offset,
      crop_width,
      crop_height,
    )
    
    qt_item_offset_x = sprite.min_x
    qt_item_offset_y = sprite.min_y
    qt_item_offset_x += crop_x_offset
    qt_item_offset_y += crop_y_offset
    
    graphics_item = EntityChunkyItem.new(chunky_image, entity, @main_window)
    
    if sprite_offset
      qt_item_offset_x += sprite_offset[:x] || 0
      qt_item_offset_y += sprite_offset[:y] || 0
    end
    graphics_item.setOffset(qt_item_offset_x, qt_item_offset_y)
    graphics_item.setPos(entity.x_pos, entity.y_pos)
    graphics_item.setParentItem(self)
  end
  
  def inspect; to_s; end
end
