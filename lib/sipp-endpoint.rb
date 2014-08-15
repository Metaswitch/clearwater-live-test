# @file sipp-endpoint.rb
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

require 'rest_client'
require 'json'
require 'erubis'
require 'cgi'
require_relative 'ellis-endpoint'

class SIPpEndpoint
  extend Forwarder
  forward_all :username, :password, :sip_uri, :domain, :private_id, :pstn, :transport, :set_simservs, :set_ifc, :cleanup, :element_type, :instance_id, to: :provisioner
  attr_reader :provisioner

  def initialize(provisioner)
    @provisioner = provisioner
  end

  def send(message, options={})
    SIPpPhase.new(message, self, options)
  end

  def recv(message, options={})
    if (Integer(message) rescue false)
      SIPpPhase.new("__receive_response", self, options.merge(response: message))
    else
      SIPpPhase.new("__receive_request", self, options.merge(request: message))
    end
  end

  def play(audio, length, options={})
    SIPpPhase.new("__play_audio", self, options.merge(audio: audio, track_length: length))
  end

  def register(auth_reqd = true)
    label_id = TestDefinition.get_next_label_id
    register_flow = []
    if auth_reqd
      register_flow << send("REGISTER")
      if @provisioner.transport == :tcp
        register_flow << recv("401", save_auth: true)
      elsif @provisioner.transport == :udp
        # In some situations, bono will allow a message through if the IP, port
        # and username match a recent REGISTER.  Since ellis allocates numbers
        # pretty deterministically, this happens quite often.
        register_flow << recv("200", optional: true, next_label: label_id, save_nat_ip: true)
        register_flow << recv("401", save_auth: true)
      else
        throw "Unrecognized transport #{@provisioner.transport}"
      end
      register_flow << send("REGISTER", auth_header: true)
    else
      register_flow << send("REGISTER")
    end
    register_flow << recv("200", save_nat_ip: true)
    register_flow << SIPpPhase.new("__label", self, label_value: label_id)

    # ReREGISTER with NAT address in the Contact header
    label_id = TestDefinition.get_next_label_id
    register_flow << send("REGISTER", nat_contact_header: true)
    register_flow << recv("200", optional: true, next_label: label_id)
    register_flow << recv("401", save_auth: true)
    register_flow << send("REGISTER", nat_contact_header: true, auth_header: true)
    register_flow << recv("200")
    register_flow << SIPpPhase.new("__label", self, label_value: label_id)
    register_flow
  end

  def unregister
    [
      send("REGISTER", expires: 0),
      recv("200")
    ]
  end

end
