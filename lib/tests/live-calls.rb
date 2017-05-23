# @file live-calls.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

SIPpTestDefinition.new("Live Call - Dial out to a real number") do |t|
  t.skip_unless_live
  t.skip_unless_pstn

  # The live call takes approximately 10 seconds to run so extend the timeout
  # for this test.
  t.timeout = 20

  sip_caller = t.add_pstn_sipp_endpoint
  live_callee = t.add_fake_endpoint(ENV['LIVENUMBER'])

  t.set_scenario(
    sip_caller.register +
    [
      sip_caller.send("INVITE", target: live_callee),
      # Live tests need long timeouts, since the PSTN adds latency and the callee needs to actually pick up.
      sip_caller.recv("100", timeout: 20000),
      sip_caller.recv("183", optional: true, timeout: 20000),
      sip_caller.recv("180", optional: true, timeout: 20000),
      sip_caller.recv("200", timeout: 20000, rrs: true),
      sip_caller.send("ACK", target: live_callee, in_dialog: true),
      sip_caller.play("g711a.pcap", 8000),
      sip_caller.send("BYE", target: live_callee, in_dialog: true),
      sip_caller.recv("200", timeout: 20000),
    ] +
    sip_caller.unregister
  )
end
