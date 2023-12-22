
require_relative 'ui_sprite_editor'

class SpriteEditor < Qt::Dialog
  RED_PEN_COLOR = Qt::Pen.new(Qt::Color.new(255, 0, 0))
  GREY_PEN_COLOR = Qt::Pen.new(Qt::Color.new(128, 128, 128))
  
  attr_reader :game, :fs
  
  slots "frame_changed(int)"
  slots "frame_data_changed()"
  slots "animation_frame_changed(int)"
  slots "toggle_hitbox(int)"
  slots "gfx_page_changed(int)"
  slots "palette_changed(int)"
  slots "part_changed(int)"
  slots "tab_changed(int)"
  slots "enemy_changed(int)"
  slots "special_object_changed(int)"
  slots "weapon_changed(int)"
  slots "skill_changed(int)"
  slots "other_sprite_changed(int)"
  slots "animation_changed(int)"
  slots "frame_delay_changed()"
  slots "toggle_animation_paused()"
  slots "advance_frame()"
  slots "reload_sprite()"
  slots "export_to_darkfunction()"
  slots "import_from_darkfunction()"
  slots "export_sprite_frames_as_png()"
  slots "open_skeleton_editor()"
  slots "open_in_gfx_editor()"
  slots "click_gfx_scene(int, int, const Qt::MouseButton&)"
  slots "drag_gfx_scene(int, int, const Qt::MouseButton&)"
  slots "stop_dragging_gfx_scene(int, int, const Qt::MouseButton&)"
  slots "toggle_part_flips(bool)"
  slots "add_animation()"
  slots "remove_animation()"
  slots "add_frame()"
  slots "remove_frame()"
  slots "add_part()"
  slots "remove_part()"
  slots "button_box_clicked(QAbstractButton*)"
  
  def initialize(main_window, game, renderer)
    super(main_window, Qt::WindowTitleHint | Qt::WindowSystemMenuHint)
    
    @game = game
    @fs = game.fs
    @renderer = renderer
    @override_part_palette_index = nil
    
    @ui = Ui_SpriteEditor.new
    @ui.setup_ui(self)
    
    # rbuic4 is bugged and ignores stretch values, so they must be manually set.
    @ui.horizontalLayout_3.setStretch(0, 1)
    @ui.horizontalLayout_3.setStretch(1, 1)
    @ui.horizontalLayout_3.setStretch(2, 1)
    @ui.horizontalLayout_5.setStretch(0, 1)
    @ui.horizontalLayout_5.setStretch(1, 1)
    @ui.horizontalLayout_5.setStretch(2, 1)
    
    @frame_graphics_scene = Qt::GraphicsScene.new
    @frame_graphics_scene.setBackgroundBrush(ClickableGraphicsScene::BACKGROUND_BRUSH)
    @ui.frame_graphics_view.setScene(@frame_graphics_scene)
    
    @gfx_file_graphics_scene = ClickableGraphicsScene.new
    @ui.gfx_file_graphics_view.setScene(@gfx_file_graphics_scene)
    connect(@gfx_file_graphics_scene, SIGNAL("clicked(int, int, const Qt::MouseButton&)"), self, SLOT("click_gfx_scene(int, int, const Qt::MouseButton&)"))
    connect(@gfx_file_graphics_scene, SIGNAL("moved(int, int, const Qt::MouseButton&)"), self, SLOT("drag_gfx_scene(int, int, const Qt::MouseButton&)"))
    connect(@gfx_file_graphics_scene, SIGNAL("released(int, int, const Qt::MouseButton&)"), self, SLOT("stop_dragging_gfx_scene(int, int, const Qt::MouseButton&)"))
    
    @part_graphics_scene = Qt::GraphicsScene.new
    @part_graphics_scene.setBackgroundBrush(ClickableGraphicsScene::BACKGROUND_BRUSH)
    @ui.part_graphics_view.setScene(@part_graphics_scene)
    
    # Add the X/Y axis lines in the background to show where the scene origin is.
    @frame_graphics_scene.addLine(-0x8000, 0, 0x8000, 0, GREY_PEN_COLOR)
    @frame_graphics_scene.addLine(0, -0x8000, 0, 0x8000, GREY_PEN_COLOR)
    @part_graphics_scene.addLine(-0x8000, 0, 0x8000, 0, GREY_PEN_COLOR)
    @part_graphics_scene.addLine(0, -0x8000, 0, 0x8000, GREY_PEN_COLOR)
    
    @animation_timer = Qt::Timer.new()
    @animation_timer.setSingleShot(true)
    connect(@animation_timer, SIGNAL("timeout()"), self, SLOT("advance_frame()"))
    
    set_animation_paused(true)
    
    connect(@ui.tabWidget, SIGNAL("currentChanged(int)"), self, SLOT("tab_changed(int)"))
    connect(@ui.enemy_list, SIGNAL("currentRowChanged(int)"), self, SLOT("enemy_changed(int)"))
    connect(@ui.special_object_list, SIGNAL("currentRowChanged(int)"), self, SLOT("special_object_changed(int)"))
    connect(@ui.weapon_list, SIGNAL("currentRowChanged(int)"), self, SLOT("weapon_changed(int)"))
    connect(@ui.skill_list, SIGNAL("currentRowChanged(int)"), self, SLOT("skill_changed(int)"))
    connect(@ui.other_sprites_list, SIGNAL("currentRowChanged(int)"), self, SLOT("other_sprite_changed(int)"))
    connect(@ui.frame_index, SIGNAL("activated(int)"), self, SLOT("frame_changed(int)"))
    connect(@ui.frame_first_part, SIGNAL("editingFinished()"), self, SLOT("frame_data_changed()"))
    connect(@ui.frame_number_of_parts, SIGNAL("editingFinished()"), self, SLOT("frame_data_changed()"))
    connect(@ui.seek_slider, SIGNAL("valueChanged(int)"), self, SLOT("animation_frame_changed(int)"))
    connect(@ui.show_hitbox, SIGNAL("stateChanged(int)"), self, SLOT("toggle_hitbox(int)"))
    connect(@ui.gfx_page_index, SIGNAL("activated(int)"), self, SLOT("gfx_page_changed(int)"))
    connect(@ui.palette_index, SIGNAL("activated(int)"), self, SLOT("palette_changed(int)"))
    connect(@ui.part_index, SIGNAL("activated(int)"), self, SLOT("part_changed(int)"))
    connect(@ui.animation_index, SIGNAL("activated(int)"), self, SLOT("animation_changed(int)"))
    connect(@ui.frame_delay, SIGNAL("editingFinished()"), self, SLOT("frame_delay_changed()"))
    connect(@ui.part_horizontal_flip, SIGNAL("clicked(bool)"), self, SLOT("toggle_part_flips(bool)"))
    connect(@ui.part_vertical_flip, SIGNAL("clicked(bool)"), self, SLOT("toggle_part_flips(bool)"))
    connect(@ui.toggle_paused_button, SIGNAL("clicked()"), self, SLOT("toggle_animation_paused()"))
    connect(@ui.reload_button, SIGNAL("clicked()"), self, SLOT("reload_sprite()"))
    connect(@ui.darkfunction_export, SIGNAL("clicked()"), self, SLOT("export_to_darkfunction()"))
    connect(@ui.darkfunction_import, SIGNAL("clicked()"), self, SLOT("import_from_darkfunction()"))
    connect(@ui.export_as_png_button, SIGNAL("clicked()"), self, SLOT("export_sprite_frames_as_png()"))
    connect(@ui.view_skeleton_button, SIGNAL("clicked()"), self, SLOT("open_skeleton_editor()"))
    connect(@ui.open_in_gfx_editor, SIGNAL("clicked()"), self, SLOT("open_in_gfx_editor()"))
    connect(@ui.animation_add, SIGNAL("clicked()"), self, SLOT("add_animation()"))
    connect(@ui.animation_remove, SIGNAL("clicked()"), self, SLOT("remove_animation()"))
    connect(@ui.frame_add, SIGNAL("clicked()"), self, SLOT("add_frame()"))
    connect(@ui.frame_remove, SIGNAL("clicked()"), self, SLOT("remove_frame()"))
    connect(@ui.part_add, SIGNAL("clicked()"), self, SLOT("add_part()"))
    connect(@ui.part_remove, SIGNAL("clicked()"), self, SLOT("remove_part()"))
    connect(@ui.buttonBox, SIGNAL("clicked(QAbstractButton*)"), self, SLOT("button_box_clicked(QAbstractButton*)"))
    
    initialize_sprite_lists()
    
    load_blank_sprite()
    
    self.show()
  end
  
  def initialize_sprite_lists
    @game.enemy_dnas.each_with_index do |enemy_dna, enemy_id|
      @ui.enemy_list.addItem("%02X %s" % [enemy_id, enemy_dna.name])
    end
    
    @special_objects = []
    SPECIAL_OBJECT_IDS.each do |special_object_id|
      special_object = SpecialObjectType.new(special_object_id, fs)
      @special_objects << special_object
      object_name = game.special_object_docs[special_object_id]
      object_name = " " if object_name.nil? || object_name.empty?
      object_name = object_name.lines.first.strip
      if object_name.length > 41
        object_name = object_name[0..40]
        object_name << "..."
      end
      @ui.special_object_list.addItem("%02X %s" % [special_object_id, object_name])
    end
    
    weapon_items = []
    skill_items = []
    game.items.each do |item|
      if item.kind == :skill
        skill_items << item
      else
        weapon_items << item
      end
    end
    
    @weapons = []
    @weapon_items_for_each_gfx_index = {}
    (0..WEAPON_GFX_COUNT-1).each do |weapon_gfx_index|
      weapon = WeaponGfx.new(weapon_gfx_index, fs)
      @weapons << weapon
      if GAME == "ooe"
        items = weapon_items.select{|item| item["Sprite"] == weapon_gfx_index+1}
      elsif GAME == "aos"
        items = weapon_items.select{|item| item["GFX Index"] == weapon_gfx_index}
      else
        items = weapon_items.select{|item| item["Sprite"] == weapon_gfx_index}
      end
      if items.any?
        weapon_name = items.map do |item|
          if item.name.empty?
            "..."
          else
            item.name
          end
        end.join(", ")
      else
        weapon_name = "Unused"
      end
      
      @weapon_items_for_each_gfx_index[weapon_gfx_index] = items
      
      @ui.weapon_list.addItem("%02X %s" % [weapon_gfx_index, weapon_name])
    end
    
    @skills = []
    @skill_items_for_each_gfx_index = {}
    (0..SKILL_GFX_COUNT-1).each do |skill_gfx_index|
      skill = SkillGfx.new(skill_gfx_index, fs)
      @skills << skill
      if GAME == "aos"
        skill_indexes = RED_SOUL_INDEX_TO_SKILL_GFX_INDEX.select do |red_soul_index, red_soul_gfx_index|
          red_soul_gfx_index == skill_gfx_index
        end
        items = skill_indexes.map{|red_soul_index, red_soul_gfx_index| game.items[SKILL_GLOBAL_ID_RANGE.begin + red_soul_index]}
      elsif GAME == "hod"
        items = skill_items.select{|item| item["GFX Index"] == skill_gfx_index}
      else
        items = skill_items.select{|item| item["Sprite"] == skill_gfx_index+1}
      end
      if items.any?
        skill_name = items.map do |item|
          if item.name.empty?
            "..."
          else
            item.name
          end
        end.join(", ")
      else
        skill_name = "Unused"
      end
      
      @skill_items_for_each_gfx_index[skill_gfx_index] = items
      
      if SYSTEM == :gba
        @ui.skill_list.addItem("%02X %s" % [skill_gfx_index, skill_name])
      else
        @ui.skill_list.addItem("%02X %s" % [skill_gfx_index + 1, skill_name])
      end
    end
    
    if GAME == "aos"
      blue_soul_type = 6
      ITEM_TYPES[6-2][:count].times do |blue_soul_index|
        skill = game.get_item_by_type_and_index(blue_soul_type, blue_soul_index)
        @ui.skill_list.addItem("%02X %s" % [blue_soul_index, skill.name])
      end
    end
    
    OTHER_SPRITES.each_with_index do |other_sprite, id|
      @ui.other_sprites_list.addItem("%02X %s" % [id, other_sprite[:desc]])
    end
  end
  
  def tab_changed(tab_id)
    case tab_id
    when 0
      id = @ui.enemy_list.currentRow
      return if id == -1
      enemy_changed(id)
    when 1
      id = @ui.special_object_list.currentRow
      return if id == -1
      special_object_changed(id)
    when 2
      id = @ui.weapon_list.currentRow
      return if id == -1
      weapon_changed(id)
    when 3
      id = @ui.skill_list.currentRow
      return if id == -1
      skill_changed(id)
    when 4
      id = @ui.other_sprites_list.currentRow
      return if id == -1
      other_sprite_changed(id)
    end
  end
  
  def enemy_changed(enemy_id)
    if (REUSED_ENEMY_INFO[enemy_id] || {})[:init_code] == -1
      load_blank_sprite()
      return
    end
    
    begin
      @sprite_info = game.get_sprite_info_for_enemy(enemy_id)
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Enemy sprite extraction failed",
        "Failed to extract gfx or palette data for enemy #{enemy_id}.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @override_part_palette_index = nil
    @one_dimensional_render_mode = false
    @transparent_trails = false
    @is_player_sprite = false
    load_sprite()
    
    @ui.enemy_list.setCurrentRow(enemy_id)
  end
  
  def special_object_changed(special_object_id)
    if (REUSED_SPECIAL_OBJECT_INFO[special_object_id] || {})[:init_code] == -1
      load_blank_sprite()
      return
    end
    
    begin
      @sprite_info = game.get_sprite_info_for_special_object(special_object_id)
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Special object sprite extraction failed",
        "Failed to extract gfx or palette data for special object #{special_object_id}.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @override_part_palette_index = nil
    @one_dimensional_render_mode = false
    @transparent_trails = false
    @is_player_sprite = false
    load_sprite()
    
    @ui.special_object_list.setCurrentRow(special_object_id)
  end
  
  def weapon_changed(weapon_gfx_index)
    begin
      @sprite_info = game.get_sprite_info_for_weapon(weapon_gfx_index)
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Weapon sprite extraction failed",
        "Failed to extract gfx or palette data for weapon #{weapon_gfx_index}.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @override_part_palette_index = nil
    @one_dimensional_render_mode = false
    if GAME == "dos"
      @transparent_trails = true
    elsif GAME == "por"
      weapon_item = @weapon_items_for_each_gfx_index[weapon_gfx_index].first
      if weapon_item && !weapon_item["Swing Modifiers"]["No transparent slash trail"]
        @transparent_trails = true
      else
        @transparent_trails = false
      end
    else
      @transparent_trails = false
    end
    @is_player_sprite = false
    load_sprite()
    
    @ui.weapon_list.setCurrentRow(weapon_gfx_index)
  end
  
  def skill_changed(skill_gfx_index)
    begin
      @sprite_info = game.get_sprite_info_for_skill(skill_gfx_index)
      if @sprite_info.nil?
        load_blank_sprite()
        return
      end
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Skill sprite extraction failed",
        "Failed to extract gfx or palette data for skill #{skill_gfx_index}.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @override_part_palette_index = nil
    @one_dimensional_render_mode = false
    if GAME == "ooe"
      skill_item = @skill_items_for_each_gfx_index[skill_gfx_index].first
      if skill_item && MELEE_GLYPH_CODE_POINTERS.include?(skill_item["Code"]) && !skill_item["Swing Modifiers"]["No transparent slash trail"]
        @transparent_trails = true
      else
        @transparent_trails = false
      end
    else
      @transparent_trails = false
    end
    @is_player_sprite = false
    load_sprite()
    
    @ui.skill_list.setCurrentRow(skill_gfx_index)
  end
  
  def other_sprite_changed(id)
    other_sprite = OTHER_SPRITES[id]
    begin
      @sprite_info = game.get_sprite_info_for_other_sprite(id)
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Sprite extraction failed",
        "Failed to extract gfx or palette data for other sprite #{id}.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @override_part_palette_index = nil
    @one_dimensional_render_mode = other_sprite[:one_dimensional_mode]
    @transparent_trails = false
    if other_sprite[:desc].end_with?(" player")
      @is_player_sprite = true
    else
      @is_player_sprite = false
    end
    load_sprite()
    
    @ui.other_sprites_list.setCurrentRow(id)
  end
  
  def load_blank_sprite
    @sprite_info = nil
    
    @ui.sprite_file_name.text = ""
    @ui.gfx_pointer.text = ""
    @ui.palette_pointer.text = ""
    
    clear_sprite()
  end
  
  def clear_sprite
    @sprite = nil
    
    @ui.view_skeleton_button.enabled = false
    @ui.frame_index.clear()
    @ui.gfx_page_index.clear()
    @ui.palette_index.clear()
    @ui.frame_first_part.text = ""
    @ui.frame_number_of_parts.text = ""
    @ui.frame_first_part.enabled = false
    @ui.frame_number_of_parts.enabled = false
    @ui.part_index.clear()
    @ui.part_horizontal_flip.checked = false
    @ui.part_horizontal_flip.enabled = false
    @ui.part_vertical_flip.checked = false
    @ui.part_vertical_flip.enabled = false
    @ui.gfx_file_name.text = ""
    @ui.show_hitbox.enabled = false
    @ui.seek_slider.enabled = false
    @ui.toggle_paused_button.enabled = false
    @ui.frame_delay.text = ""
    @ui.frame_delay.enabled = false
    @ui.animation_add.enabled = false
    @ui.animation_remove.enabled = false
    @ui.frame_add.enabled = false
    @ui.frame_remove.enabled = false
    @ui.part_add.enabled = false
    @ui.part_remove.enabled = false
    
    @rendered_gfx_pages_by_palette = {}
    @gfx_page_pixmap_items_by_palette = {}
    @part_pixmaps_for_part_view = []
    @part_pixmaps_for_frame_view = []
    @ui.animation_index.clear()
    clear_scene_leaving_lines(@frame_graphics_scene)
    clear_scene_leaving_lines(@part_graphics_scene)
    clear_scene_leaving_lines(@gfx_file_graphics_scene)
    
    @current_frame_index = nil
    @current_part_index = nil
    
    @current_animation = nil
  end
  
  def load_no_sprite_with_gfx_and_palette
    clear_sprite()
    
    @ui.sprite_file_name.text = ""
    
    @gfx_pages_with_blanks = @sprite_info.gfx_pages
    
    if @sprite_info.gfx_pages.first.render_mode == 1
      @palettes = @renderer.generate_palettes(@sprite_info.palette_pointer, 16)
    elsif @sprite_info.gfx_pages.first.render_mode == 2
      @palettes = @renderer.generate_palettes(@sprite_info.palette_pointer, 256)
    else
      raise "Unknown render mode: #{@sprite_info.gfx_pages.first.render_mode}"
    end
    
    @palettes.each_with_index do |palette, i|
      @ui.palette_index.addItem("%02X" % i)
    end
    palette_changed(@sprite_info.palette_offset, force=true)
    
    @gfx_pages_with_blanks.each_with_index do |gfx_page, i|
      @ui.gfx_page_index.addItem("%02X" % i)
    end
    gfx_page_changed(0)
    
    @ui.gfx_pointer.text = @sprite_info.gfx_file_pointers.map{|ptr| "%08X" % ptr}.join(", ")
    @ui.palette_pointer.text = "%08X" % @sprite_info.palette_pointer
  end
  
  def load_sprite
    if SYSTEM == :gba
      @one_dimensional_render_mode = true
    end
    
    if @sprite_info.sprite.nil?
      load_no_sprite_with_gfx_and_palette()
      return
    end
    
    @ui.frame_first_part.enabled = true
    @ui.frame_number_of_parts.enabled = true
    @ui.part_horizontal_flip.enabled = true
    @ui.part_vertical_flip.enabled = true
    @ui.show_hitbox.enabled = true
    @ui.frame_delay.enabled = true
    @ui.animation_add.enabled = true
    @ui.animation_remove.enabled = true
    @ui.frame_add.enabled = true
    @ui.frame_remove.enabled = true
    @ui.part_add.enabled = true
    @ui.part_remove.enabled = true
    
    @sprite = @sprite_info.sprite
    
    if @sprite_info.skeleton_file
      @ui.view_skeleton_button.enabled = true
    else
      @ui.view_skeleton_button.enabled = false
    end
    
    @current_frame_index = 0
    @current_part_index = 0
    
    sprite_file_text = "%08X" % @sprite_info.sprite_file_pointer
    if @sprite_info.sprite_file
      sprite_file_text += " (#{@sprite_info.sprite_file[:file_path]})"
    end
    if @sprite_info.skeleton_file
      sprite_file_text += ", #{@sprite_info.skeleton_file[:file_path]}"
    end
    @ui.sprite_file_name.text = sprite_file_text
    
    @ui.frame_index.clear()
    @sprite.frames.each_index do |frame_index|
      frame = @sprite.frames[frame_index]
      
      frame_text = "%02X" % frame_index
      if !@sprite.sprite_file
        offset = @sprite.frames_by_offset.key(frame)
        frame_text << " (%08X)" % offset
      end
      @ui.frame_index.addItem(frame_text)
    end
    
    @rendered_gfx_pages_by_palette = {}
    @gfx_page_pixmap_items_by_palette = {}
    
    @ui.gfx_pointer.text = @sprite_info.gfx_file_pointers.map{|ptr| "%08X" % ptr}.join(", ")
    
    @ui.palette_pointer.text = "%08X" % @sprite_info.palette_pointer
    
    begin
      @chunky_frames, @min_x, @min_y, rendered_parts, @gfx_pages_with_blanks, @palettes, @full_width, @full_height = 
        @renderer.render_sprite(
          @sprite_info,
          frame_to_render: nil,
          override_part_palette_index: @override_part_palette_index,
          one_dimensional_mode: @one_dimensional_render_mode,
          transparent_trails: @transparent_trails
        )
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Sprite rendering failed",
        "Failed to render sprite.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    @frame_graphics_scene.setSceneRect(@min_x, @min_y, @full_width, @full_height)
    @part_graphics_scene.setSceneRect(@min_x, @min_y, @full_width, @full_height)
    
    @ui.gfx_page_index.clear()
    @gfx_pages_with_blanks.each_with_index do |gfx_page, i|
      @ui.gfx_page_index.addItem("%02X" % i)
    end
    @ui.gfx_page_index.setCurrentIndex(0)
    
    @ui.palette_index.clear()
    @palettes.each_with_index do |palette, i|
      @ui.palette_index.addItem("%02X" % i)
    end
    palette_changed(0, force=true)
    
    @part_pixmaps_for_part_view = []
    @part_pixmaps_for_frame_view = []
    @ui.part_index.clear()
    ordered_rendered_parts = rendered_parts.sort_by{|part_index, chunky_image| part_index}
    ordered_rendered_parts.each do |part_index, chunky_image|
      part = @sprite.parts[part_index]
      
      pixmap = Qt::Pixmap.new
      blob = chunky_image.to_blob
      pixmap.loadFromData(blob, blob.length)
      
      @part_pixmaps_for_part_view << PartItem.new(self, part, part_index, pixmap)
      @part_pixmaps_for_frame_view << PartItem.new(self, part, part_index, pixmap)
      
      part_text = "%02X" % part_index
      if !@sprite.sprite_file
        offset = @sprite.parts_by_offset.key(part)
        part_text << " (%08X)" % offset
      end
      @ui.part_index.addItem(part_text)
    end
    part_changed(0)
    
    frame_changed(0)
    
    @ui.animation_index.clear()
    @sprite.animations.each_with_index do |animation, i|
      @ui.animation_index.addItem("%02X" % i)
    end
    animation_changed(0)
  rescue StandardError => e
    Qt::MessageBox.warning(self,
      "Failed to load sprite",
      "Failed to load sprite.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
    )
    clear_sprite()
  end
  
  def ensure_gfx_pages_for_palette_exist(palette_index)
    @rendered_gfx_pages_by_palette[palette_index] ||= @gfx_pages_with_blanks.map do |gfx|
      if gfx.nil?
        nil
      else
        canvas_width = gfx.canvas_width
        palette = @palettes[palette_index]
        if palette.nil?
          # Invalid palette, use a dummy palette instead.
          palette = @renderer.generate_palettes(nil, @palettes[0].size).first
        end
        if @one_dimensional_render_mode || SYSTEM == :gba
          chunky_image = @renderer.render_gfx_1_dimensional_mode(gfx, palette)
        else
          chunky_image = @renderer.render_gfx(gfx, palette, 0, 0, canvas_width*8, canvas_width*8, canvas_width=canvas_width*8)
        end
        
        chunky_image
      end
    end
    
    @gfx_page_pixmap_items_by_palette[palette_index] ||= @rendered_gfx_pages_by_palette[palette_index].map do |chunky_image|
      if chunky_image.nil?
        nil
      else
        pixmap = Qt::Pixmap.new
        blob = chunky_image.to_blob
        pixmap.loadFromData(blob, blob.length)
        gfx_page_pixmap_item = Qt::GraphicsPixmapItem.new(pixmap)
        
        gfx_page_pixmap_item
      end
    end
  end
  
  def load_gfx_pages(palette_index)
    ensure_gfx_pages_for_palette_exist(palette_index)
    
    @gfx_file_graphics_scene.setSceneRect(0, 0, @rendered_gfx_pages_by_palette[palette_index].first.width, @rendered_gfx_pages_by_palette[palette_index].first.height)
  end
  
  def frame_changed(i, do_not_change_current_part: false)
    @current_frame_index = i
    clear_scene_leaving_lines(@frame_graphics_scene)
    
    if i == nil || @sprite.frames[i] == nil
      @current_frame_index = nil
      @ui.frame_index.setCurrentIndex(-1)
      @ui.frame_first_part.text = ""
      @ui.frame_number_of_parts.text = ""
      return
    end
    
    @sprite.frames[i].part_indexes.reverse.each do |part_index|
      part = @sprite.parts[part_index]
      
      part_pixmap = @part_pixmaps_for_frame_view[part_index]
      @frame_graphics_scene.addItem(part_pixmap) if part_pixmap
    end
    
    @ui.frame_index.setCurrentIndex(i)
    
    frame = @sprite.frames[i]
    
    if frame.part_indexes.first
      @ui.frame_first_part.text = "%02X" % frame.part_indexes.first
    else
      @ui.frame_first_part.text = ""
    end
    unless do_not_change_current_part
      part_changed(frame.part_indexes.first)
    end
    @ui.frame_number_of_parts.text = "%02X" % frame.part_indexes.length
    
    if @ui.show_hitbox.checked
      frame.hitboxes.each do |hitbox|
        hitbox_item = Qt::GraphicsRectItem.new
        hitbox_item.setPen(RED_PEN_COLOR)
        hitbox_item.setRect(hitbox.x_pos, hitbox.y_pos, hitbox.width, hitbox.height)
        @frame_graphics_scene.addItem(hitbox_item)
      end
    end
  end
  
  def toggle_hitbox(checked)
    frame_changed(@current_frame_index)
  end
  
  def gfx_page_changed(gfx_page_index)
    if @sprite_info.ignore_part_gfx_page
      gfx_page_index = 0
    end
    clear_scene_leaving_lines(@gfx_file_graphics_scene)
    @gfx_page_index = gfx_page_index
    
    gfx_page_pixmap_item = @gfx_page_pixmap_items_by_palette[@palette_index][gfx_page_index]
    if gfx_page_pixmap_item.nil?
      @ui.gfx_file_name.text = "Invalid (gfx page index %02X)" % gfx_page_index
    else
      @gfx_file_graphics_scene.addItem(gfx_page_pixmap_item)
      gfx = @gfx_pages_with_blanks[gfx_page_index]
      if gfx.file
        @ui.gfx_file_name.text = gfx.file[:file_path]
      else
        @ui.gfx_file_name.text = "%08X" % gfx.gfx_pointer
      end
    end
    
    @ui.gfx_page_index.setCurrentIndex(gfx_page_index)
    
    return if @current_part_index.nil?
    part = @sprite.parts[@current_part_index]
    if part.gfx_page_index == @gfx_page_index
      @selection_rectangle = Qt::GraphicsRectItem.new
      @selection_rectangle.setPen(RED_PEN_COLOR)
      @selection_rectangle.setRect(part.gfx_x_offset, part.gfx_y_offset, part.width, part.height)
      @gfx_file_graphics_scene.addItem(@selection_rectangle)
    end
  end
  
  def palette_changed(palette_index, force=false)
    if @transparent_trails
      palette_index = 0
    end
    if palette_index == @palette_index && !force
      return
    end
    @palette_index = palette_index
    
    old_gfx_page_index = @gfx_page_index
    old_gfx_page_index = 0 if old_gfx_page_index.nil?
    load_gfx_pages(palette_index)
    gfx_page_changed(old_gfx_page_index)
    
    @ui.palette_index.setCurrentIndex(palette_index)
  end
  
  def part_changed(i)
    @current_part_index = i
    clear_scene_leaving_lines(@part_graphics_scene)
    
    if i == nil || @sprite.parts[i] == nil
      @current_part_index = nil
      @ui.part_index.setCurrentIndex(-1)
      return
    end
    
    @part_graphics_scene.addItem(@part_pixmaps_for_part_view[i])
    
    @ui.part_index.setCurrentIndex(i)
    
    part = @sprite.parts[i]
    gfx_page_changed(part.gfx_page_index)
    if @override_part_palette_index
      palette_changed(@override_part_palette_index)
    else
      palette_changed(part.palette_index + @sprite_info.palette_offset)
    end
    
    @ui.part_horizontal_flip.setChecked(part.horizontal_flip)
    @ui.part_vertical_flip.setChecked(part.vertical_flip)
  end
  
  def animation_changed(i)
    @animation_timer.stop()
    @current_animation_index = i
    @ui.seek_slider.value = 0
    @current_animation_frame_index = 0
    
    if i == nil
      @current_animation_index = nil
      @current_animation = nil
      @ui.animation_index.setCurrentIndex(-1)
    elsif @sprite.animations[i] == nil
      frame_changed(nil) # Blank out the frame display
      part_changed(nil) # Blank out the part display
      return
    else
      @ui.animation_index.setCurrentIndex(i)
      @current_animation = @sprite.animations[i]
    end
    
    if @current_animation.nil?
      @ui.seek_slider.enabled = false
      @ui.toggle_paused_button.enabled = false
      @ui.frame_delay.text = ""
      return
    end
    
    @ui.seek_slider.enabled = true
    @ui.seek_slider.minimum = 0
    if @current_animation.number_of_frames > 0
      @ui.seek_slider.maximum = @current_animation.frame_delays.length-1
    else
      @ui.seek_slider.maximum = 0
    end
    @ui.toggle_paused_button.enabled = true
    
    if @current_animation.number_of_frames > 0
      animation_frame_changed(0, force=true)
      start_animation()
    else
      frame_changed(nil) # Blank out the frame display
    end
  end
  
  def animation_frame_changed(i, force=false)
    return if i == @current_animation_frame_index && @ui.seek_slider.value == @current_animation_frame_index && !force
    
    @current_animation_frame_index = i
    frame_delay = @current_animation.frame_delays[@current_animation_frame_index]
    frame_changed(frame_delay.frame_index)
    @ui.seek_slider.value = @current_animation_frame_index
    @ui.frame_delay.text = "%04X" % frame_delay.delay
  end
  
  def set_animation_paused(paused)
    @animation_paused = paused
    if @animation_paused
      @ui.toggle_paused_button.text = "Play"
    else
      @ui.toggle_paused_button.text = "Pause"
      
      start_animation()
    end
  end
  
  def start_animation
    frame_delay = @current_animation.frame_delays[@current_animation_frame_index]
    millisecond_delay = (frame_delay.delay / 60.0 * 1000).round
    @animation_timer.start(millisecond_delay)
  end
  
  def toggle_animation_paused
    set_animation_paused(!@animation_paused)
  end
  
  def advance_frame
    if @current_animation && !@animation_paused
      if @current_animation_frame_index >= @current_animation.frame_delays.length-1
        animation_frame_changed(0)
        
        unless @ui.loop_animation.checked
          set_animation_paused(true)
        end
      else
        animation_frame_changed(@current_animation_frame_index+1)
      end
      
      frame_delay = @current_animation.frame_delays[@current_animation_frame_index]
      millisecond_delay = (frame_delay.delay / 60.0 * 1000).round
      @animation_timer.start(millisecond_delay)
    end
  rescue StandardError => e
    Qt::MessageBox.warning(self,
      "Failed advance to next animation frame",
      e.message
    )
    set_animation_paused(true)
  end
  
  def frame_delay_changed
    return if @current_animation.nil?
    frame_delay = @current_animation.frame_delays[@current_animation_frame_index]
    return if frame_delay.nil?
    delay_num = @ui.frame_delay.text.to_i(16)
    delay_num = [delay_num, 1].max
    frame_delay.delay = delay_num
    @ui.frame_delay.text = "%04X" % frame_delay.delay
  end
  
  def open_skeleton_editor
    if @sprite_info.skeleton_file
      @skeleton_editor = SkeletonEditorDialog.new(self, @sprite_info, game.fs, @renderer)
    end
  end
  
  def open_in_gfx_editor
    return if @sprite_info.nil? || @gfx_pages_with_blanks.nil?
    
    gfx_pages = @gfx_pages_with_blanks.compact
    
    gfx_and_palette_data = {}
    gfx_and_palette_data[:gfx_file_names] = gfx_pages.map{|gfx| "%08X" % gfx.gfx_pointer}.join(", ")
    selected_gfx_page = @gfx_pages_with_blanks[@gfx_page_index]
    gfx_page_index_without_blanks = gfx_pages.index(selected_gfx_page)
    gfx_and_palette_data[:gfx_page_index] = gfx_page_index_without_blanks
    gfx_and_palette_data[:palette_pointer] = @sprite_info.palette_pointer
    gfx_and_palette_data[:palette_index] = @palette_index
    gfx_and_palette_data[:one_dimensional_mode] = @one_dimensional_render_mode
    
    parent.open_gfx_editor(gfx_and_palette_data)
  end
  
  def save_sprite
    return if @sprite.nil?
    
    @sprite.write_to_rom()
  rescue FreeSpaceManager::FreeSpaceFindError => e
    Qt::MessageBox.warning(self,
      "Failed to find free space",
      "Failed to find free space for the sprite changes.\n\n#{NO_FREE_SPACE_MESSAGE}"
    )
  rescue Sprite::SaveError => e
    Qt::MessageBox.warning(self,
      "Failed to save sprite",
      e.message
    )
  end
  
  def button_box_clicked(button)
    if @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Ok
      save_sprite()
      self.close()
    elsif @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Cancel
      self.close()
    elsif @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Apply
      save_sprite()
    end
  end
  
  def clear_scene_leaving_lines(graphics_scene)
    graphics_scene.items.each do |item|
      next if item.is_a?(Qt::GraphicsLineItem)
      graphics_scene.removeItem(item)
    end
  end
  
  def reload_sprite
    gfx_file_names = @ui.gfx_pointer.text.split(/,\s*/)
    gfx_file_pointers = []
    gfx_file_names.each do |gfx_file_name|
      gfx_file_name = gfx_file_name.strip
      gfx_file_pointer = gfx_file_name.to_i(16)
      if !fs.is_pointer?(gfx_file_pointer) && SYSTEM == :nds
        gfx_file = @fs.files_by_path[gfx_file_name]
        if gfx_file
          gfx_file_pointer = gfx_file[:asset_pointer]
        end
      end
      gfx_file_pointers << gfx_file_pointer
    end
    
    palette_pointer = @ui.palette_pointer.text.to_i(16)
    
    if @ui.sprite_file_name.text.strip.empty?
      sprite_pointer = nil
    else
      sprite_file_name = @ui.sprite_file_name.text.strip
      sprite_pointer = sprite_file_name.to_i(16)
      if !fs.is_pointer?(sprite_pointer) && SYSTEM == :nds
        sprite_file = @fs.files_by_path[sprite_file_name]
        if sprite_file
          sprite_pointer = sprite_file[:asset_pointer]
        end
      end
    end
    
    begin
      @sprite_info = SpriteInfo.new(gfx_file_pointers, palette_pointer, @sprite_info.palette_offset, sprite_pointer, @sprite_info.skeleton_file, @fs)
    rescue StandardError => e
      Qt::MessageBox.warning(self,
        "Sprite extraction failed",
        "Failed to extract sprite info.\n#{e.message}\n\n#{e.backtrace.join("\n")}"
      )
      return
    end
    
    load_sprite()
  end
  
  def sprite_name
    if @sprite.sprite_file
      sprite_name = @sprite.sprite_file[:name]
      if sprite_name =~ /\.dat$/
        sprite_name = sprite_name[0..-5]
      end
    else
      sprite_name = "%08X" % @sprite.sprite_pointer
    end
    
    return sprite_name
  end
  
  def export_to_darkfunction
    return if @sprite.nil?
    
    if GAME == "hod"
      Qt::MessageBox.warning(self,
        "Cannot edit HoD sprites in darkFunction",
        "Editing HoD sprites in darkFunction is not currently supported."
      )
      return
    end
    
    output_folder = "./darkfunction_sprites/#{sprite_name}"
    FileUtils.mkdir_p(output_folder)
    
    if @sprite_info.gfx_pages.first.render_mode == 1
      colors_per_palette = 16
    elsif @sprite_info.gfx_pages.first.render_mode == 2
      colors_per_palette = 256
    else
      raise "Unknown render mode: #{@sprite_info.gfx_pages.first.render_mode}"
    end
    
    DarkFunctionInterface.export(
      output_folder,
      sprite_name,
      @sprite_info,
      @fs, @renderer,
      transparent_trails: @transparent_trails,
      one_dimensional_mode: @one_dimensional_render_mode || SYSTEM == :gba,
      colors_per_palette: colors_per_palette,
    )
    
    Qt::MessageBox.warning(self,
      "Exported to darkFunction",
      "This sprite has been exported in darkFunction's format to the folder #{output_folder}"
    )
  rescue DarkFunctionInterface::ExportError => e
    Qt::MessageBox.warning(self,
      "Failed to export to darkFunction",
      e.message
    )
  end
  
  def import_from_darkfunction
    return if @sprite.nil?
    
    if GAME == "hod"
      Qt::MessageBox.warning(self,
        "Cannot edit HoD sprites in darkFunction",
        "Editing HoD sprites in darkFunction is not currently supported."
      )
      return
    end
    
    folder = "./darkfunction_sprites/#{sprite_name}"
    
    if !File.directory?(folder) || !File.file?(folder + "/#{sprite_name}.sprites") || !File.file?(folder + "/#{sprite_name}.anim")
      Qt::MessageBox.warning(self,
        "Nothing to import",
        "There is no darkFunction sprite to import.\nYou must first export this sprite before you can import it."
      )
      return
    end
    
    DarkFunctionInterface.import(folder, sprite_name, @sprite_info, @fs, @renderer)
    
    reload_sprite()
    
    check_if_player_sprite_has_frames_spanning_multiple_gfx()
  rescue DarkFunctionInterface::ImportError, Sprite::SaveError, FreeSpaceManager::FreeSpaceFindError => e
    Qt::MessageBox.warning(self,
      "Failed to import from darkFunction",
      e.message
    )
  end
  
  def check_if_player_sprite_has_frames_spanning_multiple_gfx
    if !@is_player_sprite
      return
    end
    
    multi_gfx_frames = []
    @sprite.frames.each_with_index do |frame, i|
      unique_gfx_pages = frame.parts.map{|part| part.gfx_page_index}.uniq
      if unique_gfx_pages.length > 1
        multi_gfx_frames << i
      end
    end
    if multi_gfx_frames.any?
      Qt::MessageBox.warning(self,
        "Player sprite has frames using multiple GFX pages",
        "Warning: Player sprites must only make use of one GFX page per frame. Frames that have some parts on one GFX page and some on other may not properly render parts after the first one ingame.\n(This rule does not apply to Sisters Mode in PoR.)\n\nThe following frames in this sprite use multiple GFX pages: %s" % multi_gfx_frames.map{|frame_index| "%02X" % frame_index}.join(", ")
      )
      # Note: The Albus player sprite actually does have 2 frames that break this rule, but those frames are unused, and are part of a boss-Albus only animation.
    end
  end
  
  def export_sprite_frames_as_png
    return if @sprite.nil?
    
    output_folder = "./gfx/exported_sprites/#{sprite_name}"
    FileUtils.mkdir_p(output_folder)
    
    chunky_frames, _ = @renderer.render_sprite(@sprite_info, override_part_palette_index: @override_part_palette_index, one_dimensional_mode: @one_dimensional_render_mode, transparent_trails: @transparent_trails)
    chunky_frames.each_with_index do |chunky_frame, i|
      type_name = ""
      filename = "%s/frame%03X.png" % [output_folder, i]
      chunky_frame.save(filename, :fast_rgba)
    end
    
    Qt::MessageBox.warning(self,
      "Exported sprite frames",
      "All frames of this sprite have been exported as PNG files to the folder #{output_folder}"
    )
  end
  
  def check_sprite_hardcoded
    if @sprite.sprite_file.nil?
      Qt::MessageBox.warning(self,
        "Sprite has no file",
        "This sprite is hardcoded and has no standalone sprite file.\nCannot add or remove animations/frames/parts."
      )
      return true
    end
    return false
  end
  
  def add_animation
    return if check_sprite_hardcoded()
    
    new_index = @sprite.animations.length
    animation = Animation.new
    animation.initialize_frame_delays_from_pointer(@sprite.frame_delays, @sprite.frame_delays_by_offset)
    @sprite.animations << animation
    
    @ui.animation_index.addItem("%02X" % new_index)
    animation_changed(new_index)
  end
  
  def remove_animation
    return if check_sprite_hardcoded()
    
    return if @current_animation_index.nil?
    
    @sprite.animations.delete_at(@current_animation_index)
    
    @ui.animation_index.removeItem(@sprite.animations.length)
    if @sprite.animations.length == 0
      animation_changed(nil)
    else
      new_index = [@current_animation_index, @sprite.animations.length-1].min
      animation_changed(new_index)
    end
  end
  
  def add_frame
    return if check_sprite_hardcoded()
    
    new_index = @sprite.frames.length
    frame = Frame.new
    frame.initialize_parts(@sprite.parts, @sprite.parts_by_offset)
    frame.initialize_hitboxes_from_pointer([], {})
    @sprite.frames << frame
    
    @ui.frame_index.addItem("%02X" % new_index)
    frame_changed(new_index)
  end
  
  def remove_frame
    return if check_sprite_hardcoded()
    
    return if @current_frame_index.nil?
    
    @sprite.frames.delete_at(@current_frame_index)
    
    @ui.frame_index.removeItem(@sprite.frames.length)
    if @sprite.frames.length == 0
      frame_changed(nil)
    else
      new_index = [@current_frame_index, @sprite.frames.length-1].min
      frame_changed(new_index)
    end
  end
  
  def add_part
    return if check_sprite_hardcoded()
    
    new_index = @sprite.parts.length
    part = Part.new
    @sprite.parts << part
    next_part_offset = @sprite.parts_by_offset.keys.max + 16
    @sprite.parts_by_offset[next_part_offset] = part
    @part_pixmaps_for_part_view << PartItem.new(self, part, new_index, nil)
    @part_pixmaps_for_frame_view << PartItem.new(self, part, new_index, nil)
    
    @ui.part_index.addItem("%02X" % new_index)
    part_changed(new_index)
  end
  
  def remove_part
    return if check_sprite_hardcoded()
    
    return if @current_part_index.nil?
    
    part = @sprite.parts[@current_part_index]
    @sprite.parts.delete_at(@current_part_index)
    part_offset = @sprite.parts_by_offset.key(part)
    @sprite.parts_by_offset[part_offset] = nil
    @part_pixmaps_for_part_view.delete_at(@current_part_index)
    @part_pixmaps_for_frame_view.delete_at(@current_part_index)
    
    @ui.part_index.removeItem(@sprite.parts.length)
    if @sprite.parts.length == 0
      frame_changed(@current_frame_index)
    else
      new_index = [@current_part_index, @sprite.parts.length-1].min
      frame_changed(@current_frame_index)
      part_changed(new_index)
    end
  end
  
  def add_keyframe(new_index)
    return if check_sprite_hardcoded()
    
    return if @current_animation.nil?
    
    frame_delay = FrameDelay.new
    @sprite.frame_delays << frame_delay
    next_frame_delay_offset = @sprite.frame_delays_by_offset.keys.max + 8
    @sprite.frame_delays_by_offset[next_frame_delay_offset] = frame_delay
    
    @current_animation.number_of_frames += 1
    @current_animation.initialize_frame_delays(@sprite.frame_delays, @sprite.frame_delays_by_offset)
    
    animation_changed(@current_animation_index)
    animation_frame_changed(new_index)
  end
  
  def frame_data_changed
    frame = @sprite.frames[@current_frame_index]
    return if frame.nil?
    
    first_part_index = @ui.frame_first_part.text.to_i(16)
    number_of_parts = @ui.frame_number_of_parts.text.to_i(16)
    first_part_index = [first_part_index, 0].max
    first_part_index = [first_part_index, @sprite.parts.length-1].min
    number_of_parts = [number_of_parts, 0].max
    number_of_parts = [number_of_parts, @sprite.parts.length-first_part_index].min
    
    if number_of_parts == 0 && !@ui.frame_first_part.text.strip.empty?
      # The user tried to set the first part to something before increasing number of parts above 0.
      # Just automatically increase number of parts for convenience.
      number_of_parts = 1
    end
    
    first_part = @sprite.parts[first_part_index]
    part_offset = @sprite.parts_by_offset.key(first_part)
    if part_offset
      frame.first_part_offset = part_offset
      frame.number_of_parts = number_of_parts
      frame.initialize_parts(@sprite.parts, @sprite.parts_by_offset)
    end
    
    if frame.part_indexes.first
      @ui.frame_first_part.text = "%02X" % frame.part_indexes.first
      part_changed(frame.part_indexes.first)
    else
      @ui.frame_first_part.text = ""
    end
    @ui.frame_number_of_parts.text = "%02X" % frame.number_of_parts
    
    frame_changed(@current_frame_index)
  end
  
  def click_gfx_scene(mouse_x, mouse_y, button)
    # Start selecting part on gfx page.
    
    return unless @selection_rectangle
    
    max_w = @gfx_file_graphics_scene.width
    max_h = @gfx_file_graphics_scene.height
    mouse_x = [mouse_x, 0].max
    mouse_y = [mouse_y, 0].max
    mouse_x = [mouse_x, max_w].min
    mouse_y = [mouse_y, max_h].min
    
    @selection_origin = Qt::PointF.new(mouse_x, mouse_y)
    x = mouse_x
    y = mouse_y
    w = 0
    h = 0
    @selection_rectangle.setRect(x, y, w, h)
  end
  
  def drag_gfx_scene(mouse_x, mouse_y, button)
    # Resize part selection on gfx page.
    
    return unless @selection_rectangle
    
    max_w = @gfx_file_graphics_scene.width.to_i
    max_h = @gfx_file_graphics_scene.height.to_i
    mouse_x = [mouse_x, 0].max
    mouse_y = [mouse_y, 0].max
    mouse_x = [mouse_x, max_w].min
    mouse_y = [mouse_y, max_h].min
    
    x1 = @selection_origin.x.to_i
    y1 = @selection_origin.y.to_i
    x2 = mouse_x.to_i
    y2 = mouse_y.to_i
    
    if SYSTEM == :gba
      # Round X/Y to nearest multiple of 8, since the GBA works in terms of 8x8 tiles.
      x1 = (x1.to_i / 8) * 8
      y1 = (y1.to_i / 8) * 8
      x2 = (x2.to_i / 8) * 8
      y2 = (y2.to_i / 8) * 8
      
      # Get all OBJ sizes that are valid on GBA.
      obj_sizes = Part::OBJ_SIZES.values.flatten(1)
      
      w = (x2 - x1).abs
      h = (y2 - y1).abs
      
      # Then select whichever size is overall closest to what the user has selected.
      obj_sizes_by_diff = obj_sizes.map do |other_w, other_h|
        diff = (w - other_w).abs + (h - other_h).abs
        [[other_w, other_h], diff]
      end
      obj_sizes_sorted_by_min_diff = obj_sizes_by_diff.sort_by{|size, diff| diff}
      best_obj_size, best_size_diff = obj_sizes_sorted_by_min_diff.find do |(other_w, other_h), diff|
        # Limit to sizes that don't go off the canvas.
        if x1 == max_w && x2 == max_w
          next if x1 - 8 + other_w > max_w
        elsif x2 >= x1
          next if x1 + other_w > max_w
        else
          next if x1 - other_w < 0
        end
        if y1 == max_h && y2 == max_h
          next if y1 - 8 + other_h > max_h
        elsif y2 >= y1
          next if y1 + other_h > max_h
        else
          next if y1 - other_h < 0
        end
        true
      end
      
      w, h = best_obj_size
      
      if x1 == max_w && x2 == max_w
        x1 -= 8
        x2 = x1 + w
      elsif x2 >= x1
        x2 = x1 + w
      else
        x2 = x1 - w
      end
      if y1 == max_h && y2 == max_h
        y1 -= 8
        y2 = y1 + h
      elsif y2 >= y1
        y2 = y1 + h
      else
        y2 = y1 - h
      end
      puts
    end
    
    x = [x2, x1].min
    y = [y2, y1].min
    w = [x2, x1].max - x
    h = [y2, y1].max - y
    
    @selection_rectangle.setRect(x, y, w, h)
  end
  
  def stop_dragging_gfx_scene(mouse_x, mouse_y, button)
    update_current_part()
  end
  
  def toggle_part_flips(checked)
    update_current_part()
  end
  
  def update_current_part
    return if @current_part_index.nil?
    
    x = @selection_rectangle.rect.x
    y = @selection_rectangle.rect.y
    w = @selection_rectangle.rect.width
    h = @selection_rectangle.rect.height
    
    if w == 0 || h == 0
      return
    end
    if x < 0 || x >= @gfx_file_graphics_scene.width || y < 0 || y >= @gfx_file_graphics_scene.height
      return
    end
    if x+w < 0 || x+w > @gfx_file_graphics_scene.width || y+h < 0 || y+h > @gfx_file_graphics_scene.height
      return
    end
    
    part = @sprite.parts[@current_part_index]
    part.gfx_x_offset = x.to_i
    part.gfx_y_offset = y.to_i
    part.width        = w.to_i
    part.height       = h.to_i
    
    part.gfx_page_index = @gfx_page_index
    part.palette_index = @palette_index - @sprite_info.palette_offset
    part.palette_index = 0 if part.palette_index < 0
    
    part.horizontal_flip = @ui.part_horizontal_flip.checked
    part.vertical_flip = @ui.part_vertical_flip.checked
    
    reload_current_part()
  end
  
  def reload_current_part
    return if @current_part_index.nil?
    
    part = @sprite.parts[@current_part_index]
    ensure_gfx_pages_for_palette_exist(@palette_index)
    chunky_gfx_page = @rendered_gfx_pages_by_palette[@palette_index][@gfx_page_index]
    
    if chunky_gfx_page.nil?
      # Invalid gfx page index, so just render a big red square.
      first_canvas_width = @gfx_pages_with_blanks.first.canvas_width
      chunky_gfx_page = @renderer.render_gfx(nil, nil, 0, 0, first_canvas_width*8, first_canvas_width*8, canvas_width=first_canvas_width*8)
    end
    
    chunky_part = @renderer.render_sprite_part(part, chunky_gfx_page)
    
    pixmap = Qt::Pixmap.new
    blob = chunky_part.to_blob
    pixmap.loadFromData(blob, blob.length)
    
    @part_pixmaps_for_part_view[@current_part_index] = PartItem.new(self, part, @current_part_index, pixmap)
    @part_pixmaps_for_frame_view[@current_part_index] = PartItem.new(self, part, @current_part_index, pixmap)
    
    part_changed(@current_part_index)
    frame_changed(@current_frame_index, do_not_change_current_part: true)
  end
  
  def update_part_position(part_index)
    part = @sprite.parts[part_index]
    @part_pixmaps_for_part_view[part_index].setPos(part.x_pos, part.y_pos)
    @part_pixmaps_for_frame_view[part_index].setPos(part.x_pos, part.y_pos)
    
    min_x = @sprite.min_x
    min_y = @sprite.min_y
    full_width = @sprite.full_width
    full_height = @sprite.full_height
    @frame_graphics_scene.setSceneRect(min_x, min_y, full_width, full_height)
    @part_graphics_scene.setSceneRect(min_x, min_y, full_width, full_height)
  end
  
  def closeEvent(event)
    if @skeleton_editor
      @skeleton_editor.close()
    end
  end
  
  def inspect; to_s; end
