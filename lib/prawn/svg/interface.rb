#
# Prawn::Svg::Interface makes a Prawn::Svg::Document instance, uses that object to parse the supplied
# SVG into Prawn-compatible method calls, and then calls the Prawn methods.
#
module Prawn
  module Svg
    class Interface
      DEFAULT_FONT_PATHS = ["/Library/Fonts", "/System/Library/Fonts", "#{ENV["HOME"]}/Library/Fonts", "/usr/share/fonts/truetype"]
      CALLS_THAT_MUST_HAVE_A_BLOCK = ["transparent"]

      @font_path = []
      DEFAULT_FONT_PATHS.each {|path| @font_path << path if File.exists?(path)}

      class << self; attr_accessor :font_path; end

      attr_reader :data, :prawn, :document, :options

      #
      # Creates a Prawn::Svg object.
      #
      # +data+ is the SVG data to convert.  +prawn+ is your Prawn::Document object.
      #
      # +options+ must contain the key :at, which takes a tuple of x and y co-ordinates.
      #
      # +options+ can optionally contain the key :width or :height.  If both are
      # specified, only :width will be used.
      #
      def initialize(data, prawn, options, &block)
        @data = data
        @prawn = prawn
        @options = options

        @options[:at] or raise "options[:at] must be specified"

        Prawn::Svg::Font.load_external_fonts(prawn.font_families)

        @document = Document.new(data, [prawn.bounds.width, prawn.bounds.height], options, &block)
      end

      #
      # Draws the SVG to the Prawn::Document object.
      #
      def draw
        prawn.bounding_box(@options[:at], :width => @document.sizing.output_width, :height => @document.sizing.output_height) do
          prawn.save_graphics_state do
            clip_rectangle 0, 0, @document.sizing.output_width, @document.sizing.output_height
            proc_creator(prawn, Parser.new(@document).parse).call
          end
        end
      end


      private
      def proc_creator(prawn, calls)
        Proc.new {issue_prawn_command(prawn, calls)}
      end

      def issue_prawn_command(prawn, calls)
        calls.each do |call, arguments, children|
          if call == "end_path"
            issue_prawn_command(prawn, children) if children.any?
            prawn.add_content "n" # end path

          elsif rewrite_call_arguments(prawn, call, arguments) == false
            issue_prawn_command(prawn, children) if children.any?

          elsif children.empty? && CALLS_THAT_MUST_HAVE_A_BLOCK.include?(call)
            # DO NOTHING, this call requires a block but doesn't have it
            # for example an empty transparent svg tag
          elsif children.empty?
            prawn.send(call, *arguments)

          else
            prawn.send(call, *arguments, &proc_creator(prawn, children))
          end
        end
      end

      def rewrite_call_arguments(prawn, call, arguments)
        if call == 'relative_draw_text'
          call.replace "draw_text"
          arguments.last[:at][0] = @relative_text_position if @relative_text_position
        end

        case call
        when 'text_group'
          @relative_text_position = nil
          false

        when 'draw_text'
          text, options = arguments

          width = prawn.width_of(text, options.merge(:kerning => true))

          if (anchor = options.delete(:text_anchor)) && %w(middle end).include?(anchor)
            width /= 2 if anchor == 'middle'
            options[:at][0] -= width
          end

          space_width = prawn.width_of("n", options)
          @relative_text_position = options[:at][0] + width + space_width

        when 'transformation_matrix'
          left = prawn.bounds.absolute_left
          top = prawn.bounds.absolute_top
          arguments[4] += left - (left * arguments[0] + top * arguments[2])
          arguments[5] += top - (left * arguments[1] + top * arguments[3])

        when 'clip'
          prawn.add_content "W n" # clip to path
          false

        when 'save'
          prawn.save_graphics_state
          false

        when 'restore'
          prawn.restore_graphics_state
          false
        end
      end

      def clip_rectangle(x, y, width, height)
          prawn.move_to x, y
          prawn.line_to x + width, y
          prawn.line_to x + width, y + height
          prawn.line_to x, y + height
          prawn.close_path
          prawn.add_content "W n" # clip to path
      end
    end
  end
end
