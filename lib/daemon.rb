#!/usr/bin/env ruby

require 'daemons'
require 'pathname'
require 'ffi-rzmq'
require 'syslog'
require_relative './live-test'

def source(file, vars)
  ENV.replace(eval(`/bin/bash -c 'source #{file} && export #{vars.join " "} && ruby -e "p ENV"'`))
end

def raise_alarm(id)
  context = ZMQ::Context.new
  client = context.socket(ZMQ::REQ)
  client.connect("tcp://127.0.0.1:6664")

  poller = ZMQ::Poller.new
  poller.register(client, ZMQ::POLLIN)

  client.send_strings ["issue-alarm", "clearwater-live-verification", id]

  poller.poll(2000)

  if poller.readables.include? client
    response = []
    client.recv_strings(response)
  else
    Syslog.err("Dropped alarm #{id}")
  end

  client.close
end

path = Pathname.new("/var/log/clearwater-live-verification/");
Daemons.run_proc("clearwater-live-verification",
                 dir_mode: :normal,
                 dir: path) do
  # Initially we don't know the state of the deployment
  raise_alarm("6000.2")

  loop do

    # Sort out the appropriate ENV variables from clearwater config.
    source("/etc/clearwater/config", ["home_domain", "ellis_address", "pcscf_address", "signup_key"])
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
    ENV['SIGNUP_CODE'] = ENV['signup_key']
    ENV['TRANSPORT'] = 'tcp'

    # These tests exit with their success code so catch the exit status here.
    begin
      run_tests(ENV['home_domain'], "Basic *")
    rescue SystemExit => e
      success = e.status
    end

    if success == 0 then
      # Tests passed - clear the alarm
      raise_alarm("6000.1")
    else
      # Tests failed - raise the critical alarm
      raise_alarm("6000.3")

      # Sleep for a bit (failing the test can happen very fast and we don't
      # want to DoS the deployment.
      sleep 30
    end
  end
end
