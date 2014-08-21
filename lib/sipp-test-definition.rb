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

require_relative "sipp-endpoint"
require_relative "sipp-phase"
require_relative "test-definition"

class SIPpTestDefinition < TestDefinition
  # Methods for defining and running SIPp-based tests (only needed for the live
  # calls where we need real media)

  def add_sipp_endpoint
    line = provision_line
    include_endpoint SIPpEndpoint.new(line, @transport)
  end

  def add_pstn_sipp_endpoint
    line = provision_pstn_line
    include_endpoint SIPpEndpoint.new(line, @transport)
  end

  def set_scenario(scenario)
    @scenario = scenario
  end

  private
  def before_run
    clear_diags
  end

  def on_failure
    # If we failed any call scenario, dump out the log files.
    @endpoints.each do |e|
        log_file_name = File.join(File.dirname(__FILE__),
                                  "..",
                                  "scripts",
                                  "#{@name} - #{@transport.to_s.upcase} - #{e.sip_uri}.log")
        File.write(log_file_name, e.msg_log.join("\n\n================\n\n"))
      end
  end


  def extra_validation
    sipp_scripts = create_sipp_scripts
    @sipp_pids = launch_sipp sipp_scripts
    retval = wait_for_sipp
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
