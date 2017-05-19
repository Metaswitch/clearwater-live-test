# @file test-definition.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require_relative "sipp-endpoint"
require_relative "sipp-phase"
require_relative "test-definition"

class SIPpTestDefinition < TestDefinition
  # Methods for defining and running SIPp-based tests (only needed for the live
  # calls where we need real media)

  def add_sipp_endpoint
    line = provision_line
    include_endpoint SIPpEndpoint.new(line, @transport, @endpoints.length)
  end

  def add_pstn_sipp_endpoint
    line = provision_pstn_line
    include_endpoint SIPpEndpoint.new(line, @transport, @endpoints.length)
  end

  def set_scenario(scenario)
    @scenario = scenario
  end

  private
  def before_run
    clear_diags
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

  def on_failure
    # SIPp dumps out its own log files
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
