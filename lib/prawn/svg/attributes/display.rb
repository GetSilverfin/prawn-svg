module Prawn::SVG::Attributes::Display
  def parse_display_attribute
    @attributes['display'] = 'none' if @attributes['visibility'] == 'hidden'
    state.display = attributes['display'].strip if attributes['display']
  end
end
