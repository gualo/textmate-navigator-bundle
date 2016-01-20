#!/usr/bin/env ruby -KU
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

require "fileutils"
require "#{ENV['TM_SUPPORT_PATH']}/lib/osx/plist"
# require 'Logger'
require "erb"
require "yaml"
include ERB::Util
require "#{ENV['TM_SUPPORT_PATH']}/lib/web_preview"

require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/navigator.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/bookmarks.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/positions.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/notes.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/tags.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/clear_cache.rb'


class NavigatorConfigurator
	CONFIGURATION_LOG = 1

	def initialize
		@log = NavLogger.get_logger
		@log.level = NavLogger::WARN
		@log.use_html = false
		@log.set_subjects CONFIGURATION_LOG
		@tabs = ["bookmarks", "notes", "positions", "tags", "advanced"]
	end

	def configure()
		bookmarks = Bookmarks.new
		notes = Notes.new
		tags = Tags.new
		positions = Positions.new

    load_settings
    
		subtitle = ""
		html_head = ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/config_navigator_header.rhtml"), 0, '<>').result(binding)
		puts html_head(:window_title => "Navigator - Configuration", :page_title => "Navigator Configuration", :sub_title =>  "#{subtitle}", :html_head => html_head)

		puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/config_navigator_head.rhtml"), 0, '<>').result(binding)
		puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/config_navigator_footer.rhtml"), 0, '<>').result(binding)
		STDOUT.flush

		@tabs.each {|tab|
			puts ERB.new(File.read("#{ENV['TM_BUNDLE_SUPPORT']}/templates/config_navigator_#{tab}.rhtml"), 0, '<>').result(binding)
		}

		html_footer()

		STDOUT.flush
	end

  def save_settings
    @log.debug CONFIGURATION_LOG, "@settings_path=#{@settings_path}"
    @log.debug CONFIGURATION_LOG, "settings=#{@settings_container.inspect}"
		FileUtils.mkdir_p(File.dirname(@settings_path))
    File.open(@settings_path, "w") {|fd|
      fd.write @settings_container.to_plist
    }
  end

  def load_settings
		@settings_path = "#{ENV['TM_BUNDLE_SUPPORT']}/../Preferences/Settings.tmPreferences"
    @log.debug CONFIGURATION_LOG, "@settings_path=#{@settings_path}"

    @settings_container = File.open(@settings_path) { |io| OSX::PropertyList.load(io) }
    @log.debug CONFIGURATION_LOG, "settings=#{@settings_container.inspect}"
		@settings = @settings_container["settings"]
		@settings = @settings["shellVariables"]
  end


	def apply_changes(params)
		load_settings
		
		params.each {|k,v|
			@log.debug CONFIGURATION_LOG, "#{k}=#{v}"
			set_setting(k, v)
		}
		
		save_settings
		@log.debug CONFIGURATION_LOG, "calling reload bundles"

		# Tell TM to reload the settings after they are changed externally
    Navigator.reload_bundles
	end

	def set_setting(setting_name, value)
		@log.debug CONFIGURATION_LOG, "setting_name=#{setting_name}  value=#{value}"
		var = @settings.select{|v| v["name"] == setting_name}
		return if var.nil? || var.length == 0 
		var = var[0]
		var["value"] = value
	end

  def get_settings
    if @settings.nil?
      load_settings
    end
    @settings
  end

  def get_setting(setting_name, default=nil)
		var = @settings.select{|v| v["name"] == setting_name}
		return default if var.nil? || var.length == 0 
		var = var[0]
    return var["value"]
  end
end

if __FILE__ == $0
	# NavigatorConfigurator.new.configure
  # NavigatorConfigurator.new.apply_changes(NavigatorConfigurator.param_translate)
  nc = NavigatorConfigurator.new
  puts "@settings=#{nc.get_settings().inspect}"
  puts "@settings[TM_NAVIGATOR_BOOKMARKS_FNAME]=#{nc.get_setting('TM_NAVIGATOR_BOOKMARKS_FNAME')}"
  # nc.save_settings
end
