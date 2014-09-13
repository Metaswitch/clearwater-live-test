# @file isc-interface.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2013  Metaswitch Networks Ltd
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

EXPECTED_EXPIRY = ENV['EXPIRES'] || "300"

ASTestDefinition.new("ISC Interface - Terminating") do |t|
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
      incoming_call.recv_request("ACK")

      incoming_call.recv_request("BYE")
      incoming_call.send_response("200", "OK")
      incoming_call.end_call
  end
end

NotValidForUDPASTestDefinition.new("ISC Interface - Terminating (UDP AS)") do |t|
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

ASTestDefinition.new("ISC Interface - Terminating Failed") do |t|
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

ASTestDefinition.new("ISC Interface - Third-party Registration") do |t|
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

ASTestDefinition.new("ISC Interface - Third-party Registration - implicit registration") do |t|
  caller = t.add_endpoint
  ep2 = t.add_quaff_public_identity(caller)

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

NotValidForUDPASTestDefinition.new("ISC Interface - Redirect") do |t|
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

NotValidForUDPASTestDefinition.new("ISC Interface - B2BUA") do |t|
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

    sprout_outbound = Quaff::TCPSource.new invite_data.source.remote_ip, 5052

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
    incoming_call.recv_any_of ["ACK", "BYE"]
    incoming_call.recv_any_of ["ACK", "BYE"]

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
