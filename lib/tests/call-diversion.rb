# @file call-diversion.rb
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

TestDefinition.new("Call Diversion - Not registered") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee1 = t.add_endpoint
  callee2 = t.add_endpoint

  callee1.set_simservs cdiv: { active: true,
                               rules: [ { conditions: ["not-registered"],
                                          target: callee2.uri } ]
                             }

  t.add_quaff_setup do
    caller.register
    callee2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee1.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("181")

    # Call is diverted to callee2
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
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
    call2 = callee2.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_200_with_sdp
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee2.unregister
  end
end

TestDefinition.new("Call Diversion - Busy") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee1 = t.add_endpoint
  callee2 = t.add_endpoint

  callee1.set_simservs cdiv: { active: true,
                               rules: [ { conditions: ["busy"],
                                          target: callee2.uri } ]
                             }

  t.add_quaff_setup do
    caller.register
    callee1.register
    callee2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee1.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("181")

    # Call is diverted to callee2
    call.recv_response("180") unless ENV['PROVISIONAL_RESPONSES_ABSORBED']
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
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("486", "Busy Here")
    call1.recv_request("ACK")

    call1.end_call
  end

  t.add_quaff_scenario do
    call2 = callee2.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_200_with_sdp
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee1.unregister
    callee2.unregister
  end

end

TestDefinition.new("Call Diversion - No answer") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee1 = t.add_endpoint
  callee2 = t.add_endpoint

  ringing_barrier = Barrier.new(2)

  callee1.set_simservs cdiv: { active: true,
                               timeout: "20",
                               rules: [ { conditions: ["no-answer"],
                                          target: callee2.uri } ]
                             }

  t.add_quaff_setup do
    caller.register
    callee1.register
    callee2.register
  end

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
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("180", "Ringing")
    ringing_barrier.wait
    call1.send_response("408", "Request Timeout")
    call1.recv_request("ACK")
    call1.end_call
  end

  t.add_quaff_scenario do
    call2 = callee2.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_200_with_sdp
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee1.unregister
    callee2.unregister
  end
end

TestDefinition.new("Call Diversion - Bad target URI") do |t|
  t.skip_unless_mmtel

  caller = t.add_endpoint
  callee = t.add_endpoint

  callee.set_simservs cdiv: { active: true,
                              rules: [ { conditions: ["not-registered"],
                                         target: "12345" } ]
                            }

  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("INVITE")
    call.recv_response("100")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end
end

