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
require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'
require ENV['TM_BUNDLE_SUPPORT'] + '/positions.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require 'fileutils'
require "shellwords"
require 'open3'

class Tags
  TAGS_IDENTIFIER_FIELD = 0
  TAGS_PATH_FIELD = 1
  TAGS_EXPRESSION_FIELD = 2
  TAGS_KIND_FIELD = 3
  TAGS_LINE_FIELD = 4
  TAGS_CLASS_FIELD = 5
  TAGS_SEPARATOR = "\t"
  LAST_SCAN_KEY = "lastScan"

  POSITION_TAG_LOG = 0x01
  REFRESH_TAGS_LOG = 0x02
  TAG_INFO_LOG = 0x04
  HOUSE_KEEPING_LOG = 0x08

  def initialize
    @log = NavLogger.get_logger
    @log.level = NavLogger::DEBUG
    @log.use_html = false
    @log.set_subjects POSITION_TAG_LOG  # | REFRESH_TAGS_LOG | TAG_INFO_LOG | HOUSE_KEEPING_LOG

    # if we have an active project then add it's directory to the
    # project tags path
    prj_dir = "#{ENV['TM_PROJECT_DIRECTORY']}"
    if !prj_dir.empty?
      @project_tag_paths = [prj_dir]
      # set the tags file to be used for the project's tags
      @tags_path = prj_dir + "/#{ENV['TM_NAVIGATOR_TAGS_FNAME']}"
      # add also the project's tags path
      tag_path = "#{ENV['TM_NAVIGATOR_PROJECT_TAGS_PATH']}"
      if !tag_path.empty?
        @project_tag_paths.concat(tag_path.split(':'))
      end
    else
      # no active project, use the global tags instead
      @project_tag_paths = []
      # if the global tags file path is absolute (i.e. starts with a '/') then use it as is
      # otherwise use it as suffix after the user's HOME directory
      if ENV['TM_NAVIGATOR_GLOBAL_TAG_FILE_PATH'][0] == '/'
        @tags_path = "ENV['TM_NAVIGATOR_GLOBAL_TAG_FILE_PATH']/#{ENV['TM_NAVIGATOR_TAGS_FNAME']}"
      else
        @tags_path = "#{ENV['HOME']}/#{ENV['TM_NAVIGATOR_GLOBAL_TAG_FILE_PATH']}/#{ENV['TM_NAVIGATOR_TAGS_FNAME']}"
      end
    end

    # now get the global tags paths
    tag_path = "#{ENV['TM_NAVIGATOR_GLOBAL_TAG_PATH']}"
    @global_tag_paths = []
    if !tag_path.empty?
      paths = tag_path.split(':')
      paths.each {|path|
        @global_tag_paths.push(File.expand_path(path))
      }
    end
    @log.debug POSITION_TAG_LOG, "@global_tag_paths=#{@global_tag_paths.inspect}"

    @files_list_path = ENV['TMPDIR'] + "tags.lst"
    @clean_tags_path = ENV['TMPDIR'] + "cleantags.lst"
    @ctags = ENV['TM_BUNDLE_SUPPORT'] + '/bin/ctags'
    @cocoa_dialog = '"' + ENV['TM_SUPPORT_PATH'] + '/bin/CocoaDialog.app/Contents/MacOS/CocoaDialog"'
    @state_path = "#{ENV['TM_PROJECT_DIRECTORY']}/#{ENV['TM_NAVIGATOR_TAGS_FNAME']}.plist"

  end

  def search_tag(tag_exp)
    @log.debug POSITION_TAG_LOG, "search_tag:Searching :#{tag_exp.inspect}:<br>"
    tags = []
    # perform the search using the provided expression
    # if it's a regular expression use it "as is", otherwise add
    # wildcards around it to catch a matching string in any position within the identifier
    # Line format:
    # identifier	file_path	/regex_expression$/;"	kind:kind	line:42	class=

    # grep_exp = tag_exp[:regexp] ? /#{tag_exp[:exp]}/ : /.*#{tag_exp[:exp]}.*/
    grep_exp = tag_exp[:regexp] ? /#{tag_exp[:exp]}\t(.+?)\t\/(.*)\/;"\t(.+?)\t(.*)/    : /.*#{tag_exp[:exp]}.*\t(.+?)\t\/(.*)\/;"\t(.+?)\t(.*)/
    @log.debug POSITION_TAG_LOG, "grep_exp=|#{grep_exp}|"
    File.open(@tags_path).each{|tag_line|
      if grep_exp.match(tag_line)
	    	@log.debug TAG_INFO_LOG, "<br>#{tag_line}"
        tag = TagInfo.from_tag_file(tag_line.chomp)
	    	@log.debug TAG_INFO_LOG, "#{tag}"
        next if tag.nil?
	    	@log.debug TAG_INFO_LOG, "#{tag}"
        tags.push(tag)
      end
    }
    @log.debug POSITION_TAG_LOG, "tags=#{tags.inspect}"
    return tags
  end

  def position_tag(tag)
    @log.debug POSITION_TAG_LOG, "Navigating to tag.path, tag.lookup_expression, tag.line=#{tag.path}, #{tag.lookup_expression}, #{tag.line}"
    Navigator.goto_file tag.path, tag.to_lookup_expression, tag.line, 1
  end

  # initialize
  def prompt_for_tag(tags)
    sorted_tags, menu_tags, seps = prepare_prompt_menu(tags)
    @log.debug POSITION_TAG_LOG, "seps=#{seps.inspect}"
    tag_idx = TextMate::UI.menu(menu_tags)
    @log.debug POSITION_TAG_LOG, "Selected #{tag_idx}<br>"
    return nil if tag_idx.nil?

    # ensure the user didn't select a separator
    return nil if seps.include? tag_idx
    
    @log.debug POSITION_TAG_LOG, "Final Selected #{tag_idx}<br>"
    return sorted_tags[tag_idx]
  end

  # prepares the menu list from the tags
  # it returns the array [sorted_tags, menu_tags, seps] where the separators
  # is an array of the positions the menu separators have been inserted
  def prepare_prompt_menu(tags)
    sorted_tags = tags.collect{|tag|
      tag.scope = get_tag_scope(tag)
      tag
    }.sort(&get_sorter_by_scope)

    # insert a menu separator after the Document tags if any and there are more items
    seps = []
    last_idx = 0
    # insert a menu separator after the selected file tags
    last_idx = insert_menu_separator(sorted_tags, last_idx, :SELECTED_FILE_SCOPE)
    seps.push last_idx if !last_idx.nil?
    last_idx = 0 if last_idx.nil?
    # insert a menu separator after the project files tags
    last_idx = insert_menu_separator(sorted_tags, last_idx, :PROJECT_FILE_SCOPE)
    seps.push last_idx if !last_idx.nil?
    last_idx = 0 if last_idx.nil?
    # insert a menu separator after the extra project files tags
    last_idx = insert_menu_separator(sorted_tags, last_idx, :PROJECT_EXTRAS_FILE_SCOPE)
    seps.push last_idx if !last_idx.nil?

    menu_tags = sorted_tags.collect {|tag|
      if tag == "-"
        "-"
      else
        "(#{get_scope_letter(tag.scope)}) #{tag.identifier.ljust(50)}#{tag.line}:#{tag.path}"
      end
    }
    return [sorted_tags, menu_tags, seps]
  end

  def get_scope_letter(scope)
    case scope
    when :SELECTED_FILE_SCOPE
      "F"
    when :PROJECT_FILE_SCOPE
      "P"
    when :PROJECT_EXTRAS_FILE_SCOPE
      "X"
    when :GLOBAL_FILE_SCOPE
      "G"
    else
      ""
    end
  end

  def get_tag_scope(tag)
		if tag.path.nil?
    	@log.warn POSITION_TAG_LOG, "nil path in tag=#{tag}"
		end
    @log.info POSITION_TAG_LOG, "get_tag_scope for #{tag.path} against current file #{ENV['TM_FILENAME']}"
    if tag.path == ENV['TM_FILEPATH']
      :SELECTED_FILE_SCOPE
    elsif tag.path.start_with?(ENV['TM_PROJECT_DIRECTORY'])
      :PROJECT_FILE_SCOPE
    elsif @project_tag_paths.select{|path| tag.path.start_with?(path)}.size > 0
      :PROJECT_EXTRAS_FILE_SCOPE
    else
      :GLOBAL_FILE_SCOPE
    end
  end

  # The sorting algorithm sorts first by scope: Document, Project, Global
  # then by the tag's identifier
  def get_sorter_by_scope
    lambda {|tag1, tag2|
      # @log.debug HOUSE_KEEPING_LOG, "comparing tag1=#{tag1.to_s}<br/>tag2=#{tag2.to_s}<br/><br/>"

      ret_val = 0

      # same file?
      if tag1.path == tag2.path
        ret_val = (tag1.identifier <=> tag2.identifier)
      else
        # any of them is the selected file
        if tag1.scope ==  :SELECTED_FILE_SCOPE
          ret_val =  -1
        elsif tag2.scope == :SELECTED_FILE_SCOPE
          ret_val =  1
        else
          # any of them is in the project's directory tree?
          if tag1.scope == :PROJECT_FILE_SCOPE
            if tag2.scope == :PROJECT_FILE_SCOPE
              ret_val = (tag1.identifier <=> tag2.identifier)
            else
              ret_val =  -1
            end
          elsif tag2.scope == :PROJECT_FILE_SCOPE
            ret_val =  1
          else
            # any of them is in the project's extra directory trees?
            if tag1.scope == :PROJECT_EXTRAS_FILE_SCOPE
              if tag2.scope == :PROJECT_EXTRAS_FILE_SCOPE
                ret_val =  (tag1.identifier <=> tag2.identifier)
              else
                ret_val =  -1
              end
            elsif tag2.scope == :PROJECT_EXTRAS_FILE_SCOPE
              ret_val = 1
            else
              ret_val =  (tag1.identifier <=> tag2.identifier)
              # if fully equal till now then sort them by the full files paths or
              # the line number if in the same file
              if ret_val == 0
                if tag1.path == tag2.path
                  ret_val = (tag1.line <=> tag2.line)
                else
                  ret_val = (tag1.path <=> tag2.path)
                end
              end
            end
          end
        end
      end
      ret_val
    }
  end

  def insert_menu_separator(tags, idx, scope)
    count = 0
    while (idx < tags.size) && (tags[idx] == "-" || tags[idx].scope == scope)
      count += 1 if tags[idx] != "-"
      idx += 1
    end
    if count > 0 and idx < tags.size
      tags.insert(idx, "-")
      return idx
    end
    return nil
  end

  def get_lookup_tag
    # if there is a selection then use that as the matching string
    # otherwise use the context word at the cursor
    if ENV['TM_SELECTED_TEXT'].nil? or ENV['TM_SELECTED_TEXT'].strip.empty?
      tag_exp = ENV['TM_CURRENT_WORD'].strip
    else
      tag_exp = ENV['TM_SELECTED_TEXT'].strip
    end
		@log.debug TAG_INFO_LOG, "lookup expression=#{tag_exp}"
    return {:exp => Navigator.escape_regexp(tag_exp), :regexp => false}
  end

  def fetch_tag(tag_exp)
    tags = search_tag(tag_exp)
    if tags.size == 0
      @log.debug POSITION_TAG_LOG, "Found no matches<br>"
      TextMate.exit_show_tool_tip "Searching for #{tag_exp[:exp]}: No tags found"
    end
    if tags.size == 1
      @log.debug POSITION_TAG_LOG, "Found only one match, dispatching :#{tags[0]}:<br>"
      return tags[0]
    end

    # apply further logic to try and get an exact match
    if ENV['TM_NAVIGATOR_SMART_LOOKUP'].to_i == 1
      # check if any of the matches matches perfectly
      perfect_matches = tags.collect {|tag|
        @log.debug POSITION_TAG_LOG, "tag.inspect=#{tag.inspect}  tag_exp=#{tag_exp}"
        if tag_exp[:regexp]
          tag if tag.identifier.match(tag_exp[:exp])
        else
          tag if tag.identifier == tag_exp[:exp]
        end
      }.compact
      @log.debug POSITION_TAG_LOG, "perfect_matches=#{perfect_matches.inspect}"
      if perfect_matches.size == 1
        @log.debug POSITION_TAG_LOG, "Found only one perfect match, dispatching :#{perfect_matches[0]}:<br>"
        return perfect_matches[0]
      end
    end

    # @log.debug POSITION_TAG_LOG, "Selecting tags<br>"
    tag = prompt_for_tag(tags)
    if !tag.nil?
      return tag
    end
  end

  # get the tag for either the selected text or the identifier
  # at the cursor then "call" it
  def call_context_tag
    navigate_to_context_tag true
  end

  # prompt the user for a tag expression or identifier "call" it
  def call_user_tag
    tag_exp = get_user_tag
    tag = fetch_tag(tag_exp)
    TextMate.exit_discard if tag.nil?

    # check if the file exists, if not then inform the user about it and skip the
    # operation

    if !FileTest.exist?(tag.path)
      TextMate.exit_show_tool_tip("File #{tag.path} does not exist")
    end

    Positions.new.push_position
    position_tag tag
  end

  # get the tag for either the selected text or the identifier
  # at the cursor then jump to it
  def goto_context_tag
    navigate_to_context_tag false
  end

  # prompt the user for a tag expression or identifier then jump to it
  def goto_user_tag
    tag_exp = get_user_tag
    tag = fetch_tag(tag_exp)
    TextMate.exit_discard if tag.nil?

    # check if the file exists, if not then inform the user about it and skip the
    # operation
    if !FileTest.exist?(tag.path)
      TextMate.exit_show_tool_tip("File #{tag.path} does not exist")
    end
    position_tag tag
  end

  def navigate_to_context_tag(calling)
    tag_exp = get_lookup_tag
    @log.debug POSITION_TAG_LOG, "tag_exp=#{tag_exp.inspect}<br>"
    if tag_exp[:exp].empty?
      TextMate.exit_show_tool_tip "No detectable identifier or expression"
    end

    tag = fetch_tag(tag_exp)
    @log.debug POSITION_TAG_LOG, "tag.class=#{tag.class}<br>"
    TextMate.exit_discard if tag.nil?

    # check if the file exists, if not then inform the user about it and skip the
    # operation
    if !FileTest.exist?(tag.path)
      TextMate.exit_show_tool_tip("File #{tag.path} does not exist")
    end

    Positions.new.push_position if calling
    position_tag tag
  end

  def get_user_tag
    # get the expression from the user
    if ENV['TM_SELECTED_TEXT'].nil?
      if ENV['TM_CURRENT_WORD'].nil?
        default = ENV['TM_CURRENT_LINE']
      else
        default = ENV['TM_CURRENT_WORD']
      end
    else
      default = ENV['TM_SELECTED_TEXT']
    end

    # get the tag expression from the user
    tag_exp = TextMate::UI.request_string(:title => "Goto Tag", :prompt => "Expression or Identifier:", :default => default)
    TextMate.exit_discard if tag_exp.nil?

    tag_exp = tag_exp.strip
    TextMate.exit_discard if tag_exp.empty?

    # if a regex (i.e. /xxxxx/) then remove the enclosing delimiters
    # and use as provided, otherwise regex-escape the expression
    if tag_exp[0].chr == '/' and tag_exp[-1].chr == '/'
      tag_exp = tag_exp[1..-2]
      is_regexp = true
    else
      tag_exp = Navigator.escape_regexp(tag_exp)
      is_regexp = false
    end
    return {:exp => tag_exp, :regexp => is_regexp}
  end

  def refresh_project_tags
    TextMate.exit_show_tool_tip "There is no active project" if @project_tag_paths.empty?

    load_state
    @log.debug REFRESH_TAGS_LOG, "(#{__LINE__}) Previous scan at #{@state[LAST_SCAN_KEY]}"

    @sources = @project_tag_paths
    build_tagged_files_list
    refresh_tags(false)
    # clean up
    File.delete @files_list_path

    @state[LAST_SCAN_KEY] = Time.new
    save_state
  end

  def update_project_tags
    TextMate.exit_show_tool_tip "There is no active project" if @project_tag_paths.empty?
    load_state

    @sources = @project_tag_paths
    build_tagged_files_list @state[LAST_SCAN_KEY]
    if @file_count == 0
      print "No files needed update\n"
    else
      refresh_tags(false)
    end
    # clean up
    File.delete @files_list_path

    @state[LAST_SCAN_KEY] = Time.new
    save_state
  end

  def refresh_all_tags
    @sources = @project_tag_paths.concat(@global_tag_paths)
    @log.debug REFRESH_TAGS_LOG, "refresh_all_tags::sources=#{@sources.inspect}"
    build_tagged_files_list
    refresh_tags(true)
    # clean up
    # File.delete @files_list_path
  end

  def refresh_selected_files_tags
    @sources = Shellwords.shellwords(ENV['TM_SELECTED_FILES'])
    build_tagged_files_list
    refresh_tags(false)
    # clean up
    File.delete @files_list_path
  end

  def refresh_current_file_tags
    @sources = [ENV['TM_FILEPATH']]
    build_tagged_files_list
    errors = refresh_files_tags(false, nil, true)

    # clean up
    File.delete @files_list_path

    if (File.exist?(@tags_path))
      tag_count = `wc -l "#{@tags_path}"`.chomp.to_i
      puts "Analyzed 1 source files. Detected #{errors} errors. Total of #{tag_count} tags"
    end
  end

  def build_tagged_files_list(last_scan = nil)
    ignored = ENV['TM_NAVIGATOR_TAGS_IGNORE']
    excluded = (ignored.nil? || ignored.empty?) ? nil : Regexp.new(ENV['TM_NAVIGATOR_TAGS_IGNORE'])
    Open3.popen3(@cocoa_dialog + ' progressbar --text "Please wait..." --title "Navigator - Scanning Files" --indeterminate') { |progress_in, progress_out, progress_err|
      begin
        # create a temporary file with the file names
        # @log.debug REFRESH_TAGS_LOG, "Tags file at :#{@files_list_path}:<br>"
        fd = File.new(@files_list_path, "w")

        @file_count = 0
        block = Proc.new do |file|
          file = file.chomp
          @log.debug REFRESH_TAGS_LOG, "checking file '#{file}'"
          next if (!excluded.nil? && !excluded.match(file).nil?)
          next if !last_scan.nil? && File.mtime(file) < last_scan
          @log.debug REFRESH_TAGS_LOG, "source '#{file}' ACCEPTED"
          fd.puts file
          @file_count += 1
        end

        # scan the sources for files to tag, output them to the tags list file
        @sources.each { |path|
          # @log.debug REFRESH_TAGS_LOG, "checking source '#{path}'"
          if FileTest.directory?(path)
            @log.debug REFRESH_TAGS_LOG, "'#{path}' is directory"
            TextMate.scan_dir(path, block, TextMate::ProjectFileFilter.new)
          else
            block.call path
          end
        }

        fd.close
      ensure
        progress_in.close
      end
    }
  end

  # removes the tags for the files in the list
  def remove_tags(global_advance, task_advance, progress_in, silent)
    set_progress(progress_in, global_advance, "Removing previous tags") unless silent
    file_advance = ((task_advance/10.0)*9) / @files_count
    advance = global_advance
    # generate a temporary file with patterns for grep to exclude from the tags file
    # using the current file list
    # @log.debug REFRESH_TAGS_LOG, "Clean Tags file at :#{@clean_tags_path}:<br>"

    fd = File.new(@clean_tags_path, "w")
    @log.debug REFRESH_TAGS_LOG, "@clean_tags_path=#{@clean_tags_path}"
    
    @sources.each { |path|
      @log.debug REFRESH_TAGS_LOG, "added source path=#{path}"
      # regexp = "#{Navigator.escape_regexp(path)}.*"
      regexp = "#{path}.*"
      fd.puts regexp
      advance += file_advance
      set_progress(progress_in, advance, "Adding to removal list: #{Navigator.shorten_path(path, 60)}") unless silent
    }
    fd.close

    set_progress(progress_in, advance, "Removing of #{@files_count} files") unless silent
    @log.debug REFRESH_TAGS_LOG, "`grep -v -f \"#{@clean_tags_path}\" \"#{@tags_path}\"> \"#{@tags_path}.tmp\"`"
    `grep -v -f "#{@clean_tags_path}" "#{@tags_path}"> "#{@tags_path}.tmp"`

    advance += task_advance/20
    set_progress(progress_in, advance, "Removed #{@files_count} files") unless silent

    # and move it on top of the main one
    FileUtils.mv "#{@tags_path}.tmp", "#{@tags_path}"
    # clean up
    File.delete @clean_tags_path
  end

  def refresh_tags(refresh_all = false)
    # start a progress dialog for the whole operation
    Open3.popen3(@cocoa_dialog + ' progressbar --text "Please wait..." --title "Navigator - Refreshing tags" --width 600') { |progress_in, progress_out, progress_err|
      begin
        errors = refresh_files_tags(refresh_all, progress_in)
      ensure
        progress_in.close
      end
      if (File.exist?(@tags_path))
        tag_count = `wc -l "#{@tags_path}"`.chomp.to_i
        puts "Analyzed #{@file_count} source files. Detected #{errors} errors. Total of #{tag_count} tags"
      end
    }
  end

  def refresh_files_tags(refresh_all = false, progress_in = nil, silent = false)
    @files_count = `wc -l "#{@files_list_path}"`.chomp.to_i
    global_advance = 0
    set_progress(progress_in, 0, "Please wait...") unless silent
    # if we are not doing a full refresh then we need to remove
    # the files' tags from the tags file to avoid duplicates
    task_advance = 10
    if refresh_all
      File.delete @tags_path if File.exist?(@tags_path)
    else
      remove_tags global_advance, task_advance, progress_in, silent
    end
    global_advance += task_advance
    set_progress(progress_in, global_advance, "Starting tagging process...") unless silent

    # now call the tagger for that list
    task_advance = 90.0
    file_advance = task_advance / @files_count
    done_count = 0
    errors = 0
    advance = global_advance
    # TODO: Explain the usage of TM_NAVIGATOR_FORCE_OBJC in the user manual and
    # add variable setting to the configuration dialog
    # @log.debug REFRESH_TAGS_LOG, "objc exts=#{ENV['TM_NAVIGATOR_FORCE_OBJC']}"
    force_objc_exts = ENV['TM_NAVIGATOR_FORCE_OBJC'].nil? ? ["M"] : ENV['TM_NAVIGATOR_FORCE_OBJC'].upcase.split(":")
    # @log.debug REFRESH_TAGS_LOG, "force_objc_exts=#{force_objc_exts.inspect}"
    IO.foreach(@files_list_path) { |file|
      file = file.chomp
      done_count += 1
      set_progress(progress_in, advance, "(#{done_count}/#{@files_count}) #{Navigator.shorten_path(file, 70)}") unless silent

      # check if we should force ObjectiveC mode for this file's extension
      # @log.debug REFRESH_TAGS_LOG, "file=#{file.inspect} : File.extname(file).upcase)=#{File.extname(file).upcase}"
      if force_objc_exts.index(File.extname(file).upcase[1..-1]).nil?
        force_objc = ""
      else
        force_objc = "--language-force=Objc"
      end
      # @log.debug REFRESH_TAGS_LOG, "command: #{@ctags} -u --append=yes #{force_objc} -N --fields=+n+K+z -f \"#{@tags_path}\" \"#{file}\" 2>&1 1>/dev/null"
      `"#{@ctags}" -u --append=yes #{force_objc} -N --fields=+n+K+z -f \"#{@tags_path}\" \"#{file}\" 2>&1 1>/dev/null`
      if $? != 0
        errors += 1
        puts "Error tagging #{file}"
      end
      advance += file_advance
    }
    global_advance += task_advance
    set_progress(progress_in, global_advance, "Finalizing...") unless silent
    # remove the header/comment lines, sort the result sending
    # the output to a temporary target file
    `grep -v '^!' "#{@tags_path}" | sort -u > "#{@tags_path}.tmp"`
    # and move it on top of the main one
    FileUtils.mv "#{@tags_path}.tmp", "#{@tags_path}"
    set_progress(progress_in, 100, "Finished") unless silent
    sleep 0.5
    return errors
  end

  def load_state
    if File.exist?(@state_path)
      @state = open(@state_path) { |io| OSX::PropertyList.load(io) }
    else
      @state = {LAST_SCAN_KEY => Time.at(0)}
    end
  end

  def save_state
    @log.debug HOUSE_KEEPING_LOG, "final state=#{@state.inspect}"
    File.open(@state_path, "w") {|fd|
      fd.write @state.to_plist
    }
  end

  def set_progress(progress_in, advance, msg = "")
    progress_in.print "#{advance} #{msg}\n"
    progress_in.flush
  end

  def show_last_scan_date
    TextMate.exit_show_tool_tip "There is no active project" if @project_tag_paths.empty?
    load_state
    TextMate::exit_show_tool_tip "Last scan at #{@state[LAST_SCAN_KEY].localtime}"
  end
