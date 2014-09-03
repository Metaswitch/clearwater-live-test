# @file gemini.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2014  Metaswitch Networks Ltd
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version, along with the "Special Exception" for use of
# the program along with SSL, set forth below. This program is distributed
# in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details. You should have received a copy of the GNU General Public
# License along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
#
# The author can be reached by email at clearwater@metaswitch.com or by
# post at Metaswitch Networks Ltd, 100 Church St, Enfield EN2 6BQ, UK
#
# Special Exception
# Metaswitch Networks Ltd  grants you permission to copy, modify,
# propagate, and distribute a work formed by combining OpenSSL with The
# Software, or a work derivative of such a combination, even if such
# copying, modification, propagation, or distribution would otherwise
# violate the terms of the GPL. You must comply with the GPL in all
# respects for all of the code used other than OpenSSL.
# "OpenSSL" means OpenSSL toolkit software distributed by the OpenSSL
# Project and licensed under the OpenSSL Licenses, or a work based on such
# software and licensed under the OpenSSL Licenses.
# "OpenSSL Licenses" means the OpenSSL License and Original SSLeay License
# under which the OpenSSL Project distributes the OpenSSL toolkit software,
# as those licenses appear in the file LICENSE-OPENSSL.
require 'quaff'

# Test INVITE with a missing twin-prefix
TestDefinition.new("Gemini - INVITE - Missing twin prefix") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.register
  end

  # Set iFCs
  callee.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP", session_case: "1"

  # Make a call. Gemini will reject the call with a 480
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call
  end
end

# Test INVITE where the VoIP device answers so the mobile device
# receives a CANCEL
TestDefinition.new("Gemini - INVITE - VoIP device answers") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id

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

  # Set iFCs.
  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

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
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")

    # Wait before the VoIP device accepts the call
    sleep 0.3

    call_voip.send_response("180", "Ringing")
    call_voip.send_response("200", "OK")
    call_voip.recv_request("ACK")

    call_voip.recv_request("BYE")
    call_voip.send_response("200", "OK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")

    call_mobile.recv_request("CANCEL")
    call_mobile.assoc_with_msg(invite)
    call_mobile.send_response("487", "Request Terminated")

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

  # Set iFCs
  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

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
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")

    call_voip.recv_request("CANCEL")
    call_voip.assoc_with_msg(invite)
    call_voip.send_response("487", "Request Terminated")

    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    call_mobile.recv_request("INVITE")
    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")

    # Wait before the mobile device accepts the call
    sleep 0.3

    call_mobile.send_response("200", "OK")
    call_mobile.recv_request("ACK")

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

  # Set iFCs
  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    # Make the INVITE, and receive 100/180 from each forl
    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

    # Mobile device accepts call
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
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("408", "Request Timeout")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")

    # Wait to make sure the VoIP device rejects the call before the mobile device
    # accepts the call
    sleep 0.3

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("200", "OK")
    call_mobile.recv_request("ACK")

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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

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
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    # Wait to make sure the mobile device rejects the call before the VoIP device
    # accepts the call
    sleep 0.3

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("200", "OK")
    call_voip.recv_request("ACK")

    call_voip.recv_request("BYE")
    call_voip.send_response("200", "OK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call
    call_mobile.recv_request("INVITE")
    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("408", "Request Timeout")
    call_mobile.recv_request("ACK")
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

  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id

  t.add_quaff_setup do
    caller.register
    callee_voip.register

    callee_voip_phone.contact_header += ";+sip.phone"
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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")
    call.recv_response("180")

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
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("480", "Temporarily Unavailable")
    call_voip.recv_request("ACK")

    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_voip_phone = callee_voip_phone.incoming_call

    invite_phone = call_voip_phone.recv_request("INVITE")
    fail "Call for VoIP device does not include the Accept-Contact header" unless invite_phone.all_headers("Accept-Contact").include? "*;+sip.phone;explicit;require"

    call_voip_phone.send_response("100", "Trying")
    call_voip_phone.send_response("180", "Ringing")

    call_voip_phone.send_response("200", "OK")

    call_voip_phone.recv_request("ACK")
    call_voip_phone.recv_request("BYE")
    call_voip_phone.send_response("200", "OK")

    call_voip_phone.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    invite = call_mobile.recv_request("INVITE")

    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("480", "Temporarily Unavailable")
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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

    call.recv_response("500")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("408", "Request Timeout")
    call_voip.recv_request("ACK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    call_mobile.recv_request("INVITE")
    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("INVITE")

    call.recv_response("100")
    call.recv_response("180")
    call.recv_response("180")

    call.recv_response("487")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    invite = call_voip.recv_request("INVITE")
    fail "Call for VoIP device does not include the Reject-Contact header" unless invite.all_headers("Reject-Contact").include? "*;+sip.phone"

    call_voip.send_response("100", "Trying")
    call_voip.send_response("180", "Ringing")
    call_voip.send_response("487", "")
    call_voip.recv_request("ACK")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    call_mobile.recv_request("INVITE")
    call_mobile.send_response("100", "Trying")
    call_mobile.send_response("180", "Ringing")
    call_mobile.send_response("408", "Request Timeout")
    call_mobile.recv_request("ACK")
    call_mobile.end_call
  end
end

# Test SUBSCRIBE with missing twin prefix
TestDefinition.new("Gemini - SUBSCRIBE - Missing twin prefix") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  callee.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP", session_case: "1", method: "SUBSCRIBE"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("SUBSCRIBE")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call
  end
end

# Test SUBSCRIBE with correct twin-prefix
TestDefinition.new("Gemini - SUBSCRIBE - Mobile Notifies") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id

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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1", method: "SUBSCRIBE"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("SUBSCRIBE")
    call.recv_response_and_create_dialog("200")
    call.recv_request("NOTIFY")
    call.send_response("200", "OK")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    call_voip.recv_request("SUBSCRIBE")
    call_voip.send_response("500", "Server Error")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    call_mobile.recv_request("SUBSCRIBE")
    call_mobile.send_response("200", "OK")
    call_mobile.send_request("NOTIFY")
    call_mobile.recv_response("200")
    call_mobile.end_call
  end
end

# Test SUBSCRIBE with correct twin-prefix
TestDefinition.new("Gemini - SUBSCRIBE - Joint 408") do |t|
  t.skip_unless_gemini
  t.skip_unless_ellis_api_key

  caller = t.add_endpoint
  callee_voip = t.add_endpoint
  callee_mobile_id = "123" + callee_voip.username
  callee_mobile = t.add_specific_endpoint callee_mobile_id

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

  callee_voip.set_ifc server_name: "mobile-twinned@#{ENV['GEMINI']}:5054;transport=TCP;twin-prefix=123", session_case: "1", method: "SUBSCRIBE"

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_voip.uri)

    call.send_request("SUBSCRIBE")
    call.recv_response("408")
    call.end_call
  end

  t.add_quaff_scenario do
    call_voip = callee_voip.incoming_call

    call_voip.recv_request("SUBSCRIBE")
    call_voip.send_response("408", "Request Timeout")
    call_voip.end_call
  end

  t.add_quaff_scenario do
    call_mobile = callee_mobile.incoming_call

    call_mobile.recv_request("SUBSCRIBE")
    call_mobile.send_response("408", "Request Timeout")
    call_mobile.end_call
  end
end
