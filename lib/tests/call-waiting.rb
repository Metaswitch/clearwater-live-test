# @file call-waiting.rb
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

require 'barrier'

TestDefinition.new("Call Waiting - Accepted") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  interruptor = t.add_endpoint

  first_call_ringing_barrier = Barrier.new(2)
  first_call_set_up_barrier = Barrier.new(3)

  second_call_ringing_barrier = Barrier.new(2)
  second_call_set_up_barrier = Barrier.new(2)

  t.add_quaff_setup do
    caller.register
    callee.register
    interruptor.register
  end

  t.add_quaff_scenario do
    # A calls B - this is just an ordinary call from A's
    # point of view
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    first_call_ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response("200", dialog_creating: true)

    call.send_request("ACK")
    first_call_set_up_barrier.wait

    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    # B receives call from A
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    first_call_ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")
    first_call_set_up_barrier.wait
    # B's call from A is now set up

    # B receives a call from C and sends a 180 with an Alert-Info
    # header indicating that we're doing call waiting
    call3 = callee.incoming_call
    call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing", headers: {"Alert-Info" => "<urn:alert:service:call-waiting>"})
    second_call_ringing_barrier.wait

    # A hangs up
    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call

    # We can now answer the call from C
    call3.send_200_with_sdp
    call3.recv_request("ACK")
    second_call_set_up_barrier.wait

    call3.recv_request("BYE")
    call3.send_response("200", "OK")
    call3.end_call
  end

  t.add_quaff_scenario do
    # C calls A. This is an ordinary call, just with an extra
    # Alert-Info header.

    first_call_set_up_barrier.wait
    call = interruptor.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    ringing_resp = call.recv_response("180")
    second_call_ringing_barrier.wait

    # check for call waiting on 180
    fail "Alert-Info was not passed through properly" unless ringing_resp.first_header('Alert-Info') == "<urn:alert:service:call-waiting>"

    call.recv_response("200", dialog_creating: true)

    call.send_request("ACK")
    second_call_set_up_barrier.wait

    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    interruptor.unregister
  end
end

TestDefinition.new("Call Waiting - Cancelled") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  interruptor = t.add_endpoint

  first_call_ringing_barrier = Barrier.new(2)
  first_call_set_up_barrier = Barrier.new(3)

  t.add_quaff_setup do
    caller.register
    callee.register
    interruptor.register
  end

  t.add_quaff_scenario do
    # A calls B - this is just an ordinary call from A's
    # point of view
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    first_call_ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response("200", dialog_creating: true)

    call.send_request("ACK")
    first_call_set_up_barrier.wait

    call.send_request("BYE")
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    # B receives call from A
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    first_call_ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")
    first_call_set_up_barrier.wait
    # B's call from A is now set up

    # B receives a new call from C and responds with a 180 indicating
    # call waiting
    call3 = callee.incoming_call
    original_invite = call3.recv_request("INVITE")
    call3.send_response("100", "Trying")
    call3.send_response("180", "Ringing", headers: {"Alert-Info" => "<urn:alert:service:call-waiting>"})

    # C cancels its invite
    call3.recv_request("CANCEL")
    call3.send_response("200", "OK")

    call3.send_response("487", "Cancelled", response_to: original_invite)
    call3.recv_request("ACK")
    call3.end_call

    # A now ends the other call
    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    # C calls A
    first_call_set_up_barrier.wait
    call = interruptor.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")

    # C gets a call waiting indication
    ringing_resp = call.recv_response("180")

    fail "Alert-Info was not passed through properly" unless ringing_resp.first_header('Alert-Info') == "<urn:alert:service:call-waiting>"

    # C cancels the call
    call.send_request("CANCEL", new_tsx: false)
    call.recv_response("200")

    call.recv_response("487")
    call.send_request("ACK", new_tsx: false)
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
    interruptor.unregister
  end
end
