# @file memento.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2014  Metaswitch Networks Ltd
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
require 'quaff'
require_relative '../memento-client'

ANONYMOUS_URI="Anonymous"
MEMENTO_SIP_URI="#{ENV['MEMENTO_SIP']}:5054;transport=tcp"
MEMENTO_HTTP_URI="#{ENV['MEMENTO_HTTP']}"
SCHEMA="schemas/memento-schema.rng"

# Set iFCs for memento and mmtel
def set_memento_ifcs endpoint, deployment
  endpoint.set_ifc [{server_name: MEMENTO_SIP_URI, priority: 0, session_case: 0},
                    {server_name: "mmtel.#{deployment}", priority: 1, session_case: 0},
                    {server_name: "mmtel.#{deployment}", priority: 2, session_case: 1},
                    {server_name: MEMENTO_SIP_URI, priority: 3, session_case: 1}]
end

# Retrieve the last call record from the call list
def check_users_call_list user, from, to, answered, caller_id = 0
  # Find the most recent call
  client = Memento::Client.new SCHEMA, MEMENTO_HTTP_URI, user.sip_uri, user.private_id, user.password
  call_list = client.get_call_list

  fail "No calls in call record - original XML was:\n#{call_list.original_xml}" if call_list.empty?

  call = call_list[-1]

  # Determine whether the call was incoming or outgoing
  outgoing = (user == from)

  # Check some fields are as expected. First the From URI.
  if caller_id == ANONYMOUS_URI
    fail "Call record doesn't contain anonmyised from\n#{call.xml}" unless call.from_uri == "sip:anonymous@anonymous.invalid"
  else
    fail "Call record contains wrong from_uri; found: #{call.from_uri}, expected: #{from.sip_uri}\n#{call.xml}" unless call.from_uri == from.sip_uri
  end

  # From name
  if !outgoing
    fail "Call record contains wrong from_name; found: #{call.from_name}, expected: #{caller_id}\n#{call.xml}" unless call.from_name == caller_id
  end

  # To URI
  fail "Call record contains wrong to_uri; found: #{call.to_uri}, expected: #{to.sip_uri}\n#{call.xml}" unless call.to_uri == to.sip_uri

  # Was the call answered?
  fail "Call record has not correctly recorded whether or not the call was answered\n#{call.xml}" unless call.answered == answered

  # Call direction
  fail "Call record has recorded wrong call direction\n#{call.xml}" unless call.outgoing == outgoing
end

# Retrieve the user's call list and check there are no calls
# recorded from the specified caller_id
def check_no_call_list_entry user, caller_id
  client = Memento::Client.new SCHEMA, MEMENTO_HTTP_URI, user.sip_uri, user.private_id, user.password
  call_list = client.get_call_list
  call_list.each { |call| fail "Unexpected call list entry" if call.from_name == caller_id }
end

# Test trying to retrieve a call list with an incorrect password
TestDefinition.new("Memento - Incorrect Password") do |t|
  t.skip_unless_memento

  user = t.add_endpoint

  # Attempt to access the call list with the wrong password. Expect a 403.
  client = Memento::Client.new SCHEMA, MEMENTO_HTTP_URI, user.sip_uri, user.private_id, "Wrong password"
  call_list = client.get_call_list(rc=403)
end

# Test trying to retrieve someone else's call list
TestDefinition.new("Memento - Wrong Call List") do |t|
  t.skip_unless_memento

  user1 = t.add_endpoint
  user2 = t.add_endpoint

  # As user2, attempt to access user1's call list. Expect a 404.
  client = Memento::Client.new SCHEMA, MEMENTO_HTTP_URI, user1.sip_uri, user2.private_id, user2.password
  call_list = client.get_call_list(rc=404)
end

# Test basic call
TestDefinition.new("Memento - Basic Call") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee, t.deployment

  # Make a call
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("180")

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=true)
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_response("200", "OK")
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call

    check_users_call_list(user=callee, from=caller, to=callee, answered=true, caller_id=random_caller_id)
  end
end

# Test call to unknown number
TestDefinition.new("Memento - Unknown Number") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_cleanup do
    caller.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment

  # Make a call to an unknown number
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("480")
    call.send_request("ACK")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=false)
    check_no_call_list_entry(user=callee, caller_id=random_caller_id)
  end
