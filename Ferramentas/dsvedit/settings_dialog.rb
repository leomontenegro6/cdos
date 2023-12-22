
require_relative 'ui_settings'

class SettingsDialog < Qt::Dialog
  slots "browse_for_tiled_path()"
  slots "browse_for_nds_emulator_path()"
  slots "browse_for_gba_emulator_path()"
  slots "button_pressed(QAbstractButton*)"
  
  def initialize(main_window, settings)
    super(main_window, Qt::WindowTitleHint | Qt::WindowSystemMenuHint)
    @ui = Ui_Settings.new
    @ui.setup_ui(self)
    
    @settings = settings
    
    (0..2).each do |save_file_i|
      @ui.test_room_save_file.addItem("File #{save_file_i+1}")
    end
    
    @ui.tiled_path.text = @settings[:tiled_path]
    @ui.nds_emulator_path.text = @settings[:emulator_path]
    @ui.gba_emulator_path.text = @settings[:gba_emulator_path]
    @ui.test_room_save_file.currentIndex = @settings[:test_room_save_file_index] || 0
    
    connect(@ui.tiled_path_browse_button, SIGNAL("clicked()"), self, SLOT("browse_for_tiled_path()"))
    connect(@ui.nds_emulator_path_browse_button, SIGNAL("clicked()"), self, SLOT("browse_for_nds_emulator_path()"))
    connect(@ui.gba_emulator_path_browse_button, SIGNAL("clicked()"), self, SLOT("browse_for_gba_emulator_path()"))
    connect(@ui.buttonBox, SIGNAL("clicked(QAbstractButton*)"), self, SLOT("button_pressed(QAbstractButton*)"))
    
    self.show()
  end
  
  def browse_for_tiled_path
    env_vars_to_check = [
      "ProgramFiles",
      "ProgramFiles(x86)",
      "ProgramW6432",
    ]
    
    default_dir = nil
    env_vars_to_check.each do |env_var_name|
      if !ENV.include?(env_var_name)
        next
      end
      
      possible_install_path = File.join(ENV[env_var_name], "Tiled", "tiled.exe")
      if File.file?(possible_install_path)
        default_dir = possible_install_path
        break
      end
    end
    
    tiled_path = Qt::FileDialog.getOpenFileName(self, "Select Tiled install location", default_dir, "Program Files (*.exe)")
    return if tiled_path.nil?
    @ui.tiled_path.text = tiled_path
  end
  
  def browse_for_nds_emulator_path
    emulator_path = Qt::FileDialog.getOpenFileName()
    return if emulator_path.nil?
    @ui.nds_emulator_path.text = emulator_path
  end
  
  def browse_for_gba_emulator_path
    emulator_path = Qt::FileDialog.getOpenFileName()
    return if emulator_path.nil?
    @ui.gba_emulator_path.text = emulator_path
  end
  
  def button_pressed(button)
    if @ui.buttonBox.standardButton(button) == Qt::DialogButtonBox::Ok
      @settings[:tiled_path] = @ui.tiled_path.text
      @settings[:emulator_path] = @ui.nds_emulator_path.text
      @settings[:gba_emulator_path] = @ui.gba_emulator_path.text
      @settings[:test_room_save_file_index] = @ui.test_room_save_file.currentIndex
    end
  end
end
