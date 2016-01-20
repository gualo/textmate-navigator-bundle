#!/usr/bin/env ruby

###############################################################################
#	Copyright (c) 2012 Eduardo Francos,  All rights reserved.
###############################################################################
#
# DISCLAIMER
#
# Eduardo Francos makes no warranties, representations or commitments
# with regard to the contents of this software. Eduardo Francos
# specifically disclaims any and all warranties, whether express, implied or
# statutory, including, but not limited to, any warranty of merchantability
# or fitness for a particular purpose, and non-infringement. Under no
# circumstances will Eduardo Francos be liable for loss of data,
# special, incidental or consequential damages out of the use of this
# software, even if those damages were foreseeable, or Eduardo Francos
# was informed of their potential.
#
# TODO: push soft position when starting back/forward navigation so that a
# return to top can go back to where the user was positioned
# TODO: save the line context with the position so we can use
# smart positioning

# used for debugging purposes
if __FILE__ == $0
	ENV['TM_BUNDLE_PATH'] = ENV['TM_PROJECT_DIRECTORY']
	ENV['TM_BUNDLE_SUPPORT'] = "#{ENV['TM_BUNDLE_PATH']}/Support"
end

require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require 'fileutils'

class Positions
	STACK_LINE_FIELD = 0
	STACK_COLUMN_FIELD = 1
	STACK_FPATH_FIELD = 2
	STACK_EXP_FIELD = 3
	STACK_VIEW_POINT_FIELD = 0
	STACK_SEPARATOR = "\t"

	POSITION_TAG_LOG = 0x01
	REFRESH_TAGS_LOG = 0x02
	POSITION_INFO_LOG = 0x04
  HOUSEKEEPING_LOG = 0x08

	attr_accessor :stack_path

	def initialize
		@log = NavLogger.get_logger
		@log.level = NavLogger::DEBUG
		@log.set_subjects 0  # POSITION_INFO_LOG | POSITION_TAG_LOG
		@log.use_html = true;

    navstack_path = ENV['TM_NAVIGATOR_NAVSTACK_PATH']
    # if it starts with '@' then it's an environment variable
    if navstack_path[0].chr == "@"
      navstack_path = ENV[navstack_path[1..-1]]
    end
		fpath = File.expand_path(navstack_path.gsub(/\$\w+/) {|m| ENV[m[1..-1]]} )
		FileUtils.mkdir_p(fpath)
		@stack_path = File.join(fpath, "#{ENV['TM_NAVIGATOR_NAVSTACK_FNAME']}")
    @log.debug POSITION_INFO_LOG,  "stack_path=#{@stack_path}"
		@stack = []
		@view_point = 0
	end

	def create_empty_stack
		File.open(@stack_path, 'w') {|f| f.write("0") }
	end

	# loads the stack positions file and extracts
	# the positions, view_point
	def load_stack(create=true)
		# if file missing then create a new one if requested
		if !FileTest.exist?(@stack_path)
			if create
				create_empty_stack
			else
				return false
			end
		end

		@stack=[]
		IO.foreach(@stack_path) {|line|
			@stack.push line.chomp
		}

		# take the view point from the last line in the array removing it
		view_point_info = @stack.delete_at(-1)
		view_point_info = view_point_info.split(STACK_SEPARATOR)
		@view_point = view_point_info[STACK_VIEW_POINT_FIELD].to_i
    @log.debug HOUSEKEEPING_LOG, "view_point=#{@view_point}\n"

		return true
	end

	def save_stack
		File.open(@stack_path, 'w') { |fd|
			@stack.each {|line|
				fd.puts line
			}
			fd.puts "#{@view_point}"
		}
	end

	def navigate_to_position(position)
    # @log.debug POSITION_TAG_LOG, "Navigating to position.path, position.to_lookup_expression, position.line, position.column=#{position.path}, #{position.to_lookup_expression}, #{position.line}, #{position.column}"
		# check if the file exists, if not then inform the user about
		# it and skip the operation
		if !FileTest.exist?(position.path)
			TextMate.exit_show_tool_tip("File #{position.path} does not exist")
		end

    # @log.debug POSITION_TAG_LOG, "Navigating to position.path, position.to_lookup_expression, position.line, position.column=#{position.path}, #{position.to_lookup_expression}, #{position.line}, #{position.column}"
		Navigator.goto_file position.path, position.to_lookup_expression, position.line, position.column+1
	end

	def push_position
		if !Navigator.check_doc(ENV['TM_FILEPATH'])
			return
		end

		load_stack

		# cut the stack at the viewpoint in case the user was browsing
		# back in the stack history
		# we start a new "root" at the view point
    # @log.debug POSITION_INFO_LOG, "Viewpoint before slicing #{@view_point}\n"
		@stack = @stack.slice(0, @view_point)
    # @log.debug POSITION_INFO_LOG, "Stack after slicing\nSTART\n#{@stack}\nEND\n"

		# add the current pushed position
    line_number, line_index = get_caret_information
    line_content = get_position_content
    # @log.debug POSITION_INFO_LOG, "PositionInfo.new(#{line_number}, #{line_index}, '#{ENV['TM_FILEPATH']}', '#{line_content}')"
		position = PositionInfo.new(line_number, line_index, ENV['TM_FILEPATH'], line_content)
    # @log.debug POSITION_INFO_LOG, "Position line :#{position}:\n"
		@stack.push position.as_stack_item
    # @log.debug POSITION_INFO_LOG, "Stack after pushing\nSTART\n#{@stack}\nEND\n"

		# set the view point to the current position
		@view_point = @stack.size

		save_stack

		# finally tell our user we saved the position
		print "Position #{@view_point} saved at #{position.to_display}"
	end

  def get_position_content
    # TM2 TM_SELECTION=2:23[-2:13]
    if !ENV['TM_SELECTION'].nil?
      # @log.debug POSITION_INFO_LOG, "get_position_content::TM_SELECTION=#{ENV['TM_SELECTION']}"
      ""
    else
      ENV['TM_CURRENT_LINE'].strip
      # @log.debug POSITION_INFO_LOG, "get_position_content::TM_CURRENT_LINE=#{ENV['TM_CURRENT_LINE'].strip}"
    end
  end
  
  def get_caret_information
    # TM2 TM_SELECTION=2:23[ -2:13]
    if !ENV['TM_SELECTION'].nil?
      Navigator.decode_selection_spec ENV['TM_SELECTION']
    else
      # TM1
      if !ENV['TM_LINE_NUMBER'].nil?
        # @log.debug POSITION_INFO_LOG, "get_caret_information::has line number=#{[ENV['TM_LINE_NUMBER'], ENV['TM_LINE_INDEX']].inspect}"
        [ENV['TM_LINE_NUMBER'], ENV['TM_LINE_INDEX']]
      else
        # @log.debug POSITION_INFO_LOG, "get_caret_information::unknown version returning #{["1", "0"].inspect}"
        ["1", "0"]
      end
    end
  end
  
	def pop_position
		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		# extract the line at the top of the stack and remove it
		position = PositionInfo.new(@stack.delete_at(-1))

		# set the viewpoint to the end of the stack
		@view_point = @stack.size

		save_stack

		navigate_to_position position
	end

	##
	# Toggles the current cursor position with the last position
	# pushed onto the stack.
	def toggle_last_position
		if !Navigator.check_doc(ENV['TM_FILEPATH'])
			return
		end

		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		# pop the last position
		last_position = PositionInfo.new(@stack.delete_at(-1))

		# add the current position
		new_position = PositionInfo.new(ENV['TM_LINE_NUMBER'], ENV['TM_LINE_INDEX'], ENV['TM_FILEPATH'], ENV['TM_CURRENT_LINE'])
		@log.debug POSITION_TAG_LOG, "Position line :#{new_position}:\n"
		@stack.push new_position.as_stack_item
		@log.debug POSITION_TAG_LOG, "Stack after pushing\nSTART\n#{@stack}\nEND\n"

		# set the viewpoint to the end of the stack
		@view_point = @stack.size

		save_stack

		navigate_to_position last_position
	end

	#---------------------------------------------
	# moves backwards in the position stack from the current view point
	# wrapping to the top when hitting the bottom
	#---------------------------------------------
	def go_backwards
		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		# move the view point to the previous position
		@view_point -= 1

		# if are at the bottom of the stack then wrap to the top of it informing the user
		if @view_point == 0
			print "Bottom of the stack, wrapping to top"
			@view_point = @stack.size
		end

		# get the position line at the view point
		position = PositionInfo.new(@stack[@view_point-1])

		save_stack

		navigate_to_position position
	end

	#---------------------------------------------
	# moves forward in the position stack from the current view point
	# wrapping to the bottom when hitting the top
	#---------------------------------------------
	def go_forward
		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		# move the view point to the next position.
		# if we are at the top of the stack then
		# wrap to the bottom of it informing the user
		@view_point += 1
		if @view_point > @stack.size
			print "Top of the stack, wrapping to the bottom\n"
			@view_point = 1
		end

		# get the position line at the view point
		position = PositionInfo.new(@stack[@view_point - 1])

		save_stack

		navigate_to_position position
	end

	#---------------------------------------------
	# moves to the top of the stack
	#---------------------------------------------
	def go_top
		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		# move the view point to the top of the stack
		@view_point = @stack.size

		save_stack

		# get the position line at the new view point
		position = PositionInfo.new(@stack[@view_point - 1])

		navigate_to_position position

		print "Back to the top"
	end

	def clear_all
		create_empty_stack
		print "Navigation stack cleared"
	end

	# DOC: Add goto_history_position to documentation
	def goto_history_position
		if !load_stack(false) || @stack.size == 0
			TextMate.exit_show_tool_tip("The position stack is empty")
		end

		len = @stack.length
		stack_menu = []
		(0..(len-1)).reverse_each {|idx|
			pos = PositionInfo.new(@stack[idx])
			stack_menu.push(pos.to_display)
		}

		pos_idx = TextMate::UI.menu(stack_menu)
		@log.debug "Selected pos idx #{pos_idx}\n"
		if !pos_idx.nil?
			navigate_to_position PositionInfo.new(@stack[pos_idx])
		end
	end

	def display_stack
		len = @stack.length
		(0..(len-1)).reverse_each {|idx|
			pos = PositionInfo.new(@stack[idx])
			puts "#{idx+1}) #{Navigator.shorten_path(pos.path, 60)} #{Navigator.shorten_string(pos.lookup_expression, 10)}"
			# puts "#{idx+1}) #{pos.to_display}"
		}
	end
