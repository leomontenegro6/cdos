
class Sector
  class SectorReadError < StandardError ; end
  
  attr_reader :fs,
              :game,
              :area,
              :sector_ram_pointer,
              :area_index,
              :sector_index,
              :room_pointers,
              :rooms,
              :is_hardcoded,
              :rooms_list_read_from_rom_yet

  def initialize(area, sector_index, sector_ram_pointer, game, next_sector_pointer: nil, hardcoded_room_pointers: nil)
    @area = area
    @sector_ram_pointer = sector_ram_pointer
    @next_sector_pointer = next_sector_pointer
    @area_index = area.area_index
    @sector_index = sector_index
    @fs = game.fs
    @game = game
    
    if hardcoded_room_pointers
      @room_pointers = hardcoded_room_pointers
      @is_hardcoded = true
    else
      read_room_pointers_from_rom()
    end
    
    @rooms_list_read_from_rom_yet = false
  end
  
  def rooms
    @rooms ||= read_rooms_from_rom()
  end
  
  def overlay_id
    AREA_INDEX_TO_OVERLAY_INDEX[area.area_index][sector_index]
  end
  
  def load_necessary_overlay
    fs.load_overlay(overlay_id)
  end
  
  def name
    if SECTOR_INDEX_TO_SECTOR_NAME[area_index]
      SECTOR_INDEX_TO_SECTOR_NAME[area_index][sector_index]
    else
      return AREA_INDEX_TO_AREA_NAME[area_index]
    end
  end
  
  def add_new_room
    if is_hardcoded
      raise "Can't add new room; sector is hardcoded."
    end
    if rooms.length >= 0xFF
      raise "Can't add new room; sector already has FF rooms."
    end
    
    load_necessary_overlay()
    
    new_room_index = rooms.length
    
    new_room_pointer = fs.get_free_space(Room.data_size, nil)
    new_room = Room.new(self, new_room_pointer, area.area_index, sector_index, new_room_index, game)
    
    length_needed = Room.max_number_of_layers*RoomLayer.layer_list_entry_size
    new_room.layer_list_ram_pointer = fs.get_free_space(length_needed, overlay_id)
    fs.write(new_room.layer_list_ram_pointer, [0].pack("C")*length_needed)
    
    other_rooms = rooms.dup
    if GAME == "dos" && sector_index == 0xB # The Abyss
      # Move the first room to the end of the list since its tileset is nearly empty and not a very useful default.
      other_rooms.rotate!(1)
    end
    
    other_room_in_sector = other_rooms.first
    if other_room_in_sector
      new_room.gfx_list_pointer = other_room_in_sector.gfx_list_pointer
      new_room.palette_wrapper_pointer = other_room_in_sector.palette_wrapper_pointer
    else
      new_room.gfx_list_pointer = 0
      new_room.palette_wrapper_pointer = 0
    end
    
    new_room.entity_list_ram_pointer = fs.get_free_space(0xC, overlay_id)
    fs.write(new_room.entity_list_ram_pointer, [0x7FFF7FFF, 0, 0].pack("V*"))
    new_room.door_list_ram_pointer = 0
    
    new_room.entities = []
    new_room.original_number_of_entities = 0
    new_room.doors = []
    if GAME != "hod"
      new_room.number_of_doors = 0
    end
    new_room.original_number_of_doors = 0
    
    new_room.room_xpos_on_map = 0
    new_room.room_ypos_on_map = 0
    new_room.palette_page_index = 0
    
    if SYSTEM == :gba
      new_room.lcd_control = 0x1F00
      new_room.state_swap_event_flag = 0xFFFF
      new_room.alternate_room_state_pointer = 0
    end
    if GAME == "hod"
      # Create an empty entity gfx list which just immediately has the end marker.
      new_room.entity_gfx_list_pointer = fs.get_free_space(4)
      fs.write(new_room.entity_gfx_list_pointer, [0].pack("V"))
      new_room.initialize_entity_gfx_list(new_room.entity_gfx_list_pointer)
      
      new_room.special_effect = 0
      new_room.palette_shift_type = 0
      new_room.is_castle_b = (sector_index % 2)
      new_room.has_breakable_wall = 0
    end
    if GAME == "aos"
      new_room.color_effects = 0
    end
    
    # This both saves the room and then reads it to initialize various other things like layers.
    new_room.write_to_rom()
    
    new_room.layers.each_with_index do |layer, layer_index|
      layer.opacity = 0x1F
      layer.scroll_mode = 1
      layer.z_index = 0x16 + layer_index
      
      if GAME == "hod"
        layer.bg_control = 0x1D40 + (layer_index << 8)
        
        if layer_index == 0
          layer.visual_effect = 1
        else
          layer.visual_effect = 0
        end
      elsif GAME == "aos"
        layer.bg_control = 0x1D48 + (layer_index << 8)
      end
      layer.write_layer_list_entry_to_rom()
    end
    
    default_tileset_pointer = 0
    default_tileset_type = 0
    default_collision_tileset_pointer = 0
    other_rooms.each do |other_room|
      other_room_main_layer = other_room.layers.first
      if other_room_main_layer.nil? || other_room_main_layer.layer_metadata_ram_pointer == 0
        # Empty layer.
        next
      end
      
      default_tileset_pointer = other_room_main_layer.tileset_pointer
      default_tileset_type = other_room_main_layer.tileset_type
      default_collision_tileset_pointer = other_room_main_layer.collision_tileset_pointer
      break
    end
    
    main_layer = new_room.layers.first
    main_layer.tileset_pointer = default_tileset_pointer
    main_layer.tileset_type = default_tileset_type
    main_layer.collision_tileset_pointer = default_collision_tileset_pointer
    main_layer.write_to_rom()
    
    @rooms << new_room
    @room_pointers << new_room_pointer
    write_room_list_to_rom()
    
    game.generate_list_of_sectors_by_room_pointer()
  end
  
  def write_room_list_to_rom
    if is_hardcoded
      raise "Can't write room list to ROM; sector is hardcoded."
    end
    
    load_necessary_overlay()
    
    if GAME == "aos"
      # AoS is the only game without a null word marking the end of the room pointers list for some reason.
      end_marker_size = 0
    else
      end_marker_size = 4
    end
    
    old_length = (@original_number_of_rooms)*4 + end_marker_size
    new_length = (room_pointers.length)*4 + end_marker_size
    
    if GAME == "aos"
      new_length += 4 # For the custom end marker we'll add.
      
      if fs.read(sector_ram_pointer+old_length, 4).unpack("V").first == 0xDEADBEEF
        # Old list was already relocated once by DSVEdit and has the custom end marker.
        old_length += 4
      end
    end
    
    if room_pointers.length > @original_number_of_rooms
      # Repoint the room list so there's space for more doors without overwriting anything.
      
      new_room_list_pointer = fs.free_old_space_and_find_new_free_space(sector_ram_pointer, old_length, new_length, nil)
      
      @original_number_of_rooms = room_pointers.length
      
      @sector_ram_pointer = new_room_list_pointer
      fs.write(area.area_ram_pointer + sector_index*4, [sector_ram_pointer].pack("V"))
      
      if GAME == "aos"
        # Write a custom end marker so DSVEdit knows when to stop reading the list.
        fs.write(sector_ram_pointer+new_length-4, [0xDEADBEEF].pack("V"))
      end
    elsif room_pointers.length < @original_number_of_rooms
      fs.free_unused_space(sector_ram_pointer + new_length, old_length - new_length)
      
      @original_number_of_rooms = room_pointers.length
      
      if GAME == "aos"
        # Write a custom end marker so DSVEdit knows when to stop reading the list.
        fs.write(sector_ram_pointer+new_length-4, [0xDEADBEEF].pack("V"))
      end
    end
    
    offset = sector_ram_pointer
    room_pointers.each do |room_pointer|
      fs.write(offset, [room_pointer].pack("V"))
      offset += 4
    end
    if GAME != "aos"
      fs.write(offset, [0].pack("V")) # End marker
    end
  end
  
  def inspect; to_s; end
  
