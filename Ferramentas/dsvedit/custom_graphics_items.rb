
class GraphicsChunkyItem < Qt::GraphicsPixmapItem
  def initialize(chunky_image)
    pixmap = Qt::Pixmap.new
    blob = chunky_image.to_blob
    pixmap.loadFromData(blob, blob.length)
    super(pixmap)
  end
  
  def boundingRect
    # If the sprite is smaller than 16x16, make sure the bounding rectangle is at least 16x16.
    
    orig_rect = super()
    top = orig_rect.top()
    bottom = orig_rect.bottom()
    left = orig_rect.left()
    right = orig_rect.right()
    
    width = bottom - top
    height = right - left
    if width < 8
      left -= (8-width)/2
      right += (8-width)/2
    end
    if height < 8
      top -= (8-height)/2
      bottom += (8-height)/2
    end
    
    return Qt::RectF.new(left, top, right-left, bottom-top)
  end
  
  def shape
    # Make the whole bounding rectangle clickable, instead of just the sprite's pixels.
    path = Qt::PainterPath.new
    path.addRect(boundingRect())
    return path
  end
end

class EntityChunkyItem < GraphicsChunkyItem
  attr_reader :entity
  
  def initialize(chunky_image, entity, main_window)
    super(chunky_image)
    
    @main_window = main_window
    @entity = entity
    
    setFlag(Qt::GraphicsItem::ItemIsMovable)
    setFlag(Qt::GraphicsItem::ItemSendsGeometryChanges)
    
    setCursor(Qt::Cursor.new(Qt::SizeAllCursor))
  end
  
  def itemChange(change, value)
    if change == ItemPositionChange && scene()
      new_pos = value.toPointF()
      x = new_pos.x
      y = new_pos.y
      
      if $qApp.keyboardModifiers & Qt::ControlModifier == 0
        x = (x / 16).round * 16
        y = (y / 16).round * 16
        new_pos.setX(x)
        new_pos.setY(y)
      end
      
      @entity.x_pos = x
      @entity.y_pos = y
      @entity.write_to_rom()
      
      return super(change, Qt::Variant.new(new_pos))
    end
    
    return super(change, value)
  end

  def mouseReleaseEvent(event)
    @main_window.update_room_bounding_rect()
    super(event)
  end
end

class EntityRectItem < Qt::GraphicsRectItem
  NOTHING_BRUSH        = Qt::Brush.new(Qt::Color.new(200, 200, 200, 150))
  ENEMY_BRUSH          = Qt::Brush.new(Qt::Color.new(200, 0, 0, 150))
  SPECIAL_OBJECT_BRUSH = Qt::Brush.new(Qt::Color.new(0, 0, 200, 150))
  CANDLE_BRUSH         = Qt::Brush.new(Qt::Color.new(200, 200, 0, 150))
  OTHER_BRUSH          = Qt::Brush.new(Qt::Color.new(200, 0, 200, 150))
  
  attr_reader :entity
  
  def initialize(entity, main_window)
    super(-8, -8, 16-1, 16-1)
    setPos(entity.x_pos, entity.y_pos)
    
    @main_window = main_window
    
    setFlag(Qt::GraphicsItem::ItemIsMovable)
    setFlag(Qt::GraphicsItem::ItemSendsGeometryChanges)
    
    setCursor(Qt::Cursor.new(Qt::SizeAllCursor))
    
    case entity.type
    when NOTHING_ENTITY_TYPE
      self.setBrush(NOTHING_BRUSH)
    when ENEMY_ENTITY_TYPE
      self.setBrush(ENEMY_BRUSH)
    when SPECIAL_OBJECT_ENTITY_TYPE
      self.setBrush(SPECIAL_OBJECT_BRUSH)
    when CANDLE_ENTITY_TYPE
      self.setBrush(CANDLE_BRUSH)
    else
      self.setBrush(OTHER_BRUSH)
    end
    @entity = entity
  end
  
  def itemChange(change, value)
    if change == ItemPositionChange && scene()
      new_pos = value.toPointF()
      x = new_pos.x
      y = new_pos.y
      
      if $qApp.keyboardModifiers & Qt::ControlModifier == 0
        # Snap to 16x16 grid unless Ctrl is held down.
        x = (x / 16).round * 16
        y = (y / 16).round * 16
        new_pos.setX(x)
        new_pos.setY(y)
      end
      
      @entity.x_pos = x
      @entity.y_pos = y
      @entity.write_to_rom()
      
      return super(change, Qt::Variant.new(new_pos))
    end
    
    return super(change, value)
  end

  def mouseReleaseEvent(event)
    @main_window.update_room_bounding_rect()
    super(event)
  end
end