end

class PositionInfo
	attr_accessor :line
	attr_accessor :column
	attr_accessor :path
	attr_accessor :lookup_expression

	def initialize(*args)
		@log = NavLogger.get_logger
		@log.level = NavLogger::WARN
		@log.set_subjects Positions::POSITION_INFO_LOG

		if (args.size > 1)
			init_from_position_components args[0], args[1], args[2], args[3]
		else
			init_from_position_line args[0]
		end
	end

	def init_from_position_line(position)
		@log.debug Positions::POSITION_INFO_LOG, "position=#{position}"
		# position_info = position.scan("(.+?)#{Positions::STACK_SEPARATOR}(.+?)#{Positions::STACK_SEPARATOR}(.+?)#{Positions::STACK_SEPARATOR}(.*)")
		position_info = position.scan(/^(.+?)\t(.+?)\t(.+?)\t(.*)$/).flatten
		@line = position_info[Positions::STACK_LINE_FIELD].to_i
		@column = position_info[Positions::STACK_COLUMN_FIELD].to_i
		@path = position_info[Positions::STACK_FPATH_FIELD]
		@lookup_expression = position_info[Positions::STACK_EXP_FIELD]
		@log.debug Positions::POSITION_INFO_LOG, "inspect=#{inspect}"
	end

	def init_from_position_components(line, column, path, exp)
		@log.debug Positions::POSITION_INFO_LOG, "line, column, path, exp=#{line}, #{column}, #{path}, #{exp}"
		@line = line
		@column = column
		@path = path
		@lookup_expression = exp
		@log.debug Positions::POSITION_INFO_LOG, "inspect=#{inspect}"
	end

	def to_s
		"[#{@line},#{@column}] #{@path}"
	end

	def to_display
		"[#{@line},#{@column}] #{Navigator.shorten_path(@path, 60)} #{Navigator.shorten_string(@lookup_expression, 40)}"
	end

	def as_stack_item
    @log.debug Positions::POSITION_INFO_LOG, "as_stack_item:#{self.inspect}"
    @line + Positions::STACK_SEPARATOR + 
      @column + Positions::STACK_SEPARATOR + 
      @path + Positions::STACK_SEPARATOR + 
      @lookup_expression
	end

	def inspect
		"{line => #{@line}, column => #{@column}, path => #{@path}, lookup_expression => #{@lookup_expression}}"
	end

	def to_lookup_expression
		@log.debug(Positions::POSITION_INFO_LOG, "Navigator.escape_regexp(@lookup_expression, true)=#{Navigator.escape_regexp(@lookup_expression, true)}")
		exp = Navigator.escape_regexp(@lookup_expression)
		exp = Regexp.new("#{exp}")
		@log.debug(Positions::POSITION_INFO_LOG, "exp.inspect=#{exp.inspect}")
		exp
	end
end


if __FILE__ == $0
	Positions.new.push_position
	# Positions.new.pop_position
	# Positions.new.go_backwards
	# Positions.new.go_forward
end



