# @file gemini.rb
#
# Copyright (C) Metaswitch Networks 2015
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.
require 'barrier'

GEMINI_MT_SIP_URI="mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP"
TWIN_PREFIX=";twin-prefix=123"
TERM_REG = 1

EXPECTED_MOBILE_ACCEPT_CONTACT = "*;+g.3gpp.ics=\"server,principal\";explicit;require"

# Test INVITE where the VoIP device answers so the mobile device
# receives a CANCEL
TestDefinition.new("Gemini - INVITE - VoIP device answers") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  ringing_barrier = Barrier.new(3)
  end_call_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    end_call_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")

    # Wait before the VoIP device accepts the call
    ringing_barrier.wait
    call_voip.send_200_with_sdp
    call_voip.recv_request("ACK")

    end_call_barrier.wait
    call_voip.recv_request("BYE")
    call_voip.send_response("200", "OK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    ringing_barrier.wait

    call_mobile.recv_request("CANCEL")
    call_mobile.send_response("200", "OK")

    call_mobile.assoc_with_msg(invite)
    call_mobile.send_response("487", "Request Terminated")
    call_mobile.recv_request("ACK")

    call_mobile.end_call
  end
end

# Test INVITE where the mobile device accepts the call so the VoIP
# device receives a CANCEL
TestDefinition.new("Gemini - INVITE - Mobile device answers") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  ringing_barrier = Barrier.new(3)
  end_call_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']

    ringing_barrier.wait
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    end_call_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    ringing_barrier.wait

    call_voip.recv_request("CANCEL")
    call_voip.send_response("200", "OK")

    call_voip.assoc_with_msg(invite)
    call_voip.send_response("487", "Request Terminated")
    call_voip.recv_request("ACK")

    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")

    # Wait before the mobile device accepts the call
    ringing_barrier.wait
    call_mobile.send_200_with_sdp
    call_mobile.recv_request("ACK")

    end_call_barrier.wait
    call_mobile.recv_request("BYE")
    call_mobile.send_response("200", "OK")
    call_mobile.end_call
  end
end

# Test INVITE where the VoIP device rejects the call and the mobile
# device accepts it
TestDefinition.new("Gemini - INVITE - VoIP device rejects") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  ringing_barrier = Barrier.new(3)
  end_call_barrier = Barrier.new(2)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    # Make the INVITE, and receive 100/180 from each fork
    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait

    # Mobile device accepts call
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    end_call_barrier.wait
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("408", "Request Timeout")
    call_voip.recv_request("ACK")
    ringing_barrier.wait
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")

    # Wait to make sure the VoIP device rejects the call before the mobile device
    # accepts the call
    ringing_barrier.wait
    call_mobile.send_200_with_sdp
    call_mobile.recv_request("ACK")

    end_call_barrier.wait
    call_mobile.recv_request("BYE")
    call_mobile.send_response("200", "OK")
    call_mobile.end_call
  end
end

# Test INVITE where the mobile device rejects the call and the VoIP
# device accepts it
TestDefinition.new("Gemini - INVITE - Mobile device rejects") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  ringing_barrier = Barrier.new(3)
  end_call_barrier = Barrier.new(2)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    end_call_barrier.wait
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")

    # Wait to make sure the mobile device rejects the call before the VoIP device
    # accepts the call
    ringing_barrier.wait
    call_voip.send_200_with_sdp
    call_voip.recv_request("ACK")

    end_call_barrier.wait
    call_voip.recv_request("BYE")
    call_voip.send_response("200", "OK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("408", "Request Timeout")
    call_mobile.recv_request("ACK")
    ringing_barrier.wait
    call_mobile.end_call
  end
end

# Test INVITE where the mobile device rejects the call with a 480.
TestDefinition.new("Gemini - INVITE - Mobile device rejects with a 480") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_voip_phone = t.add_new_binding callee_voip

  ringing_barrier = Barrier.new(3)
  end_call_barrier = Barrier.new(2)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  t.add_quaff_setup do
    caller.register
    callee_voip.register

    callee_voip_phone.add_contact_param "+sip.with-twin", true
    ok = callee_voip_phone.register
    fail "200 OK Contact header did not contain 2 bindings" unless ok.headers["Contact"].length == 2

    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_voip_phone.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    end_call_barrier.wait
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("480", "Temporarily Unavailable")
    call_voip.recv_request("ACK")
    ringing_barrier.wait

    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_voip_phone = callee_voip_phone.incoming_call

    invite_phone = call_voip_phone.recv_request("INVITE")
    fail "Call for VoIP device does not include the Accept-Contact header" unless invite_phone.all_headers("Accept-Contact").include? "*;+sip.with-twin;explicit;require"

    call_voip_phone.send_response("100", "Trying")
    call_voip_phone.send_response("180", "Ringing")
    call_voip_phone.send_200_with_sdp
    call_voip_phone.recv_request("ACK")

    end_call_barrier.wait
    call_voip_phone.recv_request("BYE")
    call_voip_phone.send_response("200", "OK")

    call_voip_phone.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    ringing_barrier.wait
    call_mobile.send_response("480", "Temporarily Unavailable")
    call_mobile.recv_request("ACK")
    call_mobile.end_call
  end
end

# Test INVITE where both devices reject the call, and the mobile device has the
# best response
TestDefinition.new("Gemini - INVITE - Both reject, choose mobile response") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  ringing_barrier = Barrier.new(3)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait

    call.recv_response("500")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    ringing_barrier.wait

    call_voip.send_response("408", "Request Timeout")
    call_voip.recv_request("ACK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    ringing_barrier.wait

    call_mobile.send_response("500", "Server Error")
    call_mobile.recv_request("ACK")
    call_mobile.end_call
  end
end

# Test INVITE where both devices reject the call, and the VoIP device has the
# best response
TestDefinition.new("Gemini - INVITE - Both reject, choose VoIP response") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  ringing_barrier = Barrier.new(3)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier.wait

    call.recv_response("487")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    ringing_barrier.wait

    call_voip.send_response("487", "A better response than a 408")
    call_voip.recv_request("ACK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for native device does not include the Accept-Contact header" unless invite.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    ringing_barrier.wait

    call_mobile.send_response("408", "Request Timeout")
    call_mobile.recv_request("ACK")
    call_mobile.end_call
  end
end

# Test successful call to single VoIP client
TestDefinition.new("Gemini - INVITE - Successful call with GR") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "INVITE"}]

  ringing_barrier = Barrier.new(2)
  end_call_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.expected_pub_gruu)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    end_call_barrier.wait
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device has a Reject-Contact header" unless invite.headers["Reject-Contact"] == nil
    fail "Call for VoIP device has an Accept-Contact header" unless invite.headers["Accept-Contact"] == nil

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    ringing_barrier.wait

    call_voip.send_200_with_sdp
    call_voip.recv_request("ACK")

    end_call_barrier.wait
    call_voip.recv_request("BYE")
    call_voip.send_response("200", "OK")
    call_voip.end_call

    fail "Call was incorrectly forked to both endpoints" unless callee_mobile.no_new_calls?
  end
end

# Test failed call to single VoIP client
TestDefinition.new("Gemini - INVITE - Failed call with GR") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  ringing_barrier = Barrier.new(2)

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "INVITE"}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.expected_pub_gruu)

    call.send_invite_with_sdp

    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    call.recv_response("486")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device has a Reject-Contact header" unless invite.headers["Reject-Contact"] == nil
    fail "Call for VoIP device has an Accept-Contact header" unless invite.headers["Accept-Contact"] == nil

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    ringing_barrier.wait

    call_voip.send_response("486", "Busy Here")
    call_voip.recv_request("ACK")
    call_voip.end_call

    fail "Call was incorrectly forked to both endpoints" unless callee_mobile.no_new_calls?
  end
