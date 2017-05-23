#!/usr/bin/env ruby

# @file live-test.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'bundler/setup'
require 'rubygems'
require 'rest-client'
require 'joker'
require_relative 'test-definition'
require_relative 'sipp-test-definition'
require_relative 'ellis'

def run_tests(domain, glob="*")
  # Load and run all the tests
  Dir[File.join(File.dirname(__FILE__), "tests", "*.rb")].sort.each { |f| require f }
  TestDefinition.run_all(domain, Wildcard[glob, true])

  # Cleanup leaked numbers.  Ignore (but print, using the magic exception
  # variables) any exceptions.
  EllisProvisionedLine.destroy_leaked_numbers(domain) rescue puts $!, $@

  puts "#{TestDefinition.failures.length} failures out of #{TestDefinition.tests_run} tests run"
  TestDefinition.failures.each do |f|
    puts "    #{f}"
  end
  puts "#{TestDefinition.skipped} tests skipped"
  if TestDefinition.failures.empty?
    exit 0
  else
    puts "Error logs, including Call-IDs of failed calls, are in the 'logfiles' directory"
    exit 1
  end
end

def is_default_public_id? number
  /#{Regexp.escape(number["private_id"])}/ =~ number["sip_uri"]
end
