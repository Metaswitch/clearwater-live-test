# @file call-barring.rb
#
# Copyright (C) Metaswitch Networks 2014
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

TestDefinition.new("Call Barring - Outbound Rejection") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee = t.add_endpoint
  caller.set_simservs ocb: { active: true,
                             rules: [ { conditions: [],
                                        allow: false } ]
                            }

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("603")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Call Barring - Allow non-international call") do |t|
  t.skip_unless_mmtel
  t.skip_unless_pstn

  caller = t.add_pstn_endpoint
  callee = t.add_endpoint
  caller.set_simservs ocb: { active: true,
                                 rules: [ { conditions: ["international"],
                                            allow: false } ]
                               }

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.sip_uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("180")

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
    call2.send_response("200", "OK")
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

TestDefinition.new("Call Barring - Reject international call") do |t|
  t.skip_unless_mmtel
  t.skip_unless_pstn

  caller = t.add_pstn_endpoint
  callee = t.add_fake_endpoint("011447854481549")
  caller.set_simservs ocb: { active: true,
                             rules: [ { conditions: ["international"],
                                        allow: false } ]
                            }
  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.sip_uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("603")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Call Barring - Inbound Rejection") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee = t.add_endpoint
  callee.set_simservs icb: { active: true,
                             rules: [ { conditions: [],
                                        allow: false } ]
                            }

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("603")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