class DoorItem < Qt::GraphicsRectItem
  BRUSH = Qt::Brush.new(Qt::Color.new(200, 0, 200, 50))
  GLITCH_DOOR_BRUSH = Qt::Brush.new(Qt::Color.new(0, 200, 50, 50))
  CRASHING_GLITCH_DOOR_BRUSH = Qt::Brush.new(Qt::Color.new(200, 50, 50, 50))
  
  attr_reader :door
  
  def initialize(door, door_index, main_window)
    super(0, 0, SCREEN_WIDTH_IN_PIXELS-1, SCREEN_HEIGHT_IN_PIXELS-1)
    
    x = door.x_pos
    y = door.y_pos
    x = -1 if x == 0xFF
    y = -1 if y == 0xFF
    x *= SCREEN_WIDTH_IN_PIXELS
    y *= SCREEN_HEIGHT_IN_PIXELS
    setPos(x, y)
    
    @main_window = main_window
    @door = door
    @door_index = door_index
    
    if door.is_glitch_door
      setToolTip("Glitch door %02X" % door_index)
      if door.game.check_room_exists_by_metadata_pointer(door.destination_room_metadata_ram_pointer)
        self.setBrush(GLITCH_DOOR_BRUSH)
      else
        self.setBrush(CRASHING_GLITCH_DOOR_BRUSH)
      end
    else
      setToolTip("Door %02X" % door_index)
      self.setBrush(BRUSH)
      setFlag(Qt::GraphicsItem::ItemIsMovable)
      setFlag(Qt::GraphicsItem::ItemSendsGeometryChanges)
    end
    
    setCursor(Qt::Cursor.new(Qt::SizeAllCursor))
  end
  
  def itemChange(change, value)
    if change == ItemPositionChange && scene()
      new_pos = value.toPointF()
      x = (new_pos.x / SCREEN_WIDTH_IN_PIXELS).round
      y = (new_pos.y / SCREEN_HEIGHT_IN_PIXELS).round
      x = [x, 0x7F].min
      x = [x, -1].max
      y = [y, 0x7F].min
      y = [y, -1].max
      new_pos.setX(x*SCREEN_WIDTH_IN_PIXELS)
      new_pos.setY(y*SCREEN_HEIGHT_IN_PIXELS)
      
      @door.x_pos = [x].pack("C").unpack("C").first
      @door.y_pos = [y].pack("C").unpack("C").first
      @door.write_to_rom()
      
      return super(change, Qt::Variant.new(new_pos))
    end
    
    return super(change, value)
  end

  def mouseReleaseEvent(event)
    @main_window.update_room_bounding_rect()
    super(event)
  end
end

class DoorDestinationMarkerItem < Qt::GraphicsRectItem
  BRUSH = Qt::Brush.new(Qt::Color.new(255, 127, 0, 120))
  
  def initialize(dest_x, dest_y, dest_room, door_editor)
    @width = SCREEN_WIDTH_IN_PIXELS-1
    @height = SCREEN_HEIGHT_IN_PIXELS-1
    if GAME == "hod"
      @height -= 0x60
    end
    super(0, 0, @width, @height)
    
    x = dest_x
    y = dest_y
    setPos(x, y)
    
    @door_editor = door_editor
    @dest_room_width = dest_room.width*SCREEN_WIDTH_IN_PIXELS
    @dest_room_height = dest_room.height*SCREEN_HEIGHT_IN_PIXELS
    
    self.setBrush(BRUSH)
    
    setFlag(Qt::GraphicsItem::ItemIsMovable)
    setFlag(Qt::GraphicsItem::ItemSendsGeometryChanges)
    
    setCursor(Qt::Cursor.new(Qt::SizeAllCursor))
  end
  
  def set_dest_room_size(width, height)
    @dest_room_width = width*SCREEN_WIDTH_IN_PIXELS
    @dest_room_height = height*SCREEN_HEIGHT_IN_PIXELS
  end
  
  def itemChange(change, value)
    if change == ItemPositionChange && scene()
      new_pos = value.toPointF()
      x = (new_pos.x / 0x10).round
      y = (new_pos.y / 0x10).round
      x = x * 0x10
      y = y * 0x10
      #x = [x, 0x7FFF].min
      #x = [x, -0x7FFF].max
      #y = [y, 0x7FFF].min
      #y = [y, -0x7FFF].max
      x = [x, @dest_room_width-@width].min
      x = [x, 0].max
      y = [y, @dest_room_height-@height].min
      y = [y, 0].max
      new_pos.setX(x)
      new_pos.setY(y)
      
      @door_editor.update_dest_x_and_y_fields(x, y)
      
      return super(change, Qt::Variant.new(new_pos))
    end
    
    return super(change, value)
  end

  #def mouseReleaseEvent(event)
  #  @main_window.update_room_bounding_rect()
  #  super(event)
  #end
end
