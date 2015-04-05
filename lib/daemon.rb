#!/usr/bin/env ruby

require 'daemons'
require 'pathname'
require_relative './live-test'

def source(file, vars)
  ENV.replace(eval(`/bin/bash -c 'source #{file} && export #{vars.join " "} && ruby -e "p ENV"'`))
end

path = Pathname.new("/var/log/clearwater-live-verification/");
Daemons.run_proc("clearwater-live-verification",
                 dir_mode: :normal,
                 dir: path) do
  system("echo Clearing alarm")
  loop do
    # Sort out the appropriate ENV variables from clearwater config.
    source("/etc/clearwater/config", ["home_domain", "ellis_address", "pcscf_address"])
    if ENV['ellis_hostname'] then
      ENV['ELLIS'] = ENV['ellis_hostname']
    else
      ENV['ELLIS'] = "ellis.#{ENV['home_domain']}"
    end
    if ENV['pcscf_hostname'] then
      ENV['PROXY'] = ENV['pcscf_hostname']
    else
      ENV['PROXY'] = "#{ENV['home_domain']}"
    end
    ENV['TRANSPORT'] = 'tcp'

    # These tests exit with their success code so catch the exit status here.
    begin
      run_tests(ENV['home_domain'], "Basic *")
    rescue SystemExit => e
      success = e.status
    end

    if success == 0 then
      # Tests passed - clear the alarm
      system("echo Clearing alarm")
    else
      # Tests failed - raise the alarm and collect diags
      system("echo Raising alarm")
      sleep 30
    end
  end
end