end

class TagInfo
  attr_accessor :identifier
  attr_accessor :path
  attr_accessor :lookup_expression
  attr_accessor :kind
  attr_accessor :line
  attr_accessor :tag_class
  attr_accessor :log
  attr_accessor :scope

  def initialize
    @log = NavLogger.get_logger
    @log.level = NavLogger::WARN
    @log.set_subjects Tags::TAG_INFO_LOG
  end

  def self.from_tag_file(tag_line)
    tag = TagInfo.new
    tag.from_tag_file(tag_line)
    return tag
  end

  def self.from_values(identifier, path, exp, kind, line, klass)
    tag = TagInfo.new
    tag.from_values(identifier, path, exp, kind, line, klass)
    return tag
  end

  # identifier	file_path	/expression$/;"	kind:kind	line:line_number	class:class_name
  def from_tag_file(tag_line)
    @log.debug Tags::TAG_INFO_LOG, "\n\n<br/><br/>tag_line=<pre>#{tag_line}</pre>\n\n<br/><br/>"
    tag_info = tag_line.scan(/^(.+?)\t(.+?)\t\/\^(.*)\$* *\/;"\t(.+?)\t(.*)\t(.*)/).flatten
    if tag_info.size == 0
      tag_info = tag_line.scan(/^(.+?)\t(.+?)\t\/\^(.*)\$* *\/;"\t(.+?)\t(.*)/).flatten
    end
    return nil if tag_info.size == 0
    @log.debug Tags::TAG_INFO_LOG, "\n\n<br/><br/>tag_info.inspect=#{tag_info.inspect}\n\n<br/><br/>"
    @identifier = tag_info[Tags::TAGS_IDENTIFIER_FIELD]
    @path = tag_info[Tags::TAGS_PATH_FIELD]
    @lookup_expression = tag_info[Tags::TAGS_EXPRESSION_FIELD]
    @kind = tag_info[Tags::TAGS_KIND_FIELD].split(':')[1]
    @line = tag_info[Tags::TAGS_LINE_FIELD].split(":")[1].to_i
    if tag_info.size > Tags::TAGS_CLASS_FIELD
      @tag_class = tag_info[Tags::TAGS_CLASS_FIELD].split(":")[1]
    end
    @log.debug(Tags::TAG_INFO_LOG, "inspect="+to_lookup_expression.inspect)
  end

  def from_values(identifier, path, exp, kind, line, klass)
    @identifier = identifier
    @path = path
    @lookup_expression = exp
    @kind = kind
    @line = line.is_a?(String) ? line.to_i : line
    @tag_class = klass
    @log.debug TAG_INFO_LOG, "inspect=#{self.inspect}"
  end

  def to_s
    "#{@identifier}:#{@path}:#{@line}"
  end

	def to_lookup_expression
    @log.debug(Tags::TAG_INFO_LOG, "Navigator.escape_regexp(@lookup_expression)=#{@lookup_expression}")
		exp = Navigator.escape_regexp(@lookup_expression)
		exp = Regexp.new("^#{exp}")
    @log.debug(Tags::TAG_INFO_LOG, "exp.inspect=#{exp.inspect}")
		exp
	end

  def to_command_parameters
    %Q{"#{@identifier}", "#{@path}#", "#{@lookup_expression}", "#{@kind}", #{@line}, "#{@tag_class}"}
  end

end
