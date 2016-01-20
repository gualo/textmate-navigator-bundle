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

if __FILE__ == $0
  ENV['TM_BUNDLE_PATH'] = ENV['TM_PROJECT_DIRECTORY']
	ENV['TM_BUNDLE_SUPPORT'] = "#{ENV['TM_BUNDLE_PATH']}/Support"
end

require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/positions.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/notes.rb'


require 'Logger'
require "erb"
require "yaml"
include ERB::Util
require "#{ENV['TM_SUPPORT_PATH']}/lib/web_preview"

class Notes

  def browse_project_notes
    if !load_notes() || @notes.size == 0
      TextMate.exit_show_tool_tip("The are no notes for this project")
    end
    browse_notes @notes
  end

  def browse_document_notes
    if !load_notes() || @notes.size == 0
      TextMate.exit_show_tool_tip("The are no notes for this project")
    end
    doc_notes = get_document_notes
    if doc_notes.size == 0
      TextMate.exit_show_tool_tip("The are no notes for this document")
    end
    browse_notes doc_notes
  end

  def browse_notes(notes)
    notes = sort_notes(notes)
    note_types = @settings_helper.get_note_types
    @log.debug BROWSE_NOTES_LOG, "note_types=#{note_types.inspect}"
    types_matcher = make_type_search_regex_table
    @log.debug BROWSE_NOTES_LOG, "types_matcher=#{types_matcher.inspect}"

    subtitle = "Project: #{ENV['TM_PROJECT_DIRECTORY']}"
    html_head = ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_notes_header.rhtml"), 0, '<>').result(binding)
    puts html_head(:window_title => "Navigator - Notes", :page_title => "Browse Notes", :sub_title =>  "#{subtitle}", :html_head => html_head)

    @log.debug BROWSE_NOTES_LOG, "get_browser_filters=#{@settings_helper.get_browser_filters.inspect}"
		type_filters = []
    @settings_helper.get_browser_filters.each{|filter|
			type_filters[note_types.index(filter["name"])] = filter["value"]
		}
		type_filters.map!{|val| val.nil? ? true : val}
    @log.debug BROWSE_NOTES_LOG, "type_filters=#{type_filters.inspect}"
    puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_notes_head.rhtml"), 0, '<>').result(binding)

    STDOUT.flush
    note_idx = 0;
    notes.each {|note|
      puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_notes_item.rhtml"), 0, '<>').result(binding)
      note_idx += 1
    }

    puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_notes_footer.rhtml"), 0, '<>').result(binding)
    STDOUT.flush

    html_footer()
  end
end

if __FILE__ == $0
  Notes.new.browse_project_notes
  # Notes.new.browse_document_notes
end
