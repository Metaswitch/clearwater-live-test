# @file Rakefile
#
# Copyright (C) Metaswitch Networks 2013
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

task :default => [:test]
task :test, :deployment do |t, args|
  require './lib/live-test'

  # If no PCSCF is specified, assume it acts as a Proxy
  ENV['PCSCF'] ||= "PROXY"

  ENV['TESTS'] ||= "*"
  run_tests(args.deployment, ENV['TESTS'])
end
