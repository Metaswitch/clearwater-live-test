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
require_relative '../../quaff/quaff.rb'

EXPECTED_EXPIRY = ENV['EXPIRES'] || "300"

ASTestDefinition.new("ISC Interface - Terminating") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint

  sip_caller.set_ifc server_name: "#{ENV['HOSTNAME']}:5070"
  sip_callee.set_ifc server_name: "#{ENV['HOSTNAME']}:5070"

  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5070)
    begin
      incoming_cid = c.get_new_call_id
      incoming_call = Call.new(c, incoming_cid)

      invite_data = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100 Trying")
      incoming_call.send_response("200 OK")

      # This is received from Bono, so our sending destination automatically switches
      ack_data = incoming_call.recv_request("ACK")
      fail "Expecting INVITE from Sprout and ACK from Bono!" unless invite_data['source'].sock != ack_data['source'].sock

      bye_data = incoming_call.recv_request("BYE")
      fail "Expecting ACK and BYE to both come from Bono!" unless bye_data['source'].sock == ack_data['source'].sock

      incoming_call.send_response("200 OK", nil, {"CSeq" => "4 BYE"})
      sleep 2 # Ensure that the 200 OK is sent to Bono before the socket is closed
      incoming_call.end_call
    ensure
      c.terminate
    end
  end

  t.set_scenario(
    sip_caller.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee, in_dialog: true, method: "INVITE"),
      sip_caller.send("BYE", target: sip_callee, in_dialog: true),
      sip_caller.recv("200"),
    ] +
    sip_caller.unregister
  )
end

ASTestDefinition.new("ISC Interface - Terminating Failed") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint

  sip_caller.set_ifc server_name: "#{ENV['HOSTNAME']}:5070"
  sip_callee.set_ifc server_name: "#{ENV['HOSTNAME']}:5070"

  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5070)
    begin
      incoming_cid = c.get_new_call_id
      incoming_call = Call.new(c, incoming_cid)

      idata = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100 Trying")
      incoming_call.send_response("404 Not Found")
      incoming_call.recv_request("ACK")  # Comes from Bono
      incoming_call.end_call
    ensure
      c.terminate
    end
  end

  t.set_scenario(
    sip_caller.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_caller.recv("404", rrs: true),
      sip_caller.send("ACK", in_dialog: true),
    ] +
    sip_caller.unregister
  )
end

def validate_expiry c, expected_expiry
      incoming_cid = c.get_new_call_id
      incoming_call = Call.new(c, incoming_cid)

      register_data = incoming_call.recv_request("REGISTER")
      actual_expiry = register_data['message'].header("Expires")
      fail "Expected Expires of #{expected_expiry}, got expires of #{actual_expiry}!" unless actual_expiry == expected_expiry
      incoming_call.end_call
end

ASTestDefinition.new("ISC Interface - Third-party Registration") do |t|
  sip_caller = t.add_sip_endpoint

  sip_caller.set_ifc server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP", method: "REGISTER"

  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5070)
    begin
      validate_expiry c, EXPECTED_EXPIRY
      validate_expiry c, "0"
    ensure
      c.terminate
    end
  end

  t.set_scenario(
    [SIPpPhase.new("pause", sip_caller, timeout: 1000)] +
    sip_caller.register +
    [SIPpPhase.new("pause", sip_caller, timeout: 1000)] +
    sip_caller.unregister
  )
end

ASTestDefinition.new("ISC Interface - Third-party Registration - implicit registration") do |t|
  sip_caller = t.add_sip_endpoint
  ep2 = t.add_public_identity(sip_caller)

  sip_caller.set_ifc server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP", method: "REGISTER"
  ep2.set_ifc server_name: "#{ENV['HOSTNAME']}:5071;transport=TCP", method: "REGISTER"

  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5070)
    begin
      validate_expiry c, EXPECTED_EXPIRY
      validate_expiry c, "0"
    ensure
      c.terminate
    end
  end

  # Set up a second AS on port 5071, to ensure that iFCs for the second public identity are handled independently
  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5071)
    begin
      validate_expiry c, EXPECTED_EXPIRY
      validate_expiry c, "0"
    ensure
      c.terminate
    end
  end

  t.set_scenario(
    [SIPpPhase.new("pause", sip_caller, timeout: 1000)] +
    sip_caller.register +
    [SIPpPhase.new("pause", sip_caller, timeout: 1000)] +
    sip_caller.unregister +
    [SIPpPhase.new("pause", sip_caller, timeout: 1000)] +
    ep2.register +
    [SIPpPhase.new("pause", ep2, timeout: 1000)] +
    ep2.unregister
  )
end



