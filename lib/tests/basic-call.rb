# @file basic-call.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

# Converts a URI like sip:1234@example.com to tel:1234. Doesn't
# support parameters or non-numeric characters (e.g.
# "sip:+1234;npdi@example.com" won't work).
def sip_to_tel(uri)
  uri =~ /sip:(\d+)@.+/
  "tel:#{$1}"
end

TestDefinition.new("Basic Call - Mainline") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # We only send a plain text body in this INVITE, not full SDP. This reduces
    # the size of the SIP message (SDP is ~200 bytes) and increases the chance
    # that UDP messages will be small enough to get through the network without
    # fragmenting.
    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

end

TestDefinition.new("Basic Call - SDP") do |t|
  # The additional size of the SDP body pushes this over the UDP limit, so we
  # don't run it when the transport is UDP.
  t.skip_if_udp

  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

end

TestDefinition.new("Basic Call - Tel URIs") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do

    # This tests that for a subscriber like sip:1234@example.com, a
    # call to tel:1234 also reaches them. If this assumption is not
    # true (e.g. due to unusual ENUM rewriting), this test will fail.
    
    tel = sip_to_tel(callee.uri)
    call = caller.outgoing_call(tel)

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

end

TestDefinition.new("Basic Call - Unknown number") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Basic Call - Rejected by remote endpoint") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")

    call.recv_response("486")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("486", "Busy Here")
    call2.recv_request("ACK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Messages - Pager model") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Pracks") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain", "Supported" => "100rel"})
    call.recv_response("100")

    # For a PRACK, we create the dialog early, on the 180 response
    ringing_msg = call.recv_response_and_create_dialog("180")

    call.new_transaction
    call.send_request("PRACK", "", {"RAck" => "#{ringing_msg.header("RSeq")} #{ringing_msg.header("CSeq")}"})
    call.recv_response("200")

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    sleep 1
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    original_invite = call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing", "", nil, {"Require" => "100rel", "RSeq" => "1"})

    call2.recv_request("PRACK")
    call2.send_response("200", "OK")

    # Send this 200 in the original transaction, not the PRACK transaction
    call2.assoc_with_msg(original_invite)
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end
