#!/usr/bin/env ruby18
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

require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'
require ENV['TM_BUNDLE_SUPPORT'] + '/navlogger.rb'
require "fileutils"

class NotesSettings
  SETTINGS_NOTES_LOG = 1

  FILTER_PARAM = FILTER_SETTING = "filter"
  SETTINGS = "settings"
  BROWSER_SETTINGS = "browserSettings"
  NOTE_TAGS_SETTINGS = "notesTags"
  TYPE_FILTER_PREFIX = "type_filter_"
  TYPE_FILTERS_SETTING = "type_filters"
  NO_EXTRAS_SETTING = NO_EXTRAS_PARAM = "no_extras"
	RE_FILTER_SETTING = "re_filter"

  def initialize()
    @log = NavLogger.get_logger
    @log.level = NavLogger::WARN
    @log.set_subjects SETTINGS_NOTES_LOG

    # if the notes settings path is absolute (i.e. starts with a '/') then use it as is
    # otherwise use it as suffix after the user's HOME directory
    if ENV['TM_NAVIGATOR_NOTES_SETTINGS_PATH'][0] == '/'
      @settings_path = "ENV['TM_NAVIGATOR_NOTES_SETTINGS_PATH']/#{ENV['TM_NAVIGATOR_NOTES_SETTINGS_FNAME']}"
    else
      @settings_path = "#{ENV['HOME']}/#{ENV['TM_NAVIGATOR_NOTES_SETTINGS_PATH']}/#{ENV['TM_NAVIGATOR_NOTES_SETTINGS_FNAME']}"
    end

    @default_settings_path = "#{ENV['TM_BUNDLE_SUPPORT']}/../Preferences/Default Annotations Settings.tmPreferences"
  end

  def get_note_types(add_all = false)
    note_types = add_all ? [Notes::ALL_NOTES] : []
    notes_tags = get_settings[NOTE_TAGS_SETTINGS]
    @log.debug "notes_tags=#{notes_tags.inspect}"
    notes_tags.each{|type| note_types.push(type["name"])}
    return note_types
  end

  def get_settings
    if @settings.nil?
      load_settings
    end
    @settings
  end

  def get_browser_settings
    get_settings[BROWSER_SETTINGS] = [] if get_settings[BROWSER_SETTINGS].nil?
    get_settings[BROWSER_SETTINGS]
  end

  def get_browser_setting(setting)
    if setting == TYPE_FILTERS_SETTING
      return get_browser_filters
    end

    idx = get_browser_settings.index{|item|
      true if item["name"] == setting
    }

    if idx.nil?
      nil
    else
      get_browser_settings[idx]["value"]
    end
  end

  def zap_browser_settings
    get_settings[BROWSER_SETTINGS] = []
  end

  def get_browser_filters
    idx = get_browser_settings.index{|item|
      true if item["name"] == TYPE_FILTERS_SETTING
    }
    if idx.nil?
      filters = []
      get_browser_settings.push({"name" => TYPE_FILTERS_SETTING, "value" => filters})
      filters
    else
      get_browser_settings[idx]["value"]
    end
  end

  def load_settings
    @log.debug SETTINGS_NOTES_LOG, "@settings_path=#{@settings_path}"
    path = @settings_path if File.exist?(@settings_path)
    path = @default_settings_path if path.nil?
    @settings_container = File.open(path) { |io| OSX::PropertyList.load(io) }
    @settings = @settings_container[SETTINGS]
    @log.debug SETTINGS_NOTES_LOG, "@settings=#{@settings.inspect}"
  end

  def save_settings
    @log.debug SETTINGS_NOTES_LOG, "final settings=#{@settings.inspect}"
		FileUtils.mkdir_p(File.dirname(@settings_path))
    File.open(@settings_path, "w") {|fd|
      fd.write @settings_container.to_plist
    }
  end

  def save_options(params)
    @log.debug SETTINGS_NOTES_LOG, "params=#{params.inspect}"
    zap_browser_settings

    get_browser_settings.push({"name" => FILTER_SETTING, "value" => params[FILTER_PARAM]})
    get_browser_settings.push({"name" => NO_EXTRAS_SETTING, "value" => params[NO_EXTRAS_PARAM]})
    get_browser_settings.push({"name" => RE_FILTER_SETTING, "value" => params[RE_FILTER_SETTING]})

    type_filters = get_browser_filters
    params.each{|key, value|
      if (key.start_with?(TYPE_FILTER_PREFIX))
        type_filters.push({"name" => key[TYPE_FILTER_PREFIX.size .. key.size], "value" => value})
      end
    }

    save_settings
  end
  
  def logger
    @log
  end
end

if __FILE__ == $0
	ns = NotesSettings.new
  ns.logger.use_html = false
	ns.load_settings
	ns.save_settings
end