ASTestDefinition.new("ISC Interface - Redirect") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint
  sip_callee2 = t.add_sip_endpoint
  mock_as = t.add_mock_as(ENV['HOSTNAME'], 5070)

  sip_callee1.set_ifc server_name: "#{ENV['HOSTNAME']}:5070"

  t.set_scenario(
    sip_caller.register +
    sip_callee1.register +
    sip_callee2.register +
    [
      sip_caller.send("INVITE", target: sip_callee1, emit_trusted: true, call_number: 1),
      sip_caller.recv("100"),
      mock_as.recv("INVITE", extract_uas_via: true, save_remote_ip: true),
      mock_as.send("302", from: sip_caller, to: sip_callee1, redirect_target: sip_callee2, method: "INVITE", call_number: 1),
      mock_as.recv("ACK"),
      sip_caller.recv("302", from: sip_caller, to: sip_callee1, redirect_target: sip_callee2, method: "INVITE"),
      sip_caller.send("ACK", target: sip_callee1, call_number: 1),
      sip_caller.send("INVITE", target: sip_callee2, emit_trusted: true, call_number: 2),
      sip_caller.recv("100"),
      sip_callee2.recv("INVITE", extract_uas_via: true, check_trusted: true, trusted_present: false),
      sip_callee2.send("100", target: sip_caller, method: "INVITE", call_number: 2),
      sip_callee2.send("180", target: sip_caller, method: "INVITE", call_number: 2),
      sip_caller.recv("180"),
      sip_callee2.send("200-SDP", target: sip_caller, method: "INVITE", call_number: 2),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee2, in_dialog: true, call_number: 2),
      sip_callee2.recv("ACK"),
      SIPpPhase.new("pause", sip_caller, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee2, in_dialog: true, call_number: 2),
      sip_callee2.recv("BYE", extract_uas_via: true),
      sip_callee2.send("200", target: sip_caller, method: "BYE", emit_trusted: true, call_number: 2),
      sip_caller.recv("200", check_trusted: true, trusted_present: false),
    ] +
    sip_caller.unregister +
    sip_callee1.unregister +
    sip_callee2.unregister
  )
end

ASTestDefinition.new("ISC Interface - B2BUA") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint

  sip_caller.set_ifc server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP"

  t.add_quaff_endpoint do
    c = TCPSIPConnection.new(5070)
    begin
      incoming_cid = c.get_new_call_id
      incoming_call = Call.new(c, incoming_cid)

      invite_data = incoming_call.recv_request("INVITE")
      incoming_call.send_response("100")

      sprout_outbound = TCPSource.new TCPSocket.new(invite_data['source'].remote_ip, 5054)

      # Send a new call back to Sprout
      outgoing_call = Call.new(c, "2///"+incoming_cid)
      outgoing_call.setdest(sprout_outbound, recv_from_this: true)
      outgoing_call.set_callee(invite_data['message'].requri)

      # Copy top Route header to Route or Request-URI?
      outgoing_call.send_request("INVITE", nil, nil, {"From" => invite_data['message'].header("From")})

      outgoing_call.recv_response("100")
      outgoing_call.recv_response("180")
      incoming_call.send_response("180")

      ok_data = outgoing_call.recv_response("200")

      # Switch over to talking to Bono now the dialog is established
      /<sip:(.*):5058/ =~ invite_data['message'].headers['Record-Route'][0]
      bono_outbound = TCPSource.new TCPSocket.new($1, 5058)
      outgoing_call.setdest(bono_outbound, recv_from_this: true)

      /<(.*)>/ =~ invite_data['message'].headers['Contact'][0]
      outgoing_call.set_callee($1)

      outgoing_call.send_request("ACK", nil, nil, {"Route" => ok_data['message'].headers['Record-Route']})

      sleep 0.5 # Don't let these two reach SIPp in the wrong order

      incoming_call.send_response("200 OK")
      incoming_call.recv_request("ACK")  # Comes from Bono
      incoming_call.recv_request("BYE")  # Also comes from Bono

      # We automatically switch to Bono now, as that's where the BYE came from
      incoming_call.send_response("200 OK", nil, {"CSeq" => "4 BYE"})

      outgoing_call.send_request("BYE", nil, nil, {"Route" => ok_data['message'].headers['Record-Route'], "CSeq" => "8 BYE"})
      outgoing_call.recv_response("200")

      incoming_call.end_call
      outgoing_call.end_call
    ensure
      c.terminate
    end
  end

  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_callee.recv("INVITE", extract_uas_via: true, rrs: true),

      sip_callee.send("180", target: sip_caller, method: "INVITE", cid_prefix: "2///"),
      sip_caller.recv("180"),

      sip_callee.send("200", target: sip_caller, method: "INVITE", cid_prefix: "2///"),
      sip_callee.recv("ACK"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee, in_dialog: true, method: "INVITE"),

      SIPpPhase.new("pause", sip_caller, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee, in_dialog: true),
      sip_caller.recv("200"),
      sip_callee.recv("BYE"),
      sip_callee.send("200", target: sip_callee, method: "BYE", cid_prefix: "2///"),
    ] +
    sip_caller.unregister +
    sip_callee.unregister
  )
end
