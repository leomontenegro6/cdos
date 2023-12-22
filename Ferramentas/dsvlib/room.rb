
class Room
  class RoomReadError < StandardError ; end
  class WriteError < StandardError ; end
  
  attr_reader :room_metadata_ram_pointer,
              :area,
              :sector,
              :layers,
              :layer_list_ram_pointer,
              :gfx_list_pointer,
              :palette_wrapper_pointer,
              :entity_list_ram_pointer,
              :door_list_ram_pointer,
              :gfx_pages,
              :palette_pages,
              :area_index,
              :sector_index,
              :room_index,
              :glitch_doors,
              :fs,
              :game
  attr_accessor :lcd_control,
                :state_swap_event_flag,
                :alternate_room_state_pointer,
                :alternate_room_state,
                :layer_list_ram_pointer,
                :gfx_list_pointer,
                :palette_wrapper_pointer,
                :entity_list_ram_pointer,
                :door_list_ram_pointer,
                :room_xpos_on_map,
                :room_ypos_on_map,
                :palette_page_index,
                :color_effects,
                :entities,
                :doors,
                :entity_gfx_list_pointer,
                :entity_gfx_list,
                :special_effect,
                :palette_shift_type,
                :is_castle_b,
                :has_breakable_wall,
                :number_of_doors,
                :original_number_of_entities,
                :original_number_of_doors

  def initialize(sector, room_metadata_ram_pointer, area_index, sector_index, room_index, game)
    @room_metadata_ram_pointer = room_metadata_ram_pointer
    @area = sector.area
    @sector = sector
    @area_index = area_index
    @sector_index = sector_index
    @room_index = room_index
    @fs = game.fs
    @game = game
  end
  
  def read_from_rom
    if GAME == "aos"
      room_metadata = fs.read(room_metadata_ram_pointer, 36).unpack("vvVVVVVVVV")
      @lcd_control = room_metadata[0]
      @state_swap_event_flag = room_metadata[1]
      @alternate_room_state_pointer = room_metadata[2]
      @layer_list_ram_pointer = room_metadata[3]
      @gfx_list_pointer = room_metadata[4]
      @palette_wrapper_pointer = room_metadata[5]
      @entity_list_ram_pointer = room_metadata[6]
      @door_list_ram_pointer = room_metadata[7]
      extra_data = room_metadata[8]
      extra_data_2 = room_metadata[9]
      read_extra_data_from_rom(extra_data, extra_data_2)
    elsif GAME == "hod"
      room_metadata = fs.read(room_metadata_ram_pointer, 36).unpack("vvVVVVVVVV")
      @lcd_control = room_metadata[0]
      @state_swap_event_flag = room_metadata[1]
      @alternate_room_state_pointer = room_metadata[2]
      @layer_list_ram_pointer = room_metadata[3]
      @gfx_list_pointer = room_metadata[4]
      @entity_gfx_list_pointer = room_metadata[5]
      @palette_wrapper_pointer = room_metadata[6]
      @entity_list_ram_pointer = room_metadata[7]
      @door_list_ram_pointer = room_metadata[8]
      extra_data = room_metadata[9]
      read_extra_data_from_rom(extra_data)
      initialize_alternate_room_state(alternate_room_state_pointer)
      initialize_entity_gfx_list(entity_gfx_list_pointer)
    else # nds
      room_metadata = fs.read(room_metadata_ram_pointer, 32).unpack("V*")
      @layer_list_ram_pointer = room_metadata[2]
      @gfx_list_pointer = room_metadata[3]
      @palette_wrapper_pointer = room_metadata[4]
      @entity_list_ram_pointer = room_metadata[5]
      @door_list_ram_pointer = room_metadata[6]
      extra_data = room_metadata[7]
      read_extra_data_from_rom(extra_data)
    end
    
    read_layer_list_from_rom(layer_list_ram_pointer)
    read_graphic_tilesets_from_rom(gfx_list_pointer)
    read_palette_pages_from_rom(@palette_wrapper_pointer)
    read_entity_list_from_rom(entity_list_ram_pointer)
    read_door_list_from_rom(door_list_ram_pointer)
  end
  
  def read_layer_list_from_rom(layer_list_ram_pointer)
    @layers = []
    i = 0
    while true
      layer = RoomLayer.new(self, layer_list_ram_pointer + i*RoomLayer.layer_list_entry_size, game)
      layer.read_from_rom()
      @layers << layer
      
      i += 1
      break if i == Room.max_number_of_layers
    end
  rescue NDSFileSystem::ConversionError => e
    # When layer_list_ram_pointer points to something outside the overlay, that means the room has no layers.
    @layers = []
  end
  
  def read_graphic_tilesets_from_rom(gfx_list_pointer)
    @gfx_pages = RoomGfxPage.from_room_gfx_page_list(gfx_list_pointer, fs)
  rescue NDSFileSystem::ConversionError => e
    # When gfx_list_pointer is like this (e.g. 0x02195984), it just points to 00s instead of actual data.
    # What this means is that the room doesn't load any gfx pages. Instead it just keeps whatever gfx pages the previous room had loaded.
    @gfx_pages = []
  end
  
  def read_palette_pages_from_rom(palette_wrapper_pointer)
    i = 0
    @palette_pages = PaletteWrapper.from_palette_wrapper_pointer(palette_wrapper_pointer, fs)
    
    if SYSTEM == :nds
      @palette_pages = @palette_pages[palette_page_index..palette_page_index]
    end
  rescue NDSFileSystem::ConversionError => e
    # When palette_wrapper_pointer is like this (e.g. 0x02195984), it just points to 00s instead of actual data.
    # What this means is that the room doesn't load a palette. Instead it just keeps whatever palette the previous room had loaded.
    @palette_pages = []
  end
  
  def read_entity_list_from_rom(entity_list_ram_pointer)
    i = 0
    @entities = []
    while true
      if entity_list_ram_pointer == 0 && GAME == "hod"
        break
      end
      
      entity_pointer = entity_list_ram_pointer + i*12
      if fs.read(entity_pointer, 2).unpack("v").first == 0x7FFF
        break
      end
      
      @entities << Entity.new(self, fs).read_from_rom(entity_pointer)
      
      i += 1
    end
    
    @original_number_of_entities = entities.length
  end
  
  def read_door_list_from_rom(door_list_ram_pointer)
    @doors = []
    
    if GAME == "hod"
      i = 0
      while true
        if door_list_ram_pointer == 0
          break
        end
        
        door_pointer = door_list_ram_pointer + i*Door.data_size
        
        dest_room_pointer = fs.read(door_pointer, 4).unpack("V").first
        break unless fs.is_pointer?(dest_room_pointer)
        
        @doors << Door.new(self, game).read_from_rom(door_pointer)
        
        i += 1
      end
      
      @number_of_doors = doors.length
    else
      (0..number_of_doors-1).each do |i|
        door_pointer = door_list_ram_pointer + i*Door.data_size
        
        @doors << Door.new(self, game).read_from_rom(door_pointer)
      end
    end
    
    @original_number_of_doors = doors.length
  rescue NDSFileSystem::ConversionError => e
    # When door_list_ram_pointer points to nothing it indicates the room has no doors (e.g. Menace's room).
    @doors = []
    @original_number_of_doors = 0
  end
  
  def read_glitch_doors_from_rom
    if !["hod", "aos"].include?(GAME)
      return
    end
    if !glitch_doors.nil?
      return
    end
    
    unfound_door_positions = []
    (-1..width).each do |x|
      x = 255 if x == -1
      (-1..height).each do |y|
        y = 255 if y == -1
        unfound_door_positions << [x, y]
      end
    end
    
    doors.each do |door|
      unfound_door_positions.delete([door.x_pos, door.y_pos])
    end
    
    @glitch_doors = []
    
    i = 0
    on_glitch_doors = false
    while true
      if door_list_ram_pointer == 0
        break
      end
      
      door_pointer = door_list_ram_pointer + i*Door.data_size
      i += 1
      
      break if door_pointer > (0x08000000+fs.rom.size-Door.data_size)
      
      dest_room_pointer = fs.read(door_pointer, 4).unpack("V").first
      if !on_glitch_doors && !fs.is_pointer?(dest_room_pointer)
        on_glitch_doors = true
      end
      if !on_glitch_doors
        next
      end
      
      door = Door.new(self, game, is_glitch_door=true).read_from_rom(door_pointer)
      
      if !unfound_door_positions.include?([door.x_pos, door.y_pos])
        # Only the first door on each screen can be triggered.
        next
      end
      
      @glitch_doors << door
      
      unfound_door_positions.delete([door.x_pos, door.y_pos])
      if unfound_door_positions.empty?
        break
      end
    end
  end
  
  def read_extra_data_from_rom(extra_data, extra_data_2=nil)
    if GAME == "dos"
      @number_of_doors    = (extra_data & 0b00000000_00000000_11111111_11111111)
      @room_xpos_on_map   = (extra_data & 0b00000000_00111111_00000000_00000000) >> 16
      @room_ypos_on_map   = (extra_data & 0b00011111_10000000_00000000_00000000) >> 23
      @palette_page_index = 0 # Always 0 in DoS, and so not stored in this data
    elsif GAME == "aos"
      @number_of_doors    = (extra_data   & 0b00000000_00000000_11111111_11111111)
      @color_effects      = (extra_data   & 0b11111111_11111111_00000000_00000000) >> 16
      @room_xpos_on_map   = (extra_data_2 & 0b00000000_01111111_00000000_00000000) >> 16
      @room_ypos_on_map   = (extra_data_2 & 0b00111111_10000000_00000000_00000000) >> 23
      @palette_page_index = 0 # Always 0 in AoS
    elsif GAME == "hod"
      @special_effect     = (extra_data & 0b00000000_00000000_00000000_11111111)
      @palette_shift_type = (extra_data & 0b00000000_00000000_11111111_00000000) >> 8
      @room_xpos_on_map   = (extra_data & 0b00000000_01111111_00000000_00000000) >> 16
      @room_ypos_on_map   = (extra_data & 0b00111111_10000000_00000000_00000000) >> 23
      @is_castle_b        = (extra_data & 0b01000000_00000000_00000000_00000000) >> 30
      @has_breakable_wall = (extra_data & 0b10000000_00000000_00000000_00000000) >> 31
      @palette_page_index = 0 # Always 0 in HoD
    else # PoR or OoE
      @number_of_doors    = (extra_data & 0b00000000_00000000_00000000_01111111)
      @room_xpos_on_map   = (extra_data & 0b00000000_00000000_00111111_10000000) >> 7
      @room_ypos_on_map   = (extra_data & 0b00000000_00011111_11000000_00000000) >> 14
      @palette_page_index = (extra_data & 0b00001111_10000000_00000000_00000000) >> 23
    end
  end
  
  alias x_pos room_xpos_on_map
  alias y_pos room_ypos_on_map
  
  def initialize_alternate_room_state(alternate_room_state_pointer)
    @alternate_room_state = nil
    if alternate_room_state_pointer != 0
      begin
        @alternate_room_state = game.get_room_by_metadata_pointer(alternate_room_state_pointer)
      rescue Game::RoomFindError
        @alternate_room_state = Room.new(sector, alternate_room_state_pointer, area_index, sector_index, room_index, game)
        @alternate_room_state.read_from_rom()
      end
    end
  end
  
  def room_states
    base_room_state = game.areas[area_index].sectors[sector_index].rooms[room_index]
    states = [base_room_state]
    
    while true
      next_room_state = states.last.alternate_room_state
      if next_room_state && !states.include?(next_room_state) # Don't include a recursive room state or we'll get into an infinite loop.
        states << next_room_state
      else
        break
      end
    end
    
    return states
  end
  
  def initialize_entity_gfx_list(entity_gfx_list_pointer)
    @entity_gfx_list = []
    offset = entity_gfx_list_pointer
    while true
      gfx_pointer = fs.read(offset, 4).unpack("V").first
      
      if gfx_pointer == 0
        break
      end
      
      @entity_gfx_list << gfx_pointer
      
      offset += 4
    end
    
    @original_number_of_enemy_gfx = entity_gfx_list.length
  end
  
  def write_to_rom
    sector.load_necessary_overlay()
    
    case GAME
    when "aos"
      room_data = [
        lcd_control,
        state_swap_event_flag,
        alternate_room_state_pointer,
        layer_list_ram_pointer,
        gfx_list_pointer,
        palette_wrapper_pointer,
        entity_list_ram_pointer,
        door_list_ram_pointer
      ].pack("vvVVVVVV")
      fs.write(room_metadata_ram_pointer, room_data)
    when "hod"
      room_data = [
        lcd_control,
        state_swap_event_flag,
        alternate_room_state_pointer,
        layer_list_ram_pointer,
        gfx_list_pointer,
        entity_gfx_list_pointer,
        palette_wrapper_pointer,
        entity_list_ram_pointer,
        door_list_ram_pointer
      ].pack("vvVVVVVVV")
      fs.write(room_metadata_ram_pointer, room_data)
    else # nds
      room_data = [
        layer_list_ram_pointer,
        gfx_list_pointer,
        palette_wrapper_pointer,
        entity_list_ram_pointer,
        door_list_ram_pointer
      ].pack("V*")
      fs.write(room_metadata_ram_pointer + 8, room_data)
    end
    
    write_extra_data_to_rom()
    
    read_from_rom()
    
    if GAME == "hod"
      remove_entities_from_palette_list()
    end
  end
  
  def write_entities_to_rom
    sector.load_necessary_overlay()
    
    if entity_list_ram_pointer == 0 && GAME == "hod" && entities.length == 0
      # No entities before or after, so nothing to save.
      return
    end
    
    if GAME == "hod"
      entity_list_pointer_location = room_metadata_ram_pointer+6*4
    else
      entity_list_pointer_location = room_metadata_ram_pointer+5*4
    end
    
    if entities.length > @original_number_of_entities
      # Repoint the entity list so there's room for more entities without overwriting anything.
      # Entities are originally stored in the arm9 file, but we can't expand that. Instead put them into an overlay file, which can be expanded.
      # We use the same overlay that the the room's layers are stored on.
      
      if layers.empty?
        raise WriteError.new("Cannot add new entities to a room with no layers. Add a new layer first.")
      end
      
      original_length = (@original_number_of_entities+1)*12
      length_needed = (entities.length+1)*12
      
      if @entity_list_ram_pointer == 0
        # In HoD, rooms that originally had no entities have 0 for their entity pointer.
        new_entity_list_pointer = fs.get_free_space(length_needed, nil)
      else
        new_entity_list_pointer = fs.free_old_space_and_find_new_free_space(entity_list_ram_pointer, original_length, length_needed, overlay_id)
      end
      
      @original_number_of_entities = entities.length
      
      @entity_list_ram_pointer = new_entity_list_pointer
      fs.write(entity_list_pointer_location, [entity_list_ram_pointer].pack("V"))
    elsif entities.length < @original_number_of_entities
      original_length = (@original_number_of_entities+1)*12
      length_needed = (entities.length+1)*12
      
      fs.free_unused_space(entity_list_ram_pointer + length_needed, original_length - length_needed)
      
      @original_number_of_entities = entities.length
    end
    
    if SYSTEM == :nds
      new_entity_pointer = entity_list_ram_pointer
      entities.each do |entity|
        entity.entity_ram_pointer = new_entity_pointer
        
        new_entity_pointer += 12
      end
      
      entities.each do |entity|
        entity.write_to_rom()
      end
    else
      update_entity_list_order_and_save_entities()
    end
    
    end_marker_location = entity_list_ram_pointer + entities.length*12
    fs.write(end_marker_location, [0x7FFF7FFF, 0, 0].pack("V*")) # Marks the end of the entity list
    
    if GAME == "hod"
      update_entity_gfx_list()
      remove_entities_from_palette_list()
    end
  end
  
  def update_entity_list_order_and_save_entities
    if SYSTEM == :gba
      # AoS only loads entities when you get close to them in the room.
      # It checks this by looking at the x or y pos of the entity.
      # However, it assumes that all entities in the room are ordered by the x or y pos.
      # So we need to reorder them for the entities to load correctly.
      
      # Room is considered vertical if height is greater than width, otherwise horizontal.
      if main_layer_width < main_layer_height
        entities.sort_by! do |entity|
          entity.y_pos
        end
      else
        entities.sort_by! do |entity|
          entity.x_pos
        end
      end
      
      # Also, any nothing-type entities have to be at the end because the game will stop reading the list as soon as it sees one.
      entities.sort_by!.with_index do |entity, index|
        # Need to include the index as a secondary sort to preserve the position-based sort order we did above.
        if entity.type == NOTHING_ENTITY_TYPE
          [1, index]
        else
          [0, index]
        end
      end
      
      new_entity_pointer = entity_list_ram_pointer
      i = 0
      entities.each do |entity|
        entity.entity_ram_pointer = new_entity_pointer
        
        fs.write(entity.entity_ram_pointer, entity.to_data)
        
        new_entity_pointer += 12
        i += 1
      end
    end
  end
  
  def get_unused_unique_id
    if SYSTEM == :gba
      used_unique_ids = entities.map{|e| e.unique_id}
      unused_unique_ids = (0..0xFF).to_a - used_unique_ids
      return unused_unique_ids.min
    else
      return 0
    end
  end
  
  def write_doors_to_rom
    return if doors.length == 0 && @original_number_of_doors == 0
    
    if doors.length > @original_number_of_doors && layers.empty?
      raise WriteError.new("Cannot add new doors to a room with no layers. Add a new layer first.")
    end
    
    sector.load_necessary_overlay()
    
    if GAME == "hod"
      # We handle saving HoD doors differently from the other games.
      # In HoD, the number of doors a room has isn't stored anywhere.
      # So in order for DSVEdit to be able to accurately detect when to stop reading doors, we need to ensure the word immediately following the final door is not in the 0x08000000-0x08FFFFFF range, because that would look like the start of another door.
      # The way we accomplish this is by always moving the room's layer list to right after the door list every time the door list is saved.
      # (Also, when saving the layer list in HoD, we also automatically set some bits in the BG control value to the value they should be for that layer, just to avoid the user manually editing the BG control and making it look like the start of a door, causing the issue again.)
      
      old_length = @original_number_of_doors*Door.data_size
      new_length_needed = doors.length*Door.data_size
      
      layer_list_length = Room.max_number_of_layers*RoomLayer.layer_list_entry_size
      new_length_needed += layer_list_length
      
      old_layer_list_data_backup = fs.read(layer_list_ram_pointer, layer_list_length)
      fs.free_unused_space(layer_list_ram_pointer, layer_list_length)
      
      begin
        if @original_number_of_doors > 0
          new_door_list_pointer = fs.free_old_space_and_find_new_free_space(door_list_ram_pointer, old_length, new_length_needed, overlay_id)
        else
          new_door_list_pointer = fs.get_free_space(new_length_needed, overlay_id)
        end
      rescue FreeSpaceManager::FreeSpaceFindError => e
        # If there's an error grabbing free space here, we need to revert the layer list back to how it was as well.
        fs.write(layer_list_ram_pointer, old_layer_list_data_backup)
        raise e
      end
      
      @door_list_ram_pointer = new_door_list_pointer
      
      # Then actually move the layer list data to the new location after the door list.
      @layer_list_ram_pointer = door_list_ram_pointer + doors.length*Door.data_size
      fs.write(room_metadata_ram_pointer+2*4, [layer_list_ram_pointer].pack("V"))
      
      layers.each_with_index do |layer, layer_i|
        layer.layer_list_entry_ram_pointer = @layer_list_ram_pointer + layer_i*RoomLayer.layer_list_entry_size
        layer.write_layer_list_entry_to_rom()
      end
      
      if doors.length == 0
        @door_list_ram_pointer = 0
      end
    elsif doors.length > @original_number_of_doors
      # Repoint the door list so there's room for more doors without overwriting anything.
      # Doors are originally stored in the arm9 file, but we can't expand that. Instead put them into an overlay file, which can be expanded.
      # We use the same overlay that the the room's layers are stored on.
      
      old_length = @original_number_of_doors*Door.data_size
      new_length = doors.length*Door.data_size
      
      if @original_number_of_doors > 0
        new_door_list_pointer = fs.free_old_space_and_find_new_free_space(door_list_ram_pointer, old_length, new_length, overlay_id)
      else
        new_door_list_pointer = fs.get_free_space(new_length, overlay_id)
      end
      
      @door_list_ram_pointer = new_door_list_pointer
    elsif doors.length < @original_number_of_doors
      old_length = @original_number_of_doors*Door.data_size
      new_length = doors.length*Door.data_size
      
      fs.free_unused_space(door_list_ram_pointer + new_length, old_length - new_length)
    end
    
    @original_number_of_doors = doors.length
    
    if GAME == "hod"
      fs.write(room_metadata_ram_pointer+7*4, [door_list_ram_pointer].pack("V"))
    else
      fs.write(room_metadata_ram_pointer+6*4, [door_list_ram_pointer].pack("V"))
    end
    
    new_door_pointer = door_list_ram_pointer
    doors.each do |door|
      door.door_ram_pointer = new_door_pointer
      door.write_to_rom()
      
      new_door_pointer += Door.data_size
    end
    
    @number_of_doors = doors.length
    write_extra_data_to_rom() if GAME != "hod"
  end
  
  def update_entity_gfx_list
    @entity_gfx_list = []
    
    enemies = entities.select{|e| e.is_enemy?}
    enemies.each do |enemy|
    begin
      enemy_id = enemy.subtype
      if enemy_id == 0x6A
        # Spawner
        enemy_id = enemy.var_b
      elsif enemy_id == 0x66
        # Spawner timer
        next
      elsif enemy_id == 0x16 && enemy.var_a == 2
        # Peeping Eye that spawns Peeping Big
        sprite_info = game.enemy_dnas[0x42].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      elsif enemy_id == 0x3D # "O"
        # O needs Rare Ghost's exclamation point bubble, so load Rare Ghost's GFX too.
        sprite_info = game.enemy_dnas[0x4E].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      elsif enemy_id == 0x6E # Skeleton Mirror (in mirror)
        # Need to load Skeleton Mirror's GFX too.
        sprite_info = game.enemy_dnas[0x3C].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      elsif enemy_id == 0x71 # Skeleton Glass (in glass)
        # Need to load Skeleton Glass's GFX too.
        sprite_info = game.enemy_dnas[0x4F].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      elsif enemy_id == 0x36 # Giant Merman
        # His spin has a separate GFX (and sprite).
        other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Giant Merman spin"}
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:init_code], fs, nil, other_sprite)
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
        
        # Also need to load Merman's GFX too.
        sprite_info = game.enemy_dnas[0x2F].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      end
      
      if ENEMY_IDS.include?(enemy_id)
        sprite_info = game.enemy_dnas[enemy_id].extract_gfx_and_palette_and_sprite_from_init_ai
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      end
    rescue SpriteInfo::CreateCodeReadError => e
      puts e.message
    end
    end
    
    objects = entities.select{|e| e.is_special_object?}
    objects.each do |object|
      object_id = object.subtype
      begin
        sprite_info = nil
        if object_id == 5 && object.var_a > 1 # Skull door or Lure door
          other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Skull door"}
          sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:init_code], fs, nil, other_sprite)
        elsif object_id == 9 # Button and wall
          gfx_pointer = fs.read(BUTTON_AND_WALL_GFX_LIST_START + 4*object.var_a, 4).unpack("V").first
          @entity_gfx_list << gfx_pointer
          next
        elsif object_id == 0x26 # Event
          event_id = object.var_a
          other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Event %02X" % event_id}
          sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:init_code], fs, nil, other_sprite)
        elsif object_id == 0x28 # Lydie
          if objects.find{|o| o.subtype == 0x26 && [0xA, 0xB, 0x12].include?(o.var_a)}
            # If the room has one of the events at the center of the castle that includes Lydie, that loads both Lydie and Maxim's GFX.
            # Lydie herself should not have her GFX loaded in this case as it would mess everything up.
            next
          end
          sprite_info = game.special_objects[object_id].extract_gfx_and_palette_and_sprite_from_create_code
        elsif SPECIAL_OBJECT_IDS.include?(object_id)
          sprite_info = game.special_objects[object_id].extract_gfx_and_palette_and_sprite_from_create_code
        end
        
        if object_id == 0x1F && object.var_a == 2 # Elevator to center room of castle
          # Need to load the lift's GFX too.
          other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Lift to center of castle"}
          lift_sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:init_code], fs, nil, other_sprite)
          @entity_gfx_list += lift_sprite_info.gfx_list_pointer_or_gfx_file_pointers
        end
        
        if sprite_info
          @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
        end
      rescue SpriteInfo::CreateCodeReadError, GBADummyFilesystem::ReadError => e
        puts e.message
      end
    end
    
    candles = entities.select{|e| e.is_candle?}
    candles.each do |candle|
      begin
        sprite_info, _ = candle.get_hod_candle_sprite_info()
        
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      rescue SpriteInfo::CreateCodeReadError, GBADummyFilesystem::ReadError => e
        puts e.message
      end
    end
    
    if special_effect == 5
      begin
        # Has the fake 3D clock tower
        other_sprite = OTHER_SPRITES.find{|spr| spr[:desc] == "Clock tower in BG"}
        sprite_info = SpriteInfo.extract_gfx_and_palette_and_sprite_from_create_code(other_sprite[:init_code], fs, nil, other_sprite)
        
        @entity_gfx_list += sprite_info.gfx_list_pointer_or_gfx_file_pointers
      rescue SpriteInfo::CreateCodeReadError, GBADummyFilesystem::ReadError => e
        puts e.message
      end
    end
    
    @entity_gfx_list -= COMMON_SPRITE[:gfx_files]
    
    @entity_gfx_list.uniq!
    
    write_entity_gfx_list_to_rom()
  end
  
  def write_entity_gfx_list_to_rom
    list_ptr_duplicated = !!(room_states - [self]).find{|room_state| room_state.entity_gfx_list_pointer == @entity_gfx_list_pointer}
    if list_ptr_duplicated
      # Need to move this list to free space so it doesn't conflict with other room states that use the same list pointer.
      
      new_length = (entity_gfx_list.length+1)*4
      
      new_entity_gfx_list_pointer = fs.get_free_space(new_length, nil)
      
      @original_number_of_enemy_gfx = entity_gfx_list.length
      
      @entity_gfx_list_pointer = new_entity_gfx_list_pointer
      fs.write(room_metadata_ram_pointer+4*4, [entity_gfx_list_pointer].pack("V"))
    elsif entity_gfx_list.length > @original_number_of_enemy_gfx
      # Repoint the enemy gfx list so there's room for more pointers without overwriting anything.
      
      old_length = (@original_number_of_enemy_gfx+1)*4
      new_length = (entity_gfx_list.length+1)*4
      
      new_entity_gfx_list_pointer = fs.free_old_space_and_find_new_free_space(entity_gfx_list_pointer, old_length, new_length, nil)
      
      @original_number_of_enemy_gfx = entity_gfx_list.length
      
      @entity_gfx_list_pointer = new_entity_gfx_list_pointer
      fs.write(room_metadata_ram_pointer+4*4, [entity_gfx_list_pointer].pack("V"))
    elsif entity_gfx_list.length < @original_number_of_enemy_gfx
      old_length = (@original_number_of_enemy_gfx+1)*4
      new_length = (entity_gfx_list.length+1)*4
      
      fs.free_unused_space(entity_gfx_list_pointer + new_length, old_length - new_length)
      
      @original_number_of_enemy_gfx = entity_gfx_list.length
    end
    
    offset = entity_gfx_list_pointer
    entity_gfx_list.each do |enemy_gfx_pointer|
      fs.write(offset, [enemy_gfx_pointer].pack("V"))
      offset += 4
    end
    fs.write(offset, [0].pack("V"))
  end
  
  def remove_entities_from_palette_list
    return unless GAME == "hod"
    
    # Whenever entities are changed, remove all entity palettes from the room's palette list.
    # This is because if no entity palettes are in the list, the entities are capable of loading their own palettes (unlike GFX).
    # But if palettes are listed, but they're for old entities the user has removed, then these palettes being loaded can prevent the new entities from loading their palettes.
    
    old_length = (palette_pages.size+1)*PaletteWrapper.data_size
    @palette_pages = @palette_pages.reject{|palette_page| palette_page.palette_type == 1}
    new_length = (palette_pages.size+1)*PaletteWrapper.data_size
    
    pointer = palette_wrapper_pointer
    palette_pages.each do |palette_page|
      fs.write(pointer, palette_page.to_data)
      
      pointer += PaletteWrapper.data_size
    end
    fs.write(pointer, [0, 0].pack("VV"))
    pointer += PaletteWrapper.data_size
    
    fs.free_unused_space(pointer, old_length - new_length)
  end
  
  def write_extra_data_to_rom
    extra_data = 0
    if GAME == "dos"
      extra_data |= (@number_of_doors         ) & 0b00000000_00000000_11111111_11111111
      extra_data |= (@room_xpos_on_map   << 16) & 0b00000000_00111111_00000000_00000000
      extra_data |= (@room_ypos_on_map   << 23) & 0b00011111_10000000_00000000_00000000
      
      fs.write(room_metadata_ram_pointer+7*4, [extra_data].pack("V"))
    elsif GAME == "aos"
      extra_data_2 = 0
      extra_data   |= (@number_of_doors         ) & 0b00000000_00000000_11111111_11111111
      extra_data   |= (@color_effects      << 16) & 0b11111111_11111111_00000000_00000000
      extra_data_2 |= (@room_xpos_on_map   << 16) & 0b00000000_00111111_00000000_00000000
      extra_data_2 |= (@room_ypos_on_map   << 23) & 0b00011111_10000000_00000000_00000000
      
      fs.write(room_metadata_ram_pointer+7*4, [extra_data].pack("V"))
      fs.write(room_metadata_ram_pointer+8*4, [extra_data_2].pack("V"))
    elsif GAME == "hod"
      extra_data |= (@special_effect          ) & 0b00000000_00000000_00000000_11111111
      extra_data |= (@palette_shift_type <<  8) & 0b00000000_00000000_11111111_00000000
      extra_data |= (@room_xpos_on_map   << 16) & 0b00000000_01111111_00000000_00000000
      extra_data |= (@room_ypos_on_map   << 23) & 0b00111111_10000000_00000000_00000000
      extra_data |= (@is_castle_b        << 30) & 0b01000000_00000000_00000000_00000000
      extra_data |= (@has_breakable_wall << 31) & 0b10000000_00000000_00000000_00000000
      
      fs.write(room_metadata_ram_pointer+8*4, [extra_data].pack("V"))
    else
      extra_data |= (@number_of_doors         ) & 0b00000000_00000000_00000000_01111111
      extra_data |= (@room_xpos_on_map   <<  7) & 0b00000000_00000000_00111111_10000000
      extra_data |= (@room_ypos_on_map   << 14) & 0b00000000_00011111_11000000_00000000
      extra_data |= (@palette_page_index << 23) & 0b00001111_10000000_00000000_00000000
      
      fs.write(room_metadata_ram_pointer+7*4, [extra_data].pack("V"))
    end
  end
  
  def create_layer_list
    # There are some invalid unused rooms in PoR where the layer list pointer points outside the overlay file.
    # This function initializes a layer list for these rooms.
    
    if SYSTEM == :gba
      # All rooms in AoS and HoD already have the maximum of 3 layers. There's no way to add more.
      return
    end
    if layers.length != 0
      raise "Can't create layer list, room already has a layer list."
    end
    
    sector.load_necessary_overlay()
    
    overlay = fs.overlays[overlay_id]
    overlay_ram_end = overlay[:ram_start_offset]+overlay[:size]
    
    # Create the layer list.
    @layer_list_ram_pointer = fs.get_free_space(RoomLayer.layer_list_entry_size*Room.max_number_of_layers, overlay_id)
    fs.write(room_metadata_ram_pointer+2*4, [@layer_list_ram_pointer].pack("V"))
    
    # Create the layers.
    Room.max_number_of_layers.times do |new_layer_i|
      new_layer = RoomLayer.new(self, layer_list_ram_pointer + new_layer_i*RoomLayer.layer_list_entry_size, game)
      
      new_layer.z_index = 0x16
      new_layer.scroll_mode = 0x01
      new_layer.main_gfx_page_index = 0x00
      new_layer.opacity = 0x1F
      
      layer_metadata_ram_pointer = fs.get_free_space(16, overlay_id)
      new_layer.bg_layer = BGLayer.new(layer_metadata_ram_pointer, fs, overlay_id: overlay_id)
      
      main_layer = layers.first
      if main_layer
        new_layer.width = main_layer.width
        new_layer.height = main_layer.height
        new_layer.tileset_pointer = main_layer.tileset_pointer
        new_layer.collision_tileset_pointer = main_layer.collision_tileset_pointer
        new_layer.tileset_type = main_layer.tileset_type
      else
        # Room that has no layers.
        new_layer.width = 1
        new_layer.height = 1
        
        other_room_in_sector = sector.rooms.select{|room| room.layers.length > 0}.first
        if other_room_in_sector
          new_layer.tileset_pointer = other_room_in_sector.layers.first.tileset_pointer
          new_layer.collision_tileset_pointer = other_room_in_sector.layers.first.collision_tileset_pointer
          new_layer.tileset_type = other_room_in_sector.layers.first.tileset_type
        else
          new_layer.tileset_pointer = 0
          new_layer.collision_tileset_pointer = 0
          new_layer.tileset_type = 0
        end
      end
      new_layer.layer_tiledata_ram_start_offset = nil # Layer#write_to_rom will get free space and put this there.
      new_layer.tiles = []
      
      new_layer.write_to_rom()
      
      @layers << new_layer
    end
    
    self.write_to_rom()
  end
  
  def add_new_entity
    entity = Entity.new(self, fs)
    entities << entity
    write_entities_to_rom()
    
    return entity
  end
  
  def clear_contents
    @entities = []
    write_entities_to_rom()
    
    @doors = []
    write_doors_to_rom()
    
    layers.each do |layer|
      layer.clear_contents()
    end
    
    case GAME
    when "aos"
      @color_effects = 0
    when "hod"
      @special_effect = 0
      @palette_shift_type = 0
      @is_castle_b = (sector_index % 2)
      @has_breakable_wall = 0
    end
    if SYSTEM == :gba
      @lcd_control = 0x1F00
      @state_swap_event_flag = 0xFFFF
      @alternate_room_state_pointer = 0
      
      if !@alternate_room_state.nil?
        @alternate_room_state.clear_contents()
      end
    end
    
    write_to_rom()
  end
  
  def overlay_id
    AREA_INDEX_TO_OVERLAY_INDEX[sector.area.area_index][sector.sector_index]
  end
  
  def z_ordered_layers
    layers.sort_by{|layer| -layer.z_index}
  end
  
  def filename
    "room_%02X-%02X-%02X_%08X" % [area_index, sector_index, room_index, room_metadata_ram_pointer]
  end
  
  def area_name
    sector.name
  end
  
  def self.max_number_of_layers
    if SYSTEM == :nds
      4
    else
      3
    end
  end
  
  def max_layer_width
    layers.map(&:width).max || 0
  end
  
  def max_layer_height
    layers.map(&:height).max || 0
  end
  
  def main_layer_width
    if layers.length > 0
      layers.first.width
    else
      0
    end
  end
  
  def main_layer_height
    if layers.length > 0
      layers.first.height
    else
      0
    end
  end
  
  alias width main_layer_width
  alias height main_layer_height
  
  def connected_rooms
    doors.map{|door| door.destination_door.room}.uniq
  end
  
  def self.data_size
    if SYSTEM == :gba
      36
    else
      32
    end
  end
  
  def room_str
    @room_str ||= "%02X-%02X-%02X" % [area_index, sector_index, room_index]
  end
  
  def to_s
    "<Room:#{room_str}>"
  end
  
  def inspect; to_s; end
