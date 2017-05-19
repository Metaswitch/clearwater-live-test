# @file call-waiting.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'barrier'

TestDefinition.new("Call Waiting - Accepted") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  interruptor = t.add_endpoint

  first_call_ringing_barrier = Barrier.new(2)
  first_call_set_up_barrier = Barrier.new(3)

  second_call_ringing_barrier = Barrier.new(2)
  second_call_set_up_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
    interruptor.register
  end

  t.add_quaff_scenario do
    # A calls B - this is just an ordinary call from A's
    # point of view
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    first_call_ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    first_call_set_up_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    # B receives call from A
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    first_call_ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")
    first_call_set_up_barrier.wait
    # B's call from A is now set up

    # B receives a call from C and sends a 180 with an Alert-Info
    # header indicating that we're doing call waiting
    call3 = callee.incoming_call
    call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing", "", false, {"Alert-Info" => "<urn:alert:service:call-waiting>"})
    second_call_ringing_barrier.wait

    # A hangs up
    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call

    # We can now answer the call from C
    call3.send_200_with_sdp
    call3.recv_request("ACK")
    second_call_set_up_barrier.wait

    call3.recv_request("BYE")
    call3.send_response("200", "OK")
    call3.end_call
  end

  t.add_quaff_scenario do
    # C calls A. This is an ordinary call, just with an extra
    # Alert-Info header.

    first_call_set_up_barrier.wait
    call = interruptor.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    ringing_resp = call.recv_response("180")
    second_call_ringing_barrier.wait

    # check for call waiting on 180
    fail "Alert-Info was not passed through properly" unless ringing_resp.first_header('Alert-Info') == "<urn:alert:service:call-waiting>"

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    second_call_set_up_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    interruptor.unregister
  end
end

TestDefinition.new("Call Waiting - Cancelled") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  interruptor = t.add_endpoint

  first_call_ringing_barrier = Barrier.new(2)
  first_call_set_up_barrier = Barrier.new(3)

  t.add_quaff_setup do
    caller.register
    callee.register
    interruptor.register
  end

  t.add_quaff_scenario do
    # A calls B - this is just an ordinary call from A's
    # point of view
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    first_call_ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    first_call_set_up_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    # B receives call from A
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    first_call_ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")
    first_call_set_up_barrier.wait
    # B's call from A is now set up

    # B receives a new call from C and responds with a 180 indicating
    # call waiting
    call3 = callee.incoming_call
    original_invite = call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing", "", false, {"Alert-Info" => "<urn:alert:service:call-waiting>"})

    # C cancels its invite
    call3.recv_request("CANCEL")
    call3.send_response("200", "OK")

    call3.assoc_with_msg(original_invite)
    call3.send_response("487", "Cancelled")
    call3.recv_request("ACK")
    call3.end_call

    # A now ends the other call
    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    # C calls A
    first_call_set_up_barrier.wait
    call = interruptor.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")

    # C gets a call waiting indication
    ringing_resp = call.recv_response("180")

    fail "Alert-Info was not passed through properly" unless ringing_resp.first_header('Alert-Info') == "<urn:alert:service:call-waiting>"

    # C cancels the call
    call.send_request("CANCEL")
    call.recv_response("200")

    call.recv_response("487")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    interruptor.unregister
  end
end
