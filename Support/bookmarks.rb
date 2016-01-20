#!/usr/bin/env ruby
# encoding: utf-8

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

# used for debugging purposes
if __FILE__ == $0
	ENV['TM_BUNDLE_PATH'] = ENV['TM_PROJECT_DIRECTORY']
	ENV['TM_BUNDLE_SUPPORT'] = "#{ENV['TM_BUNDLE_PATH']}/Support"
end
require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/positions.rb'
require 'fileutils'

BOOKMARKS_NAME_FIELD = 0
BOOKMARKS_LINE_FIELD = 1
BOOKMARKS_FPATH_FIELD = 2
BOOKMARKS_CONTENTS_FIELD = 3
BOOKMARKS_VIEW_POINT_FIELD = 0
BOOKMARKS_SEPARATOR = "\t"
BOOKMARKS_ALT_SEPARATOR = '-'
PROJECT_SCOPE = 'Project'
GLOBAL_SCOPE = 'Global'
DOCUMENT_SCOPE = 'Document'

class Bookmarks
  UPDATE_BMS_LOG = 1
  BOOKMARK_INFO_LOG = 2
	POSITION_BM_LOG = 4
	attr_accessor :global_bookmarks_path


  def initialize
    @log = NavLogger.get_logger
    @log.level = NavLogger::WARN
    # @log.set_subjects UPDATE_BMS_LOG | BOOKMARK_INFO_LOG
    @log.set_subjects 0

    prj_dir = "#{ENV['TM_PROJECT_DIRECTORY']}"
    if !prj_dir.empty?
      @project_bookmarks_path = "#{prj_dir}/#{ENV['TM_NAVIGATOR_BOOKMARKS_FNAME']}"
    end

    # if the global bookmarks path is absolute (i.e. starts with a '/') then use it as is
    # otherwise use it as suffix after the user's HOME directory
    if ENV['TM_NAVIGATOR_BOOKMARKS_PATH'][0] == '/'
      @global_bookmarks_path = "ENV['TM_NAVIGATOR_BOOKMARKS_PATH']/#{ENV['TM_NAVIGATOR_BOOKMARKS_FNAME']}"
    else
      @global_bookmarks_path = "#{ENV['HOME']}/#{ENV['TM_NAVIGATOR_BOOKMARKS_PATH']}/#{ENV['TM_NAVIGATOR_BOOKMARKS_FNAME']}"
    end
    @bookmarks = []
    @view_point = 0
  end

  def create_empty_bookmarks(path)
		# ensure path exists
		bmPath = File.dirname(path)
		if !File.exist?(bmPath)
			FileUtils.mkdir_p(bmPath)
		end
    File.open(path, 'w') {|f| f.write("0") }
  end

  # loads the bookmarks positions file and extracts
  # the bookmark tags and view_point
  def load_bookmarks(scope, create=true)
    path = scope == PROJECT_SCOPE ? @project_bookmarks_path : @global_bookmarks_path
    @log.info "scope=#{scope} path=#{path}\n"
    # if file missing then create a new one if requested
    if !FileTest.exist?(path)
      if create
        create_empty_bookmarks path
      else
        return false
      end
    end

    @bookmarks=[]
    IO.foreach(path) {|line|
      @log.info "loading bm=#{line.chomp}\n"
      bm = BookmarkInfo.from_tag_line(line.chomp, scope)
      # error in bm? must be the viewpoint line
      if bm.nil?
        # take the view point from the last line in the array removing it
        @view_point = line.chomp.to_i
        break
      else
        @bookmarks.push bm
        @log.info "Loaded bm #{bm.to_s}\n"
      end
    }

    return true
  end

  def save_bookmarks_table(scope)
    path = scope == PROJECT_SCOPE ? @project_bookmarks_path : @global_bookmarks_path
    @log.info "Saving to #{scope} scope path=#{path}"
    File.open(path, 'w') { |fd|
      @bookmarks.each {|bm|
        fd.puts bm.to_s
      }
      fd.puts "#{@view_point}"
    }
  end

  def position_bookmark(bm)
    path = bm.full_path
    # check if the file exists, if not then inform the user about
    # it and skip the operation
    if !FileTest.exist?(path)
      TextMate.exit_show_tool_tip("File #{path} does not exist")
    end

    @log.debug POSITION_BM_LOG, "Navigating to tag.path, tag.lookup_expression, tag.line=#{path}, #{bm.to_lookup_expression}, #{bm.line}"
    Navigator.goto_file path, bm.to_lookup_expression, bm.line, 1
  end

  def select_bookmark(bookmarks)
    @log.info "Bookmarks for select\n#{bookmarks.inspect}\n"
    sorted_bms = bookmarks.sort {|bm1, bm2| bm1.name <=> bm2.name}
    @log.info "Sorted Bookmarks\n#{bookmarks.inspect}\n"

		name_width = sorted_bms.max{|bm1,bm2| bm1.name.length<=>bm2.name.length }.name.length + 5
    bms_menu = sorted_bms.collect {|bm| "#{bm.name.ljust(name_width)}#{bm.line}:#{File.basename(bm.path).ljust(30)}#{bm.contents}"}

    bm_idx = TextMate::UI.menu(bms_menu)
    @log.info "Selected bm idx #{bm_idx}\n"
    if !bm_idx.nil?
      selected_bm = sorted_bms[bm_idx]
      # find it in the bookmarks table
      bm_idx = @bookmarks.index{|bm| bm.name  == selected_bm.name}
    end
    @log.info "Final bm idx #{bm_idx}\n"

    return bm_idx
  end

  def set_project_bookmark
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    set_bookmark PROJECT_SCOPE
  end

  def set_global_bookmark
    set_bookmark GLOBAL_SCOPE
  end

  def set_bookmark(scope)
    # first check if the document has not been linked to a file yet
    if !Navigator.check_doc(ENV['TM_FILEPATH'])
      return
    end

    load_bookmarks scope

    # get the bookmark's name from the user
    if ENV['TM_SELECTED_TEXT'].nil?
      if ENV['TM_CURRENT_WORD'].nil?
        default = ENV['TM_CURRENT_LINE'].strip
      else
        default = ENV['TM_CURRENT_WORD'].strip
        default = ENV['TM_CURRENT_LINE'].strip if default.empty?
      end
    else
      default = ENV['TM_SELECTED_TEXT'].strip
    end
    bm_name = TextMate::UI.request_string(:title => "Set #{scope} Named Bookmark", :prompt => "Bookmark name:", :default => "#{default}")
    return if bm_name.nil?
    # clean up
    bm_name = bm_name.strip.gsub(BOOKMARKS_SEPARATOR, BOOKMARKS_ALT_SEPARATOR)
    bm_name = Time.new.strftime("%Y_%m_%d-%I_%M_%S") if bm_name.empty?

    # check if the name exists already and if so just replace its contents
    bm = @bookmarks.select{|abm| abm.name == bm_name}[0]

    # new bookmark?, add a slot in the table
    if bm.nil?
      bm = BookmarkInfo.for_name(bm_name, scope)
      @bookmarks.push(bm)
      action = 'set'
    else
      action = 'updated'
    end

    if scope == PROJECT_SCOPE
      # for project scope we keep a project relative path
      bm.path = ENV['TM_FILEPATH'][ENV['TM_PROJECT_DIRECTORY'].size+1..ENV['TM_FILEPATH'].size]
    else
      bm.path = ENV['TM_FILEPATH']
    end
    bm.line = get_caret_information.first.to_i
    bm.contents = get_position_content

    save_bookmarks_table scope

    # finally tell our user we saved the position
    print "Bookmark '#{bm.name}' #{action} at #{bm.to_display}"
  end

  def get_position_content
    # TM2 TM_SELECTION=2:23[-2:13]
    if !ENV['TM_SELECTION'].nil?
      ""
    else
      ENV['TM_CURRENT_LINE'].strip
    end
  end
  
  def get_caret_information
    # TM2 TM_SELECTION=2:23[-2:13]
    if !ENV['TM_SELECTION'].nil?
      Navigator.decode_selection_spec ENV['TM_SELECTION']
    else
      # TM1
      if !ENV['TM_LINE_NUMBER'].nil?
        [ENV['TM_LINE_NUMBER'], ENV['TM_LINE_INDEX']]
      else
        ["1", "0"]
      end
    end
  end
  

  def goto_global_bookmark
    goto_bookmark GLOBAL_SCOPE
  end

  def goto_project_bookmark
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    goto_bookmark PROJECT_SCOPE
  end

  # goto a bookmark in this document
  def goto_document_bookmark
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE
    goto_bookmark scope, true
  end

  # goto a bookmark in any document
  def goto_bookmark(scope, filter_document = false)
    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{scope} bookmarks")
    end
    @log.info "Bookmarks after loading\n#{@bookmarks.inspect}\n"

    if filter_document
      docbms = get_document_bookmarks
      @log.info "Doc Bookmarks\n#{docbms.inspect}\n"
      bm_idx = select_bookmark(get_document_bookmarks)
    else
      bm_idx = select_bookmark(@bookmarks)
    end
    if !bm_idx.nil?
      position_bookmark @bookmarks[bm_idx]
    end
  end

  # call a bookmark in this project
  def call_project_bookmark
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    call_bookmark PROJECT_SCOPE
  end

  # call a bookmark in any document
  def call_global_bookmark
    call_bookmark GLOBAL_SCOPE
  end

  # call a bookmark in this document
  def call_document_bookmark
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE
    call_bookmark scope, true
  end

  def call_bookmark(scope, filter_document = false)
    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{scope} bookmarks")
    end

    if filter_document
      bm_idx = select_bookmark(get_document_bookmarks)
    else
      bm_idx = select_bookmark(@bookmarks)
    end
    if !bm_idx.nil?
      Positions.new.push_position
      position_bookmark @bookmarks[bm_idx]
    end
  end

  def get_document_bookmarks
    doc_path = ENV['TM_SELECTED_FILE']
    doc_bms = @bookmarks.select {|bm|
      @log.info "comparing tag #{bm.to_s}\n\n"
      @log.info "comparing #{bm.inspect} against #{doc_path}\n\n"
      doc_path.end_with?(bm.path)
    }
    return doc_bms
  end

  def remove_global_bookmark
    if !load_bookmarks(GLOBAL_SCOPE, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{GLOBAL_SCOPE} bookmarks")
    end
    remove_bookmark @bookmarks, GLOBAL_SCOPE
  end

  def remove_project_bookmark
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    if !load_bookmarks(PROJECT_SCOPE, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{PROJECT_SCOPE} bookmarks")
    end
    remove_bookmark @bookmarks, PROJECT_SCOPE
  end

  def remove_document_bookmark
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE

    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{scope} bookmarks")
    end
    remove_bookmark get_document_bookmarks, scope
  end

  def remove_bookmark(bookmarks, scope)
    bm_idx = select_bookmark bookmarks
    if bm_idx.nil?
      TextMate.exit_discard
    end

    # remove it
    bm = @bookmarks.delete_at(bm_idx)

    # check the view point
    if @view_point > @bookmarks.size
      @view_point = @bookmarks.size
    end

    save_bookmarks_table scope

    print "Bookmark '#{bm.name}' was removed"
  end

  def clear_all_document_bookmarks()
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE
    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved bookmarks for this document")
    end
    count = @bookmarks.size
    @bookmarks.reject! {|bm|
      @log.info "comparing path\n(#{path}) to\n #{path}"
      bm.full_path == ENV['TM_SELECTED_FILE']
    }

    # check the view point
    if @view_point > @bookmarks.size
      @view_point = @bookmarks.size
    end

    save_bookmarks_table scope

    if (delta = (count - @bookmarks.size)) > 0
      print "#{delta} bookmarks have been removed"
    else
      print "No bookmarks have been removed"
    end
  end

  def clear_all_global_bookmarks
    clear_all GLOBAL_SCOPE
  end

  def clear_all_project_bookmarks
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    clear_all PROJECT_SCOPE
  end

  def clear_all(scope)
    TextMate.exit_discard if !TextMate::UI.request_confirmation(:title => "Navigator - Clear all #{scope} Bookmarks", :prompt => "Are you sure you want to clear all the #{scope} bookmarks?")
    path = scope == PROJECT_SCOPE ? @project_bookmarks_path : @global_bookmarks_path
    create_empty_bookmarks path
    print "#{scope} bookmarks cleared"
  end

  def update_project_bookmarks
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    if !load_bookmarks(PROJECT_SCOPE, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{PROJECT_SCOPE} bookmarks")
    end

    # cleanup bookmarks to missing files
    count = @bookmarks.size
    # @log.info "bms size=#{count} class=#{@bookmarks.class}"
    @bookmarks.delete_if {|bm|
      !File.exist?(bm.full_path)
    }
    deleted = count - @bookmarks.size

    changed = update_bookmarks(@bookmarks, PROJECT_SCOPE)

    if changed > 0 or deleted > 0
      save_bookmarks_table PROJECT_SCOPE
      print "<h1>#{changed} bookmarks updated and #{deleted} deleted</h1>"
    else
      print "No bookmarks have been updated or deleted"
    end
  end

  def update_global_bookmarks
    if !load_bookmarks(GLOBAL_SCOPE, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{GLOBAL_SCOPE} bookmarks")
    end

    # cleanup bookmarks to missing files
    count = @bookmarks.size
    @bookmarks.delete_if{|bm|
      !File.exist?(bm.full_path)
    }
    deleted = count - @bookmarks.size

    changed = update_bookmarks(@bookmarks, GLOBAL_SCOPE)

    if changed > 0 or deleted > 0
      save_bookmarks_table GLOBAL_SCOPE
      print "#{changed} bookmarks updated and #{deleted} deleted"
    else
      print "No bookmarks have been updated or deleted"
    end
  end

  def update_document_bookmarks
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE
    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no saved #{scope} bookmarks")
    end
    bms_changed = update_bookmarks(get_document_bookmarks, scope)
    if bms_changed > 0
      save_bookmarks_table scope
      print "#{bms_changed} bookmark#{bms_changed > 1 ? 's have' : ' has'} been updated"
    else
      print "No bookmarks have been updated"
    end
  end

  def update_bookmarks(bookmarks, scope)
    # @log.info "\nglobal #{@bookmarks.inspect}"
    # @log.info "\nlocal #{bookmarks.inspect}"

    max_delta_lines = ENV['TM_NAVIGATOR_MAX_DELTA_LINES'].to_i
    bms_changed = 0
    bookmarks.each {|bm|
      @log.info "fixing bm=#{bm.to_s}"
      # grep for the expression in the file and use the one nearest to the current line
      delta = 1000000000
      new_line = bm.line
      search_regex = Regexp.new("\s*#{Navigator.escape_regexp(bm.contents)}\s*")
      curr_line = 0
      IO.foreach(bm.full_path){|line|
        curr_line += 1
        matches = search_regex.match(line.chomp)
        next if matches.nil?
        if (new_delta = (bm.line - curr_line).abs) < delta
          delta = new_delta
          new_line = curr_line
        end
        break if new_delta > delta
      }
      # check anyway the distance so that it's not TOO far
      if (1..max_delta_lines).include?(delta)
        bm.line = new_line
        bms_changed += 1
        @log.info "changed bm=#{bm.to_s} to new_line=#{new_line} delta=#{delta}"
      end
    }

    return bms_changed
  end
end

class BookmarkInfo
  attr_accessor :name
  attr_accessor :line
  attr_accessor :path
  attr_accessor :contents
  attr_accessor :scope

  def initialize()
    @log = NavLogger.get_logger
    @log.level = NavLogger::WARN
    # @log.set_subjects Bookmarks::BOOKMARK_INFO_LOG
    @log.set_subjects 0
  end

  def self.for_name(name, scope)
    bm = BookmarkInfo.new
    bm.name = name
    bm
  end

  def self.from_tag_line(tag_line, scope)
    BookmarkInfo.new.from_tag_line(tag_line, scope)
  end

  def from_tag_line(tag_line, scope)
    @log.debug(Bookmarks::BOOKMARK_INFO_LOG, "loading tag_line=|#{tag_line}|")
    tag_info = tag_line.scan(/^(.+?)\t(.+?)\t(.+?)\t(.*)/).flatten
    return nil if tag_info.size == 0

    @name = tag_info[BOOKMARKS_NAME_FIELD]
    @line = tag_info[BOOKMARKS_LINE_FIELD].to_i
    @path = tag_info[BOOKMARKS_FPATH_FIELD]
    @contents = tag_info[BOOKMARKS_CONTENTS_FIELD]
    @scope = scope
    @log.debug(Bookmarks::BOOKMARK_INFO_LOG, "to_s=#{to_s}")

		return self
  end

  def full_path
    # if project scope then prepend the projects directory
    if @scope == PROJECT_SCOPE
      return "#{ENV['TM_PROJECT_DIRECTORY']}/#{@path}"
    else
      return @path
    end
  end
  def to_s
    return "#{@name}#{BOOKMARKS_SEPARATOR}#{@line}#{BOOKMARKS_SEPARATOR}#{@path}#{BOOKMARKS_SEPARATOR}#{@contents}"
  end
  def to_display
    return "#{@line}#{BOOKMARKS_SEPARATOR}#{@path}"
  end
  def to_lookup_expression
    @log.debug(Bookmarks::BOOKMARK_INFO_LOG, "Navigator.escape_regexp(@contents)=#{Navigator.escape_regexp(@contents)}")
    exp = Navigator.escape_regexp(@contents)
    exp = Regexp.new(exp)
    @log.debug(Bookmarks::BOOKMARK_INFO_LOG, "exp.inspect=#{exp.inspect}")
    exp
  end
end

if __FILE__ == $0
  # Bookmarks.new.set_project_bookmark
  # Bookmarks.new.set_global_bookmark
  # Bookmarks.new.goto_project_bookmark
  # Bookmarks.new.goto_global_bookmark
  # Bookmarks.new.goto_document_bookmark
  # Bookmarks.new.call_project_bookmark
  # Bookmarks.new.call_global_bookmark
  # Bookmarks.new.call_document_bookmark
  # Bookmarks.new.update_project_bookmarks
  # Bookmarks.new.update_document_bookmarks
  # Bookmarks.new.clear_all_document_bookmarks
end
