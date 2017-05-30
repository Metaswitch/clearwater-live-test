# @file nonce-count.rb
#
# Copyright (C) Metaswitch Networks 2016
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

# Note that all our nonce count tests use multiple identities.  This is to
# ensure that the P-CSCF doesn't mark the request as
# integrity-protected=ip-assoc-yes, which would bypass authentication.

TestDefinition.new("Nonce-Count - Mainline") do |t|
  t.skip_unless_nonce_count_supported

  ep1 = t.add_endpoint
  ep2 = t.add_public_identity(ep1)

  t.add_quaff_scenario do
    # Register once with nonce-count 1
    call = ep1.outgoing_call(ep1.uri)
    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q[Digest username="#{ep1.private_id}"] })
    response_data = call.recv_response("401")
    www_auth_hdr = response_data.header("WWW-Authenticate")
    auth_hdr = Quaff::Auth.gen_auth_header www_auth_hdr, ep1.private_id, ep1.password, "REGISTER", ep1.uri, "", "auth", 1
    call.new_transaction
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok = call.recv_response("200")

    # Now register with nonce-count 2
    call2 = ep2.outgoing_call(ep2.uri)
    auth_hdr = Quaff::Auth.gen_auth_header www_auth_hdr, ep2.private_id, ep2.password, "REGISTER", ep1.uri, "", "auth", 2
    call2.new_transaction
    call2.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok2 = call2.recv_response("200")
  end

  t.add_quaff_cleanup do
    ep1.unregister
    ep2.unregister
  end
end

TestDefinition.new("Nonce-Count - Reject Re-Use") do |t|
  t.skip_unless_nonce_count_supported

  ep1 = t.add_endpoint
  ep2 = t.add_public_identity(ep1)

  t.add_quaff_scenario do
    # Register with nonce-count 1
    call = ep1.outgoing_call(ep1.uri)
    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q[Digest username="#{ep1.private_id}"] })
    response_data = call.recv_response("401")
    www_auth_hdr = response_data.header("WWW-Authenticate")
    auth_hdr = Quaff::Auth.gen_auth_header www_auth_hdr, ep1.private_id, ep1.password, "REGISTER", ep1.uri, "", "auth", 1
    call.new_transaction
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok = call.recv_response("200")

    # Try to register with nonce-count 1 again - rejected
    call2 = ep2.outgoing_call(ep2.uri)
    auth_hdr = Quaff::Auth.gen_auth_header www_auth_hdr, ep2.private_id, ep2.password, "REGISTER", ep1.uri, "", "auth", 1
    call2.new_transaction
    call2.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok2 = call2.recv_response("401")
  end

  t.add_quaff_cleanup do
    ep1.unregister
    ep2.unregister
  end
end
