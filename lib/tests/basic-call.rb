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

# Converts a URI like sip:1234@example.com to tel:1234. Doesn't
# support parameters or non-numeric characters (e.g.
# "sip:+1234;npdi@example.com" won't work).
def sip_to_tel(uri)
  uri =~ /sip:(\d+)@.+/
  "tel:#{$1}"
end

TestDefinition.new("Basic Call - Mainline") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # We only send a plain text body in this INVITE, not full SDP. This reduces
    # the size of the SIP message (SDP is ~200 bytes) and increases the chance
    # that UDP messages will be small enough to get through the network without
    # fragmenting.
    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

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
    ringing_barrier.wait

    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
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

TestDefinition.new("Basic Call - SDP") do |t|
  # The additional size of the SDP body pushes this over the UDP limit, so we
  # don't run it when the transport is UDP.
  t.skip_if_udp

  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

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
    ringing_barrier.wait

    call2.send_200_with_sdp
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

TestDefinition.new("Basic Call - Tel URIs") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do

    # This tests that for a subscriber like sip:1234@example.com, a
    # call to tel:1234 also reaches them. If this assumption is not
    # true (e.g. due to unusual ENUM rewriting), this test will fail.
    
    tel = sip_to_tel(callee.uri)
    call = caller.outgoing_call(tel)

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

end

TestDefinition.new("Basic Call - Unknown number") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("100")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Basic Call - Rejected by remote endpoint") do |t|
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

    call.recv_response("486")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("486", "Busy Here")
    call2.recv_request("ACK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Messages - Pager model") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE", "hello world\r\n", {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Basic Call - Pracks") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE", "hello world\r\n", {"Content-Type" => "text/plain", "Supported" => "100rel"})
    call.recv_response("100")

    # For a PRACK, we create the dialog early, on the 180 response
    ringing_msg = call.recv_response_and_create_dialog("180")

    call.new_transaction
    call.send_request("PRACK", "", {"RAck" => "#{ringing_msg.header("RSeq")} #{ringing_msg.header("CSeq")}"})
    call.recv_response("200")

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
    original_invite = call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing", "", nil, {"Require" => "100rel", "RSeq" => "1"})

    call2.recv_request("PRACK")
    call2.send_response("200", "OK")

    # Send this 200 in the original transaction, not the PRACK transaction
    call2.assoc_with_msg(original_invite)
    call2.send_response("200", "OK", "hello world\r\n", nil, {"Content-Type" => "text/plain"})
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