end

class PartItem < Qt::GraphicsPixmapItem
  def initialize(sprite_editor, part, part_index, pixmap)
    super(pixmap)
    setPos(part.x_pos, part.y_pos)
    
    @sprite_editor = sprite_editor
    @part = part
    @part_index = part_index
    
    setFlag(Qt::GraphicsItem::ItemIsMovable)
    setFlag(Qt::GraphicsItem::ItemSendsGeometryChanges)
    setFlag(Qt::GraphicsItem::ItemIsSelectable)
    setFlag(Qt::GraphicsItem::ItemIsFocusable)
  end
  
  def itemChange(change, value)
    if change == ItemPositionChange && scene()
      new_pos = value.toPointF()
      x = new_pos.x
      y = new_pos.y
      new_pos.setX(x)
      new_pos.setY(y)
      
      @part.x_pos = x.round
      @part.y_pos = y.round
      
      return super(change, Qt::Variant.new(new_pos))
    end
    
    return super(change, value)
  end
  
  def keyPressEvent(event)
    case event.key
    when Qt::Key_Up
      setPos(pos.x, pos.y-1)
      @sprite_editor.update_part_position(@part_index)
    when Qt::Key_Down
      setPos(pos.x, pos.y+1)
      @sprite_editor.update_part_position(@part_index)
    when Qt::Key_Left
      setPos(pos.x-1, pos.y)
      @sprite_editor.update_part_position(@part_index)
    when Qt::Key_Right
      setPos(pos.x+1, pos.y)
      @sprite_editor.update_part_position(@part_index)
    end
    
    super(event)
  end
  
  def mouseReleaseEvent(event)
    @sprite_editor.update_part_position(@part_index)
    super(event)
  end
end
