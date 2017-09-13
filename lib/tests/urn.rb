# @file urn.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

# These tests want to work on an originating MESSAGE that's sent to the I-CSCF.
# In order to achieve this we make Bono act as an IBCF, and have it proxy an
# originating request to the I-CSCF.
TestDefinition.new("Message - URN URIs") do |t|
  t.skip_unless_hostname
  t.skip_unless_ibcf
  t.skip_unless_icscf

  caller = t.add_endpoint

  # iFC that matches originating MESSAGEs where the Request URI includes
  # cat. This uses session case 3 (originating unregistered).
  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP",
                   priority: 0,
                   session_case: 3,
                   method: "MESSAGE",
                   req_uri: "cat"}]

  t.add_quaff_scenario do
    # The message has the Request URI set to urn:services:sos.
    call = caller.outgoing_call("urn:services:sos")

    # This message doesn't trigger any iFCs, so it fails cleanly on the
    # terminating side as 'urn:services:sos' isn't a subscriber.
    call.send_request("MESSAGE", "", {"P-Asserted-Identity" => "#{caller.sip_uri}",
                                      "Route" => "sip:#{ENV['ICSCF_HOSTNAME']};transport=TCP;lr;orig"})
    call.recv_response("480")
    call.end_call
  end

end

TestDefinition.new("Message - URN URIs to AS") do |t|
  t.skip_unless_hostname
  t.skip_unless_ibcf
  t.skip_unless_icscf

  caller = t.add_endpoint
  as = t.add_as 5070

  # iFC that matches originating MESSAGEs where the Request URI includes
  # sos.
  caller.set_ifc [{server_name: "#{ENV['HOSTNAME']}:5070;transport=TCP",
                   priority: 0,
                   session_case: 3,
                   method: "MESSAGE",
                   req_uri: "sos"}]

  t.add_quaff_scenario do
    # The message has the Request URI set to urn:services:sos.
    call = caller.outgoing_call("urn:services:sos")

    # This message does trigger the iFCs, so the request is routed to the AS,
    # which returns 200.
    call.send_request("MESSAGE", "", {"P-Asserted-Identity" => "#{caller.sip_uri}",
                                      "Route" => "sip:#{ENV['ICSCF_HOSTNAME']};transport=TCP;lr;orig"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    incoming_call = as.incoming_call
    message_data = incoming_call.recv_request("MESSAGE")
    fail unless message_data.requri == "urn:services:sos"
    incoming_call.send_response("200", "OK", "", nil, {"To" => "urn:services:sos"})
    incoming_call.end_call
  end

end