end

class RoomGfxPage
  attr_reader :gfx_pointer,
              :gfx_wrapper,
              :gfx_load_offset,
              :first_chunk_index,
              :num_chunks,
              :unknown
              
  def initialize(pointer, fs, hod_gfx_load_offset=nil)
    if GAME == "hod"
      @gfx_pointer = fs.read(pointer, 4).unpack("V").first
      @gfx_load_offset = hod_gfx_load_offset
      @first_chunk_index = 0
      @num_chunks = 4
      @unknown = 0
    else
      @gfx_pointer, @gfx_load_offset, @first_chunk_index, @num_chunks, @unknown = fs.read(pointer, 8).unpack("VCCCC")
    end
    @gfx_wrapper = GfxWrapper.new(gfx_pointer, fs)
  end
  
  def colors_per_palette
    gfx_wrapper.colors_per_palette
  end
  
  def self.from_room_gfx_page_list(gfx_list_pointer, fs)
    gfx_pages = []
    i = 0
    offset = gfx_list_pointer
    while true
      gfx_pointer = fs.read(offset, 4).unpack("V").first
      
      if GAME == "hod"
        if gfx_pointer == 0
          i += 1
          offset += 4
          if i >= 4
            break
          end
          next
        end
      else
        break if gfx_pointer == 0
      end
      
      if GAME == "hod"
        if i == 3
          # The one at index 3 in HoD is always a 256 color GFX page that gets loaded to 06008000 in VRAM.
          hod_gfx_load_offset = 0x10
        else
          # The ones at indexes 0-2 are 16 color GFX pages that get loaded to 06000000, 06002000, 06004000 in VRAM.
          hod_gfx_load_offset = i*4
        end
      end
      
      gfx_page = RoomGfxPage.new(offset, fs, hod_gfx_load_offset)
      gfx_pages << gfx_page
      
      i += 1
      if GAME == "hod"
        offset += 4
        if i >= 4
          break
        end
      else
        offset += 8
      end
    end
    
    return gfx_pages
  end
end