end

# Test a successful call with an Accept-Contact header
TestDefinition.new("Gemini - INVITE - Successful call with Accept-Contact") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "INVITE"}]

  ringing_barrier = Barrier.new(2)
  end_call_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE", "", {"Accept-Contact" => "*;+g.3gpp.ics=\"server,principal\""})

    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")

    end_call_barrier.wait
    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for VoIP device has a Reject-Contact header" unless invite.headers["Reject-Contact"] == nil

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    ringing_barrier.wait

    call_mobile.send_200_with_sdp
    call_mobile.recv_request("ACK")

    end_call_barrier.wait
    call_mobile.recv_request("BYE")
    call_mobile.send_response("200", "OK")
    call_mobile.end_call

    fail "Call was incorrectly forked to both endpoints" unless callee_voip.no_new_calls?
  end
end

# Test a failed call with an Accept-Contact header
TestDefinition.new("Gemini - INVITE - Failed call with Accept-Contact") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "INVITE"}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE", "", {"Accept-Contact" => "*;+g.3gpp.ics=\"server,principal\""})
    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("486")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")
    fail "Call for VoIP device has a Reject-Contact header" unless invite.headers["Reject-Contact"] == nil

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("486", "Busy Here")
    call_mobile.recv_request("ACK")
    call_mobile.end_call

    fail "Call was incorrectly forked to both endpoints" unless callee_voip.no_new_calls?
  end