private
  
  def read_room_pointers_from_rom
    @room_pointers = []
    room_index = 0
    while true
      offset = sector_ram_pointer + room_index*4
      break if offset == @next_sector_pointer
      
      begin
        room_metadata_ram_pointer = fs.read(offset, 4).unpack("V*").first
      rescue NDSFileSystem::ConversionError => e
        # Hit the end of the file.
        break
      end
      
      break if room_metadata_ram_pointer == 0
      break if room_metadata_ram_pointer == 0xDEADBEEF && GAME == "aos" # Used by DSVEdit to signify the end of the rooms list if a new room has been added in AoS.
      break unless fs.is_pointer?(room_metadata_ram_pointer)
      break if offset == area.area_ram_pointer && GAME == "aos"
      
      room_pointers << room_metadata_ram_pointer
      
      room_index += 1
    end
    @original_number_of_rooms = room_pointers.size
  end
  
  def read_rooms_from_rom
    fs.load_overlay(AREAS_OVERLAY) if AREAS_OVERLAY
    
    load_necessary_overlay()
    
    rooms = []
    loaded_rooms_by_room_pointer = {}
    room_pointers.each_with_index do |room_pointer, room_index|
      # Avoid instantiating duplicate rooms even if the room list has the same pointer multiple times (e.g. first room of HoD).
      existing_room_in_this_sector = loaded_rooms_by_room_pointer[room_pointer]
      existing_room_in_other_sector = game.get_room_by_metadata_pointer_dont_load_from_rom(room_pointer)
      if existing_room_in_this_sector
        room = existing_room_in_this_sector
      elsif existing_room_in_other_sector
        room = existing_room_in_other_sector
      else
        room = Room.new(self, room_pointer, area.area_index, sector_index, room_index, game)
        room.read_from_rom()
      end
      rooms << room
      loaded_rooms_by_room_pointer[room_pointer] = room
    end
    
    @rooms_list_read_from_rom_yet = true
    
    rooms
  end
end
