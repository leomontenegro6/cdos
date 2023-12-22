
require 'oily_png'

class Renderer
  COLLISION_SOLID_COLOR = ChunkyPNG::Color::BLACK
  COLLISION_SEMISOLID_COLOR = ChunkyPNG::Color.rgba(127, 127, 127, 255)
  COLLISION_DAMAGE_COLOR = ChunkyPNG::Color.rgba(208, 32, 32, 255)
  COLLISION_WATER_COLOR = ChunkyPNG::Color.rgba(32, 32, 208, 255)
  COLLISION_CONVEYOR_COLOR = ChunkyPNG::Color.rgba(32, 208, 32, 255)
  
  class GFXImportError < StandardError ; end
  
  attr_reader :fs,
              :fill_color,
              :save_fill_color,
              :warp_fill_color,
              :secret_fill_color,
              :entrance_fill_color,
              :transition_fill_color,
              :line_color,
              :door_color,
              :door_center_color,
              :secret_door_color,
              :wall_pixels,
              :door_pixels,
              :secret_door_pixels,
              :warp_castle_b_fill_color,
              :warp_both_castles_fill_color
              
  def initialize(fs)
    @fs = fs
  end
  
  def render_room(folder, room, collision = false)
    rendered_layers = []
    
    if collision
      rendered_layers << render_room_layer(folder, room.layers.first, room, collision)
    else
      room.z_ordered_layers.each do |layer|
        next if layer.layer_metadata_ram_pointer == 0
        
        rendered_layers << render_room_layer(folder, layer, room, collision)
      end
    end
    
    if collision
      bg_color = ChunkyPNG::Color::WHITE
    else
      bg_color = ChunkyPNG::Color::BLACK
    end
    
    rendered_level = ChunkyPNG::Image.new(room.max_layer_width*SCREEN_WIDTH_IN_PIXELS, room.max_layer_height*SCREEN_HEIGHT_IN_PIXELS, bg_color)
    rendered_layers.each do |layer|
      rendered_level.compose!(layer)
    end
    
    if collision
      filename = "#{folder}/#{room.area_name}/Rendered Rooms/#{room.filename}_collision.png"
    else
      filename = "#{folder}/#{room.area_name}/Rendered Rooms/#{room.filename}.png"
    end
    FileUtils::mkdir_p(File.dirname(filename))
    rendered_level.save(filename, :fast_rgba)
    #puts "Wrote #{filename}"
  end
  
  def render_room_layer(folder, layer, room, collision = false)
    if layer.layer_metadata_ram_pointer == 0
      # Empty layer
      return ChunkyPNG::Image.new(layer.width*SCREEN_WIDTH_IN_PIXELS, layer.height*SCREEN_HEIGHT_IN_PIXELS, ChunkyPNG::Color::TRANSPARENT)
    end
    
    tileset_filename = "#{folder}/#{room.area_name}/Tilesets/#{layer.tileset_filename}.png"
    fs.load_overlay(AREA_INDEX_TO_OVERLAY_INDEX[room.area_index][room.sector_index])
    if collision
      tileset_filename = "#{folder}/#{room.area_name}/Tilesets/#{layer.tileset_filename}_collision.png"
      tileset = render_collision_tileset(layer.collision_tileset_pointer, tileset_filename)
    else
      tileset = get_tileset(
        layer.tileset_pointer,
        layer.tileset_type,
        room.palette_pages,
        room.gfx_pages,
        layer.gfx_base_block,
        layer.colors_per_palette,
        layer.collision_tileset_pointer,
        tileset_filename
      )
    end
    
    rendered_layer = render_layer(layer)
    
    if layer.opacity != 0x1F
      alpha = (layer.opacity << 3) | (layer.opacity >> 2) # Swizzle 5 bits to 8 bits
      
      rendered_layer.height.times do |y|
        rendered_layer.width.times do |x|
          color = rendered_layer[x, y]
          orig_alpha = ChunkyPNG::Color.a(color)
          next if orig_alpha < alpha
          
          r = ChunkyPNG::Color.r(color)
          g = ChunkyPNG::Color.g(color)
          b = ChunkyPNG::Color.b(color)
          rendered_layer[x, y] = ChunkyPNG::Color.rgba(r, g, b, alpha)
        end
      end
    end
    
    return rendered_layer
  end
  
  def render_layer(layer, tileset)
    rendered_layer = ChunkyPNG::Image.new(layer.width*SCREEN_WIDTH_IN_PIXELS, layer.height*SCREEN_HEIGHT_IN_PIXELS, ChunkyPNG::Color::TRANSPARENT)
    
    layer.tiles.each_with_index do |tile, index_on_level|
      x_on_tileset = tile.index_on_tileset % TILESET_WIDTH_IN_TILES
      y_on_tileset = tile.index_on_tileset / TILESET_WIDTH_IN_TILES
      x_on_level = index_on_level % (layer.width*SCREEN_WIDTH_IN_TILES)
      y_on_level = index_on_level / (layer.width*SCREEN_WIDTH_IN_TILES)
      
      tile_gfx = tileset.crop(x_on_tileset*TILE_WIDTH, y_on_tileset*TILE_HEIGHT, TILE_WIDTH, TILE_HEIGHT)
      
      if tile.horizontal_flip
        tile_gfx.mirror!
      end
      if tile.vertical_flip
        tile_gfx.flip!
      end
      
      rendered_layer.compose!(tile_gfx, x_on_level*TILE_WIDTH, y_on_level*TILE_HEIGHT)
    end
    
    return rendered_layer
  end
  
  def get_tileset(pointer_to_tileset_for_layer, tileset_type, palette_pages, gfx_pages, gfx_base_block, colors_per_palette, collision_tileset_offset, tileset_filename)
    if File.exist?(tileset_filename)
      ChunkyPNG::Image.from_file(tileset_filename)
    else
      render_tileset(
        pointer_to_tileset_for_layer,
        tileset_type,
        palette_pages,
        gfx_pages,
        gfx_base_block,
        colors_per_palette,
        collision_tileset_offset,
        tileset_filename
      )
    end
  end
  
  def ensure_tilesets_exist(folder, room, collision=false)
    room.layers.each do |layer|
      next if layer.layer_metadata_ram_pointer == 0 # Empty layer
      
      tileset_filename = "#{folder}/#{room.area_name}/Tilesets/#{layer.tileset_filename}.png"
      if !File.exist?(tileset_filename) && layer.tileset_pointer != 0
        render_tileset(
          layer.tileset_pointer,
          layer.tileset_type,
          room.palette_pages,
          room.gfx_pages,
          layer.gfx_base_block,
          layer.colors_per_palette,
          layer.collision_tileset_pointer,
          tileset_filename
        )
      end
      
      if collision && layer.collision_tileset_pointer != 0
        collision_tileset_filename = "#{folder}/#{room.area_name}/Tilesets/#{layer.tileset_filename}_collision.png"
        
        if !File.exist?(collision_tileset_filename)
          render_collision_tileset(layer.collision_tileset_pointer, collision_tileset_filename)
        end
      end
    end
  end
  
  def render_tileset_for_bg_layer(bg_layer, gfx_file_pointers, palette_list_pointer, first_palette_index=0)
    folder = "cache/#{GAME}/menus"
    tileset_path = "#{folder}/Tilesets/%08X.png" % bg_layer.tileset_pointer
    
    gfx_wrappers = gfx_file_pointers.map{|gfx_ptr| GfxWrapper.new(gfx_ptr, fs)}
    
    if gfx_wrappers.all?{|gfx| gfx.colors_per_palette == 256}
      colors_per_palette = 256
    else
      colors_per_palette = 16
    end
    
    if SYSTEM == :nds
      tileset = render_tileset_nds(
        bg_layer.tileset_pointer,
        bg_layer.tileset_type,
        palette_list_pointer,
        gfx_wrappers,
        colors_per_palette,
        bg_layer.collision_tileset_pointer,
        output_filename=nil,
        one_dimensional_mode: true
      )
    else
      gfx_chunks = []
      gfx_wrappers.each_with_index do |gfx_wrapper, gfx_wrapper_index|
        4.times do |i|
          gfx_chunks[gfx_wrapper_index*4+i] = [gfx_wrapper_index, i]
        end
      end
      
      gfx_base_block = 0
      
      palettes = generate_palettes(palette_list_pointer, colors_per_palette)
      palettes = palettes[first_palette_index..-1]
      
      if gfx_wrappers.any?{|gfx| gfx.colors_per_palette == 256}
        palettes_256 = generate_palettes(palette_list_pointer, 256)
        palettes_256 = palettes_256[first_palette_index..-1]
      else
        palettes_256 = []
      end
      
      tileset = render_tileset_gba(
        bg_layer.tileset_pointer,
        bg_layer.tileset_type,
        palettes,
        palettes_256,
        gfx_wrappers,
        gfx_chunks,
        gfx_base_block,
        colors_per_palette,
        bg_layer.collision_tileset_pointer,
        output_filename=nil
      )
    end
    
    FileUtils::mkdir_p(File.dirname(tileset_path))
    tileset.save(tileset_path)
    
    return tileset_path
  end
  
  def render_tileset(tileset_offset, tileset_type, palette_pages, gfx_pages, gfx_base_block, colors_per_palette, collision_tileset_offset, output_filename=nil, one_dimensional_mode: false)
    if SYSTEM == :nds
      render_room_tileset_nds(tileset_offset, tileset_type, palette_pages, gfx_pages, colors_per_palette, collision_tileset_offset, output_filename, one_dimensional_mode: one_dimensional_mode)
    else
      gfx_wrappers = []
      gfx_chunks = []
      gfx_pages.each do |gfx_page|
        gfx_wrappers << gfx_page.gfx_wrapper
        gfx_wrapper_index = gfx_wrappers.length-1
        
        gfx_page.num_chunks.times do |i|
          gfx_chunks[gfx_page.gfx_load_offset+i] = [gfx_wrapper_index, gfx_page.first_chunk_index+i]
        end
      end
      
      palettes = []
      palettes_256 = []
      palette_pages.each do |palette_page|
        next if palette_page.palette_type == 1 # Foreground palette
        
        pals_for_page = generate_palettes(palette_page.palette_list_pointer, colors_per_palette)
        palettes[palette_page.palette_load_offset, palette_page.num_palettes] = pals_for_page[palette_page.palette_index, palette_page.num_palettes]
        
        if gfx_wrappers.any?{|gfx| gfx.colors_per_palette == 256}
          pals_for_page_256 = generate_palettes(palette_page.palette_list_pointer, 256)
          palettes_256[palette_page.palette_load_offset, palette_page.num_palettes] = pals_for_page_256[palette_page.palette_index, palette_page.num_palettes]
        end
      end
      
      render_tileset_gba(tileset_offset, tileset_type, palettes, palettes_256, gfx_wrappers, gfx_chunks, gfx_base_block, colors_per_palette, collision_tileset_offset, output_filename)
    end
  end
  
  def render_room_tileset_nds(tileset_offset, tileset_type, palette_pages, gfx_pages, colors_per_palette, collision_tileset_offset, output_filename=nil, one_dimensional_mode: false)
    if palette_pages.empty?
      palette_list_pointer = nil
    else
      palette_list_pointer = palette_pages.first.palette_list_pointer
    end
    gfx_wrappers = gfx_pages.map{|gfx_page| gfx_page.gfx_wrapper}
    
    return render_tileset_nds(
      tileset_offset,
      tileset_type,
      palette_list_pointer,
      gfx_wrappers,
      colors_per_palette,
      collision_tileset_offset,
      output_filename=output_filename,
      one_dimensional_mode: one_dimensional_mode
    )
  end
  
  def render_tileset_nds(tileset_offset, tileset_type, palette_list_pointer, gfx_wrappers, colors_per_palette, collision_tileset_offset, output_filename=nil, one_dimensional_mode: false)
    rendered_tileset = ChunkyPNG::Image.new(TILESET_WIDTH_IN_TILES*16, TILESET_HEIGHT_IN_TILES*16, ChunkyPNG::Color::TRANSPARENT)
    
    if gfx_wrappers.empty?
      if output_filename
        FileUtils::mkdir_p(File.dirname(output_filename))
        rendered_tileset.save(output_filename, :fast_rgba)
      end
      return rendered_tileset
    end
    
    tileset = Tileset.new(tileset_offset, tileset_type, fs)
    palette_list = generate_palettes(palette_list_pointer, 16)
    if gfx_wrappers.any?{|gfx| gfx.colors_per_palette == 256}
      palette_list_256 = generate_palettes(palette_list_pointer, 256)
    end
    
    tileset.tiles.each_with_index do |tile, index_on_tileset|
      gfx = gfx_wrappers[tile.tile_page]
      if gfx.nil?
        next # TODO: figure out why this sometimes happens.
      end
      
      if tile.palette_index == 0xFF # TODO. 255 seems to have some special meaning besides an actual palette index.
        puts "Palette index is 0xFF, tileset #{output_filename}"
        next
      end
      
      if gfx.colors_per_palette == 16
        palette = palette_list[tile.palette_index]
      else
        palette = palette_list_256[tile.palette_index]
      end
      if palette.nil?
        puts "Palette index #{tile.palette_index} out of range, tileset #{output_filename}"
        next # TODO: figure out why this sometimes happens.
      end
      
      if one_dimensional_mode
        graphic_tile = render_16x16_graphic_tile_1_dimensional_mode(gfx, palette, tile.index_on_tile_page)
      else
        graphic_tile = render_graphic_tile(gfx, palette, tile.index_on_tile_page)
      end
      
      if tile.horizontal_flip
        graphic_tile.mirror!
      end
      if tile.vertical_flip
        graphic_tile.flip!
      end
      
      x_on_tileset = index_on_tileset % 16
      y_on_tileset = index_on_tileset / 16
      rendered_tileset.compose!(graphic_tile, x_on_tileset*16, y_on_tileset*16)
    end
    
    if output_filename
      FileUtils::mkdir_p(File.dirname(output_filename))
      rendered_tileset.save(output_filename, :fast_rgba)
    end
    return rendered_tileset
  end
  
  def render_tileset_gba(tileset_offset, tileset_type, palettes, palettes_256, gfx_wrappers, gfx_chunks, gfx_base_block, colors_per_palette, collision_tileset_offset, output_filename=nil)
    rendered_tileset = ChunkyPNG::Image.new(TILESET_WIDTH_IN_TILES*TILE_WIDTH, TILESET_HEIGHT_IN_TILES*TILE_HEIGHT, ChunkyPNG::Color::TRANSPARENT)
    
    if gfx_wrappers.empty?
      if output_filename
        FileUtils::mkdir_p(File.dirname(output_filename))
        rendered_tileset.save(output_filename, :fast_rgba)
      end
      return rendered_tileset
    end
    
    tileset = Tileset.new(tileset_offset, tileset_type, fs)
    
    tileset.tiles.each_with_index do |tile, index_on_tileset|
      rendered_tile = ChunkyPNG::Image.new(32, 32)
      minitile_x = 0
      minitile_y = 0
      tile.minitiles.each do |minitile|
        x_on_gfx_page = minitile.index_on_tile_page % 16
        y_on_gfx_page = minitile.index_on_tile_page / 16
        
        if minitile.tile_page >= gfx_wrappers.length
          rendered_minitile = ChunkyPNG::Image.new(8, 8, ChunkyPNG::Color.rgba(255, 0, 0, 255))
        else
          gfx_chunk_index_on_page = (minitile.index_on_tile_page & 0xC0) >> 6
          gfx_chunk_index = gfx_base_block*8 + minitile.tile_page*4 + gfx_chunk_index_on_page
          gfx_wrapper_index, chunk_offset = gfx_chunks[gfx_chunk_index]
          if chunk_offset.nil?
            rendered_minitile = ChunkyPNG::Image.new(8, 8, ChunkyPNG::Color.rgba(255, 0, 0, 255))
          else
            minitile_index_on_page = minitile.index_on_tile_page & 0x3F
            minitile_index_on_page += chunk_offset * 0x40
            
            gfx = gfx_wrappers[gfx_wrapper_index]
            
            if gfx.colors_per_palette == 16
              palette = palettes[minitile.palette_index]
            else
              palette = palettes_256[minitile.palette_index]
            end
            
            rendered_minitile = render_1_dimensional_minitile(gfx, palette, minitile_index_on_page)
          end
        end
        
        if minitile.horizontal_flip
          rendered_minitile.mirror!
        end
        if minitile.vertical_flip
          rendered_minitile.flip!
        end
        rendered_tile.compose!(rendered_minitile, minitile_x*8, minitile_y*8)
        minitile_x += 1
        if minitile_x > 3
          minitile_x = 0
          minitile_y += 1
        end
      end
      
      x_on_tileset = index_on_tileset % TILESET_WIDTH_IN_TILES
      y_on_tileset = index_on_tileset / TILESET_WIDTH_IN_TILES
      rendered_tileset.compose!(rendered_tile, x_on_tileset*TILE_WIDTH, y_on_tileset*TILE_HEIGHT)
    end
    
    if output_filename
      FileUtils::mkdir_p(File.dirname(output_filename))
      rendered_tileset.save(output_filename, :fast_rgba)
    end
    return rendered_tileset
  end
  
  def render_graphic_tile(gfx_page, palette, tile_index_on_page)
    x_block_on_tileset = tile_index_on_page % 8
    y_block_on_tileset = tile_index_on_page / 8
    render_gfx(gfx_page, palette, x=x_block_on_tileset*16, y=y_block_on_tileset*16, width=16, height=16)
  end
  
  def render_16x16_graphic_tile_1_dimensional_mode(gfx_page, palette, tile_index_16x16_on_page)
    x_16x16_block_on_tileset = tile_index_16x16_on_page % 8
    y_16x16_block_on_tileset = tile_index_16x16_on_page / 8
    first_minitile_index_on_page = x_16x16_block_on_tileset*2 + y_16x16_block_on_tileset*0x10*2
    
    rendered_16x16_tile = ChunkyPNG::Image.new(16, 16, ChunkyPNG::Color::TRANSPARENT)
    
    (0..1).each do |y_off|
      (0..1).each do |x_off|
        rendered_minitile = render_1_dimensional_minitile(gfx_page, palette, first_minitile_index_on_page + x_off + (y_off*0x10))
        rendered_16x16_tile.compose!(rendered_minitile, x_off*8, y_off*8)
      end
    end
    
    return rendered_16x16_tile
  end
  
  def render_gfx_page(gfx_page, palette, canvas_width=16)
    if palette.length == 16
      pixels_per_byte = 2
    elsif palette.length == 256
      pixels_per_byte = 1
    else
      raise "Unknown palette length: #{palette.length}"
    end
    
    width = canvas_width*8
    num_pixels = gfx_page.gfx_data_length * pixels_per_byte
    height = num_pixels / width
    
    render_gfx(gfx_page, palette, x=0, y=0, width=width, height=height, canvas_width=canvas_width*8)
  end
  
  def render_gfx(gfx_page, palette, x, y, width, height, canvas_width=128)
    rendered_gfx = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::TRANSPARENT)
    
    if gfx_page.nil?
      # Invalid graphics, render a red rectangle instead.
      
      rendered_gfx = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgba(255, 0, 0, 255))
      return rendered_gfx
    end
    if palette.nil?
      # Invalid palette, use a dummy palette instead.
      
      palette = generate_palettes(nil, 256).first
    end
    
    if palette.length == 16
      pixels_per_byte = 2
    elsif palette.length == 256
      pixels_per_byte = 1
    else
      raise "Unknown palette length: #{palette.length}"
    end
    
    bytes_per_full_row = canvas_width / pixels_per_byte
    bytes_per_requested_row = width / pixels_per_byte
    
    offset = y*bytes_per_full_row + x/pixels_per_byte
    (0..height-1).each do |i|
      pixels_for_chunky = []
      
      gfx_page.read_from_data(offset, bytes_per_requested_row).each_byte do |byte|
        if pixels_per_byte == 2
          pixels = [byte & 0b00001111, byte >> 4] # get the low 4 bits, then the high 4 bits (it's reversed). each is one pixel, two pixels total inside this byte.
        else
          pixels = [byte]
        end
        
        pixels.each do |pixel|
          if pixel == 0 # transparent
            pixels_for_chunky << ChunkyPNG::Color::TRANSPARENT
          else
            pixel_color = palette[pixel]
            pixels_for_chunky << pixel_color
          end
        end
      end
      
      rendered_gfx.replace_row!(i, pixels_for_chunky)
      offset += bytes_per_full_row
    end
    
    return rendered_gfx
  rescue NDSFileSystem::OffsetPastEndOfFileError
    rendered_gfx = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgba(255, 0, 0, 255))
    return rendered_gfx
  end
  
  def render_1_dimensional_minitile(gfx_page, palette, minitile_index_on_page)
    width = height = 8
    
    if gfx_page.nil?
      # Invalid graphics, render a red rectangle instead.
      
      rendered_minitile = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgba(255, 0, 0, 255))
      return rendered_minitile
    end
    if palette.nil?
      # Invalid palette, use a dummy palette instead.
      
      palette = generate_palettes(nil, 16).first
    end
    
    rendered_minitile = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::TRANSPARENT)
    
    if palette.length == 16
      pixels_per_byte = 2
    elsif palette.length == 256
      pixels_per_byte = 1
    else
      raise "Unknown palette length: #{palette.length}"
    end
    
    bytes_per_block = 8*8 / pixels_per_byte
    
    pixels_for_chunky = []
    
    offset = bytes_per_block*minitile_index_on_page
    gfx_page.read_from_data(offset, bytes_per_block).each_byte do |byte|
      if pixels_per_byte == 2
        pixels = [byte & 0b00001111, byte >> 4] # get the low 4 bits, then the high 4 bits (it's reversed). each is one pixel, two pixels total inside this byte.
      else
        pixels = [byte]
      end
      
      pixels.each do |pixel|
        if pixel == 0 # transparent
          pixels_for_chunky << ChunkyPNG::Color::TRANSPARENT
        else
          pixel_color = palette[pixel]
          pixels_for_chunky << pixel_color
        end
      end
    end
    
    pixels_for_chunky.each_with_index do |pixel, pixel_num|
      pixel_x = (pixel_num % 8)
      pixel_y = (pixel_num / 8)
      
      rendered_minitile[pixel_x, pixel_y] = pixel
    end
    
    return rendered_minitile
  end
  
  def render_gfx_1_dimensional_mode(gfx_page, palette, first_minitile_index: 0, max_num_minitiles: nil)
    if gfx_page.nil?
      # Invalid graphics, render a red rectangle instead.
      
      rendered_gfx = ChunkyPNG::Image.new(128, 128, ChunkyPNG::Color.rgba(255, 0, 0, 255))
      return rendered_gfx
    end
    if palette.nil?
      # Invalid palette, use a dummy palette instead.
      
      palette = generate_palettes(nil, 16).first
    end
    
    if palette.length == 16
      pixels_per_byte = 2
    elsif palette.length == 256
      pixels_per_byte = 1
    else
      raise "Unknown palette length: #{palette.length}"
    end
    
    bytes_per_block = 8*8 / pixels_per_byte
    
    num_minitiles = gfx_page.gfx_data.length / bytes_per_block
    if max_num_minitiles && num_minitiles > max_num_minitiles
      num_minitiles = max_num_minitiles
    end
    
    width = 128
    height = (num_minitiles+15)/16*8
    
    rendered_gfx = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::TRANSPARENT)
    
    (0..num_minitiles-1).each do |minitile_index|
      rendered_minitile = render_1_dimensional_minitile(gfx_page, palette, minitile_index+first_minitile_index)
      
      minitile_x = (minitile_index % 16) * 8
      minitile_y = (minitile_index / 16) * 8
      
      rendered_gfx.compose!(rendered_minitile, minitile_x, minitile_y)
    end
    
    return rendered_gfx
  end
  
  def generate_palettes(palette_data_start_offset, colors_per_palette)
    if palette_data_start_offset.nil?
      # Invalid palette, use a dummy palette instead.
      
      palette = [ChunkyPNG::Color.rgba(0, 0, 0, 0)] + [ChunkyPNG::Color.rgba(255, 0, 0, 255)] * (colors_per_palette-1)
      palette_list = [palette] * 128 # 128 is the maximum number of palettes
      return palette_list
    end
    
    if colors_per_palette == 256
      # color_offsets_per_palette_index: How many colors one index offsets by. This is always 16 for 16-color palettes. But for 256-color palettes it differs between HoD/AoS/DoS and PoR/OoE. In DoS one index only offsets by 16 colors, meaning you use indexes 0x00, 0x10, 0x20, etc. In PoR and OoE one index offsets by the full 256 colors, meaning you use indexes 0x00, 0x01, 0x02, etc
      color_offsets_per_palette_index = COLOR_OFFSETS_PER_256_PALETTE_INDEX
    else
      color_offsets_per_palette_index = 16
    end
    
    dummy1, unknown, number_of_palettes_rows, dummy2 = fs.read(palette_data_start_offset, 4).unpack("C*")
    if dummy1 != 0 || dummy2 != 0
      raise "Invalid palette list pointer: %08X" % palette_data_start_offset
    end
    if color_offsets_per_palette_index == 256
      number_of_palettes = (number_of_palettes_rows+15) / 16 # +15 to round upwards
    else
      number_of_palettes = number_of_palettes_rows
    end
    
    palette_data_start_offset += 4 # Skip the first 4 bytes, as they contain the length of this palette page, not the palette data itself.
    
    palette_data_end_offset = palette_data_start_offset + number_of_palettes_rows*2*16
    
    palette_list = []
    (0..number_of_palettes-1).each do |palette_index|
      specific_palette_pointer = palette_data_start_offset + (2*color_offsets_per_palette_index)*palette_index
      
      # Don't read past the end of the palette list.
      num_colors_to_read = colors_per_palette
      remaining_num_colors = (palette_data_end_offset - specific_palette_pointer) / 2
      if num_colors_to_read > remaining_num_colors
        num_colors_to_read = remaining_num_colors
      end
      
      palette = read_single_palette(specific_palette_pointer, num_colors_to_read)
      
      # If we need more colors to finish a 256 color palette, use a dummy bright red color to fill in the blanks.
      if num_colors_to_read < colors_per_palette
        palette += [ChunkyPNG::Color.rgba(255, 0, 0, 255)]*(colors_per_palette-num_colors_to_read)
      end
      
      palette_list << palette
    end
    
    palette_list
  end
  
  def read_single_palette(specific_palette_pointer, num_colors_to_read)
    palette_data = fs.read(specific_palette_pointer, num_colors_to_read*2)
    
    palette = palette_data.unpack("v*").map do |color|
      # These two bytes hold the rgb data for the color in this format:
      # Xbbbbbgggggrrrrr
      # the X is unused.
      blue_bits   = (color & 0b0111_1100_0000_0000) >> 10
      green_bits  = (color & 0b0000_0011_1110_0000) >> 5
      red_bits    =  color & 0b0000_0000_0001_1111
      
      red = red_bits << 3
      green = green_bits << 3
      blue = blue_bits << 3
      alpha = 255
      ChunkyPNG::Color.rgba(red, green, blue, alpha)
    end
    
    return palette
  end
  
  def export_palette_to_palette_swatches_file(palette, file_path)
    image = convert_palette_to_palette_swatches_image(palette)
    image.save(file_path, :fast_rgba)
  end
  
  def convert_palette_to_palette_swatches_image(palette)
    image = ChunkyPNG::Image.new(16, palette.size/16)
    palette.each_with_index do |color, i|
      x = i % 16
      y = i / 16
      image[x,y] = color
    end
    image.resample_nearest_neighbor!(image.width*16, image.height*16) # Make the color swatches 16 by 16 instead of a single pixel.
    
    return image
  end
  
  def import_palette_from_palette_swatches_file(file_path, colors_per_palette)
    image = ChunkyPNG::Image.from_file(file_path)
    if image.width != 16*16 || image.height != colors_per_palette
      raise GFXImportError.new("The palette file #{file_path} is not the right size, it must be a palette exported by DSVEdit.\n\nIf you want to generate a palette from an arbitrary file use \"Generate palette from file(s)\" instead.")
    end
    
    colors = []
    (0..image.height-1).step(16) do |y|
      (0..image.width-1).step(16) do |x|
        color = image[x,y]
        
        # Verify that all pixels within each swatch are the same color in case the user scaled the swatches down and back up or something.
        (0..15).each do |y_within_block|
          (0..15).each do |x_within_block|
            if color != image[x+x_within_block,y+y_within_block]
              raise GFXImportError.new("The palette file #{file_path} is not a proper palette swatch exported by DSVEdit.\n\nIf you want to generate a palette from an arbitrary file use \"Generate palette from file(s)\" instead.")
            end
          end
        end
        
        colors << color
      end
    end
    if colors.size > colors_per_palette
      raise GFXImportError.new("The number of colors in this file (#{file_path}) is greater than #{colors_per_palette}. Cannot import.")
    end
    
    return colors
  end
  
  def import_palette_from_file(file_path, colors_per_palette)
    image = ChunkyPNG::Image.from_file(file_path)
    colors = [ChunkyPNG::Color::TRANSPARENT]
    image.pixels.each do |pixel|
      colors << pixel unless colors.include?(pixel)
    end
    if colors.size > colors_per_palette
      raise GFXImportError.new("The number of colors in this file (#{file_path}) is greater than #{colors_per_palette}. Cannot import.")
    end
    
    return colors
  end
  
  def import_palette_from_multiple_files(file_paths, colors_per_palette)
    colors = []
    file_paths.each do |file_path|
      colors += import_palette_from_file(file_path, colors_per_palette)
    end
    colors.uniq!
    
    if colors.size > colors_per_palette
      raise GFXImportError.new("The combined number of unique colors in these files is greater than #{colors_per_palette}. Cannot import.")
    end
    
    return colors
  end
  
  def save_palette(colors, palette_list_pointer, palette_index, colors_per_palette)
    if colors_per_palette == 256
      color_offsets_per_palette_index = COLOR_OFFSETS_PER_256_PALETTE_INDEX
    else
      color_offsets_per_palette_index = 16
    end
    
    colors = truncate_palette_to_fit_list(colors, palette_list_pointer, palette_index, colors_per_palette)
    
    specific_palette_pointer = palette_list_pointer + 4 + (2*color_offsets_per_palette_index)*palette_index
    save_palette_by_specific_palette_pointer(specific_palette_pointer, colors)
  end
  
  def save_palette_by_specific_palette_pointer(specific_palette_pointer, colors)
    new_palette_data = convert_chunky_color_list_to_palette_data(colors)
    fs.write(specific_palette_pointer, new_palette_data)
  end
  
  def truncate_palette_to_fit_list(colors, palette_list_pointer, palette_index, colors_per_palette)
    if colors_per_palette == 256
      color_offsets_per_palette_index = COLOR_OFFSETS_PER_256_PALETTE_INDEX
    else
      color_offsets_per_palette_index = 16
    end
  
    number_of_palettes_rows = fs.read(palette_list_pointer+2,1).unpack("C*").first
    number_of_colors_in_list = number_of_palettes_rows*16
    first_color_index_in_list = palette_index*color_offsets_per_palette_index
    max_allowed_colors = number_of_colors_in_list - first_color_index_in_list
    if max_allowed_colors > color_offsets_per_palette_index
      max_allowed_colors = color_offsets_per_palette_index
    end
    if max_allowed_colors < 16 || max_allowed_colors > 256
      raise "Tried to truncate palette to invalid maximum size: #{max_allowed_colors}"
    end
    if colors.length > max_allowed_colors
      colors = colors[0...max_allowed_colors]
    end
    
    return colors
  end
  
  def convert_chunky_color_list_to_palette_data(chunky_colors)
    game_colors = []
    chunky_colors.each do |chunky_color|
      red = ChunkyPNG::Color.r(chunky_color)
      green = ChunkyPNG::Color.g(chunky_color)
      blue = ChunkyPNG::Color.b(chunky_color)
      
      red_bits   = red >> 3
      green_bits = green >> 3
      blue_bits  = blue >> 3
      
      bits = (blue_bits << 10) | (green_bits << 5) | red_bits
      
      game_colors << bits
    end
    
    return game_colors.pack("v*")
  end
  
  # Limits an image to a given palette in a way that looks good.
  def convert_image_to_palette(image, palette)
    new_image = ChunkyPNG::Image.new(image.width, image.height)
    
    image.width.times do |x|
      image.height.times do |y|
        old_color = image[x,y]
        new_color = get_nearest_color(old_color, palette)
        
        new_image[x,y] = new_color
      end
    end
    
    return new_image
  end
  
  # Picks a color from a palette that is visually the closest to the given color.
  # Based off Aseprite's code: https://github.com/aseprite/aseprite/blob/cc7bde6cd1d9ab74c31ccfa1bf41a000150a1fb2/src/doc/palette.cpp#L226-L272
  def get_nearest_color(color, palette)
    if palette.include?(color)
      return color
    end
    if (color & 0xFF) == 0 # Transparent
      return palette[0]
    end
    
    min_dist = Float::INFINITY
    value = nil
    
    col_diff_g = []
    col_diff_r = []
    col_diff_b = []
    col_diff_a = []
    128.times do |i|
      col_diff_g[i] = 0
      col_diff_r[i] = 0
      col_diff_b[i] = 0
      col_diff_a[i] = 0
    end
    (1..63).each do |i|
      k = i*i
      col_diff_g[i] = col_diff_g[128-i] = k * 59 * 59
      col_diff_r[i] = col_diff_r[128-i] = k * 30 * 30
      col_diff_b[i] = col_diff_b[128-i] = k * 11 * 11
      col_diff_a[i] = col_diff_a[128-i] = k * 8 * 8
    end
    
    palette.each do |indexed_color|
      r1 = ChunkyPNG::Color.r(color)         >> 3
      r2 = ChunkyPNG::Color.r(indexed_color) >> 3
      g1 = ChunkyPNG::Color.g(color)         >> 3
      g2 = ChunkyPNG::Color.g(indexed_color) >> 3
      b1 = ChunkyPNG::Color.b(color)         >> 3
      b2 = ChunkyPNG::Color.b(indexed_color) >> 3
      a1 = ChunkyPNG::Color.a(color)         >> 3
      a2 = ChunkyPNG::Color.a(indexed_color) >> 3
      
      coldiff = col_diff_g[g2 - g1 & 127]
      if coldiff < min_dist
        coldiff += col_diff_r[r2 - r1 & 127]
        if coldiff < min_dist
          coldiff += col_diff_b[b2 - b1 & 127]
          if coldiff < min_dist
            coldiff += col_diff_a[a2 - a1 & 127]
            if coldiff < min_dist
              min_dist = coldiff
              value = indexed_color
            end
          end
        end
      end
    end
    
    return value
  end
  
  # Checks whether all the colors in a given image are within a given palette.
  def check_image_uses_palette(input_image, palette_list_pointer, colors_per_palette, palette_index)
    colors = generate_palettes(palette_list_pointer, colors_per_palette)[palette_index]
    colors[0] = ChunkyPNG::Color::TRANSPARENT
    
    colors = colors.map{|color| color & 0b11111000111110001111100011111111} # Get rid of unnecessary bits so equality checks work correctly.
    
    input_image.pixels.each_with_index do |pixel, i|
      if pixel & 0xFF == 0 # Transparent
        # Do nothing
      else
        pixel &= 0b11111000111110001111100011111111
        color_index = colors.index(pixel)
        
        if color_index.nil?
          return false
        end
      end
    end
    
    return true
  end
  
  def save_gfx_page(input_image, gfx, palette_list_pointer, colors_per_palette, palette_index, should_convert_image_to_palette: false)
    if input_image.width != input_image.height || ![128, 256].include?(input_image.width)
      raise GFXImportError.new("Invalid image size. Image must be 128x128 or 256x256.")
    end
    
    colors = generate_palettes(palette_list_pointer, colors_per_palette)[palette_index]
    colors[0] = ChunkyPNG::Color::TRANSPARENT
    
    colors = colors.map{|color| color & 0b11111000111110001111100011111111} # Get rid of unnecessary bits so equality checks work correctly.
    
    if should_convert_image_to_palette
      input_image = convert_image_to_palette(input_image, colors)
    end
    
    gfx_data_bytes = []
    input_image.pixels.each_with_index do |pixel, i|
      if pixel & 0xFF == 0 # Transparent
        color_index = 0
      else
        pixel &= 0b11111000111110001111100011111111
        color_index = colors.index(pixel)
        
        if color_index.nil?
          raise GFXImportError.new("The imported image uses different colors than the existing palette. Cannot import.")
        end
        if color_index < 0 || color_index > colors_per_palette-1
          raise GFXImportError.new("Invalid color (this error shouldn't happen)")
        end
      end
      
      if i.even? || colors_per_palette == 256
        gfx_data_bytes << color_index
      else
        gfx_data_bytes[-1] = (gfx_data_bytes[-1] | color_index << 4)
      end
    end
    
    gfx.write_gfx_data(gfx_data_bytes.pack("C*"))
    
    gfx.canvas_width = input_image.width/8
    gfx.write_to_rom()
  end
  
  def save_gfx_page_1_dimensional_mode(input_image, gfx, palette_list_pointer, colors_per_palette, palette_index, should_convert_image_to_palette: false)
    colors = generate_palettes(palette_list_pointer, colors_per_palette)[palette_index]
    colors[0] = ChunkyPNG::Color::TRANSPARENT
    
    colors = colors.map{|color| color & 0b11111000111110001111100011111111} # Get rid of unnecessary bits so equality checks work correctly.
    
    if should_convert_image_to_palette
      input_image = convert_image_to_palette(input_image, colors)
    end
    
    if gfx.colors_per_palette == 16
      pixels_per_byte = 2
    elsif gfx.colors_per_palette == 256
      pixels_per_byte = 1
    else
      raise "Unknown colors per palette: #{gfx.colors_per_palette}"
    end
    bytes_per_block = 8*8 / pixels_per_byte
    num_minitiles = gfx.gfx_data.length / bytes_per_block
    
    gfx_data_bytes = []
    (0..num_minitiles-1).each do |block_num|
      (0..64-1).each do |pixel_num|
        block_x = (block_num % 16) * 8
        block_y = (block_num / 16) * 8
        pixel_x = (pixel_num % 8) + block_x
        pixel_y = (pixel_num / 8) + block_y
        
        pixel = input_image[pixel_x,pixel_y]
        
        if pixel & 0xFF == 0 # Transparent
          color_index = 0
        else
          pixel &= 0b11111000111110001111100011111111
          color_index = colors.index(pixel)
          
          if color_index.nil?
            raise GFXImportError.new("The imported image uses different colors than the existing palette. Cannot import.")
          end
          if color_index < 0 || color_index > colors_per_palette-1
            raise GFXImportError.new("Invalid color (this error shouldn't happen)")
          end
        end
        
        if pixel_num.even? || colors_per_palette == 256
          gfx_data_bytes << color_index
        else
          gfx_data_bytes[-1] = (gfx_data_bytes[-1] | color_index << 4)
        end
      end
    end
    
    gfx.write_gfx_data(gfx_data_bytes.pack("C*"))
  end
  
  def render_collision_tileset(collision_tileset_offset, output_filename=nil)
    if output_filename && File.exist?(output_filename)
      return ChunkyPNG::Image.from_file(output_filename)
    end
    
    collision_tileset = CollisionTileset.new(collision_tileset_offset, fs)
    rendered_tileset = ChunkyPNG::Image.new(TILESET_WIDTH_IN_TILES*TILE_WIDTH, TILESET_HEIGHT_IN_TILES*TILE_HEIGHT, ChunkyPNG::Color::TRANSPARENT)
    
    if SYSTEM == :nds
      collision_tileset.tiles.each_with_index do |tile, index_on_tileset|
        graphic_tile = render_collision_tile(tile)
        
        x_on_tileset = index_on_tileset % TILESET_WIDTH_IN_TILES
        y_on_tileset = index_on_tileset / TILESET_WIDTH_IN_TILES
        rendered_tileset.compose!(graphic_tile, x_on_tileset*16, y_on_tileset*16)
      end
    else
      tileset_width = 16*4
      collision_tileset.tiles.each_slice(16).each_with_index do |big_tile, index_on_tileset|
        x_on_tileset = index_on_tileset % TILESET_WIDTH_IN_TILES
        y_on_tileset = index_on_tileset / TILESET_WIDTH_IN_TILES
        
        minitile_x = 0
        minitile_y = 0
        big_tile.each_with_index do |minitile|
          graphic_tile = render_collision_tile(minitile)
          
          x = x_on_tileset*4 + minitile_x
          y = y_on_tileset*4 + minitile_y
          rendered_tileset.compose!(graphic_tile, x*8, y*8)
          
          minitile_x += 1
          if minitile_x > 3
            minitile_x = 0
            minitile_y += 1
          end
        end
      end
    end
    
    if output_filename
      FileUtils::mkdir_p(File.dirname(output_filename))
      rendered_tileset.save(output_filename, :fast_rgba)
      #puts "Wrote #{output_filename}"
    end
    return rendered_tileset
  end
  
  def render_collision_tile(tile)
    color = COLLISION_SOLID_COLOR
    bg_color = ChunkyPNG::Color::TRANSPARENT
    if tile.is_water
      if tile.is_slope?
        if tile.has_top
          bg_color = COLLISION_WATER_COLOR
        else
          # Water slopes with no top are water slopes instead of solid slopes, so they don't have water in the background.
          bg_color = ChunkyPNG::Color::TRANSPARENT
          color = COLLISION_WATER_COLOR
        end
      else
        bg_color = COLLISION_WATER_COLOR
      end
    elsif tile.is_damage?
      bg_color = COLLISION_DAMAGE_COLOR
    end
    graphic_tile = ChunkyPNG::Image.new(16, 16, bg_color)
    
    case tile.block_shape
    when 0..1
      # Full block.
      if tile.has_top && tile.has_sides_and_bottom
        graphic_tile.rect(0, 0, 15, 15, stroke_color = color, fill_color = color)
      elsif tile.has_top
        graphic_tile.rect(0, 0, 15, 15, stroke_color = color, fill_color = COLLISION_SEMISOLID_COLOR)
          
        # Add an upwards pointing arrow for jumpthrough platforms.
        graphic_tile.polygon([3, 7, 7, 3, 8, 3, 12, 7, 8, 7, 8, 12, 7, 12, 7, 7], stroke_color = color, fill_color = color)
      elsif tile.has_sides_and_bottom
        graphic_tile.polygon([0, 0, 7, 7, 15, 0, 15, 15, 0, 15], stroke_color = color, fill_color = color)
      end
    when 2
      # Half-height block (top half).
      if tile.is_conveyor_left?
        if tile.has_top && tile.has_sides_and_bottom
          graphic_tile.rect(0, 0, 15, 15, stroke_color = color, fill_color = color)
          graphic_tile.polygon([10, 1, 4, 7, 4, 8, 10, 14], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        elsif tile.has_top
          graphic_tile.rect(0, 0, 15, 7, stroke_color = color, fill_color = COLLISION_SEMISOLID_COLOR)
          graphic_tile.polygon([5, 1, 3, 3, 3, 4, 5, 6, 5, 4, 12, 4, 12, 3, 5, 3], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        else
          graphic_tile.polygon([10, 1, 4, 7, 4, 8, 10, 14], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        end
      else
        if tile.has_top && tile.has_sides_and_bottom
          graphic_tile.rect(0, 0, 15, 7, stroke_color = color, fill_color = color)
        elsif tile.has_top
          graphic_tile.rect(0, 0, 15, 7, stroke_color = color, fill_color = COLLISION_SEMISOLID_COLOR)
          
          # Add an upwards pointing arrow for jumpthrough platforms.
          graphic_tile.polygon([4, 4, 7, 1, 8, 1, 11, 4, 8, 4, 8, 6, 7, 6, 7, 4], stroke_color = color, fill_color = color)
        elsif tile.has_sides_and_bottom
          graphic_tile.polygon([0, 0, 7, 3, 15, 0, 15, 7, 0, 7], stroke_color = color, fill_color = color)
        end
      end
    when 3
      # Half-height block (bottom half).
      if tile.is_conveyor_right?
        if tile.has_top && tile.has_sides_and_bottom
          graphic_tile.rect(0, 0, 15, 15, stroke_color = color, fill_color = color)
          graphic_tile.polygon([5, 1, 11, 7, 11, 8, 5, 14], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        elsif tile.has_top
          graphic_tile.rect(0, 0, 15, 7, stroke_color = color, fill_color = COLLISION_SEMISOLID_COLOR)
          graphic_tile.polygon([10, 1, 12, 3, 12, 4, 10, 6, 10, 4, 3, 4, 3, 3, 10, 3], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        else
          graphic_tile.polygon([5, 1, 11, 7, 11, 8, 5, 14], stroke_color = COLLISION_CONVEYOR_COLOR, fill_color = COLLISION_CONVEYOR_COLOR)
        end
      else
        if tile.has_top && tile.has_sides_and_bottom
          graphic_tile.rect(0, 8, 15, 15, stroke_color = color, fill_color = color)
        elsif tile.has_top
          graphic_tile.rect(0, 8, 15, 15, stroke_color = color, fill_color = COLLISION_SEMISOLID_COLOR)
          
          # Add an upwards pointing arrow for jumpthrough platforms.
          graphic_tile.polygon([4, 12, 7, 9, 8, 9, 11, 12, 8, 12, 8, 14, 7, 14, 7, 12], stroke_color = color, fill_color = color)
        elsif tile.has_sides_and_bottom
          graphic_tile.polygon([0, 8, 7, 8+3, 15, 8, 15, 15, 0, 15], stroke_color = color, fill_color = color)
        end
      end
    when 4..15
      # Slope.
      case tile.block_shape
      when 4
        width = 16
        x_offset = 0
      when 8, 10
        width = 2*16
        x_offset = (tile.block_shape-8)*8
      when 12..15
        width = 4*16
        x_offset = (tile.block_shape-12)*16
      else
        puts "Unknown block shape: #{tile.block_shape}"
        graphic_tile.rect(1, 1, 14, 14, stroke_color = color, fill_color = ChunkyPNG::Color.rgba(0, 255, 0, 255))
        if SYSTEM == :gba
          graphic_tile = graphic_tile.resize(8, 8)
        end
        return graphic_tile
      end
      
      if tile.vertical_flip
        x_end = width-1
        y_end = 0
      else
        x_end = 0
        y_end = 15
      end
      
      graphic_tile.polygon([0-x_offset, 0, width-1-x_offset, 15, x_end-x_offset, y_end], stroke_color = color, fill_color = color)
      if tile.horizontal_flip
        graphic_tile.mirror!
      end
    end
    
    if SYSTEM == :gba
      graphic_tile = graphic_tile.resize(8, 8)
    end
    
    return graphic_tile
  end
  
  def render_map(map, scale = 1, hardcoded_transition_rooms=[], color_code_regions: false)
    if map.tiles.any?
      map_width_in_blocks = map.tiles.map{|tile| tile.x_pos}.max + 1
      map_height_in_blocks = map.tiles.map{|tile| tile.y_pos}.max + 1
    else
      map_width_in_blocks = map_height_in_blocks = 0
    end
    map_image_width = map_width_in_blocks*4 + 1
    map_image_height = map_height_in_blocks*4 + 1
    fill_img = ChunkyPNG::Image.new(map_image_width, map_image_height, ChunkyPNG::Color::TRANSPARENT)
    lines_img = ChunkyPNG::Image.new(map_image_width, map_image_height, ChunkyPNG::Color::TRANSPARENT)
    
    # 25 pixels per tile. But they overlap, so the left and top of a tile overlaps the right and bottom of other tiles.
    map.tiles.each do |tile|
      if tile.is_blank && !tile.left_door && !tile.left_wall && !tile.top_door && !tile.top_wall && !tile.right_door && !tile.right_wall && !tile.bottom_door && !tile.bottom_wall
        next
      end
      
      fill_tile, lines_tile = render_map_tile(tile, hardcoded_transition_rooms=hardcoded_transition_rooms, color_code_regions: color_code_regions)
      
      fill_img.compose!(fill_tile, tile.x_pos*4, tile.y_pos*4)
      lines_img.compose!(lines_tile, tile.x_pos*4, tile.y_pos*4)
    end
    
    img = fill_img
    img.compose!(lines_img, 0, 0)
    unless scale == 1
      img.resample_nearest_neighbor!(map_image_width*scale, map_image_height*scale)
    end
    
    return img
  end
  
  def render_map_tile(tile, hardcoded_transition_rooms=[], color_code_regions: false)
    @fill_color            ||= ChunkyPNG::Color.rgba(*MAP_FILL_COLOR)
    @save_fill_color       ||= ChunkyPNG::Color.rgba(*MAP_SAVE_FILL_COLOR)
    @warp_fill_color       ||= ChunkyPNG::Color.rgba(*MAP_WARP_FILL_COLOR)
    @secret_fill_color     ||= ChunkyPNG::Color.rgba(*MAP_SECRET_FILL_COLOR)
    @entrance_fill_color   ||= ChunkyPNG::Color.rgba(*MAP_ENTRANCE_FILL_COLOR)
    @transition_fill_color ||= ChunkyPNG::Color.rgba(0, 0, 0, 255)
    @line_color            ||= ChunkyPNG::Color.rgba(*MAP_LINE_COLOR)
    @door_color            ||= ChunkyPNG::Color.rgba(*MAP_DOOR_COLOR)
    @door_center_color     ||= ChunkyPNG::Color.rgba(*MAP_DOOR_CENTER_PIXEL_COLOR)
    @secret_door_color     ||= ChunkyPNG::Color.rgba(*MAP_SECRET_DOOR_COLOR)
    if GAME == "hod"
      @warp_castle_b_fill_color     ||= ChunkyPNG::Color.rgba(*MAP_CASTLE_B_WARP_FILL_COLOR)
      @warp_both_castles_fill_color ||= ChunkyPNG::Color.rgba(*MAP_BOTH_CASTLES_WARP_FILL_COLOR)
    end
  
    @wall_pixels           ||= [line_color]*5
    @door_pixels           ||= [line_color, door_color, door_center_color, door_color, line_color]
    @secret_door_pixels    ||= [line_color, secret_door_color, secret_door_color, secret_door_color, line_color]
    
    is_hardcoded_transition = false
    hardcoded_transition_rooms.each do |room|
      if ["dos", "aos"].include?(GAME) && tile.sector_index == room.sector_index && tile.room_index == room.room_index
        is_hardcoded_transition = true
        break
      end
    end
    
    color = if tile.is_blank
      ChunkyPNG::Color::TRANSPARENT
    elsif GAME == "hod" && color_code_regions
      region_color_string = [
        "ac3232",
        "d77bba",
        "df7126",
        "f7f068",
        "6abe30",
        "37946e",
        "3f3f74",
        "5b6ee1",
        "5fcde4",
        "76428a",
        "8f974a",
        "d9a066",
        "663931",
      ][tile.region_index]
      ChunkyPNG::Color.from_hex(region_color_string)
    elsif tile.is_transition || is_hardcoded_transition
      transition_fill_color
    elsif tile.is_entrance
      entrance_fill_color
    elsif tile.is_warp && tile.is_castle_b_warp
      warp_both_castles_fill_color
    elsif tile.is_warp
      warp_fill_color
    elsif tile.is_castle_b_warp
      warp_castle_b_fill_color
    elsif tile.is_secret
      secret_fill_color
    elsif tile.is_save
      save_fill_color
    else
      fill_color
    end
    
    fill_tile = ChunkyPNG::Image.new(5, 5, color)
    lines_tile = ChunkyPNG::Image.new(5, 5, ChunkyPNG::Color::TRANSPARENT)
    
    if tile.left_secret
      lines_tile.replace_column!(0, secret_door_pixels)
    elsif tile.left_wall
      lines_tile.replace_column!(0, wall_pixels)
    elsif tile.left_door
      lines_tile.replace_column!(0, door_pixels)
    end
    
    if tile.right_secret
      lines_tile.replace_column!(4, secret_door_pixels)
    elsif tile.right_wall
      lines_tile.replace_column!(4, wall_pixels)
    elsif tile.right_door
      lines_tile.replace_column!(4, door_pixels)
    end
    
    if tile.top_secret
      lines_tile.replace_row!(0, secret_door_pixels)
    elsif tile.top_wall
      lines_tile.replace_row!(0, wall_pixels)
    elsif tile.top_door
      lines_tile.replace_row!(0, door_pixels)
    end
    
    if tile.bottom_secret
      lines_tile.replace_row!(4, secret_door_pixels)
    elsif tile.bottom_wall
      lines_tile.replace_row!(4, wall_pixels)
    elsif tile.bottom_door
      lines_tile.replace_row!(4, door_pixels)
    end
    
    return [fill_tile, lines_tile]
  end
  
  def ensure_sprite_exists(folder, sprite_info, frame_to_render)
    sprite_filename = "%08X %08X %08X %02X" % [sprite_info.sprite.sprite_pointer, sprite_info.gfx_file_pointers.first, sprite_info.palette_pointer, sprite_info.palette_offset]
    output_path = "#{folder}/#{sprite_filename}_frame#{frame_to_render}.png"
    
    if !File.exist?(output_path)
      FileUtils::mkdir_p(File.dirname(output_path))
      rendered_frames, _ = render_sprite(sprite_info, frame_to_render: frame_to_render)
      rendered_frames.first.save(output_path, :fast_rgba)
      #puts "Wrote #{output_path}"
    end
    
    return output_path
  end
  
  def render_sprite(sprite_info, frame_to_render: :all, render_hitboxes: false, override_part_palette_index: nil, one_dimensional_mode: false, transparent_trails: false)
    gfx_pages = sprite_info.gfx_pages
    palette_pointer = sprite_info.palette_pointer
    palette_offset = sprite_info.palette_offset
    sprite = sprite_info.sprite
    
    if SYSTEM == :gba
      one_dimensional_mode = true
    end
    
    gfx_with_blanks = []
    gfx_pages.each do |gfx|
      gfx_with_blanks << gfx
      blanks_needed = (gfx.canvas_width/0x10 - 1) * 3
      gfx_with_blanks += [nil]*blanks_needed
    end
    
    if gfx_with_blanks.first.render_mode == 1
      palettes = generate_palettes(palette_pointer, 16)
      dummy_palette = generate_palettes(nil, 16).first
    elsif gfx_with_blanks.first.render_mode == 2
      palettes = generate_palettes(palette_pointer, 256)
      dummy_palette = generate_palettes(nil, 256).first
    else
      raise "Unknown render mode: #{gfx_with_blanks.first.render_mode}"
    end
    
    rendered_gfx_files_by_palette = Hash.new{|h, k| h[k] = {}}
    
    rendered_parts = {}
    
    if frame_to_render == :all
      frames = sprite.frames
    elsif frame_to_render
      frame = sprite.frames[frame_to_render]
      if frame.nil?
        raise "Invalid frame to render: #{frame_to_render}"
      end
      frames = [frame]
    else
      frames = []
    end
    
    parts_and_hitboxes = (sprite.parts + sprite.hitboxes)
    min_x = parts_and_hitboxes.map{|item| item.x_pos}.min
    min_y = parts_and_hitboxes.map{|item| item.y_pos}.min
    max_x = parts_and_hitboxes.map{|item| item.x_pos + item.width}.max
    max_y = parts_and_hitboxes.map{|item| item.y_pos + item.height}.max
    full_width = max_x - min_x
    full_height = max_y - min_y
    
    sprite.parts.each_with_index do |part, part_index|
      part_palette_index = part.palette_index
      if transparent_trails && part_palette_index != 0
        part_palette_index = 0
        transparent_part = true
      else
        transparent_part = false
      end
      
      part_gfx_page_index = part.gfx_page_index
      if sprite_info.ignore_part_gfx_page
        part_gfx_page_index = 0
      end
      
      if part_gfx_page_index >= gfx_with_blanks.length
        puts "GFX page index too large (#{part_gfx_page_index+1} pages needed, have #{gfx_with_blanks.length})"
        
        # Invalid gfx page index, so just render a big red square.
        first_canvas_width = gfx_with_blanks.first.canvas_width
        rendered_gfx_files_by_palette[part_palette_index+palette_offset][part_gfx_page_index] ||= render_gfx(nil, nil, 0, 0, first_canvas_width*8, first_canvas_width*8, canvas_width=first_canvas_width*8)
      else
        gfx_page = gfx_with_blanks[part_gfx_page_index]
        canvas_width = gfx_page.canvas_width
        if override_part_palette_index
          # For weapons (which always use the first palette) and skeletally animated enemies (which have their palette specified in the skeleton file).
          palette = palettes[override_part_palette_index+palette_offset]
        else
          palette = palettes[part_palette_index+palette_offset]
        end
        
        rendered_gfx_files_by_palette[part_palette_index+palette_offset][part_gfx_page_index] ||= begin
          if one_dimensional_mode
            rendered_gfx_file = render_gfx_1_dimensional_mode(gfx_page, palette || dummy_palette)
          else
            rendered_gfx_file = render_gfx(gfx_page, palette || dummy_palette, 0, 0, canvas_width*8, canvas_width*8, canvas_width=canvas_width*8)
          end
          
          if rendered_gfx_file.height < 128
            # One of those partial GFX pages from AoS. We pad it to 128px tall so parts that go past the bottom don't cause errors.
            padded_gfx_file = ChunkyPNG::Image.new(128, 128)
            padded_gfx_file.compose!(rendered_gfx_file)
            rendered_gfx_file = padded_gfx_file
          end
          
          rendered_gfx_file
        end
      end
      
      rendered_gfx_file = rendered_gfx_files_by_palette[part_palette_index+palette_offset][part_gfx_page_index]
      rendered_parts[part_index] ||= render_sprite_part(part, rendered_gfx_file)
      if transparent_part
        # Transparent trails require us to go through all pixels and change their opacity to 0xC/0x1F.
        rendered_parts[part_index].width.times do |x|
          rendered_parts[part_index].height.times do |y|
            color = rendered_parts[part_index][x,y]
            next if ChunkyPNG::Color.fully_transparent?(color)
            transparent_color = ChunkyPNG::Color.rgba(ChunkyPNG::Color.r(color), ChunkyPNG::Color.g(color), ChunkyPNG::Color.b(color), 96)
            rendered_parts[part_index][x,y] = transparent_color
          end
        end
      end
    end
    
    hitbox_color = ChunkyPNG::Color.rgba(255, 0, 0, 128)
    rendered_frames = []
    frames.each do |frame|
      rendered_frame = ChunkyPNG::Image.new(full_width, full_height, ChunkyPNG::Color::TRANSPARENT)

      frame.part_indexes.reverse.each do |part_index|
        part = sprite.parts[part_index]
        part_gfx = rendered_parts[part_index]
        
        x = part.x_pos - min_x
        y = part.y_pos - min_y
        rendered_frame.compose!(part_gfx, x, y)
      end
      
      if render_hitboxes
        puts frame.hitboxes.size
        frame.hitboxes.each do |hitbox|
          x = hitbox.x_pos - min_x
          y = hitbox.y_pos - min_y
          rendered_frame.rect(x, y, x + hitbox.width, y + hitbox.height, stroke_color = hitbox_color, fill_color = ChunkyPNG::Color::TRANSPARENT)
        end
      end
      
      rendered_frames << rendered_frame
    end
    
    return [rendered_frames, min_x, min_y, rendered_parts, gfx_with_blanks, palettes, full_width, full_height]
  end
  
  def render_sprite_part(part, rendered_gfx_file)
    gfx_x_offset = part.gfx_x_offset
    gfx_y_offset = part.gfx_y_offset
    width = part.width
    height = part.height
    
    if SYSTEM == :gba
      gfx_x_offset = (gfx_x_offset / 8) * 8
      gfx_y_offset = (gfx_y_offset / 8) * 8
    end
    
    # Clamp the part width/height so it doesn't go past the bounds of a GFX page.
    width = [width, rendered_gfx_file.width-gfx_x_offset].min
    height = [height, rendered_gfx_file.height-gfx_y_offset].min
    
    part_gfx = rendered_gfx_file.crop(gfx_x_offset, gfx_y_offset, width, height)
    if part.horizontal_flip
      part_gfx.mirror!
    end
    if part.vertical_flip
      part_gfx.flip!
    end
    
    return part_gfx
  end
  
  def nil_image_if_invisible(image)
    invisible = image.palette.all? do |color|
      ChunkyPNG::Color.fully_transparent?(color)
    end
    
    if invisible
      nil
    else
      image
    end
  end
  
  def render_icon_by_item(item, mode=:item)
    icon_index, palette_index = GenericEditable.extract_icon_index_and_palette_index(item["Icon"])
    
    render_icon(icon_index, palette_index, mode)
  end
  
  def render_icon(icon_index, palette_index, mode=:item)
    icon_width = mode == :item ? 16 : 32
    icon_height = icon_width
    icons_per_row = 128 / icon_width
    icons_per_column = 128 / icon_height
    icons_per_page = 128*128 / icon_width / icon_width
    
    gfx_page_index = icon_index / icons_per_page
    
    palette_pointer = mode == :item ? ITEM_ICONS_PALETTE_POINTER : GLYPH_ICONS_PALETTE_POINTER
    palettes = generate_palettes(palette_pointer, 16)
    palette = palettes[palette_index]
    
    gfx_page = icon_gfx_pages(mode)[gfx_page_index]
    
    if mode == :item
      gfx_page_image = render_gfx_1_dimensional_mode(gfx_page, palette)
    else
      gfx_page_image = render_gfx_page(gfx_page, palette)
    end
    
    x_pos = ((icon_index % icons_per_page) % icons_per_row) * icon_width
    y_pos = ((icon_index % icons_per_page) / icons_per_column) * icon_height
    item_image = gfx_page_image.crop(x_pos, y_pos, icon_width, icon_height)
    
    item_image = nil_image_if_invisible(item_image)
    
    return item_image
  end
  
  def icon_gfx_pages(mode)
    gfx_pages = []
    
    if SYSTEM == :nds
      filename = mode == :item ? "item" : "rune"
      gfx_files = fs.files.values.select do |file|
        file[:file_path] =~ /\/sc\/f_#{filename}\d+\.dat/
      end
      
      gfx_files.each do |gfx_file|
        gfx_page = GfxWrapper.new(gfx_file[:asset_pointer], fs)
        gfx_pages << gfx_page
      end
    else
      ITEM_ICONS_GFX_POINTERS.each do |gfx_pointer|
        gfx_page = GfxWrapper.new(gfx_pointer, fs)
        gfx_pages << gfx_page
      end
    end
    
    gfx_pages
  end
  
  def render_font_nds(font_path, char_width, char_height)
    char_size_in_bytes = 2 + (char_width * char_height) / 8
    if REGION == :jp
      num_chars_wide = 16
      num_chars_tall = 128
    else
      num_chars_wide = 16
      num_chars_tall = 16
    end
    
    font_image = ChunkyPNG::Image.new(char_width*num_chars_wide, char_height*num_chars_tall, ChunkyPNG::Color::TRANSPARENT)
    
    file_size = fs.files_by_path[font_path][:size]
    offset = 0
    seen_chars = []
    index_in_file = 0
    while offset <= file_size-char_size_in_bytes
      char_number = fs.read_by_file(font_path, offset, 2).unpack("n").first # big endian
      pixel_data = fs.read_by_file(font_path, offset+2, char_size_in_bytes-2).unpack("C*")
      
      puts "%02X" % char_number
      if seen_chars.include?(char_number)
        # TODO hack
        puts "!%02X" % char_number
        char_number += 0xC0
      end
      
      index_on_image = index_in_file#char_number
      char_x = (index_on_image % num_chars_wide)*char_width
      char_y = (index_on_image / num_chars_wide)*char_height
      x = 0
      y = 0
      pixel_data.each do |byte|
        8.times do |i|
          if byte & (0x80 >> i) != 0
            font_image[char_x+x, char_y+y] = ChunkyPNG::Color::BLACK
          end
          x += 1
          if x == char_width
            x = 0
            y += 1
          end
        end
      end
      seen_chars << char_number
      
      index_in_file += 1
      offset += char_size_in_bytes
    end
    
    font_image.resample_nearest_neighbor!(font_image.width*4, font_image.height*4)
    
    basename = File.basename(font_path, ".*")
    font_image.save("%s.png" % basename, :fast_rgba)
  end
  
  def render_font_gba(font_address, font_data_size, char_width, char_height)
    char_size_in_bytes = 2 + (char_width * char_height) / 8
    if REGION == :jp || GAME == "hod"
      num_chars_wide = 16
      num_chars_tall = 128
    else
      num_chars_wide = 16
      num_chars_tall = 16
    end
    
    font_image = ChunkyPNG::Image.new(char_width*num_chars_wide, char_height*num_chars_tall, ChunkyPNG::Color::TRANSPARENT)
    
    offset = 0
    seen_chars = []
    index_in_file = 0
    while offset <= font_data_size-char_size_in_bytes
      char_number = fs.read(font_address+offset+char_size_in_bytes-2, 2).unpack("n").first # big endian
      pixel_data = fs.read(font_address+offset, char_size_in_bytes-2).unpack("C*")
      
      puts "%02X" % char_number
      
      index_on_image = index_in_file#char_number
      char_x = (index_on_image % num_chars_wide)*char_width
      char_y = (index_on_image / num_chars_wide)*char_height
      x = 0
      y = 0
      pixel_data.each do |byte|
        8.times do |i|
          if byte & (0x80 >> i) != 0
            font_image[char_x+x, char_y+y] = ChunkyPNG::Color::BLACK
          end
          x += 1
          if x == char_width
            x = 0
            y += 1
          end
        end
      end
      seen_chars << char_number
      
      index_in_file += 1
      offset += char_size_in_bytes
    end
    
    font_image.resample_nearest_neighbor!(font_image.width*4, font_image.height*4)
    
    basename = "%08X" % font_address
    font_image.save("%s.png" % basename, :fast_rgba)
  end
  
  def inspect; to_s; end
end
