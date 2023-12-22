
class PaletteWrapper
  attr_accessor :palette_wrapper_pointer,
                :palette_list_pointer,
                :fs,
                :palette_index,
                :num_palettes,
                :palette_load_offset,
                :unknown_2,
                :palette_type
              
  def initialize(fs)
    @fs = fs
  end
  
  def read(palette_wrapper_pointer)
    @palette_wrapper_pointer = palette_wrapper_pointer
    
    if GAME == "hod"
      @palette_type, @palette_wrapper_info, @palette_list_pointer = fs.read(palette_wrapper_pointer, 8).unpack("vvV")
      if @palette_type == 0 # Background palette
        @palette_load_offset = 0
        @palette_index = 0
        num_palettes_in_list = fs.read(palette_list_pointer+2, 1).unpack("C").first
        @num_palettes = [0xD, num_palettes_in_list].min
      else # Foreground palette
        @num_palettes = 2
        @palette_index = (@palette_wrapper_info & 0xFF00) >> 8
        @palette_load_offset = @palette_wrapper_info & 0xF
      end
    else
      @palette_list_pointer, @palette_load_offset, @palette_index, @num_palettes, @unknown_2 = fs.read(palette_wrapper_pointer, 8).unpack("VCCCC")
    end
  end
  
  def to_data
    if GAME == "hod"
      [
        palette_type,
        @palette_wrapper_info,
        palette_list_pointer,
      ].pack("vvV")
    else
      [
        palette_list_pointer,
        palette_load_offset,
        palette_index,
        num_palettes,
        unknown_2,
      ].pack("VCCCC")
    end
  end
  
  def self.data_size
    8
  end
  
  def self.from_palette_wrapper_pointer(palette_wrapper_list_pointer, fs)
    offset = palette_wrapper_list_pointer
    palette_wrappers = []
    while true
      if GAME == "hod"
        palette_list_pointer = fs.read(offset+4, 4).unpack("V").first
      else
        palette_list_pointer = fs.read(offset, 4).unpack("V").first
      end
      break if palette_list_pointer == 0
      
      palette_wrapper = PaletteWrapper.new(fs)
      palette_wrapper.read(offset)
      palette_wrappers << palette_wrapper
      
      offset += 8
    end
    
    return palette_wrappers
  end
end
