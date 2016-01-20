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

# This will set up the TM_BUNDLE_PATH environment variable either from
# the environment or the TM_BUNDLE_PATH ruby variable set up
# by an external calling script

# if __FILE__ == $0
# ENV['TM_BUNDLE_PATH'] = ENV['TM_PROJECT_DIRECTORY']
# ENV['TM_BUNDLE_SUPPORT'] = "#{ENV['TM_BUNDLE_PATH']}/Support"
# end

require ENV['TM_SUPPORT_PATH'] + '/lib/textmate.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui.rb'
require 'Logger'
require ENV['TM_BUNDLE_SUPPORT'] + '/navlogger.rb'

class Navigator

  GENERAL_LOG = 1
  NAVIGATOR_LOG = 2
  POSITION_LOG = 4

  @log = NavLogger.get_logger
  @log.level = NavLogger::WARN
  @log.set_subjects GENERAL_LOG | NAVIGATOR_LOG | POSITION_LOG
  @log.use_html = true;

  def self.check_doc(doc)
    if doc.nil? || doc.empty?
      button1 = "Oops!"
      title   = "This document is not linked to a file"
      prompt  = "The document must be linked to a file in order to retrieve it later"
      TextMate::UI.alert(:critical, title, prompt, button1)
      return false
    end
    return true
  end

  # Request an item from a list of items
  # this is a copy of the 'request_item' method of UI
  # but uses an initially wider dialog
  def self.request_item(options = Hash.new,&block)
    items = options[:items] || []
    case items.size
    when 0 then block_given? ? raise(SystemExit) : nil
    when 1 then block_given? ? yield(items[0]) : items[0]
    else
      params = default_buttons(options)
      params["title"] = options[:title] || "Select item:"
      params["prompt"] = options[:prompt] || ""
      params["string"] = options[:default] || ""
      params["items"] = items

      return_plist = %x{#{TM_DIALOG} -cmp #{e_sh params.to_plist} #{e_sh(ENV['TM_BUNDLE_SUPPORT'] + "/nibs/SelectTagDialog")}}
      return_hash = OSX::PropertyList::load(return_plist)

      # return string is in hash->result->returnArgument.
      # If cancel button was clicked, hash->result is nil.
      return_value = return_hash['result']
      return_value = return_value['returnArgument'] if not return_value.nil?
      return_value = return_value.first if return_value.is_a? Array

      if return_value == nil then
        block_given? ? raise(SystemExit) : nil
      else
        block_given? ? yield(return_value) : return_value
      end
    end
  end

  def self.default_buttons(user_options = Hash.new)
    options = Hash.new
    options['button1'] = user_options[:button1] || "OK"
    options['button2'] = user_options[:button2] || "Cancel"
    options
  end

  def self.escape_regexp(regexp, script_escapes = false)
    @log.debug NAVIGATOR_LOG, "regexp=#{regexp}  script_escapes=#{script_escapes}"
    # escape the standard Regexp characters
    regexp = Regexp.escape(regexp)
    @log.debug NAVIGATOR_LOG, "regexp=#{regexp}"

    regexp = regexp.gsub("'", "\\'")
    # script escapes requires doubling the back-slashes so that
    # the final expression has the right number of escapes
    regexp = regexp.gsub("\\", "\\\\") if script_escapes
    @log.debug NAVIGATOR_LOG, "regexp=#{regexp}"
    return regexp
  end

  # shortens the path for display so that the max length
  # does not exceed the supplied length while keeping the full file basename
  def self.shorten_path(fpath, max_length)
    begin
      if fpath.size <= max_length
        return fpath
      end
      bname = File.basename(fpath)
      path = File.dirname(fpath)
      path_length = max_length - bname.size - 4
      half_length = path_length / 2
      path = path[0, half_length]  + '....' + path[-half_length, path.size]
      return path + "/" + bname
    rescue
      return fpath
    end
  end

  def self.shorten_string(aString, max_length)
    begin
      if aString.size <= max_length
        return aString
      end
      split_length = max_length - 4
      half_length = split_length / 2
      str = aString[0, half_length]  + '....' + aString[-half_length, aString.size]
      return str
    rescue
      return aString
    end
  end

  # makes a TextMate compatible URL to open a file at a given line and position
  def self.make_file_link (file, lineNumber = 0, column = nil)
    url = "txmt://open/?url=file://"
    url += file.gsub(/([^a-zA-Z0-9.-\/]+)/) { '%' + $1.unpack('H2' * $1.size).join('%').upcase }
    url += "&amp;line=" + lineNumber.to_s if !lineNumber.nil?
    url += "&amp;column="+ column.to_s if !column.nil?
    url
  end

  def self.goto_file(path, lookup_expression = nil, lineNumber = nil, column = nil)
    @log.debug POSITION_LOG, "path, lookup_expression, lineNumber, column=#{path}, #{lookup_expression.inspect}, #{lineNumber}, #{column}"
    params = {}
    params[:file] = path if !path.nil?
    params[:line] = lineNumber if !lineNumber.nil?
    params[:column] = column if !column.nil?
    TextMate.go_to(params)

    if !lookup_expression.nil? && (ENV['TM_NAVIGATOR_SMART_POSITIONING'].to_i != 0) && !"#{ENV['TMTOOLS']}".empty?
      lineNumber = 1 if lineNumber.nil?
      column = 1 if column.nil?

      params = make_command_parameters(path, lookup_expression, lineNumber, column)
      fine_positioning = %Q{#!/usr/bin/env ruby
        ENV["TM_BUNDLE_SUPPORT"] = "#{ENV['TM_BUNDLE_SUPPORT']}"\n
        ENV["TM_SUPPORT_PATH"] = "#{ENV['TM_SUPPORT_PATH']}"\n
        require "#{ENV['TM_BUNDLE_SUPPORT']}/navigator.rb"\n
        Navigator.fine_position #{params} \n
      }
      @log.debug POSITION_LOG, "calling fine position=#{fine_positioning}"
      # call_tm_script(fine_positioning, path, "document", "showAsHTML")
      call_tm_script(fine_positioning, path, "document", "discard")
    else
      if lookup_expression.nil?
        @log.debug POSITION_LOG, "no lookup expression"
      end
      if ENV['TM_NAVIGATOR_SMART_POSITIONING'].to_i == 0
        @log.debug POSITION_LOG, "no smart positioning ENV['TM_NAVIGATOR_SMART_POSITIONING'].to_i=#{ENV['TM_NAVIGATOR_SMART_POSITIONING'].to_i}"
      end
      if "#{ENV['TMTOOLS']}".empty?
        @log.debug POSITION_LOG, "`no TMTOOLS"
      end
    end
  end

  def self.make_command_parameters(path, lookup_expression, lineNumber, column)
    @log.debug NAVIGATOR_LOG, "path, lookup_expression, lineNumber, column=#{path}, #{lookup_expression.inspect}, #{lineNumber}, #{column}"
    params = %Q{"#{path}", #{lookup_expression.inspect}, #{lineNumber}, #{column}}
    @log.debug NAVIGATOR_LOG, "params=#{params}"
    params
  end

  def self.call_tm_script(cmd, path, input = "none", output = "discard", before_running = "nop")
    @log.debug NAVIGATOR_LOG, "cmd, path, input, output, before_running=<br><pre>#{cmd}</pre><br>#{path}<br>#{input}<br>#{output}\n#{before_running}"
    cmd = %Q{<dict>
      <key>beforeRunningCommand</key>
      <string>#{before_running}</string>
      <key>command</key>
      <string>#{cmd}</string>
      <key>input</key>
      <string>#{input}</string>
      <key>output</key>
      <string>#{output}</string>
      </dict>
    }
    @log.debug NAVIGATOR_LOG, "cmd=<pre>#{cmd}</pre>"
    file_link = make_file_link(path)
    @log.debug NAVIGATOR_LOG, "file_link=#{file_link}"
    command = "open '#{file_link}';\"$TMTOOLS\" call command \'#{cmd}\'"
    @log.debug NAVIGATOR_LOG, "\ncommand=<pre>#{command}</pre>"
    `#{command}`
  end

  # tries to position the cursor as close as possible to the original line by comparing  
  def self.fine_position(path, lookup_expression, lineNumber, column)
    @log.debug POSITION_LOG, "path, lookup_expression, lineNumber, column=#{path}, <pre>#{lookup_expression.to_s}</pre>, #{lineNumber}, #{column}"

    @log.debug POSITION_LOG, "lookup_expression=|<pre>#{lookup_expression.inspect}</pre>|"

    # TODO: check if the current line is already ok
    @log.debug POSITION_LOG, "current line |#{ENV['TM_CURRENT_LINE']}|"
    # @log.debug POSITION_LOG, "current line |#{ENV['TM_CURRENT_LINE']}| ok" if pos_regexp.match(ENV['TM_CURRENT_LINE'])
    # return if pos_regexp.match(ENV['TM_CURRENT_LINE'])

    max_delta_lines = ENV['TM_NAVIGATOR_MAX_DELTA_LINES'].to_i

    # grep for the position's expression in the lines starting from the current position
    # line minus the max delta allowed and use the one nearest to the current line

    @log.debug POSITION_LOG, "Original delta=#{}"

    delta = max_delta_lines
    new_line = lineNumber

    # get the document's lines, as few as possible to avoid delays
    curr_line = 0
    @log.debug POSITION_LOG, "before reading from STDIN.class=#{STDIN.class}"
    STDIN.each{|line|
      curr_line += 1
      # skip lines outside the max_delta_lines range
      next if (lineNumber - curr_line).abs > delta

      @log.debug POSITION_LOG, "(#{curr_line}) #{line}"

      # try a match
      if lookup_expression.match(line)
        @log.debug POSITION_LOG, "<span style='color:red'>found match</span>"
        if (new_delta = (lineNumber - curr_line).abs) < delta
          # smaller delta, we are getting closer...
          delta = new_delta
          new_line = curr_line
          @log.debug POSITION_LOG, "new new_line=#{new_line}delta=#{new_delta}"
          # got a precise match?, no need to go on
          break if delta == 0
        end
      end
      # are we are going to go farther than the last match delta?
      # if so then no point in continuing the search
      if (lineNumber - (curr_line + 1)).abs > delta
        @log.debug POSITION_LOG, "braking out from the loop on line #{curr_line}"
        break
      end
    }
    @log.debug POSITION_LOG, "after reading line #{curr_line}"

    # check the distance so that it's not TOO far
    # Note that for a zero delta we don't reposition
    if 1 <= delta && delta <= max_delta_lines
      @log.debug POSITION_LOG, "repositioning at (#{new_line},#{column-1})"
      # reposition the cursor on the new line
      # puts "Position adjusted by #{delta} lines. Consider refreshing tags"
      %x{"$TMTOOLS" set caretTo '{line=#{new_line};index=#{column-1};}'}
    end
  end

  def self.get_font_name
    textmate_pref_file = '~/Library/Preferences/com.macromates.textmate.plist'
    prefs = OSX::PropertyList.load(File.open(File.expand_path(textmate_pref_file)))
    prefs['OakTextViewNormalFontName'] || 'Monaco'
  end

  def self.get_font_size
    textmate_pref_file = '~/Library/Preferences/com.macromates.textmate.plist'
    prefs = OSX::PropertyList.load(File.open(File.expand_path(textmate_pref_file)))
    prefs['OakTextViewNormalFontSize'] || 11
  end
  
  # Currently limited to just on selection
  # Precondition: the selection specification must be valid
  def self.decode_selection_spec(selection_spec)
    selStart, selEnd = selection_spec.split('-')
    selEnd = selStart if selEnd.nil?
  
    selLine, selCol = selStart.split(':')
    selCol = "0" if selCol.nil?
    
    [selLine, selCol]
  end

  def self.reload_bundles
    begin
      # FIX: This blocks the script execution and TM2 will eventually detect
      # changes automatically so no need to reload them manually
      ### %x{osascript -e 'tell app "TextMate" to reload bundles'}
    rescue
      @log.warn GENERAL_LOG, "Error while reloading bundles.\n#{$!}"
    end
  end

  def self.test
    puts "testing using puts"
    @log.error POSITION_LOG, "testing using log"
  end
end

if __FILE__ == $0
  Navigator.test
end
