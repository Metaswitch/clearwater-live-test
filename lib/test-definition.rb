# @file test-definition.rb
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

# Source: RedGreen gem - https://github.com/kule/redgreen
module RedGreen
  module Color
    # 37 = white, 30 = black
    FG_COLORS = { :for_clear => 37, :for_red => 37, :for_green => 37, :for_yellow => 30}
    BG_COLORS = { :clear => 0, :red => 41, :green => 42, :yellow => 43 }
    def self.method_missing(color_name, *args)
      color(color_name) + args.first + color(:clear)
    end
    def self.color(color)
      fg_color = FG_COLORS["for_#{color}".to_sym]
      bg_color = BG_COLORS[color.to_sym]
      "\e[#{fg_color};#{bg_color}m"
    end
  end
end

class TestDefinition
  attr_accessor :name, :current_label_id

  @@tests = []
  @@current_test = nil
  @@failures = 0

  def self.add_instance(i)
    @@tests << i
  end

  def self.tests
    @@tests
  end

  def record_failure
    @@failures += 1
  end

  def self.failures
    @@failures
  end

  def self.run_all(deployment, glob)
    ENV['REPEAT'] ||= "1"
    repeat = ENV['REPEAT'].to_i
    tests_to_run = @@tests.select { |t| t.name =~ glob }
    repeat.times do |r|
      puts "Test iteration #{r + 1}" if repeat != 1
      tests_to_run.product([:tcp, :udp]).collect do |test, trans|
        begin
          print "#{test.name} (#{trans.to_s.upcase}) - "
          test.run(deployment, trans)
        rescue Exception => e
          record_failure
          puts RedGreen::Color.red("Failed")
          puts "  #{e.class} thrown:"
          puts "   - #{e}"
          puts e.backtrace.map { |line| "     - " + line }.join("\n")
        end
      end
    end
  end

  def self.set_current_test(t)
    @@current_test = t
  end

  def self.unset_current_test
    @@current_test = nil
  end

  def self.get_next_label_id
    fail "No currently running test" if @@current_test.nil?
    @@current_test.current_label_id += 1
    @@current_test.current_label_id.to_s
  end

  def initialize(name, &blk)
    TestDefinition.add_instance self
    @name = name
    @endpoints = []
    @blk = blk
    @current_label_id = 0
  end

  def cleanup
    @endpoints.each do |e|
      e.cleanup
    end
  end

  # @@TODO - Don't pass transport in once UDP authentication is fixed
  def add_sip_endpoint
    new_endpoint = SIPpEndpoint.new(false, @deployment, @transport)
    @endpoints << new_endpoint
    return new_endpoint
  end

  # @@TODO - Don't pass transport in once UDP authentication is fixed
  def add_pstn_endpoint
    new_endpoint = SIPpEndpoint.new(true, @deployment, @transport)
    @endpoints << new_endpoint
    return new_endpoint
  end

  def add_fake_endpoint(username, domain)
    new_endpoint = FakeEndpoint.new(username, domain)
    @endpoints << new_endpoint
    return new_endpoint
  end

  def set_scenario(scenario)
    @scenario = scenario
  end

  def create_sipp_script
    sipp_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n" +
      "<scenario name=\"#{@test_name}\">\n" +
      @scenario.each { |s| s.to_s }.join("\n") +
      "\n" +
      "  <ResponseTimeRepartition value=\"10, 20, 30, 40, 50, 100, 150, 200\" />\n" +
      "  <CallLengthRepartition value=\"10, 50, 100, 500, 1000, 5000, 10000\" />\n" +
      "</scenario>"
    output_file_name = File.join(File.dirname(__FILE__),
                                 "..",
                                 "scripts",
                                 "#{@name} - #{@transport.to_s.upcase}.xml")
    File.write(output_file_name, sipp_xml)
    @scenario_file = output_file_name
  end

  def run(deployment, transport)
    @deployment = deployment
    @transport = transport
    clear_diags
    TestDefinition.set_current_test(self)
    begin
      @blk.call(self)
      create_sipp_script
      launch_sipp
      wait_for_sipp
    ensure
      cleanup
      TestDefinition.unset_current_test
    end
  end

  def launch_sipp
    fail "No scenario file" if @scenario_file.nil?
    fail "SIPp is already running" if not @sipp_pid.nil?

    @deployment = ENV['PROXY'] if ENV['PROXY']
    transport_flag = { udp: "u1", tcp: "t1" }[@transport]

    @sipp_pid = Process.spawn("sudo TERM=xterm ./sipp -m 1 -t #{transport_flag} --trace_msg --trace_err -max_socket 100 -sf \"#{@scenario_file}\" #{@deployment}",
                              :out => "/dev/null", :err => "#{@scenario_file}.err")
  end

  def get_diags
    Dir["scripts/#{@name} - #{@transport.to_s.upcase}*"]
  end

  def clear_diags
    get_diags.each do |d|
      File.unlink(d)
    end
  end

  def wait_for_sipp
    fail if @sipp_pid.nil?
    rc = Process.wait2(@sipp_pid)[1].exitstatus
    @sipp_pid = nil
    if rc != 0
      record_failure
      puts RedGreen::Color.red("ERROR (#{rc})")
      puts "  Diags can be found at:"
      get_diags.each do |d|
        puts "   - #{d}"
      end
    else
      puts RedGreen::Color.green("Passed")
      clear_diags
    end
  end
end

class SkippedTestDefinition < TestDefinition
  def run(*args)
    clear_diags
    puts RedGreen::Color.yellow("Skipped") + " (Test disabled)"
  end
end

class PSTNTestDefinition < TestDefinition
  def run(*args)
    clear_diags
    if ENV['PSTN']
      super
    else
      puts RedGreen::Color.yellow("Skipped") + " (No PSTN support)"
      puts "   - Call with PSTN=true to run test"
    end
  end
end

class LiveTestDefinition < PSTNTestDefinition
  def run(*args)
    clear_diags
    if ENV['LIVENUMBER']
      super
    else
      puts RedGreen::Color.yellow("Skipped") + " (No live number given)"
      puts "   - Call with LIVENUMBER=<number>"
    end
  end
end
