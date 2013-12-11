# @file basic-call.rb
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

TestDefinition.new("Basic Call - Mainline") do |t|
  caller = t.add_quaff_endpoint
  callee = t.add_quaff_endpoint
  caller.register
  callee.register

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("180")
    data =  call.recv_response("200")

    call.create_dialog(data["message"])
    call.send_request("ACK")
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
    caller.unregister
  end

  t.add_quaff_endpoint do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
    call2.recv_request("ACK")
    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Unknown number") do |t|
  caller = t.add_quaff_endpoint
  callee = t.add_quaff_endpoint
  caller.register

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("404")
    call.send_request("ACK")
    call.end_call
    caller.unregister
  end

end

TestDefinition.new("Basic Call - Rejected by remote endpoint") do |t|
  caller = t.add_quaff_endpoint
  callee = t.add_quaff_endpoint
  caller.register
  callee.register

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("486")
    call.send_request("ACK")
    call.end_call
    caller.unregister
  end

  t.add_quaff_endpoint do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("486", "")
    call2.recv_request("ACK")
    call2.end_call
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Messages - Pager model") do |t|
  caller = t.add_quaff_endpoint
  callee = t.add_quaff_endpoint
  caller.register
  callee.register

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    caller.unregister
  end

  t.add_quaff_endpoint do
    call2 = callee.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Pracks") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint
  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_callee.recv("INVITE", extract_uas_via: true, check_trusted: true, trusted_present: false),
      sip_callee.send("100", target: sip_caller, method: "INVITE"),
      sip_callee.send("180", prack_expected: true, target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_caller.send("PRACK", target: sip_callee),
      sip_callee.recv("PRACK", extract_second_via: true),
      sip_callee.send("200", second_transaction: true, target: sip_caller, method: "PRACK"),
      sip_caller.recv("200", target: sip_caller, method: "PRACK"),
      sip_callee.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee, in_dialog: true),
      sip_callee.recv("ACK"),
      SIPpPhase.new("pause", sip_caller, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee, in_dialog: true),
      sip_callee.recv("BYE", extract_uas_via: true),
      sip_callee.send("200", target: sip_caller, method: "BYE", emit_trusted: true),
      sip_caller.recv("200", check_trusted: true, trusted_present: false),
  ] +
  sip_caller.unregister +
  sip_callee.unregister
  )
end

