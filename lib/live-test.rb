#!/usr/bin/env ruby

# @file live-test.rb
#
# Copyright (C) 2013  Metaswitch Networks Ltd
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# The author can be reached by email at clearwater@metaswitch.com or by post at
# Metaswitch Networks Ltd, 100 Church St, Enfield EN2 6BQ, UK

require 'rubygems'
require 'require_all'
require 'rest-client'
require 'joker'
require_relative 'test-definition'
require_relative 'sipp-phase'
require_relative 'sipp-endpoint'
require_relative 'fake-endpoint'

def run_tests(domain, glob="*")
  # Set the global domain
  $domain = domain

  # Load and run all the tests
  require_all 'lib/tests'
  TestDefinition.run_all($domain, Wildcard[glob, true])

  destroy_leaked_numbers
end

def destroy_leaked_numbers
  # Despite trying to clean up numbers, we seem to leak them pretty fast, destroy them now
  r = RestClient.post("http://ellis.#{$domain}/session",
                      username: "system.test@cw-ngv.com",
                      password: "Please enter your details")
  cookie = r.cookies
  r = RestClient::Request.execute(method: :get,
                                  url: "http://ellis.#{$domain}/accounts/system.test@cw-ngv.com/numbers",
                                  cookies: cookie)
  j = JSON.parse(r)

  j["numbers"].each do |n|
    puts "Deleting leaked number: #{n["sip_uri"]}"
    RestClient::Request.execute(method: :delete,
                                url: "http://ellis.#{$domain}/accounts/system.test@cw-ngv.com/numbers/#{CGI.escape(n["sip_uri"])}/",
                              cookies: cookie)
  end
end
