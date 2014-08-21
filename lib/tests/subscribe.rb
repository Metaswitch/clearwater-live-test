# @file subscribe.rb
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

TestDefinition.new("SIP SUBSCRIBE-NOTIFY") do |t|
  t.skip

  ep1 = t.add_endpoint
  t.add_quaff_setup do
    ep1.register
  end

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)

    call.send_request("SUBSCRIBE", "", {"Event" => "reg", "To" => %Q[<#{ep1.uri}>], "From" => %Q[<#{ep1.uri}>;tag=2342342342]})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    call.recv_any_of [200, "NOTIFY"]
    call.recv_any_of [200, "NOTIFY"]

    call.send_response("200", "OK")

    ep1.register # Re-registration

    call.recv_request("NOTIFY")
    call.send_response("200", "OK")

    call.update_branch
    call.send_request("SUBSCRIBE", "", {"Event" => "reg", "To" => %Q[<#{ep1.uri}>;tag=1231231231], "From" => %Q[<#{ep1.uri}>;tag=2342342342], "Expires" => 0})

    call.recv_any_of [200, "NOTIFY"]
    call.recv_any_of [200, "NOTIFY"]

    call.send_response("200", "OK")

    ep1.register # Re-registration

    call.end_call
  end

  t.add_quaff_cleanup do
    ep1.unregister
  end

end
