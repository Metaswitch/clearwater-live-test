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

    call.send_request("SUBSCRIBE", headers: {"Event" => "reg"})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify1 = call.recv_200_and_notify

    call.send_response("200", "OK")

    ep1.register # Re-registration

    notify2 = call.recv_request("NOTIFY")
    call.send_response("200", "OK")

    call.send_request("SUBSCRIBE", headers: {"Event" => "reg", "Expires" => 0})

    notify3 = call.recv_200_and_notify

    call.send_response("200", "OK")

    ep1.register # Re-registration

    call.end_call
    fail "NOTIFY responses have the same CSeq!" if notify2.header('CSeq') == notify3.header('CSeq')
    validate_notify notify1.body
    validate_notify notify2.body
    validate_notify notify3.body
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

    call.send_request("SUBSCRIBE", headers: {"Event" => "reg"})

    # 200 and NOTIFY can come in any order, so expect either of them, twice
    notify = call.recv_200_and_notify

    call.send_response("200", "OK")
    validate_notify notify.body

    xmldoc = Nokogiri::XML.parse(notify.body) do |config|
      config.noblanks
    end

    fail "Binding 1 has no pub-gruu node" unless (xmldoc.child.child.children[0].children[1].name == "pub-gruu")
    fail "Binding 1 has an incorrect pub-gruu node" unless (xmldoc.child.child.children[0].children[1]['uri'] == ep1.expected_pub_gruu)
    validate_notify xmldoc.child.child.children[0].children[1].dup.to_s, "schemas/gruuinfo.xsd"
  end

  t.add_quaff_cleanup do
    ep1.unregister
  end


end

