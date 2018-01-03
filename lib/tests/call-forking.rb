# @file call-forking.rb
#
# Copyright (C) Metaswitch Networks 2018
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.


# Tests that a call made to a user with 2 bindings is forked correctly
TestDefinition.new("Call Forking - Mainline") do |t|
  caller = t.add_endpoint
  callee_binding1 = t.add_endpoint
  callee_binding2 = t.add_new_binding callee_binding1

  ringing_barrier = Barrier.new(3)
  answered_barrier = Barrier.new(3)

  t.add_quaff_setup do
    caller.register
    callee_binding1.register
    callee_binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_binding1.uri)

    # We only send a plain text body in this INVITE, not full SDP
    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")

    # We expect to get one or two 180 responses, depending on whether the P-CSCF
    # acts as a B2BUA or proxy
    call.recv_response("180")

    if ENV['PCSCF'] == "PROXY"
      call.recv_response("180")
    end

    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    answered_barrier.wait()
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee_binding1.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    # This binding answers the call
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")
    answered_barrier.wait()

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    call3 = callee_binding2.incoming_call

    original_invite = call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing")
    ringing_barrier.wait

    # The call is cancelled as the other binding picks up
    call3.recv_request("CANCEL")
    call3.send_response("200", "OK")

    # assoc_with_msg ensures the CSeq of the 487 follows the INVITE
    call3.assoc_with_msg(original_invite)
    call3.send_response("487", "Request Terminated")
    call3.recv_request("ACK")
    call3.end_call

    # Allow the rest of the test to proceed
    answered_barrier.wait()

  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_binding1.unregister
    callee_binding2.unregister
  end

end

# Tests that if one of two bindings is unresponsive, a call can still succeed to
# the remaining binding
TestDefinition.new("Call Forking - Endpoint offline") do |t|
  caller = t.add_endpoint
  callee_binding1 = t.add_endpoint
  callee_binding2 = t.add_new_binding callee_binding1

  ringing_barrier = Barrier.new(2)
  answered_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_binding1.register
    callee_binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_binding1.uri)

    # We only send a plain text body in this INVITE, not full SDP
    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")

    # We expect only one 180 response, as only one binding responds to the caller
    call.recv_response("180")

    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    answered_barrier.wait()
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee_binding1.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    # This binding answers the call
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")
    answered_barrier.wait()

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    call3 = callee_binding2.incoming_call

    # Check that this binding receives the INVITE, but don't respond
    call3.recv_request("INVITE")

  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_binding1.unregister
    callee_binding2.unregister
  end

end

# Tests that if one of two bindings becomes unresponsive while in the ringing
# state, a call can still succeed to the other binding
TestDefinition.new("Call Forking - Endpoint offline while ringing") do |t|
  caller = t.add_endpoint
  callee_binding1 = t.add_endpoint
  callee_binding2 = t.add_new_binding callee_binding1

  ringing_barrier = Barrier.new(3)
  answered_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_binding1.register
    callee_binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_binding1.uri)

    # We only send a plain text body in this INVITE, not full SDP
    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")

    # We expect to get one or two 180 responses, depending on whether the P-CSCF
    # acts as a B2BUA or proxy
    call.recv_response("180")

    if ENV['PCSCF'] == "PROXY"
      call.recv_response("180")
    end

    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    answered_barrier.wait()
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee_binding1.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    # This binding answers the call
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")
    answered_barrier.wait()

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    call3 = callee_binding2.incoming_call

    # Check that this binding receives the INVITE, gets to the Ringing state and
    # then stops responding
    call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing")
    ringing_barrier.wait

  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_binding1.unregister
    callee_binding2.unregister
  end

end
