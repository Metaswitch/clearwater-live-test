# @file call-diversion-as.rb
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

CDIV_AS_SIP_URI="communication-diversion@#{ENV['CDIV_AS']}:5054;transport=TCP"

class CDivASTD < TestDefinition

  def generic_setup endpoints_to_register
    add_quaff_setup do
      endpoints_to_register.each do |ep|
        ep.register
      end
    end

    add_quaff_cleanup do
      endpoints_to_register.each do |ep|
        ep.unregister
      end
    end

  end

  def add_caller_scenario caller, callee_uri, ringing_barrier, ack_barrier
    add_quaff_scenario do
      call = caller.outgoing_call(callee_uri)

      call.send_invite_with_sdp
      call.recv_response("100")
      call.recv_response("181")

      # Call is diverted to callee2
      call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
      ringing_barrier.wait

      call.recv_response_and_create_dialog("200")
      call.new_transaction
      call.send_request("ACK")
      ack_barrier.wait

      call.new_transaction
      call.send_request("BYE")
      call.recv_response("200")
      call.end_call
    end
  end

  def add_redirectee_scenario redirectee, ringing_barrier, ack_barrier
    add_quaff_scenario do
      call2 = redirectee.incoming_call
      call2.recv_request("INVITE")
      call2.send_response("100", "Trying")
      call2.send_response("180", "Ringing")
      ringing_barrier.wait

      call2.send_200_with_sdp
      call2.recv_request("ACK")
      ack_barrier.wait

      call2.recv_request("BYE")
      call2.send_response("200", "OK")
      call2.end_call
    end
  end

end

CDivASTD.new("Call Diversion AS - Unconditional") do |t|
  t.skip_unless_call_diversion_as
  t.skip_unless_ellis_api_key

  caller, callee1, callee2 = t.add_endpoint, t.add_endpoint, t.add_endpoint

  ringing_barrier = Barrier.new(2)

  # Wait on three threads, so we can use a third thread to do some
  # post-call checks.
  ack_barrier = Barrier.new(3)

  # Set iFCs
  as_uri = "#{CDIV_AS_SIP_URI};target=#{CGI.escape(callee2.uri)}"
  callee1.set_ifc [{server_name: as_uri, session_case: TERM_REG}]

  endpoints_to_register = [caller, callee1, callee2]
  t.generic_setup endpoints_to_register

  # A calls B. Because the forwarding rule is unconditional, the call is immediately
  # forwarded to C with no involvement from B.
  t.add_caller_scenario caller, callee1.uri, ringing_barrier, ack_barrier
  t.add_redirectee_scenario callee2, ringing_barrier, ack_barrier

  t.add_quaff_scenario do
    # Wait until the call is set up, then do some extra checks on
    # other lines
    ack_barrier.wait
    fail "Callee 1 received a call despite unconditional call forwarding" unless callee1.no_new_calls?
  end
end

CDivASTD.new("Call Diversion AS - Busy") do |t|
  t.skip_unless_call_diversion_as
  t.skip_unless_ellis_api_key

  caller, callee1, callee2 = t.add_endpoint, t.add_endpoint, t.add_endpoint

  ringing_barrier = Barrier.new(2)
  ack_barrier = Barrier.new(2)

  # Set iFCs
  as_uri = "#{CDIV_AS_SIP_URI};target=#{CGI.escape(callee2.uri)};conditions=busy"
  callee1.set_ifc [{server_name: as_uri, session_case: TERM_REG}]

  endpoints_to_register = [caller, callee1, callee2]
  t.generic_setup endpoints_to_register

  # A calls B. B doesn't ring and just responds with an error, so the
  # call is forwarded to C.
  t.add_caller_scenario caller, callee1.uri, ringing_barrier, ack_barrier
  t.add_redirectee_scenario callee2, ringing_barrier, ack_barrier

  t.add_quaff_scenario do
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("486", "Busy Here")
    call1.recv_request("ACK")

    call1.end_call
  end
end

CDivASTD.new("Call Diversion AS - No answer") do |t|
  t.skip_unless_call_diversion_as
  t.skip_unless_ellis_api_key

  caller, callee1, callee2 = t.add_endpoint, t.add_endpoint, t.add_endpoint

  ringing_barrier = Barrier.new(2)
  ringing_barrier_2 = Barrier.new(2)
  ack_barrier = Barrier.new(2)

  # Set iFCs
  as_uri = "#{CDIV_AS_SIP_URI};target=#{CGI.escape(callee2.uri)};conditions=no-answer;no-reply-timer=20"
  callee1.set_ifc [{server_name: as_uri, session_case: TERM_REG}]

  endpoints_to_register = [caller, callee1, callee2]
  t.generic_setup endpoints_to_register

  # A sends a call to B, which starts ringing, but is then unanswered
  # - call is then redirected to C. Because B starts ringing before
  # the redirect, we need a custom caller scenario.
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee1.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")

    # "No answer" requires ringing to have started, so enforce that
    # with a barrier
    ringing_barrier.wait
    call.recv_response("181") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']

    # Call is diverted to callee2
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
    ringing_barrier_2.wait
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    ack_barrier.wait

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call

  end

  # First callee receives a call, but doesn't answer
  t.add_quaff_scenario do
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("180", "Ringing")
    ringing_barrier.wait

    call1.send_response("408", "Request Timeout")
    call1.recv_request("ACK")

    call1.end_call
  end

  t.add_redirectee_scenario callee2, ringing_barrier_2, ack_barrier

end
