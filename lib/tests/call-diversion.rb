# @file call-diversion.rb
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

TestDefinition.new("Call Diversion - Not registered") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint
  sip_callee2 = t.add_sip_endpoint

  sip_callee1.set_simservs cdiv: { active: true,
                                  rules: [ { conditions: ["not-registered"],
                                             target: sip_callee2.sip_uri } ]
                                }
  t.set_scenario(
    sip_caller.register +
    sip_callee2.register +
    [
      sip_caller.send("INVITE", target: sip_callee1),
      sip_caller.recv("100"),
      sip_caller.recv("181"),
      sip_callee2.recv("INVITE", extract_uas_via: true),
      sip_callee2.send("100", target: sip_caller, method: "INVITE"),
      sip_callee2.send("180", target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_callee2.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("ACK"),
      SIPpPhase.new("pause", nil, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("BYE", extract_uas_via: true),
      sip_callee2.send("200", target: sip_caller, method: "BYE"),
      sip_caller.recv("200"),
    ] +
    sip_caller.unregister +
    sip_callee2.unregister
  )
end

TestDefinition.new("Call Diversion - Busy") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint
  sip_callee2 = t.add_sip_endpoint

  sip_callee1.set_simservs cdiv: { active: true,
                                  rules: [ { conditions: ["busy"],
                                             target: sip_callee2.sip_uri } ]
                                }
  t.set_scenario(
    sip_caller.register +
    sip_callee1.register +
    sip_callee2.register +
    [
      sip_caller.send("INVITE", target: sip_callee1),
      sip_caller.recv("100"),
      sip_callee1.recv("INVITE", extract_uas_via: true),
      sip_callee1.send("100", target: sip_caller, method: "INVITE"),
      sip_callee1.send("486", target: sip_caller, method: "INVITE"),
      sip_callee1.recv("ACK"),
      sip_caller.recv("181"),
      sip_callee2.recv("INVITE", extract_uas_via: true),
      sip_callee2.send("100", target: sip_caller, method: "INVITE"),
      sip_callee2.send("180", target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_callee2.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("ACK"),
      SIPpPhase.new("pause", nil, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("BYE", extract_uas_via: true),
      sip_callee2.send("200", target: sip_caller, method: "BYE"),
      sip_caller.recv("200"),
    ] +
    sip_caller.unregister +
    sip_callee1.unregister +
    sip_callee2.unregister
  )
end

TestDefinition.new("Call Diversion - No answer") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint
  sip_callee2 = t.add_sip_endpoint

  sip_callee1.set_simservs cdiv: { active: true,
                                   timeout: "20",
                                  rules: [ { conditions: ["no-answer"],
                                             target: sip_callee2.sip_uri } ]
                                }
  t.set_scenario(
    sip_caller.register +
    sip_callee1.register +
    sip_callee2.register +
    [
      sip_caller.send("INVITE", target: sip_callee1),
      sip_caller.recv("100"),
      sip_callee1.recv("INVITE", extract_uas_via: true),
      sip_callee1.send("100", target: sip_caller, method: "INVITE"),
      sip_callee1.send("180", target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_callee1.send("408", target: sip_caller, method: "INVITE"),
      sip_callee1.recv("ACK"),
      sip_caller.recv("181"),
      sip_callee2.recv("INVITE", extract_uas_via: true),
      sip_callee2.send("100", target: sip_caller, method: "INVITE"),
      sip_callee2.send("180", target: sip_caller, method: "INVITE"),
      sip_caller.recv("180"),
      sip_callee2.send("200-SDP", target: sip_caller, method: "INVITE"),
      sip_caller.recv("200", rrs: true),
      sip_caller.send("ACK", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("ACK"),
      SIPpPhase.new("pause", nil, timeout: 1000),
      sip_caller.send("BYE", target: sip_callee2, in_dialog: true),
      sip_callee2.recv("BYE", extract_uas_via: true),
      sip_callee2.send("200", target: sip_caller, method: "BYE"),
      sip_caller.recv("200"),
    ] +
    sip_caller.unregister +
    sip_callee1.unregister +
    sip_callee2.unregister
  )
end
TestDefinition.new("Call Diversion - Bad target URI") do |t|
  sip_caller = t.add_sip_endpoint
  sip_callee1 = t.add_sip_endpoint

  sip_callee1.set_simservs cdiv: { active: true,
                                  rules: [ { conditions: ["not-registered"],
                                             target: "12345" } ]
                                }
  t.set_scenario(
    sip_caller.register +
    [ 
      sip_caller.send("INVITE", target: sip_callee1),
      sip_caller.recv("100"),
      sip_caller.recv("404"),
      sip_caller.send("ACK", target: sip_callee1),
    ] +
    sip_caller.unregister
  )
end