end

# Test rejected call
TestDefinition.new("Memento - Rejected Call") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee, t.deployment

  # Make a call which is rejected by the remote endpoint
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")

    call.recv_response("486")
    call.send_request("ACK")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=false)
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("486", "Busy Here")
    call2.recv_request("ACK")
    call2.end_call

    check_users_call_list(user=callee, from=caller, to=callee, answered=false, caller_id=random_caller_id)
  end
end

# Test cancelled call
TestDefinition.new("Memento - Cancelled Call") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee, t.deployment

  # Make a call which is cancelled by the caller
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("180")

    # New transaction, but CANCELs share the original branch parameter
    call.send_request("CANCEL")
    call.recv_response("200")

    call.recv_response("487")
    call.send_request("ACK")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=false)
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    original_invite = call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")

    call2.recv_request("CANCEL")
    call2.send_response("200", "OK")

    # Use assoc_with_msg to make the CSeq of the 487 follow the INVITE, not the CANCEL
    call2.assoc_with_msg(original_invite)

    call2.send_response("487", "Cancelled")
    call2.recv_request("ACK")

    call2.end_call

    check_users_call_list(user=callee, from=caller, to=callee, answered=false, caller_id=random_caller_id)
  end
end

# Test basic call with privacy turned on
TestDefinition.new("Memento - Privacy Call") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee, t.deployment

  caller.set_simservs oip: { active: true },
                      oir: { active: true,
                             restricted: true
                           }

  # Make a call
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("180")

    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=true)
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call

    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_response("200", "OK")
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call

    check_users_call_list(user=callee, from=caller, to=callee, answered=true, caller_id=ANONYMOUS_URI)
  end
end

# Test barred call
TestDefinition.new("Memento - Barred Call") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee, t.deployment

  caller.set_simservs ocb: { active: true,
                             rules: [ { conditions: [],
                                        allow: false } ]
                           }

  # Make a call which is rejected by the remote endpoint
  t.add_quaff_scenario do
    call = caller.outgoing_call(callee.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("603")
    call.send_request("ACK")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee, answered=false)
    check_no_call_list_entry(user=callee, caller_id=random_caller_id)
  end
end

# Test call which is busy call forwarded
TestDefinition.new("Memento - Busy Call Forwarding") do |t|
  t.skip_unless_memento

  caller = t.add_endpoint
  callee1 = t.add_endpoint
  callee2 = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
    callee1.register
    callee2.register
  end

  t.add_quaff_cleanup do
    caller.unregister
    callee1.register
    callee2.unregister
  end

  # Set iFCs
  set_memento_ifcs caller, t.deployment
  set_memento_ifcs callee1, t.deployment
  set_memento_ifcs callee2, t.deployment

  callee1.set_simservs cdiv: { active: true,
                               rules: [ { conditions: ["busy"],
                                          target: callee2.uri } ]
                             }

  t.add_quaff_scenario do
    call = caller.outgoing_call(callee1.uri)

    # Manipulate the From header by adding a random string as
    # the name of the caller. This will only show up in the callee's
    # call record, but will help us to identify the correct call
    # records.
    call.send_request("INVITE", "", {"From" => "#{random_caller_id} <#{caller.sip_uri}>;tag=" + SecureRandom::hex})
    call.recv_response("100")
    call.recv_response("181")

    # Call is diverted to callee2
    call.recv_response("180")
    call.recv_response_and_create_dialog("200")

    call.new_transaction
    call.send_request("ACK")
    sleep 1

    call.new_transaction
    call.send_request("BYE")
    call.recv_response("200")
    call.end_call

    check_users_call_list(user=caller, from=caller, to=callee1, answered=true)
  end

  t.add_quaff_scenario do
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("486", "Busy Here")
    call1.recv_request("ACK")

    call1.end_call

    check_users_call_list(user=callee1, from=caller, to=callee1, answered=false, caller_id=random_caller_id)
  end

  t.add_quaff_scenario do
    call2 = callee2.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("180", "Ringing")
    call2.send_response("200", "OK")
    call2.recv_request("ACK")

    call2.recv_request("BYE")
    call2.send_response("200", "OK")
    call2.end_call

    check_users_call_list(user=callee2, from=caller, to=callee2, answered=true, caller_id=random_caller_id)
  end
end
