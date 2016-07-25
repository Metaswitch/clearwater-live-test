#!/usr/bin/env ruby

# @file live-test.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2013  Metaswitch Networks Ltd
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version, along with the "Special Exception" for use of
# the program along with SSL, set forth below. This program is distributed
# in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details. You should have received a copy of the GNU General Public
# License along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
#
# The author can be reached by email at clearwater@metaswitch.com or by
# post at Metaswitch Networks Ltd, 100 Church St, Enfield EN2 6BQ, UK
#
# Special Exception
# Metaswitch Networks Ltd  grants you permission to copy, modify,
# propagate, and distribute a work formed by combining OpenSSL with The
# Software, or a work derivative of such a combination, even if such
# copying, modification, propagation, or distribution would otherwise
# violate the terms of the GPL. You must comply with the GPL in all
# respects for all of the code used other than OpenSSL.
# "OpenSSL" means OpenSSL toolkit software distributed by the OpenSSL
# Project and licensed under the OpenSSL Licenses, or a work based on such
# software and licensed under the OpenSSL Licenses.
# "OpenSSL Licenses" means the OpenSSL License and Original SSLeay License
# under which the OpenSSL Project distributes the OpenSSL toolkit software,
# as those licenses appear in the file LICENSE-OPENSSL.

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
  exit (TestDefinition.failures.length == 0) ? 0 : 1
end

def is_default_public_id? number
  /#{Regexp.escape(number["private_id"])}/ =~ number["sip_uri"]
end
