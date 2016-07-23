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

def validate_notify xml_s, schema_file="schemas/reginfo.xsd"
  xsd = Nokogiri::XML::Schema(File.read(schema_file))
  reginfo_xml = Nokogiri::XML.parse(xml_s)
  errors = false
  xsd.validate(reginfo_xml).each do |error|
    puts error.message
    errors = true
  end
  if errors
    fail "Could not validate XML against #{schema_file} - see above errors. XML was:\n\n#{xml_s}"
  end
end

TestDefinition.new("SUBSCRIBE - reg-event") do |t|
  ep1 = t.add_endpoint

  t.add_quaff_setup do
    ep1.register
  end

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)

    call.send_request("SUBSCRIBE", "", {"Event" => "reg"})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify1 = call.recv_200_and_notify

    call.send_response("200", "OK")

    ep1.register # Re-registration

    notify2 = call.recv_request("NOTIFY")
    call.send_response("200", "OK")

    call.update_branch
    call.send_request("SUBSCRIBE", "", {"Event" => "reg", "From" => notify1.headers['To'], "To" => notify1.headers['From'], "Expires" => 0})

    notify3 = call.recv_200_and_notify

    call.send_response("200", "OK")

    ep1.register # Re-registration

    call.end_call
    fail "NOTIFY responses have invalid CSeq! (same or non-incrementing)" if notify2.header('CSeq') >= notify3.header('CSeq')
    validate_notify notify1.body
    validate_notify notify2.body
    validate_notify notify3.body

    fail "Final Subscription-State header not set to terminated" if notify3.header('Subscription-State') != "terminated;reason=timeout"

  end

  t.add_quaff_cleanup do
    ep1.unregister
  end

end

TestDefinition.new("SUBSCRIBE - reg-event with a GRUU") do |t|
  ep1 = t.add_endpoint

  t.add_quaff_setup do
    ep1.register
  end

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)

    call.send_request("SUBSCRIBE", "", {"Event" => "reg"})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify = call.recv_200_and_notify

    call.send_response("200", "OK")
    validate_notify notify.body

    xmldoc = Nokogiri::XML.parse(notify.body) do |config|
      config.noblanks
    end

    fail "Binding 1 has no pub-gruu node" unless (xmldoc.child.child.children[0].children[1].name == "pub-gruu")
    fail "Binding 1 has an incorrect pub-gruu node (expected #{ep1.expected_pub_gruu}):\n#{notify.body}" unless (xmldoc.child.child.children[0].children[1]['uri'] == ep1.expected_pub_gruu)
    validate_notify xmldoc.child.child.children[0].children[1].dup.to_s, "schemas/gruuinfo.xsd"
  end

  t.add_quaff_cleanup do
    ep1.unregister
  end


end

# Test that subscriptions are actively timed out on expiry
TestDefinition.new("SUBSCRIBE - Subscription timeout") do |t|
  ep1 = t.add_endpoint

  t.add_quaff_setup do
    ep1.register
  end

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)

    # Set the subscription to expire shortly, sleep until it is nearly expired, then expect a NOTIFY
    call.send_request("SUBSCRIBE", "", {"Event" => "reg", "Expires" => 3})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify1 = call.recv_200_and_notify
    call.send_response("200", "OK")

    sleep 2.5
    notify2 = call.recv_request("NOTIFY")
    call.send_response("200", "OK")

    call.end_call

    # Validate NOTIFYs are correctly formed
    fail "NOTIFY responses have invalid CSeq! (same or non-incrementing)" if notify1.header('CSeq') >= notify2.header('CSeq')

    validate_notify notify1.body
    validate_notify notify2.body

    # Validate that the first NOTIFY was sent as active with the correct expiry
    fail "Subscription-State header not indicating active; expiry=x" if notify1.header('Subscription-State') != "active;expires=3"
 
    # Validate that the final NOTIFY was sent due to subscription expiry
    fail "Final Subscription-State header not set to terminated" if notify2.header('Subscription-State') != "terminated;reason=timeout"
  end

  t.add_quaff_cleanup do
    ep1.unregister
  end

end

# Test that registrations are actively timed out on expiry
TestDefinition.new("SUBSCRIBE - Registration timeout") do |t|
  ep1 = t.add_endpoint
  ep2 = t.add_public_identity(ep1)

  t.add_quaff_setup do
    ep2.register
  end

  t.add_quaff_scenario do
    call = ep1.outgoing_call(ep1.uri)

    call.send_request("REGISTER", "", { "Expires" => "3600", "Authorization" => %Q!Digest username="#{ep1.private_id}"! })
    response_data = call.recv_response("401")
    auth_hdr = Quaff::Auth.gen_auth_header response_data.header("WWW-Authenticate"), ep1.private_id, ep1.password, "REGISTER", ep1.uri
    call.update_branch

    # If testing against something with a min-expires set for registers, alter the 'Expires'
    # value below to be just above it, and the sleep value below this to be just less than it
    # i.e. if min-expires is set to 300, set Expires => 301, and sleep 295
    #
    # If the min-expires value is longer than 60 seconds, also change t.join(60) in lib/test-definition
    # to be longer than the expires header in the REGISTER sent here.
    call.send_request("REGISTER", "", {"Authorization" => auth_hdr, "Expires" => "3"})
    response_data = call.recv_response("200")

    sub = ep2.outgoing_call(ep1.uri)
    sub.send_request("SUBSCRIBE", "", {"Event" => "reg"})
    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify1 = sub.recv_200_and_notify
    sub.send_response("200", "OK")

    sleep 2.5

    notify2 = sub.recv_request("NOTIFY")
    sub.send_response("200", "OK")

    sub.end_call
    call.end_call

    # Validate NOTIFYs are correctly formed
    if notify1.header('CSeq') >= notify2.header('CSeq')
      fail "NOTIFY responses have same or non-incrementing CSeq - \
first one had '#{notify1.header('CSeq')}', second one had '#{notify2.header('CSeq')}'"
    end

    validate_notify notify1.body
    validate_notify notify2.body

    # Validate that the NOTIFY body indicates is was triggered by the registration expiring
    xmldoc = Nokogiri::XML.parse(notify2.body) do |config|
      config.noblanks
    end

    fail "NOTIFY does not indicate register has expired" unless (xmldoc.child.child.children[0]['event'] == "expired")
  end

  t.add_quaff_cleanup do
    # Keeping the unregister here as cleanup. If the register does not timeout correctly, 
    # we want to remove it, rather than have it affect later tests. This may also fail, as
    # without the register expiring, the subscription will remain active, and this will
    # trigger an unexpected NOTIFY
    ep1.unregister
    ep2.unregister
  end

end
