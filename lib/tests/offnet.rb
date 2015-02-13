# @file offnet.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2015 Metaswitch Networks Ltd
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


TestDefinition.new("Off-net calls - tel: URI") do |t|
  t.skip_unless_offnet_tel

  caller = t.add_endpoint
  as = t.add_as 5072


  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call("tel:#{ENV['OFF_NET_TEL']}")

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = as.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

TestDefinition.new("Off-net calls - sip: URI") do |t|
  t.skip_unless_offnet_tel

  caller = t.add_endpoint
  as = t.add_as 5072


  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call("sip:#{ENV['OFF_NET_TEL']}@#{t.deployment};user=phone")

    call.send_request("MESSAGE", "hello world\r\n",
                      {"Content-Type" => "text/plain"})
    call.recv_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = as.incoming_call

    call2.recv_request("MESSAGE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

end

