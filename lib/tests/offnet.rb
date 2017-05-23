# @file offnet.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.


TestDefinition.new("Off-net calls - tel: URI") do |t|
  t.skip_unless_offnet_tel

  caller = t.add_endpoint
  as = t.add_as 5072


  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call("tel:#{ENV['OFF_NET_TEL']}")

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = as.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Off-net calls - sip: URI") do |t|
  t.skip_unless_offnet_tel

  caller = t.add_endpoint
  as = t.add_as 5072


  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call("sip:#{ENV['OFF_NET_TEL']}@#{t.deployment};user=phone")

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = as.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

