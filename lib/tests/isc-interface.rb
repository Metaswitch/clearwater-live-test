# @file isc-interface.rb
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

TestDefinition.new("ISC Interface - Redirect") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint
  sip_callee2 = t.add_sip_endpoint
  mock_as = t.add_mock_as

  sip_callee1.set_ifc server_name: "felix.cw-ngv.com:5070"
  
  t.set_scenario(
    sip_caller.register +
    sip_callee1.register +
    sip_callee2.register +
    [
      sip_caller.send("INVITE", target: sip_callee1, emit_trusted: true, call_number: 1),
      sip_caller.recv("100"),
      mock_as.recv("INVITE", extract_uas_via: true, save_remote_ip: true),
      mock_as.send("302", from: sip_caller, to: sip_callee1, redirect_target: sip_callee2, method: "INVITE", call_number: 1),
      sip_caller.recv("302", from: sip_caller, to: sip_callee1, redirect_target: sip_callee2, method: "INVITE", rrs: true),
      sip_caller.send("ACK", target: sip_callee1, in_dialog: true, call_number: 1),
      # Basic call - disabled for now as rrs=true fails the second time it is invoked
      # sip_caller.send("INVITE", target: sip_callee2, emit_trusted: true, call_number: 2),
      # sip_caller.recv("100"),
      # sip_callee2.recv("INVITE", extract_uas_via: true, check_trusted: true, trusted_present: false),
      # sip_callee2.send("100", target: sip_caller, method: "INVITE", call_number: 2),
      # sip_callee2.send("180", target: sip_caller, method: "INVITE", call_number: 2),
      # sip_caller.recv("180"),
      # sip_callee2.send("200-SDP", target: sip_caller, method: "INVITE", call_number: 2),
      # sip_caller.recv("200", rrs: true),
      # sip_caller.send("ACK", target: sip_callee2, in_dialog: true, call_number: 2),
      # sip_callee2.recv("ACK"),
      # SIPpPhase.new("pause", nil, timeout: 1000),
      # sip_caller.send("BYE", target: sip_callee2, in_dialog: true, call_number: 2),
      # sip_callee2.recv("BYE", extract_uas_via: true),
      # sip_callee2.send("200", target: sip_caller, method: "BYE", emit_trusted: true, call_number: 2),
      # sip_caller.recv("200", check_trusted: true, trusted_present: false),
    ] +
    sip_caller.unregister +
    sip_callee1.unregister +
    sip_callee2.unregister
  )
end

