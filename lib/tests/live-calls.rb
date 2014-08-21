# @file live-calls.rb
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

SIPpTestDefinition.new("Live Call - Dial out to a real number") do |t|
  t.skip_unless_live
  t.skip_unless_pstn

  # The live call takes approximately 10 seconds to run so extend the timeout
  # for this test.
  t.timeout = 20

  sip_caller = t.add_pstn_sipp_endpoint
  live_callee = t.add_fake_endpoint(ENV['LIVENUMBER'])

  t.set_scenario(
    sip_caller.register +
    [
      sip_caller.send("INVITE", target: live_callee),
      # Live tests need long timeouts, since the PSTN adds latency and the callee needs to actually pick up.
      sip_caller.recv("100", timeout: 20000),
      sip_caller.recv("183", optional: true, timeout: 20000),
      sip_caller.recv("180", optional: true, timeout: 20000),
      sip_caller.recv("200", timeout: 20000, rrs: true),
      sip_caller.send("ACK", target: live_callee, in_dialog: true),
      sip_caller.play("g711a.pcap", 8000),
      sip_caller.send("BYE", target: live_callee, in_dialog: true),
      sip_caller.recv("200", timeout: 20000),
    ] +
    sip_caller.unregister
  )
end
