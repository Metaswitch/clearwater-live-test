# @file isc-interface.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.
require 'quaff'

EXPECTED_EXPIRY = ENV['EXPIRES'] || "300"

TestDefinition.new("ISC Interface - Terminating") do |t|
  t.skip_unless_hostname

  caller = t.add_endpoint
  callee = t.add_endpoint
  as = t.add_as 5070

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  sdp = ""
  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]
  callee.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call.recv_response("100")

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 0.1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end


  t.add_quaff_scenario do
      incoming_call = as.incoming_call

      invite_data = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100", "Trying")

      incoming_call.send_response("200", "OK")

      # We expect an ACK and a BYE - protect against them being sent out-of-order
      bye_ack = incoming_call.recv_any_of ["ACK", "BYE"]
      if bye_ack.method == "ACK"
          incoming_call.recv_request("BYE")
          incoming_call.send_response("200", "OK")
      else
          incoming_call.send_response("200", "OK")
          incoming_call.recv_request("ACK")
      end
      incoming_call.end_call
  end
end

TestDefinition.new("ISC Interface - Terminating (UDP AS)") do |t|
  t.skip_if_udp
  t.skip_unless_hostname

  caller = t.add_endpoint
  callee = t.add_endpoint
  as = t.add_udp_as 5070

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  sdp = ""
  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=UDP"}]
  callee.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=UDP"}]

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call.recv_response("100")

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 0.1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end


  t.add_quaff_scenario do
      incoming_call = as.incoming_call

      invite_data = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100", "Trying")

      incoming_call.send_response("200", "OK")
      incoming_call.recv_request("ACK")

      incoming_call.recv_request("BYE")
      incoming_call.send_response("200", "OK")
      incoming_call.end_call
  end
end

TestDefinition.new("ISC Interface - Terminating Failed") do |t|
  t.skip_unless_hostname

  caller = t.add_endpoint
  callee = t.add_endpoint
  as = t.add_as 5070

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  sdp = ""
  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]
  callee.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call.recv_response("100")

    # Save off Contact and routeset
    call.recv_response("404")

    call.new_transaction
    call.send_request("ACK")
    call.end_call
  end


  t.add_quaff_scenario do
      incoming_call = as.incoming_call

      invite_data = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100", "Trying")

      incoming_call.send_response("404", "Not Found")
      incoming_call.recv_request("ACK")

      incoming_call.end_call
  end
end

def validate_expiry c, expected_expiry
      incoming_call = c.incoming_call

      register = incoming_call.recv_request("REGISTER")
      actual_expiry = register.header("Expires")
      fail "Expected Expires of #{expected_expiry}, got expires of #{actual_expiry}!" unless actual_expiry == expected_expiry
      incoming_call.end_call
end

TestDefinition.new("ISC Interface - Third-party Registration") do |t|
  t.skip_unless_hostname

  caller = t.add_endpoint
  as = t.add_as 5070

  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP", method: "REGISTER"}]

  t.add_quaff_scenario do
    caller.register
    validate_expiry as, EXPECTED_EXPIRY
    caller.unregister
    validate_expiry as, "0"
  end
end

TestDefinition.new("ISC Interface - Third-party Registration - implicit registration") do |t|
  t.skip_unless_hostname

  caller = t.add_endpoint
  ep2 = t.add_public_identity(caller)

  as1 = t.add_as 5070
  as2 = t.add_as 5071

  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP", method: "REGISTER"}]
  ep2.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5071;transport=TCP", method: "REGISTER"}]

  t.add_quaff_scenario do
    caller.register
    ep2.register
    ep2.unregister
    caller.unregister
  end

  t.add_quaff_scenario do
    validate_expiry as1, EXPECTED_EXPIRY
    validate_expiry as1, "0"
  end

  # Set up a second AS on port 5071, to ensure that iFCs for the second public identity are handled independently
  t.add_quaff_scenario do
    validate_expiry as2, EXPECTED_EXPIRY
    validate_expiry as2, "0"
  end
end

