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

# Retrieve the last call record from the call list
def check_call_list_entry caller, callee, outgoing, answered, caller_id = 0, anonymous = false
  if outgoing
    client = Memento::Client.new "schemas/memento-schema.rng", "#{ENV['CALL_LIST']}", caller.sip_uri, caller.private_id, caller.password
    log_string = "Caller's call record"
  else
    client = Memento::Client.new "schemas/memento-schema.rng", "#{ENV['CALL_LIST']}", callee.sip_uri, callee.private_id, callee.password
    log_string = "Callee's call record"
  end

  # Find the most recent call
  call_list = client.get_call_list
  call = call_list[-1]

  # Check some fields
  if anonymous
    fail "#{log_string} doesn't contain anonmyised caller" unless call.from_uri == "sip:anonymous@anonymous.invalid"
  else
    fail "#{log_string} contains wrong from_uri; found: #{call.from_uri}, expected: #{caller.sip_uri}" unless call.from_uri == caller.sip_uri
  end
  if !outgoing
    fail "#{log_string} contains wrong from_name; found: #{call.from_name}, expected: #{caller_id}" unless call.from_name == caller_id
  end
  fail "#{log_string} contains wrong to_uri; found: #{call.to_uri}, expected: #{callee.sip_uri}" unless call.to_uri == callee.sip_uri
  fail "#{log_string} has not correctly recorded whether or not the call was answered" unless call.answered == answered
  fail "#{log_string} has recorded wrong call direction" unless call.outgoing == outgoing
end

# Retrieve the callee's call list and check there are no calls
# recorded from the specified caller_id
def check_no_call_list_entry callee, caller_id
    client = Memento::Client.new "schemas/memento-schema.rng", "#{ENV['CALL_LIST']}", callee.sip_uri, callee.private_id, callee.password
    call_list = client.get_call_list
    call_list.each { |call| fail "Unexpected call list entry" if call.from_name == caller_id }
end

# Test basic call
MementoTestDefinition.new("Memento - Basic Call") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, true
      check_call_list_entry caller, callee, false, true, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end
end

# Test call to unknown number
MementoTestDefinition.new("Memento - Unknown Number") do |t|
  caller = t.add_endpoint
  callee = t.add_endpoint
  random_caller_id = SecureRandom::hex

  t.add_quaff_setup do
    caller.register
  end

  t.add_quaff_cleanup do
    caller.unregister

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, false
      check_no_call_list_entry callee, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end
end

# Test rejected call
MementoTestDefinition.new("Memento - Rejected Call") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, false
      check_call_list_entry caller, callee, false, false, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end

  t.add_quaff_scenario do
    call2 = callee.incoming_call
    call2.recv_request("INVITE")
    call2.send_response("100", "Trying")
    call2.send_response("486", "Busy Here")
    call2.recv_request("ACK")
    call2.end_call
  end
end

# Test cancelled call
MementoTestDefinition.new("Memento - Cancelled Call") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, false
      check_call_list_entry caller, callee, false, false, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end
end

# Test basic call with privacy turned on
MementoTestDefinition.new("Memento - Privacy Call") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, true
      check_call_list_entry caller, callee, false, true, "Anonymous", true
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end
end

# Test barred call
MementoTestDefinition.new("Memento - Barred Call") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee, true, false
      check_no_call_list_entry callee, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end
end

# Test call which is busy call forwarded
MementoTestDefinition.new("Memento - Busy Call Forwarding") do |t|
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

    if ENV['CALL_LIST']
      check_call_list_entry caller, callee1, true, true
      check_call_list_entry caller, callee1, false, false, random_caller_id
      check_call_list_entry caller, callee2, false, true, random_caller_id
    end
  end

  # Set iFCs
  caller.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee1.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"
  callee2.set_memento_ifc memento: "#{ENV['MEMENTO']}:5054;transport=tcp", mmtel: "mmtel.#{t.deployment}"

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
  end

  t.add_quaff_scenario do
    call1 = callee1.incoming_call
    call1.recv_request("INVITE")
    call1.send_response("100", "Trying")
    call1.send_response("486", "Busy Here")
    call1.recv_request("ACK")

    call1.end_call
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
  end
end
