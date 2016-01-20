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

require "erb"
include ERB::Util

class NavLogger
  NONE = 0
  DEBUG = 1
  INFO = 2
  WARN = 3
  ERROR = 4
  FATAL = 5
  @@levels = {
    NONE => "NONE",
    DEBUG=>"DEBUG",
    INFO=>"INFO",
    WARN=>"WARN",
    ERROR=>"ERROR",
    FATAL=>"FATAL"
  }
  ALL_SUBJECTS = 0xFFFFFFFF

  attr_accessor :use_html
  attr_accessor :level
  attr_accessor :formatter
  attr_accessor :stream
  attr_accessor :subjects

  def self.get_logger()
    if ENV['TM_NAVIGATOR_DEBUG'].to_i > 0
      NavLogger.new(STDOUT)
    else
      @logger = DummyLogger.new()
    end
  end

  def initialize(stream)
    @stream = stream
    @use_html = true
    @subjects = 0
    @level = DEBUG

    @formatter = proc do |severity, datetime, filename, linenumber, calling_method, msg|
      if @use_html
        filename = "<a href='#{make_file_link(filename, linenumber)}'>#{html_escape(File.basename(filename))}</a>"
			else
        filename = html_escape(File.basename(filename))
      end
      "#{severity} (#{datetime}) [#{filename}#{calling_method.nil? ? "" : "::#{calling_method}(#{linenumber})"}] - #{msg}#{@use_html ? "<br/>" : "\n"}"
    end
  end

  # define a logging method for each one of the levels
  @@levels.each{|level, name|
    define_method("subject_#{name.downcase}") {|subject, msg|
      @stream.puts(build_message(level, msg)) unless (@level > level) || ((@subjects & subject) == 0)
    }
  }

  # def subject_debug(subject, msg)
  # 	@stream.puts(build_message(DEBUG, msg)) unless (@level > DEBUG) || ((@subjects & subject) == 0)
  # end
  #
  def method_missing(m, *args, &block)
    if @@levels.has_value?("#{m}".upcase)
      if args.size == 1
        send("subject_#{m}", ALL_SUBJECTS, args[0])
      else
        send("subject_#{m}", args[0], args[1])
      end
    else
      puts "Undefined method #{m}"
    end
  end

  def add_subjects(subjectsMask)
    @subjects |= subjectsMask
  end

  def set_subjects(subjectsMask)
    @subjects = subjectsMask
  end

  def unset_subjects(subjectsMask)
    @subjects &= ~subjectsMask
  end

  def build_message(severity, msg)
    frame = caller[3].split(':')
    prog = frame[0]
    # file_base = File.basename(prog)
    line = frame[1].to_i
    if frame.size > 2
      begin
        from = frame[2].scan(/in `([_a-zA-Z0-9]*)/)[0][0]
      rescue
        from = ""
      end
    else
      from = ""
    end

    severity_str = @@levels[severity]
    return @formatter.call(severity_str, Time.new.strftime("%I:%M:%S"), prog, line, from, msg)
  end

  def make_file_link (file, line = 0)
    return "txmt://open/?url=file://" +
    file.gsub(/([^a-zA-Z0-9.-\/]+)/) { '%' + $1.unpack('H2' * $1.size).join('%').upcase } +
    "&amp;line=" + line.to_s
  end

end

class DummyLogger
  def method_missing(name, *args, &block)
    # silently ignore any possible call
  end
  def respond_to?(meth)
    return true
  end
end

if __FILE__ == $0
  class NavLoggerTester
    def self.test
      l = NavLogger.get_logger
      l.use_html = false

      l.set_subjects NavLogger::ALL_SUBJECTS
      l.debug    "1) without subject"
      l.debug 2, "1) with subject 2"
      l.debug 3, "1) with subject 3"

      l.set_subjects 2
      l.debug    "2) without subject"
      l.debug 2, "2) with subject 2"
      l.debug 4, "2) with subject 4"

      l.set_subjects 1
      l.debug    "3) without subject"
      l.debug 2, "3) with subject 2"
      l.debug 4, "3) with subject 4"
    end
    def self.test2
      l = NavLogger.get_logger
      l.level = NavLogger::DEBUG
      l.use_html = false

      l.set_subjects NavLogger::ALL_SUBJECTS
      l.debug    "1) without subject"
    end
  end

	NavLoggerTester.test2
end
