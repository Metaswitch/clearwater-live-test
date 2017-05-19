# @file cancel.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'barrier'

TestDefinition.new("CANCEL - Mainline") do |t|
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
    call.recv_response("180")

    # New transaction, but CANCELs share the original branch parameter
    call.send_request("CANCEL")
    call.recv_response("200")

    call.recv_response("487")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    original_invite = call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")

    call2.recv_request("CANCEL")
    call2.send_response("200", "OK")

    # Use assoc_with_msg to make the CSeq of the 487 follow the INVITE, not the CANCEL
    call2.assoc_with_msg(original_invite)

    call2.send_response("487", "Cancelled")
    call2.recv_request("ACK")

    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end
