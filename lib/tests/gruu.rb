# @file gruu.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

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
    binding1.add_contact_param "pub-gruu", "ok"
    binding1.register
    binding2.add_contact_param "pub-gruu", "hello"
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
    binding.add_contact_param "+sip.instance", '"geo:37.786971,-122.399677;crs=Moon-2011;u=35"'
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
    binding1.add_contact_param "audio", true
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
    binding1.add_contact_param "audio", true
    binding2.add_contact_param "audio", true
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

TestDefinition.new("GRUU - Call - GRUU with other param as target") do |t|
  caller = t.add_endpoint
  binding1 = t.add_endpoint
  binding2 = t.add_new_binding binding1

  t.add_quaff_setup do
    caller.register
    binding1.register
    binding2.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(binding2.expected_pub_gruu + ";meaningless-param")

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
