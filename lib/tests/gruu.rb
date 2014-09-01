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

require 'nokogiri'

def get_pub_gruu contact_header
  md = /pub-gruu=(?<gruu>".+?"|.+?;)/.match(contact_header)
  if md and md['gruu']
    md['gruu'].tr("\"","")
  else
    ""
  end
end

def pub_gruu_in_headers? gruu, contact_headers
  contact_headers.each do |contact|
    return true if get_pub_gruu(contact) == gruu
  end
  return false
end

TestDefinition.new("GRUU - REGISTER - two bindings with and without GRUU") do |t|
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1, false

  t.add_quaff_scenario do
    binding1.register
    ok = binding2.register
    contact_headers = ok.headers['Contact']
    fail "Binding 2 has a pub-gruu" if (get_pub_gruu(contact_headers[1]) != "")
    fail "Binding 1 has no pub-gruu (expected #{binding1.expected_pub_gruu})" unless
      (get_pub_gruu(contact_headers[0]) == binding1.expected_pub_gruu)
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
  end
end

TestDefinition.new("GRUU - REGISTER - binding suggested GRUU") do |t|
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1, false

  t.add_quaff_scenario do
    binding1.contact_header += ";pub-gruu=ok"
    binding1.register
    binding2.contact_header += ";pub-gruu=hello"
    ok = binding2.register
    contact_headers = ok.headers['Contact']
    fail "Binding 2 was allowed to suggest a pub-gruu" if (get_pub_gruu(contact_headers[1]) != "")
    fail "Binding 1 was allowed to suggest a pub-gruu" unless
      (get_pub_gruu(contact_headers[0]) == binding1.expected_pub_gruu)
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
  end
end

TestDefinition.new("GRUU - REGISTER - instance ID requires escaping") do |t|
  binding = t.add_endpoint(nil, false)

  t.add_quaff_scenario do
    binding.contact_header += ";+sip.instance=\"geo:37.786971,-122.399677;crs=Moon-2011;u=35\""
    ok = binding.register
    contact_headers = ok.headers['Contact']
    fail "pub-gruu was not correctly escaped" unless get_pub_gruu(contact_headers[0]) == "#{binding.sip_uri};gr=geo:37.786971%2c-122.399677%3bcrs%3dMoon-2011%3bu%3d35"
  end

  t.add_quaff_cleanup do
    binding.unregister
  end
end

TestDefinition.new("GRUU - REGISTER - three bindings with GRUUs") do |t|
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1
  binding3 = t.add_new_binding binding1

  t.add_quaff_scenario do
    binding1.register
    binding2.register
    ok = binding3.register
    contact_headers = ok.headers['Contact']
    fail "Binding 1's pub-gruu not found in headers" unless pub_gruu_in_headers?(binding1.expected_pub_gruu, contact_headers)
    fail "Binding 2's pub-gruu not found in headers" unless pub_gruu_in_headers?(binding2.expected_pub_gruu, contact_headers)
    fail "Binding 3's pub-gruu not found in headers" unless pub_gruu_in_headers?(binding3.expected_pub_gruu, contact_headers)
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    binding3.unregister
  end
end

TestDefinition.new("GRUU - Call - first endpoint GRUU as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding1.expected_pub_gruu)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    fail "Call was incorrectly forked to both endpoints" unless binding2.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding1.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - second endpoint GRUU as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.expected_pub_gruu)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    fail "Call was incorrectly forked to both endpoints" unless binding1.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding2.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - only GRUU as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1, false

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding1.expected_pub_gruu)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    fail "Call was incorrectly forked to both endpoints" unless binding2.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding1.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - AoR as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.sip_uri)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    fail "Call was not forked to both endpoints" if binding1.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding2.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - unknown GRUU as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.sip_uri + ";gr=nonsense")

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("480")
    call.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - unknown GRUU as target - no GRUUs assigned") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint nil, false
  binding2 = t.add_new_binding binding1, false

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.sip_uri + ";gr=nonsense")

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("480")
    call.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - Reject-Contact interop") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.contact_header += ";audio"
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding1.expected_pub_gruu)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain",
                      "Reject-Contact" => "*;audio"})
    call.recv_response("480")
    call.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - Accept-Contact interop") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.contact_header += ";audio"
    binding2.contact_header += ";audio"
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding1.expected_pub_gruu)

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain",
                        "Accept-Contact" => "*;audio"})
    call.recv_response("200")
    call.end_call
    fail "Call was incorrectly forked to both endpoints" unless binding2.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding1.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

TestDefinition.new("GRUU - Call - AoR with other param as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.sip_uri + ";arbitrary-param=\"an;gr=y\"")

    call.send_request("MESSAGE",
                      "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
    fail "Call was not forked to both endpoints" if binding1.no_new_calls?
  end

  t.add_quaff_scenario do
    call2 = binding2.incoming_call
    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    binding1.unregister
    binding2.unregister
    caller.unregister
  end
end

