# @file contact-filtering.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2014 Metaswitch Networks Ltd
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

TestDefinition.new("Filtering - Accept-Contact") do |t|

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain", "Accept-Contact" => "*;+sip.instance=\"<urn:uuid:#{callee.instance_id}>\";explicit;require"})
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

TestDefinition.new("Filtering - Accept-Contact no match") do |t|

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain", "Accept-Contact" => "*;+sip.instance=\"<wrong>\";explicit;require"})
    call.recv_response("480")
    call.end_call
    fail unless callee.no_new_calls?
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end

TestDefinition.new("Filtering - Accept-Contact negated match") do |t|

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    callee.add_contact_param '+sip.test', '"hello,goodbye"'
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain", "Accept-Contact" => "*;+sip.test=\"!hello\";explicit;require"})
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

TestDefinition.new("Filtering - RFC3841 example") do |t|

  caller = t.add_endpoint
  callee_binding1 = t.add_endpoint
  callee_binding2 = t.add_new_binding callee_binding1
  callee_binding3 = t.add_new_binding callee_binding1
  callee_binding4 = t.add_new_binding callee_binding1
  callee_binding5 = t.add_new_binding callee_binding1

  t.add_quaff_setup do
    callee_binding1.add_contact_param 'audio', true
    callee_binding1.add_contact_param 'video', true
    callee_binding1.add_contact_param 'methods', '"INVITE,BYE"'
    callee_binding1.add_contact_param 'q', '0.2'

    callee_binding2.add_contact_param 'audio', '"FALSE"'
    callee_binding2.add_contact_param 'methods', '"INVITE"'
    callee_binding2.add_contact_param 'actor', '"msg-taker"'
    callee_binding2.add_contact_param 'q', '0.2'

    callee_binding3.add_contact_param 'audio', true
    callee_binding3.add_contact_param 'actor', '"msg-taker"'
    callee_binding3.add_contact_param 'methods', '"INVITE"'
    callee_binding3.add_contact_param 'video', true
    callee_binding3.add_contact_param 'q', '0.3'

    callee_binding4.add_contact_param 'audio', true
    callee_binding4.add_contact_param 'methods', '"INVITE,OPTIONS"'
    callee_binding4.add_contact_param 'q', '0.2'

    callee_binding5.add_contact_param 'q', '0.5'

    caller.register
    callee_binding1.register
    callee_binding2.register
    callee_binding3.register
    callee_binding4.register
    ok = callee_binding5.register
    fail "200 OK Contact header did not contain 5 bindings" unless ok.headers["Contact"].length == 5
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee_binding1.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain",
                        "Accept-Contact" => ["*;audio;require", "*;video;explicit", '*;methods="BYE";class="business";q=1.0'],
                      "Reject-Contact" => '*;actor="msg-taker";video'})
    call.recv_response("200")
    call.end_call

  end

  t.add_quaff_scenario do
    # Call should be forked to bindings 1, 4 and 5 simultaneously -
    # check that 1 and 4 have a call come in and then answer it from 5.
    call2 = callee_binding1.incoming_call
    call2.recv_request("MESSAGE")

    call3 = callee_binding4.incoming_call
    call3.recv_request("MESSAGE")

    call4 = callee_binding5.incoming_call
    call4.recv_request("MESSAGE")
    call4.send_response("200", "OK")
    call4.end_call

    # Expect binding 3 to be rejected because it matches the Reject-Contact
    fail "Call was forked to binding 3" unless callee_binding3.no_new_calls?
    # Expect binding 2 to be rejected because audio is required
    fail "Call was forked to binding 2" unless callee_binding2.no_new_calls?
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee_binding1.unregister
    callee_binding2.unregister
    callee_binding3.unregister
    callee_binding4.unregister
    callee_binding5.unregister
  end
end

TestDefinition.new("Filtering - Reject-Contact no match") do |t|

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain", "Reject-Contact" => "*;+sip.instance=\"<wrong>\""})
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

TestDefinition.new("Filtering - Reject-Contact match") do |t|

  caller = t.add_endpoint
  callee = t.add_endpoint

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain",
                        "Reject-Contact" => "*;+sip.instance=\"<urn:uuid:#{callee.instance_id}>\""})
    call.recv_response("480")
    call.end_call
    fail unless callee.no_new_calls?
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end
end


