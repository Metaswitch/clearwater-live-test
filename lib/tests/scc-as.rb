# @file scc-as.rb
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

# Converts a URI like sip:1234@example.com to tel:1234. Doesn't
# support parameters or non-numeric characters (e.g.
# "sip:+1234;npdi@example.com" won't work).
def sip_to_tel(uri)
  uri =~ /sip:(\d+)@.+/
  "tel:#{$1}"
end

TestDefinition.new("SCC-AS - 4g to 3g failover") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  gcallee = t.add_fake_endpoint('123')

  ringing_barrier = Barrier.new(2)
  call_set_up_barrier = Barrier.new(3)
  handover_complete_barrier = Barrier.new(3)

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    call.send_invite_with_sdp
    call.recv_response("100")
    call.recv_response("180")
    ringing_barrier.wait

    # Save off Contact and routeset
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    call_set_up_barrier.wait

#### DIE and call 3g callee 
    handover_complete_barrier.wait
    
    call.new_transaction
    call.recv_request("BYE")
    call.send_response("200")
    call.end_call
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    ringing_barrier.wait

    call2.send_200_with_sdp
    call2.recv_request("ACK")
    call_set_up_barrier.wait
####
    call2.recv_request("INVITE")

    call2.send_response("200", "OK")
    handover_complete_barrier.wait

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call
  end

  t.add_quaff_scenario do
    gcall = caller.outgoing_call(gcallee.uri)
    call_set_up_barrier.wait

    gcall.send_invite
    gcall.recv_response("200")
    handover_complete_barrier.wait
  end


  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

end
  
