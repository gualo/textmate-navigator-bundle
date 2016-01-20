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

# require ENV['TM_BUNDLE_SUPPORT'] + '/notes.rb'
# 
# class Notes
# 
# 
# 	def save_options(params)
# 		zap_browser_settings
# 		
# 		# get_browser_settings.push({"name" => FILTER_SETTING, "value" => params[FILTER_PARAM]})
# 		get_browser_settings.push({"name" => NO_EXTRAS_SETTING, "value" => (params[NO_EXTRAS_PARAM] == "true")})
# 		
# 		type_filters = get_browser_filters
# 		params.each{|key, value|
# 			if (key.start_with?(TYPE_FILTER_PREFIX))
# 				type_filters.push({"name" => key[TYPE_FILTER_PREFIX.size .. key.size], "value" => (value == "true")})
# 			end
# 		}
# 
# 		save_settings
# 	end
# end
