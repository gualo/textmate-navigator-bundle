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
# TODO: Add documentation to methods
# FIXME: Handle errors. Currently I'm hoping for the best and _ignoring_ the worst :P
#

# used for debugging purposes
if __FILE__ == $0
	ENV['TM_BUNDLE_PATH'] = ENV['TM_PROJECT_DIRECTORY']
	ENV['TM_BUNDLE_SUPPORT'] = ENV['TM_BUNDLE_PATH'] + '/Support'
end

require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/positions.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/notes_settings.rb'
require 'shellwords'
require "open3"

class Notes
  NOTES_FPATH_FIELD = 0
  NOTES_LINE_FIELD = 1
  NOTES_TYPE_FIELD = 2
  NOTES_NOTE_FIELD = 3
  NOTES_SEPARATOR = "\t"
  ALL_NOTES = 'All'

  BROWSE_NOTES_LOG = 1
  REFRESH_NOTES_LOG = 2
  TOOLS_NOTES_LOG = 4
  SETTINGS_NOTES_LOG = 8
	POSITION_NOTES_LOG = 16
	NOTES_INFO_LOG = 32

	NO_FILTER = 0
	FILTER_DOCUMENT = 1
	FILTER_PROJECT = 2

  attr_accessor :log
	attr_accessor :clean_notes_path

  def initialize
    @log = NavLogger.get_logger
    @log.level = NavLogger::DEBUG
    @log.set_subjects BROWSE_NOTES_LOG | REFRESH_NOTES_LOG | TOOLS_NOTES_LOG | SETTINGS_NOTES_LOG
    @log.set_subjects 0
    # @log.use_html = false

    # we _MUST_ have an active project. Add it's directory to the
    # project notes path
    prj_dir = "#{ENV['TM_PROJECT_DIRECTORY']}"
    TextMate.exit_show_tool_tip("There is no active project") if prj_dir.empty?

    # DOC: TM_NAVIGATOR_PROJECT_NOTE_PATH
    @project_note_lookup_paths = [prj_dir]
    # set the notes file to be used to the project's notes
    @notes_path = prj_dir + "/#{ENV['TM_NAVIGATOR_NOTES_FNAME']}"
    # add also the project's notes lookup path setting from the ENV var
    notes_lookup_path = "#{ENV['TM_NAVIGATOR_PROJECT_NOTES_PATH']}"
    if !notes_lookup_path.empty?
      @project_note_lookup_paths.concat(notes_lookup_path.split(':'))
    end

    @log.debug "project_note_lookup_paths=#{@project_note_lookup_paths.inspect}<br>"
    @log.debug "notes_path=#{@notes_path.inspect}<br>"

    @files_list_path = ENV['TMPDIR'] + "notes.lst"
    @clean_notes_path = ENV['TMPDIR'] + "cleannotes.lst"

		@settings_helper = NotesSettings.new
		
    # @cocoa_dialog = '"' + ENV['TM_BUNDLE_SUPPORT'] + '/bin/CocoaDialog.app/Contents/MacOS/CocoaDialog"'
    @cocoa_dialog = '"' + ENV['TM_SUPPORT_PATH'] + '/bin/CocoaDialog.app/Contents/MacOS/CocoaDialog"'

  end

  def load_notes
    @notes=[]
    @log.debug "notes_path=#{@notes_path}"
    return false unless File.exist?(@notes_path)

    IO.foreach(@notes_path) {|line|
      @log.debug "line=#{line}"
      note =  NoteInfo.from_tag_line(line.chomp)
      @notes.push note
    }
    @notes.each{|note| @log.debug "note.inspect=#{note.to_s}"}
    return true
  end

  def search_notes(note_exp, filter_document = NO_FILTER)
    @log.debug BROWSE_NOTES_LOG, "Searching |#{note_exp.inspect}| with filter #{filter_document}<br>\n"
		case filter_document
		when FILTER_PROJECT
			filter_path = ENV['TM_PROJECT_DIRECTORY']
		when FILTER_DOCUMENT
			filter_path = ENV['TM_SELECTED_FILE']
		end
		
    notes = @notes.collect {|note|
			result = nil
      if filter_document != NO_FILTER && !note.path.start_with?(filter_path)
				result = nil
      elsif note_exp[:type] == :type
	      @log.debug BROWSE_NOTES_LOG, "matching note |#{note.to_code_line}|<br>\n"
        result = note if !note_exp[:exp].match(note.to_code_line).nil?
      else
	      @log.debug BROWSE_NOTES_LOG, "matching note |#{note.note}|<br>\n"
        result = note if !note_exp[:exp].match(note.note).nil?
      end
			result
    }
    notes.compact!
    notes.each{|note| @log.debug BROWSE_NOTES_LOG, "selected_note::note=#{note.to_s}"}
    return nil if notes.empty?
    return notes
  end

  def position_note(note)
    @log.debug POSITION_NOTES_LOG, "Navigating to note.path, note.lookup_expression, note.line=#{note.path}, #{note.to_lookup_expression}, #{note.line}"
    Navigator.goto_file note.path, note.to_lookup_expression, note.line, 1
  end

  def prompt_for_note_type
    note_types = @settings_helper.get_note_types(true)

    type_idx = TextMate::UI.menu(note_types)
    return nil if type_idx.nil?

    return note_types[type_idx]
  end

  # Sort the notes by type, path and line number
  def sort_notes(notes)
    note_types = make_type_search_regex_table()
    @log.debug BROWSE_NOTES_LOG, "note_types=#{note_types.inspect}"
    notes.each{|note| @log.debug "sort_notes::#{note.to_s}"}
    sorted_notes = notes.sort {|note1, note2|
      # @log.debug BROWSE_NOTES_LOG, "sorting note1.inspect=#{note1.to_s}<br>"
      # @log.debug BROWSE_NOTES_LOG, "sorting note2.inspect=#{note2.to_s}<br>"
      n1_idx = get_note_type_index(note1, note_types)
      # @log.debug BROWSE_NOTES_LOG, "n1_idx=#{n1_idx}"
      n2_idx = get_note_type_index(note2, note_types)
      # @log.debug BROWSE_NOTES_LOG, "n2_idx=#{n2_idx}"
      if n1_idx == n2_idx
        if note1.path == note2.path
          note1.line <=> note2.line
        else
          note1.path <=> note2.path
        end
      else
        n1_idx <=> n2_idx
      end
    }
    return sorted_notes
  end

  def get_note_type_index(note, note_types)
		@log.debug TOOLS_NOTES_LOG, "get_note_type_index note=#{note.inspect}"
		@log.debug TOOLS_NOTES_LOG, "get_note_type_index note_types=#{note_types.inspect}"
		code_line = note.is_a?(NoteInfo) ? note.to_code_line : NoteInfo.to_code_line(note)
		@log.debug TOOLS_NOTES_LOG, "code_line=#{code_line}"
    idx = note_types.index {|t|
      !t.match(code_line).nil?
    }
    idx
  end

  def prompt_for_note(notes)
    sorted_notes = sort_notes(notes)
    menu_notes = sorted_notes.collect {|note|
			note_type = "#{note.note_type}(#{File.basename(note.path)})"
      "#{note_type.ljust(30)} #{note.note}"
    }

    note_idx = TextMate::UI.menu(menu_notes)
    # @log.debug "Selected #{note_idx}<br>"
    return nil if note_idx.nil?

    return sorted_notes[note_idx]
  end

  def align_column(str, width)
    len = str.size
    spaces = (width - len) * 1.5
    spaces > 0 ? str + (" " * spaces) : str
  end

  def fetch_note(note_exp, filter_document = NO_FILTER)
    notes = search_notes(note_exp, filter_document)
    return nil if notes.nil?

    if notes.size == 1
      @log.debug "Found only one match, dispatching"
      return notes[0]
    end

    note = prompt_for_note notes
    TextMate.exit_discard if note.nil?

    return note
  end

  # make a regexp to look for matching notes
  def make_note_search_regex(note_type)
    notes_regexp = ""
    if note_type == ALL_NOTES
      first = true
      @settings_helper.get_settings[NotesSettings::NOTE_TAGS_SETTINGS].each {|type|
        # @log.debug "adding type |#{type["name"]}|=|#{type["value"]}|"
        notes_regexp += "(#{type["value"]})|"
        if first
          notes_regexp += "(#{type["value"]})|"
          first = false
        end
      }
      # remove the last '|'
      notes_regexp = notes_regexp[0..-2]
    else
      @settings_helper.get_settings[NotesSettings::NOTE_TAGS_SETTINGS].each{|type|
        notes_regexp += type["value"] if type["name"].casecmp(note_type) == 0
      }
    end

    @log.debug "make_note_search_regex::notes_regexp=#{notes_regexp}"
    return notes_regexp
  end

  # make an array of regexps to look for matching note types
  def make_type_search_regex_table(note_type = ALL_NOTES)
    types_regexp = []
    if note_type == ALL_NOTES
      @settings_helper.get_settings[NotesSettings::NOTE_TAGS_SETTINGS].each {|type|
        # @log.debug "adding type |#{type["name"]}|=|#{type["value"]}|"
        types_regexp.push Regexp.new(type["value"], true)
      }
    else
      @settings_helper.get_settings[NotesSettings::NOTE_TAGS_SETTINGS].each{|type|
        notes_regexp.push Regexp.new(type["value"], true) if type["name"] == note_type
      }
    end
    return types_regexp
  end

  # Prompts the user for a note to navigate to
  # DOC: The argument may be:
  # 	- empty, in which case all the note types are included
  # 	- a specific note type from thise given by the parameters in the settings
  # 	- a question mark '?' in which case the system will first prompt for the type
  def goto_note(note_type = ALL_NOTES, filter_document = NO_FILTER)
    if !load_notes() || @notes.size == 0
      TextMate.exit_show_tool_tip("The are no notes in this project.")
    end

    if note_type == "?"
      note_type = prompt_for_note_type
      TextMate.exit_discard if note_type.nil?
    end

    regexp = Regexp.new(make_note_search_regex(note_type.nil? ? ALL_NOTES : note_type))
    notes_regexp = {:exp => regexp, :type => :type}
    note = fetch_note(notes_regexp, filter_document)
    TextMate.exit_show_tool_tip "No notes found" if note.nil?

    # check if the file exists, if not then inform the user about it and skip the
    # operation
    if !File.exist?(note.path)
      TextMate.exit_show_tool_tip("File #{note.path} does not exist")
    end

    position_note note
  end

  def find_note
    if !load_notes() || @notes.size == 0
      TextMate.exit_show_tool_tip("The are no notes in this project.")
    end

    # prompt the user for the search text
    note_exp = TextMate::UI.request_string(:title => "Find Note", :prompt => "Search expression:")
    TextMate.exit_discard if note_exp.nil?

    note_exp_str = note_exp.strip
    TextMate.exit_discard if note_exp_str.empty?

    # if a regex (i.e. /xxxxx/) then remove the enclosing delimiters
    # and use as provided, otherwise regex-escape the expression
    if note_exp_str[0].chr == '/' and note_exp_str[-1].chr == '/'
      note_exp_str = note_exp_str[1..-2]
      note_exp = {:exp => Regexp.new(note_exp_str, Regexp::IGNORECASE), :type => :note}
    else
      note_exp = {:exp => Regexp.new(".*#{Navigator.escape_regexp(note_exp_str)}.*", Regexp::IGNORECASE), :type => :note}
    end

    @log.debug "note_exp=|#{note_exp}|<br>\n"
    note = fetch_note(note_exp)
    TextMate.exit_show_tool_tip("No note containing \"#{note_exp_str}\" found") if note.nil?

    # check if the file exists, if not then inform the user about it and skip the
    # operation
    if !File.exist?(note.path)
      TextMate.exit_show_tool_tip("File #{note.path} does not exist")
    end

    position_note note
  end

  def refresh_project_notes
    @log.debug "refresh_project_notes<br>"
    build_annotated_files_list(@project_note_lookup_paths)
    refresh_notes true
  end

  def refresh_current_file_notes
    files = [ENV['TM_SELECTED_FILE']]
    build_annotated_files_list(files)
    refresh_notes false
  end


  def refresh_selected_files_notes
		TextMate.exit_show_tool_tip("No seleted project files") if ENV['TM_SELECTED_FILES'].nil?
    files = Shellwords.shellwords(ENV['TM_SELECTED_FILES'])
    build_annotated_files_list(files)
    refresh_notes false
  end

  # removes the notes for the files in the list
  def remove_notes(global_progress, task_progress, progress_in)
    set_progress progress_in, global_progress, "Removing previous tags"
    file_progress = ((task_progress/10.0)*9) / @files_count
    progress = global_progress
    # generate a temporary file with patterns for grep to exclude from the notes file
    # using the current file list
    # @log.debug REFRESH_NOTES_LOG, "Clean Notes file at |#{@clean_notes_path}|<br>"
    fd = File.new(@clean_notes_path, "w")
    IO.foreach(@files_list_path) { |file|
      @log.debug REFRESH_NOTES_LOG, "current file=#{file}<br>\n"
      file = file.chomp
      regexp = "^#{Navigator.escape_regexp(file)}#{NOTES_SEPARATOR}"
      fd.puts regexp
      progress += file_progress
      set_progress progress_in, progress, "Removing #{Navigator.shorten_path(file, 60)}"
    }
    fd.close

    `grep -v -f "#{@clean_notes_path}" "#{@notes_path}"> "#{@notes_path}.tmp"`
    progress += task_progress/20
    set_progress progress_in, progress, "Removed #{@files_count} files"

    # and move it on top of the main one
		# TODO whatever
    FileUtils.mv "#{@notes_path}.tmp", "#{@notes_path}"
    # clean up
    File.delete @clean_notes_path
  end

  def refresh_notes(refresh_all = false)
    # start a progress dialog for the whole operation
    @files_count = `wc -l "#{@files_list_path}"`.chomp.to_i
    @log.debug REFRESH_NOTES_LOG, "Total files=#{@files_count}"
    global_progress = 0
    errorStr = ""
    cocoaProgressString = @cocoa_dialog + ' progressbar --text "Please wait..." --title "Navigator - Refreshing notes" --width 600'
    Open3.popen3(cocoaProgressString) { |progress_in, progress_out, progress_err|
      begin
        set_progress progress_in, 0, "Please wait..."
        # if we are not doing a full refresh then we need to remove
        # the files' notes from the notes file to avoid duplicates
        task_progress = 10
        if refresh_all
          @log.debug REFRESH_NOTES_LOG, "refreshing all"
          File.delete @notes_path if File.exist?(@notes_path)
        else
          @log.debug REFRESH_NOTES_LOG, "removing notes for selection"
          remove_notes global_progress, task_progress, progress_in
        end
        global_progress += task_progress
        set_progress progress_in, global_progress, "Starting tagging process..."

        # now extract notes from each file in the list
        task_progress = 90.0
        file_progress = task_progress / @files_count
        progress = global_progress
        search_regex_str = make_note_search_regex(ALL_NOTES)
        search_regex = Regexp.new(search_regex_str, true)
        @log.debug REFRESH_NOTES_LOG, "search_regex_str=#{search_regex_str}"
        # @log.debug "search_regex=#{search_regex.inspect}"
        errors = 0
        skipped = 0
        note_count = 0
        done_count = 0
        notes_fd = File.open(@notes_path, "a")
        note = NoteInfo.new
        excluded = ENV['TM_NAVIGATOR_NOTES_IGNORE'].split(':').collect{|exclusion|
          Regexp.new(exclusion)
        }
        @log.debug REFRESH_NOTES_LOG, "excluded #{excluded.inspect}"
        begin
          # files = ["/Users/gualo/Library/Application Support/TextMate/Bundles/Navigator.tmbundle/Support/notes.rb"]
          # files.each { |file|
          IO.foreach(@files_list_path) { |file|
            set_progress progress_in, progress, "(#{done_count}/#{@files_count}:#{note_count}) #{Navigator.shorten_path(file, 70)}"
            file = file.chomp
            begin
              @log.debug REFRESH_NOTES_LOG, "scanning #{file}"
              line_idx = 1
              IO.foreach(file){|line|
                begin
                  # @log.debug REFRESH_NOTES_LOG, "matching |#{line.chomp}|"
                  matches = search_regex.match(line.chomp)
                  if !matches.nil?
                    @log.debug "match found #{line}"

                    values = (1..matches.size).collect{|idx| matches[idx]}.compact
                    note.path = file
                    note.line = line_idx
                    note.note_type = values[1]
                    note.note = values[2]
                    notes_fd.puts note.to_tag_line
                    @log.debug "matched=#{note.to_tag_line}"

                    note_count += 1
                  end
                rescue Exception => ex
                  errorMsg = "error #{ex} in line |#{line}|"
                  @log.error REFRESH_NOTES_LOG, errorMsg
                  errorStr = errorStr + "\n" + errorMsg
                end
                line_idx += 1
              }
            rescue Exception => ex
              errorMsg = "error #{ex} in file |#{file}|"
              @log.debug REFRESH_NOTES_LOG, errorMsg
              errorStr = errorStr + "\n" + errorMsg
              errors += 1
              progress += file_progress
            end
            progress += file_progress
            done_count += 1
          }
        rescue Exception => ex
          File.delete(@notes_path) if File.exist?(@notes_path)
          TextMate::UI.alert(:critical, "Navigator - Refresh Project Notes", "An error has occurred when scanning the project's files\n" + "error #{ex}")
          TextMate.exit_show_tool_tip "An error has occurred when scanning the project's files\n" + "error #{ex}"
        end

        @log.debug REFRESH_NOTES_LOG, "progress after scan finished=#{progress}"
        global_progress += task_progress
        set_progress progress_in, global_progress, "Finalizing..."

        # clean up
        File.delete @files_list_path

        set_progress progress_in, 100, "Finished"
        sleep 0.5
      ensure
	      if (File.exist?("/Users/gualo/tmp/navphore.txt"))
	        File.delete "/Users/gualo/tmp/navphore.txt"
	      end
        progress_in.close
      end
      if (File.exist?(@notes_path))
        TextMate.exit_show_tool_tip "Analyzed #{@file_count} documents, skipped #{skipped}. Total of #{note_count} notes.  #{errors} errors"
      end
    }
  end

  def build_annotated_files_list(sources, exclusions = [])
    excluded = Regexp.new(ENV['TM_NAVIGATOR_NOTES_IGNORE'])

    cocoaProgressString = @cocoa_dialog + ' progressbar --text "Selecting files, please wait..." --title "Navigator - Scanning Files" --indeterminate'
    Open3.popen3(cocoaProgressString) { |progress_in, progress_out, progress_err|
      begin
        # create a temporary file with the file names
        # @log.debug "Notes file at |#{@files_list_path}|<br>\n"
        fd = File.new(@files_list_path, "w")

        @file_count = 0
        block = Proc.new do |file|
          if excluded.match(file).nil?
            fd.puts file
            @file_count += 1
          else
            @log.debug REFRESH_NOTES_LOG, "excluding #{file}"
          end
        end

        # scan the sources for files to tag, output them to the notes list file
        sources.each { |path|
          if File.directory?(path)
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

  def set_progress(progress_in, progress, msg = "")
    @log.debug REFRESH_NOTES_LOG, "setting progress=#{progress}"
    progress_in.print "#{progress} #{msg}\n"
    progress_in.flush
  end

end

class NoteInfo
  attr_accessor :path
  attr_accessor :line
  attr_accessor :note_type
  attr_accessor :note

	def initialize
    @log = NavLogger.get_logger
    @log.level = NavLogger::WARN
    @log.set_subjects Notes::NOTES_INFO_LOG
	end
	
  def self.from_tag_line(note_line)
    note = NoteInfo.new
    note.from_tag_line(note_line)
  end

	def self.to_code_line(type_string)
	    " #{type_string}:"
	end

  def from_tag_line(note_line)
    note_info = note_line.scan(/^(.+?)\t(.+?)\t(.+?)\t(.*)/).flatten
    return nil if note_info.size == 0

    @path = note_info[Notes::NOTES_FPATH_FIELD]
    @line = note_info[Notes::NOTES_LINE_FIELD].strip.to_i
    @note_type = note_info[Notes::NOTES_TYPE_FIELD]
    @note = note_info[Notes::NOTES_NOTE_FIELD]

		return self
  end

  # answer true if the file is outside the project's directory
  def extraFile?
    !projectFile?
  end

  # answer true if the file is within the project's directory
  def projectFile?
    @path.start_with?(ENV['TM_PROJECT_DIRECTORY'])
  end

	def to_lookup_expression
    @log.debug(Notes::NOTES_INFO_LOG, "@note=#{@note}")
    @log.debug(Notes::NOTES_INFO_LOG, "Navigator.escape_regexp(@note, true)=#{Navigator.escape_regexp(@note, true)}")
    exp = Navigator.escape_regexp(@note)
    exp = Regexp.new(exp)
    @log.debug(Notes::NOTES_INFO_LOG, "exp.inspect=#{exp.inspect}")
    exp
	end
	
  def to_s
    to_tag_line
  end

  def to_tag_line
    "#{@path}#{Notes::NOTES_SEPARATOR}#{line}#{Notes::NOTES_SEPARATOR}#{note_type}#{Notes::NOTES_SEPARATOR}#{note}"
  end

  def to_code_line
    " #{note_type}:"
  end
end

if __FILE__ == $0
  # Notes.new.goto_note
  # Notes.new.refresh_project_notes
  # Notes.new.refresh_selected_files_notes
  # Notes.new.find_note
  notes = Notes.new
	notes.goto_note
	#   notes.settings_helper.load_settings
	# notes.settings_helper.save_settings
end
