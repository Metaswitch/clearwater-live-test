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

require 'timeout'
require "snmp"
require 'resolv'
require_relative "ellis"
require_relative "quaff-endpoint"
require_relative "sipp-endpoint"

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
      if ENV['TERM']
        fg_color = FG_COLORS["for_#{color}".to_sym]
        bg_color = BG_COLORS[color.to_sym]
        "\e[#{fg_color};#{bg_color}m"
      else
        ""
      end
    end
  end
end

class SkipThisTest < Exception
  attr_accessor :why_skipped, :how_to_enable
  def initialize why_skipped, how_to_enable=nil
    super why_skipped
    @why_skipped = why_skipped
    @how_to_enable = how_to_enable
  end
end

class TestDefinition
  attr_accessor :name, :current_label_id
  attr_writer :timeout

  @@tests = []
  @@current_test = nil
  @@failures = 0

# Class methods

  def self.add_instance(i)
    @@tests << i
  end

  def self.tests
    @@tests
  end

  def self.record_failure
    @@failures += 1
  end

  def self.failures
    @@failures
  end

  def self.run_all(deployment, glob)
    ENV['REPEAT'] ||= "1"
    ENV['TRANSPORT'] ||= "tcp,udp"
    repeat = ENV['REPEAT'].to_i
    req_transports = ENV['TRANSPORT'].downcase.split(',').map { |t| t.to_sym }
    transports = [:tcp, :udp].select { |t| req_transports.include? t }

    unless req_transports == transports
      STDERR.puts "ERROR: Unsupported transports #{req_transports - transports} requested"
      exit 2
    end
    tests_to_run = @@tests.select { |t| t.name =~ glob }
    repeat.times do |r|
      puts "Test iteration #{r + 1}" if repeat != 1
      tests_to_run.product(transports).collect do |test, trans|
        begin
          print "#{test.name} (#{trans.to_s.upcase}) - "
          success = test.run(deployment, trans)
          if success == true
            puts RedGreen::Color.green("Passed")
          elsif success == false
            record_failure
          end # Do nothing if success == nil - that means we skipped a test
        rescue StandardError => e
          record_failure
          puts RedGreen::Color.red("Failed")
          puts "  #{e.class} thrown:"
          puts "   - #{e}"
          puts e.backtrace.map { |line| "     - " + line }.join("\n")
        rescue SkipThisTest => e
          puts RedGreen::Color.yellow("Skipped") + " (#{e.why_skipped})"
          puts "   - #{e.how_to_enable}" if e.how_to_enable
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

  # Instance methods

  def initialize(name, &blk)
    TestDefinition.add_instance self
    @name = name
    @endpoints = []
    @as_list = []
    @blk = blk
    @current_label_id = 0
    @timeout = 10
  end

  # Methods for defining Quaff endpoints

  def add_endpoint
    line = provision_line
    include_endpoint QuaffEndpoint.new(line, @transport)
  end

  def add_specific_endpoint user_part
    line = provision_specific_line user_part
    include_endpoint QuaffEndpoint.new(line, @transport)
  end

  def add_pstn_endpoint
    line = provision_pstn_line
    include_endpoint QuaffEndpoint.new(line, @transport)
  end

  def add_public_identity(ep)
    line = provision_associated_line ep
    include_endpoint QuaffEndpoint.new(line, @transport)
  end

  def add_new_binding(ep)
    include_endpoint QuaffEndpoint.new(ep.line_info, @transport)
  end


  # Methods for defining Quaff-based test scenarios
  def add_quaff_setup &blk
    @quaff_setup_blk = blk
  end

  def add_quaff_scenario &blk
    @quaff_scenario_blocks.push blk
  end

  def add_quaff_cleanup &blk
    @quaff_cleanup_blk = blk
  end

  # Methods for defining application servers

  def add_as port
    c = Quaff::TCPSIPEndpoint.new("as1@#{@deployment}",
                                  nil,
                                  nil,
                                  port,
                                  nil)
    @as_list.push c
    c
  end

  def add_udp_as port
    c = Quaff::UDPSIPEndpoint.new("as1@#{@deployment}",
                                  nil,
                                  nil,
                                  port,
                                  nil)
    @as_list.push c
    c
  end

  def add_fake_endpoint(username)
    include_endpoint FakeEndpoint.new(username, @deployment)
  end

  def add_mock_as(domain, port)
    # TODO - pass in actual domain
    include_endpoint MockAS.new(domain, port)
  end

    # Methods for defining and running SIPp-based tests (only needed for the live
  # calls where we need real media)

  def add_sip_endpoint
    line = provision_line
    include_endpoint SIPpEndpoint.new(line, @transport)
  end

  def add_pstn_sip_endpoint
    line = provision_pstn_line
    include_endpoint SIPpEndpoint.new(line, @transport)
  end

  def set_scenario(scenario)
    @scenario = scenario
  end

  def run(deployment, transport)
    @deployment = deployment
    @transport = transport
    clear_diags
    @quaff_scenario_blocks = []
    @quaff_threads = []
    TestDefinition.set_current_test(self)
    retval = false
    begin
      @blk.call(self)
      print "(#{@endpoints.map { |e| e.sip_uri }.join ", "}) "
      @quaff_setup_blk.call if @quaff_setup_blk
      @quaff_threads = @quaff_scenario_blocks.map { |blk| Thread.new &blk }
      if @scenario
        sipp_scripts = create_sipp_scripts
        @sipp_pids = launch_sipp sipp_scripts
        retval = wait_for_sipp
      else
        retval = true
      end
      verify_snmp_stats if ENV['SNMP'] != "N"
    ensure
      retval &= cleanup
      TestDefinition.unset_current_test
    end
    return retval
  end

  def skip
    raise SkipThisTest.new "Test disabled"
  end

  def skip_unless_pstn
    raise SkipThisTest.new "No PSTN support", "Call with PSTN=true to run test" unless ENV['PSTN']
  end

  def skip_unless_mmtel
    raise SkipThisTest.new "No MMTel TAS support" if ENV['NOMMTEL']
  end

  def skip_unless_hostname
    raise SkipThisTest.new "No hostname given", "Call with HOSTNAME=<publicly accessible hostname/IP of this machine>" unless ENV['HOSTNAME']
  end

  def skip_unless_ellis_api_key
    raise SkipThisTest.new "No Ellis API key given", "Call with ELLIS_API_KEY=<key>" unless ENV['ELLIS_API_KEY']
  end

  def skip_if_udp
    raise SkipThisTest.new "Test is not valid for UDP" unless @transport == :udp
  end

  def skip_unless_live
    raise SkipThisTest.new "No live number given", "Call with LIVENUMBER=<number>" unless ENV['LIVENUMBER']
  end

  private

  # Methods for provisioning/retrieving various types of users

  def provision_line
    EllisProvisionedLine.new(@deployment)
  end

  def provision_specific_line
    EllisProvisionedLine.specific_line(user_part, @deployment)
  end

  def provision_pstn_line
    EllisProvisionedLine.new_pstn_line(@deployment)
  end

  def provision_associated_line ep
    line = EllisProvisionedLine.associated_public_identity(ep)
    fail "Added public identity does not share private ID" unless line.private_id == ep.private_id
    line
  end

  def include_endpoint new_endpoint
    @endpoints << new_endpoint
    new_endpoint
  end

  def cleanup
    retval = true
    @quaff_threads.each do |t|
      # Join the threads, this will do one of three things:
      #  - Return the thread handle, indicating complete success
      #  - Return nil indicating that the 60 seconds passed
      #  - Throw an exception caught in the thread
      result_of_join = begin
                         t.join(60)
                       rescue StandardError => e
                         e
                       end
      unless result_of_join == t
        puts RedGreen::Color.red("Failed") if retval

        if result_of_join.nil?
          puts "Endpoint had outstanding work to do, current backtrace:"
          t.backtrace.each { |b| puts "   - #{b}" }
          t.kill
        else
          puts "Endpoint threw exception:"
          puts " - #{e.message}"
          e.backtrace.each { |b| puts "   - #{b}" }
        end

        retval = false
      end
    end

    if @quaff_cleanup_blk
      @quaff_cleanup_blk.call
    end

    # If we failed any call scenario, dump out the log files.
    unless retval
      @endpoints.each do |e|
        log_file_name = File.join(File.dirname(__FILE__),
                                  "..",
                                  "scripts",
                                  "#{@name} - #{@transport.to_s.upcase} - #{e.sip_uri}.log")
        File.write(log_file_name, e.msg_log.join("\n\n================\n\n"))
      end
    end

    # Reverse the endpoints list so that associated public IDs are
    # deleted before the default public ID (which was created first).
    @endpoints.reverse.each do |e|
      e.cleanup
    end
    @endpoints = []

    @as_list.reverse.each do |e|
      e.terminate
    end
    @as_list = []

    retval
  end


  def verify_snmp_stats
    latency_threshold = 250
    average_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.2"
    hwm_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.4"
    lwm_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.5"

    snmp_host = Resolv::DNS.new.getaddress(@deployment).to_s
    snmp_map = {}
    SNMP::Manager.open(:host => snmp_host, :community => "clearwater") do |manager|
      manager.walk("1.2.826.0.1.1578918.9.2") do |row|
        row.each { |vb| snmp_map[vb.oid] = vb.value }
      end
    end

    if (snmp_map[lwm_oid] && snmp_map[hwm_oid] && snmp_map[average_oid])
      if (snmp_map[lwm_oid] > snmp_map[hwm_oid])
        raise "Bono SNMP values are inconsistent - the LWM (#{snmp_map[lwm_oid]}ms) is above the HWM (#{snmp_map[hwm_oid]}ms): #{snmp_map.inspect}"
      end


      if (snmp_map[average_oid] > snmp_map[hwm_oid])
        raise "Bono SNMP values are inconsistent - the average (#{snmp_map[average_oid]}ms) is above the HWM (#{snmp_map[hwm_oid]}ms): #{snmp_map.inspect}"
      end


      if (snmp_map[lwm_oid] > snmp_map[average_oid])
        raise "Bono SNMP values are inconsistent - the LWM (#{snmp_map[lwm_oid]}ms) is above the average (#{snmp_map[average_oid]}ms): #{snmp_map.inspect}"
      end

      if (snmp_map[average_oid] > (1000 * latency_threshold))
        raise "Bono's average latency is greater than #{latency_threshold}ms"
      end
    else
      puts "No SNMP responses from Bono"
    end
  end

  def create_sipp_scripts
    sipp_scripts = []
    # Filter out AS scenario as it will go into a separate SIPp file
    grouped_scripts = @scenario.group_by { |s| s.sender.element_type }
    grouped_scripts.each do |element_type, scenario|
      sipp_scripts.push(create_sipp_script(scenario, element_type)) unless scenario.empty?
    end
    sipp_scripts
  end

  def create_sipp_script(scenario, element_type)
    sipp_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n" +
      "<scenario name=\"#{@name} - #{element_type.to_s}\">\n" +
      scenario.each { |s| s.to_s }.join("\n") +
      "\n" +
      "  <ResponseTimeRepartition value=\"10, 20, 30, 40, 50, 100, 150, 200\" />\n" +
      "  <CallLengthRepartition value=\"10, 50, 100, 500, 1000, 5000, 10000\" />\n" +
      "</scenario>"
    output_file_name = File.join(File.dirname(__FILE__),
                                 "..",
                                 "scripts",
                                 "#{@name} - #{@transport.to_s.upcase} - #{element_type.to_s}.xml")
    File.write(output_file_name, sipp_xml)
    { scenario_file: output_file_name, element_type: element_type }
  end


  def launch_sipp(sipp_scripts)
    sipp_pids = sipp_scripts.map do |s|
      fail "No scenario file" if s[:scenario_file].nil?

      @deployment = ENV['PROXY'] if ENV['PROXY']
      transport_flag = s[:element_type] == :as ? "t1" : { udp: "u1", tcp: "t1" }[@transport]
      cmd = "sudo TERM=xterm ./sipp -m 1 -t #{transport_flag} --trace_msg --trace_err -max_socket 100 -sf \"#{s[:scenario_file]}\" #{@deployment}"
      cmd += " -p 5070" if s[:element_type] == :as
      Process.spawn(cmd, :out => "/dev/null", :err => "#{s[:scenario_file]}.err")
    end
    fail if sipp_pids.any? { |pid| pid.nil? }
    sipp_pids
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
    # Limit test execution to 10 seconds
    return_codes = ( Timeout::timeout(@timeout) { Process.waitall.map { |p| p[1].exitstatus } } rescue nil )
    if return_codes.nil? or return_codes.any? { |rc| rc != 0 }
      TestDefinition.record_failure
      if return_codes.nil?
        puts RedGreen::Color.red("ERROR (TIMED OUT)")
        @sipp_pids.each { |pid| Process.kill("SIGKILL", pid) rescue puts "Could not kill process with pid #{pid}" }
      else
        puts RedGreen::Color.red("ERROR (#{return_codes.join ", "})")
      end
      puts "  Diags can be found at:"
      get_diags.each do |d|
        puts "   - #{d}"
      end
      return false
    else
      clear_diags
      return true
    end
  end
end


