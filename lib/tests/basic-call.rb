# @file basic-call.rb
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

TestDefinition.new("Basic Call - Mainline") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint
  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_callee.recv("INVITE", extract_uas_via: true, check_trusted: true, trusted_present: false),
      sip_callee.send("100", target: sip_caller, method: "INVITE"),
      sip_callee.send("180", target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_callee.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee, in_dialog: true),
      sip_callee.recv("ACK"),
      SIPpPhase.new("pause", sip_caller, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee, in_dialog: true),
      sip_callee.recv("BYE", extract_uas_via: true),
      sip_callee.send("200", target: sip_caller, method: "BYE", emit_trusted: true),
      sip_caller.recv("200", check_trusted: true, trusted_present: false),
  ] +
  sip_caller.unregister +
  sip_callee.unregister
  )
end

TestDefinition.new("Basic Call - Unknown number") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint

  # We test this by not registering the callee.
  t.set_scenario(
    sip_caller.register +
    [
      sip_caller.send("INVITE", target: sip_callee),
      sip_caller.recv("100"),
      sip_caller.recv("404"),
      sip_caller.send("ACK", target: sip_callee),
    ] +
    sip_caller.unregister
  )
end

TestDefinition.new("Basic Call - Rejected by remote endpoint") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint

  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("INVITE", target: sip_callee),
      sip_caller.recv("100"),
      sip_callee.recv("INVITE", extract_uas_via: true),
      sip_callee.send("100", target: sip_caller, method: "INVITE"),
      sip_callee.send("486", target: sip_caller, method: "INVITE"),
      # The following two packets normally arrive in this order, there's a chance that one could be
      # held up and arrive later.  In this case, the test will fail artificially.
      sip_callee.recv("ACK"),
      sip_caller.recv("486"),
      sip_caller.send("ACK", target: sip_callee),
    ] +
    sip_caller.unregister +
    sip_callee.unregister
  )
end

TestDefinition.new("Basic Call - Pracks") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint
  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("INVITE", target: sip_callee, emit_trusted: true),
      sip_caller.recv("100"),
      sip_callee.recv("INVITE", extract_uas_via: true, check_trusted: true, trusted_present: false),
      sip_callee.send("100", target: sip_caller, method: "INVITE"),
      sip_callee.send("180", prack_expected: true, target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_caller.send("PRACK", target: sip_callee),
      sip_callee.recv("PRACK", extract_second_via: true),
      sip_callee.send("200", second_transaction: true, target: sip_caller, method: "PRACK"),
      sip_caller.recv("200", target: sip_caller, method: "PRACK"),
      sip_callee.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee, in_dialog: true),
      sip_callee.recv("ACK"),
      SIPpPhase.new("pause", sip_caller, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee, in_dialog: true),
      sip_callee.recv("BYE", extract_uas_via: true),
      sip_callee.send("200", target: sip_caller, method: "BYE", emit_trusted: true),
      sip_caller.recv("200", check_trusted: true, trusted_present: false),
  ] +
  sip_caller.unregister +
  sip_callee.unregister
  )
end

# This test isn't valid for UDP (due to a limitation of sipp running both
# endpoints in the same scenario)
NotValidForUDPTestDefinition.new("Basic Call - Messages - Pager model") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee = t.add_sip_endpoint
  t.set_scenario(
    sip_caller.register +
    sip_callee.register +
    [
      sip_caller.send("MESSAGE", target: sip_callee),
      sip_callee.recv("MESSAGE", extract_uas_via: true),
      sip_callee.send("200", target: sip_caller, method: "MESSAGE"),
      sip_caller.recv("200", target: sip_caller, method: "MESSAGE"),
  ] +
  sip_caller.unregister +
  sip_callee.unregister
  )
end

