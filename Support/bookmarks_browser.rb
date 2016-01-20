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
require ENV['TM_BUNDLE_SUPPORT'] + '/bookmarks.rb'
require 'Logger'
require "erb"
require "yaml"
include ERB::Util
require "#{ENV['TM_SUPPORT_PATH']}/lib/web_preview"

class Bookmarks
  def browse_project_bookmarks
    if @project_bookmarks_path.nil?
      TextMate.exit_show_tool_tip("There is no active project")
    end
    if !load_bookmarks(PROJECT_SCOPE, false)
      TextMate.exit_show_tool_tip("The are no #{PROJECT_SCOPE} bookmarks")
    end
    browse_bookmarks @bookmarks, PROJECT_SCOPE
  end

  def browse_document_bookmarks
    # if there is an active project we use project bookmarks
    scope = @project_bookmarks_path.nil? ? GLOBAL_SCOPE : PROJECT_SCOPE
    if !load_bookmarks(scope, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no #{scope} bookmarks")
    end
    docbms = get_document_bookmarks
    if docbms.size == 0
      TextMate.exit_show_tool_tip("The are no #{DOCUMENT_SCOPE} bookmarks")
    end
    browse_bookmarks docbms, DOCUMENT_SCOPE
  end

  def browse_global_bookmarks
    if !load_bookmarks(GLOBAL_SCOPE, false) || @bookmarks.size == 0
      TextMate.exit_show_tool_tip("The are no #{GLOBAL_SCOPE} bookmarks")
    end
    browse_bookmarks @bookmarks, GLOBAL_SCOPE
  end

  def browse_bookmarks(bookmarks, scope)
		# sort by name
		bookmarks.sort! {|bm1, bm2|
			if bm1.name == bm2.name
				bm1.line <=> bm2.line
			end
			bm1.name <=>bm2.name
		}
		
    subtitle = (scope == GLOBAL_SCOPE) ? "" :
			(scope == PROJECT_SCOPE) ? "Project: #{ENV['TM_PROJECT_DIRECTORY']}" :
			"Document: #{ENV['TM_SELECTED_FILE']}"
    html_head = ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_bookmarks_header.rhtml"), 0, '<>').result(binding)
    puts html_head(:window_title => "Navigator - Bookmarks", :page_title => "Browse #{scope} Bookmarks", :sub_title =>  "#{subtitle}", :html_head => html_head)

    puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_bookmarks_head.rhtml"), 0, '<>').result(binding)

    STDOUT.flush
		bm_idx = 0
    bookmarks.each {|bm|
      puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_bookmarks_item.rhtml"), 0, '<>').result(binding)
			bm_idx += 1
    }

    puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/browse_bookmarks_footer.rhtml"), 0, '<>').result(binding)
    STDOUT.flush

    html_footer()
  end
end

if __FILE__ == $0
  Bookmarks.new.browse_project_bookmarks
  # Bookmarks.new.browse_global_bookmarks
end
