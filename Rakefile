# @file Rakefile
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

task :default => [:test]
task :test, :deployment do |t, args|
  require './lib/live-test'
  ENV['TESTS'] ||= "*"
  run_tests(args.deployment, ENV['TESTS'])
end
