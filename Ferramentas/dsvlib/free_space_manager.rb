
module FreeSpaceManager
  class FreeSpaceFindError < StandardError ; end
  
  attr_reader :free_spaces
  
  def read_free_space_from_text_file
    @free_spaces = []
    @changes_in_current_free_space_batch = nil
    
    if SYSTEM == :nds
      initialize_sector_overlay_free_spaces()
    end
    
    if @filesystem_directory.nil?
      return
    end
    
    freespace_file = File.join(@filesystem_directory, "_dsvedit_freespace.txt")
    if !File.file?(freespace_file)
      if SYSTEM == :gba
        initialize_rom_free_space()
      end
      
      return
    end
    
    file_contents = File.read(freespace_file)
    free_space_strs = file_contents.scan(/^(\h+) (\h+) (\S+)$/)
    free_space_strs.each do |offset, length, path|
      offset = offset.to_i(16)
      length = length.to_i(16)
      if path == "rom.gba"
        path = "/rom.gba"
      end
      @free_spaces << {path: path, offset: offset, length: length}
    end
    
    merge_overlapping_free_spaces()
    
    remove_fake_free_spaces()
    
    round_free_spaces()
  end
  
  def initialize_sector_overlay_free_spaces
    ROOM_OVERLAYS.each do |overlay_id|
      overlay = overlays[overlay_id]
      length = MAX_ALLOWABLE_ROOM_OVERLAY_SIZE - overlay[:size]
      next if length == 0
      
      offset = overlay[:size]
      path = overlay[:file_path]
      
      @free_spaces << {path: path, offset: offset, length: length}
    end
    
    remove_fake_free_spaces()
    
    round_free_spaces()
  end
  
  def initialize_rom_free_space
    @free_spaces << {path: "/rom.gba", offset: ROM_FREE_SPACE_START, length: ROM_FREE_SPACE_SIZE}
    
    remove_fake_free_spaces()
    
    round_free_spaces()
  end
  
  def remove_fake_free_spaces
    FAKE_FREE_SPACES.each do |fake_space|
      remove_free_space(fake_space[:path], fake_space[:offset], fake_space[:length])
    end
  end
  
  def write_free_space_to_text_file(base_directory=@filesystem_directory)
    if base_directory.nil?
      return
    end
    
    output_string = ""
    output_string << "This file lists regions of currently unused space in this project.\n"
    output_string << "Some of these are from expanding overlay files.\n"
    output_string << "Others were once used, but DSVEdit freed them up when relocating the data to a different location.\n"
    output_string << "DSVEdit reads from this file to know what regions it can reuse later.\n"
    output_string << "Don't modify this file manually unless you know what you're doing.\n\n"
    
    free_spaces_sorted_by_path = @free_spaces.sort_by{|free_space| [free_space[:path], free_space[:offset]]}
    free_spaces_sorted_by_path.each do |free_space|
      offset = free_space[:offset]
      length = free_space[:length]
      path = free_space[:path]
      output_string << "%08X %08X %s\n" % [offset, length, path]
    end
    
    freespace_file = File.join(base_directory, "_dsvedit_freespace.txt")
    File.open(freespace_file, "w") do |f|
      f.write(output_string)
    end
  end
  
  def free_unused_space(ram_address, length)
    return if length <= 0
    
    actual_length = length
    path, offset = convert_ram_address_to_path_and_offset(ram_address)
    file = files_by_path[path]
    if offset + length > file[:size]
      diff = (offset + length) - file[:size]
      if diff < 4
        # If the free space goes 1-3 bytes past the end of the file, it's probably just something caused by rounding the free spaces up to the nearest 4 bytes, so simply decrease the length to avoid the error.
        actual_length -= diff
      end
    end
    
    if !@changes_in_current_free_space_batch.nil?
      data = read(ram_address, length)
      @changes_in_current_free_space_batch << [:free_unused_space, [ram_address, data]]
    end
    
    @free_spaces << {path: path, offset: offset, length: length}
    write_by_file(path, offset, "\0"*actual_length, freeing_space: true)
    merge_overlapping_free_spaces()
    
    round_free_spaces()
  end
  
  def mark_space_unused(file_path, offset_in_file, length)
    # Marks some space as unused like free_unused_space, but does NOT overwrite it with null bytes.
    return if length <= 0
    
    @free_spaces << {path: file_path, offset: offset_in_file, length: length}
    merge_overlapping_free_spaces()
    
    round_free_spaces()
  end
  
  def remove_free_space(file_path, offset_in_file, length)
    return if @free_spaces.nil? # Only open in memory
    
    new_free_spaces = [] # In case a free space is only partly deleted, we might need to split it into smaller free spaces.
    @free_spaces.delete_if do |free_space|
      next unless free_space[:path] == file_path
      
      free_space_range = (free_space[:offset]...free_space[:offset]+free_space[:length])
      remove_range = (offset_in_file...offset_in_file+length)
      next if free_space_range.max < remove_range.begin || remove_range.max < free_space_range.begin
      
      if remove_range.begin > free_space_range.begin
        range_before = (free_space_range.begin...remove_range.begin)
        offset = range_before.begin
        length = range_before.end - offset
        new_free_spaces << {path: file_path, offset: offset, length: length}
      end
      if remove_range.max < free_space_range.max
        range_after = (remove_range.end...free_space_range.end)
        offset = range_after.begin
        length = range_after.end - offset
        new_free_spaces << {path: file_path, offset: offset, length: length}
      end
      
      true
    end
    
    @free_spaces += new_free_spaces
    
    round_free_spaces()
  end
  
  def merge_overlapping_free_spaces
    merged_free_spaces = []
    
    free_space_groups = @free_spaces.group_by{|free_space| free_space[:path]}
    free_space_groups.each do |path, free_space_group|
      merged_free_space_group = []
      
      free_space_group.sort_by{|free_space| free_space[:offset]}.each do |free_space|
        if merged_free_space_group.empty?
          merged_free_space_group << free_space
          next
        end
        
        prev_free_space = merged_free_space_group.last
        prev_range = (prev_free_space[:offset]..prev_free_space[:offset]+prev_free_space[:length])
        curr_range = (free_space[:offset]..free_space[:offset]+free_space[:length])
        if curr_range.include?(prev_range.begin) || prev_range.include?(curr_range.begin)
          new_offset = [curr_range.begin, prev_range.begin].min
          new_length = [curr_range.end, prev_range.end].max - new_offset
          new_free_space = {path: path, offset: new_offset, length: new_length}
          merged_free_space_group[-1] = new_free_space
        else
          merged_free_space_group << free_space
          next
        end
      end
      
      merged_free_spaces += merged_free_space_group
    end
    
    @free_spaces = merged_free_spaces
    
    round_free_spaces()
  end
  
  def round_free_spaces
    @free_spaces.each do |free_space|
      offset = free_space[:offset]
      end_offset = free_space[:offset] + free_space[:length]
      
      offset = (offset + 3) / 4 * 4 # Round up to the nearest word.
      
      free_space[:offset] = offset
      free_space[:length] = end_offset - free_space[:offset]
    end
    @free_spaces.delete_if do |free_space|
      free_space[:length] <= 0
    end
  end
  
  def automatically_remove_nonzero_free_spaces_for_overlay(overlay_id = nil)
    files_to_check = get_files_to_check_for_overlay(overlay_id)
    automatically_remove_nonzero_free_spaces(files_to_check)
  end
  
  def automatically_remove_nonzero_free_spaces(files_to_check)
    # This is an extra safeguard to make absolutely sure no nonzero data is treated as free space.
    # (We also count FF as zero data, since HoD's free space is all FFs by default.)
    # This can be necessary if the _dsvedit_freespace.txt file got deleted.
    
    if @filesystem_directory.nil?
      # If the ROM is just extracted into memory and does not a project directory, there can't be a free space file for the user to edit anyway, so we can skip this check.
      return
    end
    
    free_spaces_to_check = @free_spaces.select{|free_space| files_to_check.include?(free_space[:path])}
    free_spaces_to_check.each do |free_space|
      (free_space[:offset]..free_space[:offset]+free_space[:length]-1).step(4) do |offset|
        file_size = files_by_path[free_space[:path]][:size]
        if offset >= file_size
          break
        end
        
        space_left_in_file = files_by_path[free_space[:path]][:size] - offset
        case space_left_in_file
        when 1
          byte = read_by_file(free_space[:path], offset, 1).unpack("C").first
          if byte != 0 && byte != 0xFF
            remove_free_space(free_space[:path], offset, 1)
          end
        when 2
          halfword = read_by_file(free_space[:path], offset, 2).unpack("v").first
          if halfword != 0 && byte != 0xFFFF
            remove_free_space(free_space[:path], offset, 2)
          end
        when 3
          bytes = read_by_file(free_space[:path], offset, 3).unpack("CCC")
          unless bytes.all?{|byte| byte == 0 || byte == 0xFF}
            remove_free_space(free_space[:path], offset, 2)
          end
        else
          word = read_by_file(free_space[:path], offset, 4).unpack("V").first
          if word != 0 && word != 0xFFFFFFFF
            remove_free_space(free_space[:path], offset, 4)
          end
        end
      end
    end
  end
  
  def get_files_to_check_for_overlay(overlay_id = nil)
    files_to_check = []
    
    if SYSTEM == :nds
      # Check the specific overlay first, then arm9 if there's no free space in the overlay, and the free space overlay as a last resort.
      if overlay_id
        files_to_check << File.join("/ftc", "overlay9_#{overlay_id}")
      end
      files_to_check << File.join("/ftc", "arm9.bin")
      if has_free_space_overlay?
        files_to_check << File.join("/ftc", "overlay9_#{NEW_OVERLAY_ID}")
      end
    else
      files_to_check << "/rom.gba"
    end
    
    return files_to_check
  end
  
  def get_free_space(length_needed, overlay_id = nil, remove_nonzero_spaces = true)
    if length_needed <= 0
      raise FreeSpaceFindError.new("Invalid free space length to find: #{length_needed}")
    end
    
    files_to_check = get_files_to_check_for_overlay(overlay_id)
    
    if remove_nonzero_spaces
      automatically_remove_nonzero_free_spaces(files_to_check)
    end
    
    free_spaces_sorted = @free_spaces.sort_by{|free_space| free_space[:length]}
    
    files_to_check.each do |file_path|
      file = files_by_path[file_path]
      
      free_space = free_spaces_sorted.find do |free_space|
        free_space[:length] >= length_needed && free_space[:path] == file_path
      end
      
      if free_space
        #puts "Found free space at %08X,%04X (%08X in %s)" % [file[:ram_start_offset] + free_space[:offset], length_needed, free_space[:offset], file[:file_path]]
        
        expand_length_needed = free_space[:offset] + length_needed - file[:size]
        if expand_length_needed > 0
          expand_file(file, expand_length_needed)
        end
        
        if !@changes_in_current_free_space_batch.nil?
          @changes_in_current_free_space_batch << [:found_free_space, [file_path, free_space[:offset], length_needed]]
        end
        
        remove_free_space(file_path, free_space[:offset], length_needed)
        
        free_space_ram_pointer = file[:ram_start_offset] + free_space[:offset]
        return free_space_ram_pointer
      end
    end
    
    raise FreeSpaceFindError.new("Failed to find any free space!")
  end
  
  def free_old_space_and_find_new_free_space(old_pointer, old_length, new_length_needed, overlay_id = nil)
    old_data = read(old_pointer, old_length)
    free_unused_space(old_pointer, old_length)
    
    begin
      return get_free_space(new_length_needed, overlay_id)
    rescue FreeSpaceFindError => e
      # Failed to find space, so put the old data back how it was, then re-raise the error.
      write(old_pointer, old_data)
      raise e
    end
  end
  
  def start_free_space_batch
    @changes_in_current_free_space_batch = []
  end
  
  def end_free_space_batch
    @changes_in_current_free_space_batch = nil
  end
  
  def undo_free_space_batch
    changes_in_current_free_space_batch = @changes_in_current_free_space_batch
    @changes_in_current_free_space_batch = nil
    
    changes_in_current_free_space_batch.reverse_each do |change_type, params|
      case change_type
      when :free_unused_space
        old_pointer, old_data = params
        write(old_pointer, old_data)
      when :found_free_space
        file_path, offset_in_file, length = params
        mark_space_unused(file_path, offset_in_file, length)
      when :overwrite
        old_pointer, old_data = params
        write(old_pointer, old_data)
      when :overwrite_by_file
        file_path, offset_in_file, old_data = params
        write_by_file(file_path, offset_in_file, old_data)
      else
        raise "Invalid free space batch change type: #{change_type}"
      end
    end
  end
  
  def initialize_copy(orig)
    super
    
    orig_free_spaces = @free_spaces
    @free_spaces = []
    orig_free_spaces.each do |free_space|
      @free_spaces << free_space.dup
    end
  end
end