end

# Test SUBSCRIBE that forks to both devices, mobile device responds
TestDefinition.new("Gemini - SUBSCRIBE - Mobile Notifies") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "SUBSCRIBE"}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  # Quaff doesn't cope well with messages crossing so we use a barrier to make sure the SUBSCRIBE-200 and NOTIFY
  # do not get re-ordered.
  subscribe_complete_barrier = Barrier.new(2)

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("SUBSCRIBE", "", {"Event" => "arbitrary"})
    call.recv_response("200", "OK")
    subscribe_complete_barrier.wait

    call.recv_request("NOTIFY")
    call.send_response("200", "OK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    subscribe = call_voip.recv_request("SUBSCRIBE")
    fail "Subscribe for VoIP device has an Accept-Contact header" unless subscribe.headers["Accept-Contact"] == nil
    fail "Subscribe for VoIP device does not include the Reject-Contact header" unless subscribe.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("500", "Server Error")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    subscribe = call_mobile.recv_request("SUBSCRIBE")
    fail "Subscribe for native device does not include the Accept-Contact header" unless subscribe.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT
    fail "Subscribe for native device does not include the Reject-Contact header" unless subscribe.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_mobile.send_response("200", "OK")
    subscribe_complete_barrier.wait

    call_mobile.new_transaction
    call_mobile.send_request("NOTIFY")
    call_mobile.recv_response("200")
    call_mobile.end_call
  end
end

# Test SUBSCRIBE where both endpoints return 408
TestDefinition.new("Gemini - SUBSCRIBE - Joint 408") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id
  callee_mobile.add_contact_param '+g.3gpp.ics', "\"server,principal\""

  # Set iFCs.
  callee_voip.set_ifc [{server_name: GEMINI_MT_SIP_URI + TWIN_PREFIX, session_case: TERM_REG, method: "SUBSCRIBE"}]

  t.add_quaff_setup do
    caller.register
    callee_voip.register
    callee_mobile.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_voip.unregister
    callee_mobile.unregister
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("SUBSCRIBE", "", {"Event" => "arbitrary"})
    call.recv_response("408")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    subscribe = call_voip.recv_request("SUBSCRIBE")
    fail "Subscribe for VoIP device has an Accept-Contact header" unless subscribe.headers["Accept-Contact"] == nil
    fail "Subscribe for VoIP device does not include the Reject-Contact header" unless subscribe.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_voip.send_response("408", "Request Timeout")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    subscribe = call_mobile.recv_request("SUBSCRIBE")
    fail "Subscribe for native device does not include the Accept-Contact header" unless subscribe.all_headers("Accept-Contact").include? EXPECTED_MOBILE_ACCEPT_CONTACT
    fail "Subscribe for native device does not include the Reject-Contact header" unless subscribe.all_headers("Reject-Contact").include? "*;+sip.with-twin"

    call_mobile.send_response("408", "Request Timeout")
    call_mobile.end_call
  end
end

