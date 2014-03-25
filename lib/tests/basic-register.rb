# @file basic-register.rb
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

TestDefinition.new("Basic Registration") do |t|
  caller = t.add_endpoint

  t.add_quaff_scenario do
    call = caller.outgoing_call(caller.uri)
    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q!Digest username="#{caller.private_id}"! })
    response_data = call.recv_response("401")
    auth_hdr = Quaff::Auth.gen_auth_header response_data.header("WWW-Authenticate"), caller.private_id, caller.password, "REGISTER", caller.uri
    call.update_branch
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3600", "CSeq" => "2 REGISTER"})
    response_data = call.recv_response("200")
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Multiple Identities") do |t|
  ep1 = t.add_endpoint
  ep2 = t.add_quaff_public_identity(ep1)

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

    fail "200 OK for #{ep1.uri} does not include <#{ep1.uri}>" unless ok.all_headers("P-Associated-URI").include? "<#{ep1.uri}>"
    fail "200 OK for #{ep1.uri} does not include <#{ep2.uri}>" unless ok.all_headers("P-Associated-URI").include? "<#{ep2.uri}>"
    fail "200 OK for #{ep2.uri} does not include <#{ep1.uri}>" unless ok2.all_headers("P-Associated-URI").include? "<#{ep1.uri}>"
    fail "200 OK for #{ep2.uri} does not include <#{ep2.uri}>" unless ok2.all_headers("P-Associated-URI").include? "<#{ep2.uri}>"
  end

  t.add_quaff_cleanup do
    ep1.unregister
    ep2.unregister
  end
end
