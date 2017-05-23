# @file basic-register.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

TestDefinition.new("Basic Registration") do |t|
  caller = t.add_endpoint

  t.add_quaff_scenario do
    call = caller.outgoing_call(caller.uri)
    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q!Digest username="#{caller.private_id}"! })
    response_data = call.recv_response("401")
    auth_hdr = Quaff::Auth.gen_auth_header response_data.header("WWW-Authenticate"), caller.private_id, caller.password, "REGISTER", caller.uri
    call.update_branch
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    response_data = call.recv_response("200")
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Multiple Identities") do |t|
  ep1 = t.add_endpoint
  ep2 = t.add_public_identity(ep1)

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)
    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q[Digest username="#{ep1.private_id}"] })
    response_data = call.recv_response("401")
    auth_hdr = Quaff::Auth.gen_auth_header response_data.header("WWW-Authenticate"), ep1.private_id, ep1.password, "REGISTER", ep1.uri
    call.new_transaction
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok = call.recv_response("200")

    call2 = ep2.outgoing_call(ep2.uri)
    call2.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q[Digest username="#{ep2.private_id}"] })
    response_data = call2.recv_response("401")
    auth_hdr = Quaff::Auth.gen_auth_header response_data.header("WWW-Authenticate"), ep2.private_id, ep2.password, "REGISTER", ep1.uri
    call2.new_transaction
    call2.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600"})
    ok2 = call2.recv_response("200")

    fail "200 OK for #{ep1.uri} does not include <#{ep1.uri}>" unless
      ((ok.all_headers("P-Associated-URI").include? "#{ep1.uri}") or (ok.all_headers("P-Associated-URI").include? "<#{ep1.uri}>"))
    fail "200 OK for #{ep1.uri} does not include <#{ep2.uri}>" unless
      ((ok.all_headers("P-Associated-URI").include? "#{ep2.uri}") or (ok.all_headers("P-Associated-URI").include? "<#{ep2.uri}>"))
    fail "200 OK for #{ep2.uri} does not include <#{ep1.uri}>" unless
      ((ok2.all_headers("P-Associated-URI").include? "#{ep1.uri}") or (ok2.all_headers("P-Associated-URI").include? "<#{ep1.uri}>"))
    fail "200 OK for #{ep2.uri} does not include <#{ep2.uri}>" unless
      ((ok2.all_headers("P-Associated-URI").include? "#{ep2.uri}") or (ok2.all_headers("P-Associated-URI").include? "<#{ep2.uri}>"))
  end

  t.add_quaff_cleanup do
    ep1.unregister
    ep2.unregister
  end
end
