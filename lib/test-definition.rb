# @file test-definition.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'timeout'
require "snmp"
require_relative "ellis"
require_relative "quaff-endpoint"
require_relative "fake-endpoint"

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

class SkipThisTest < StandardError
  attr_accessor :why_skipped, :how_to_enable
  def initialize why_skipped, how_to_enable=nil
    super why_skipped
    @why_skipped = why_skipped
    @how_to_enable = how_to_enable
  end
end

class TestDefinition
  attr_accessor :name, :current_label_id, :num_lives
  attr_reader :deployment
  attr_writer :timeout

  @@tests = []
  @@current_test = nil
  @@failures = []
  @@tests_run = 0
  @@skipped = 0

# Class methods

  def self.add_instance(i)
    @@tests << i
  end

  def self.tests
    @@tests
  end

  def self.record_failure test_id
    @@failures << "#{test_id} at #{Time.new.inspect}"
  end

  def self.failures
    @@failures
  end

  def self.tests_run
    @@tests_run
  end

  def self.skipped
    @@skipped
  end

  def self.get_diags
    Dir["logfiles/*.log"]
  end

  def self.clear_diags
    get_diags.each do |d|
      File.unlink(d)
    end
  end

  def self.run_all(deployment, glob)
    ENV['REPEAT'] ||= "1"
    ENV['TRANSPORT'] ||= "tcp"
    repeat = ENV['REPEAT'].to_i
    req_transports = ENV['TRANSPORT'].downcase.split(',').map { |t| t.to_sym }
    transports = [:tcp, :udp].select { |t| req_transports.include? t }

    unless req_transports.sort == transports.sort
      STDERR.puts "ERROR: Unsupported transports #{req_transports - transports} requested"
      exit 2
    end
    clear_diags
    tests_to_run = @@tests.select { |t| t.name =~ glob }
    tests_to_exclude = if ENV['EXCLUDE_TESTS']
                         ENV['EXCLUDE_TESTS'].split ","
                       else
                         []
                       end
    (1..repeat).each do |r|
      tests_to_run.product(transports).collect do |test, trans|
        begin
          if repeat == 1
              test_id = "#{test.name} (#{trans.to_s.upcase})"
          else
              test_id = "#{test.name} (#{trans.to_s.upcase}) (iter #{r})"
          end
          print "#{test_id} - "
          tests_to_exclude.each do |exclusion|
            if test_id.start_with? exclusion
              raise SkipThisTest.new("Test skipped by EXCLUDE_TESTS (matched #{exclusion})")
            end
          end
          @@tests_run += 1
          success = test.run(deployment, trans, r)
          if success == true
            puts RedGreen::Color.green("Passed")
          elsif success == false
            record_failure(test_id)
          else
            # Do nothing if success == nil - that means we skipped a test
            @@skipped += 1
          end
        rescue SkipThisTest => e
          puts RedGreen::Color.yellow("Skipped") + " (#{e.why_skipped})"
          puts "   - #{e.how_to_enable}" if e.how_to_enable
          @@skipped += 1
        rescue StandardError => e
          record_failure(test_id)
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

  # Instance methods

  def initialize(name, &blk)
    TestDefinition.add_instance self
    @name = name
    @endpoints = []
    @as_list = []
    @blk = blk
    @current_label_id = 0
    @timeout = 10
    @num_lives = 0
    @lives_used = 0
  end

  # Methods for defining Quaff endpoints

  def add_endpoint line=nil, use_instance_id=true
    line ||= provision_line
    include_endpoint QuaffEndpoint.new(line, @transport, @endpoints.length, use_instance_id)
  end

  def add_specific_endpoint user_part
    line = provision_specific_line user_part
    add_endpoint line
  end

  def add_pstn_endpoint
    line = provision_pstn_line
    add_endpoint line
  end

  def add_public_identity(ep)
    line = provision_associated_line ep
    add_endpoint line
  end

  def add_new_binding(ep, use_instance_id=true)
    add_endpoint ep.line_info, use_instance_id
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

  def run(deployment, transport, iteration)
    before_run
    @deployment = deployment
    @transport = transport
    @iteration = iteration
    @quaff_scenario_blocks = []
    @quaff_threads = []
    @quaff_setup_blk = nil
    @quaff_cleanup_blk = nil
    TestDefinition.set_current_test(self)
    retval = false
    begin
      @blk.call(self)
      print "(#{@endpoints.map { |e| e.username }.uniq.join ", "}) "
      @quaff_setup_blk.call if @quaff_setup_blk
      @quaff_threads = @quaff_scenario_blocks.map { |blk| Thread.new &blk }
      retval = extra_validation
      verify_snmp_bono_latency if ENV['BONO_SNMP'] == "Y"
    ensure
      retval &= cleanup

      # If the test failed and we have retries set, recursively call run
      if !retval and @num_lives > @lives_used
        @lives_used += 1
        puts "WARNING - Test failed iteration #{@lives_used}, retrying"
        retval = self.run(deployment, transport, iteration)
      end

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

  def skip_unless_offnet_tel
    raise SkipThisTest.new "No off-net number given",
                           "Call with OFF_NET_TEL=<a number set up in ENUM/BGCF to route to port 5072 on this machine>" unless ENV['OFF_NET_TEL']
  end

  def skip_unless_ellis_api_key
    raise SkipThisTest.new "No Ellis API key given", "Call with ELLIS_API_KEY=<key>" unless ENV['ELLIS_API_KEY']
  end

  def skip_if_udp
    raise SkipThisTest.new "Test is not valid for UDP" if @transport == :udp
  end

  def skip_unless_live
    raise SkipThisTest.new "No live number given", "Call with LIVENUMBER=<number>" unless ENV['LIVENUMBER']
  end

  def skip_unless_gemini
    raise SkipThisTest.new "No gemini hostname provided", "Call with GEMINI=<hostname>" unless ENV['GEMINI']
  end

  def skip_unless_memento
    raise SkipThisTest.new "No memento hostnames provided", "Call with MEMENTO_SIP=<SIP hostname> and MEMENTO_HTTP=<HTTP hostname>" unless ENV['MEMENTO_SIP'] && ENV['MEMENTO_HTTP']
  end

  def skip_unless_call_diversion_as
    raise SkipThisTest.new "No Call Diversion AS hostname provided", "Call with CDIV_AS=<hostname>" unless ENV['CDIV_AS']
  end

  def skip_unless_nonce_count_supported
    raise SkipThisTest.new "No nonce-count support", "Call with NONCE_COUNT=true to run test" unless ENV['NONCE_COUNT']
  end

  private

  def before_run
  end

  def extra_validation
    return true
  end

  # Methods for provisioning/retrieving various types of users

  def provision_line
    EllisProvisionedLine.new(@deployment)
  end

  def provision_specific_line user_part
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

  def on_failure
    # If we failed any call scenario, dump out the log files.
    @endpoints.each do |e|
        log_file_name = File.join(File.dirname(__FILE__),
                                  "..",
                                  "logfiles",
                                  "#{@name.tr(' /','_')}_#{@transport.to_s.upcase}_#{@iteration}_#{e.sip_uri}.log")
        File.write(log_file_name, e.msg_log.join("\n\n================\n\n"))
      end
  end

  def cull_thread t, timeout, print_failed
    # Join the threads, this will do one of three things:
    #  - If the thread has finished successfully, return the thread handle
    #  - If the thread has finished abnormally, return the exception thrown,
    #    and also print out the backtrace
    #  - If the thread has not finished within the timeout, return nil
    result_of_join = begin
                       t.join(timeout)
                     rescue StandardError => e
                       e
                     end

    if result_of_join and (result_of_join != t)
      puts RedGreen::Color.red("Failed") if print_failed

      puts "Endpoint threw exception:"
      puts " - #{e.message}"
      e.backtrace.each { |b| puts "   - #{b}" }
    end

    return result_of_join
  end

  def cleanup
    retval = true

    # Poll the finished and non-finished threads one per second - this allows
    # us to exit the first time a thread throws an exception.
    (1..60).each do |second|
      finished_threads = @quaff_threads.select { |t| t.stop? }
      alive_threads = @quaff_threads.select { |t| t.alive? }

      finished_threads.each do |t|
        result_of_join = cull_thread(t, 0, retval)

        if result_of_join and (result_of_join != t)
          # If cull_thread doesn't return the thread handle, the thread has
          # exited abnormally. We know the test has failed in this case, so
          # stop the other threads now.
          puts "Terminating other threads after failure"
          other_threads = @quaff_threads.reject { |other_thread| other_thread == t }
          other_threads.each do |t|
            t.kill
            cull_thread(t, 60, false)
          end

          retval = false
          break
        end
      end

      all_threads_finished = @quaff_threads.select { |t| t.alive? }.empty?

      # End even though 60 seconds haven't passed
      break if all_threads_finished
      
      sleep 1
    end

    all_threads_finished = @quaff_threads.select { |t| t.alive? }.empty?

    unless all_threads_finished
      puts RedGreen::Color.red("Failed") if retval
      @quaff_threads.select { |t| t.alive? }.each do |t|
        puts "Endpoint had outstanding work to do, current backtrace:"
        t.backtrace.each { |b| puts "   - #{b}" }
        t.kill
      end
    end

    if @quaff_cleanup_blk
      begin
        @quaff_cleanup_blk.call
      rescue => exception
        puts "WARNING: Exception in quaff_cleanup_blk:\n - #{exception}"
      end
    end

    on_failure unless retval

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

  def verify_snmp_bono_latency
    latency_threshold = 250
    average_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.2.1"
    hwm_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.4.1"
    lwm_oid = SNMP::ObjectId.new "1.2.826.0.1.1578918.9.2.2.1.5.1"
    snmp_host = ENV['PROXY'] ? IPSocket.getaddress(ENV['PROXY']) : IPSocket.getaddress(@deployment)
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

end