TestDefinition.new("ISC Interface - Redirect") do |t|
  t.skip_unless_hostname
  t.skip_if_udp

  caller = t.add_endpoint
  callee = t.add_endpoint
  callee2 = t.add_endpoint

  as = t.add_as 5070

  callee.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]

  t.add_quaff_setup do
    caller.register
    callee.register
    callee2.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    callee2.unregister
  end

  sdp = ""

  # Caller scenario - call, receive a 302, start a new call
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call.recv_response("100")

    redirect = call.recv_response("302")
    call.send_request("ACK")
    call.end_call

    call2 = caller.outgoing_call(redirect.header("Contact").gsub(/[<>]/, ""))
    call2.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call2.recv_response("100")
    call2.recv_response("180")

    # Save off Contact and routeset
    call2.recv_response_and_create_dialog("200")

    call2.new_transaction
    call2.send_request("ACK")
    sleep 0.1

    call2.new_transaction
    call2.send_request("BYE")
    call2.recv_response("200")
    call2.end_call
  end

  # AS scenario - receive INVITE, send 302
  t.add_quaff_scenario do
    incoming_call = as.incoming_call

    incoming_call.recv_request("INVITE")
    incoming_call.send_response("302", "Moved Temporarily", "", nil, {"Contact" => callee2.uri})
    incoming_call.recv_request("ACK")

    incoming_call.end_call
  end

  # Redirected callee scenario - receive INVITE, answer it
  t.add_quaff_scenario do
      incoming_call = callee2.incoming_call

      invite_data = incoming_call.recv_request("INVITE")

      incoming_call.send_response("180", "Ringing")
      incoming_call.send_response("200", "OK")
      incoming_call.recv_request("ACK")

      incoming_call.recv_request("BYE")
      incoming_call.send_response("200", "OK")

      incoming_call.end_call
  end
end

TestDefinition.new("ISC Interface - B2BUA") do |t|
  t.skip_unless_hostname
  t.skip_if_udp

  caller = t.add_endpoint
  callee = t.add_endpoint
  callee2 = t.add_endpoint

  as = t.add_as 5070

  callee.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"}]

  t.add_quaff_setup do
    caller.register
    callee.register
    callee2.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    callee2.unregister
  end

  sdp = ""

  t.add_quaff_scenario do
    incoming_call = as.incoming_call

    # Receive an incoming INVITE
    invite_data = incoming_call.recv_request("INVITE")
    incoming_call.send_response("100", "Trying")

    sprout_outbound = Quaff::TCPSource.new invite_data.source.ip, 5052

    # Send a new call back to Sprout - send it to a different callee
    # to avoid looping (we could also set a specific header here and
    # in the iFC)
    outgoing_call = as.outgoing_call(callee2.uri)
    outgoing_call.setdest(sprout_outbound, recv_from_this: true)

    outgoing_call.send_request("INVITE", "", {"From" => invite_data['message'].header("From")})
    outgoing_call.recv_response("100")

    # Get the 180 and pass it back
    outgoing_call.recv_response("180")
    incoming_call.send_response("180", "Ringing")

    # Get the 200 OK, ACK it, and pass it back
    outgoing_call.recv_response_and_create_dialog("200")
    outgoing_call.new_transaction
    outgoing_call.send_request("ACK")

    incoming_call.send_response("200", "OK")

    # We expect an ACK and a BYE - protect against them being sent out-of-order
    bye_ack = incoming_call.recv_any_of ["ACK", "BYE"]
    if bye_ack.method == "ACK"
        incoming_call.recv_request("BYE")
        incoming_call.send_response("200", "OK")
    else
        incoming_call.send_response("200", "OK")
        incoming_call.recv_request("ACK")
    end

    # Get the BYE, OK it, and pass it back
    incoming_call.send_response("200", "OK")

    outgoing_call.new_transaction
    outgoing_call.send_request("BYE")
    outgoing_call.recv_response("200")

    incoming_call.end_call
    outgoing_call.end_call
  end

  # Caller scenario
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", sdp, {"Content-Type" => "application/sdp"})
    call.recv_response("100")

    call.recv_response("180")

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 0.1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  # Callee scenario - receive INVITE from B2BUA, answer it
  t.add_quaff_scenario do
      incoming_call = callee2.incoming_call

      invite_data = incoming_call.recv_request("INVITE")

      incoming_call.send_response("180", "Ringing")
      incoming_call.send_response("200", "OK")
      incoming_call.recv_request("ACK")

      incoming_call.recv_request("BYE")
      incoming_call.send_response("200", "OK")

      incoming_call.end_call
  end
end
