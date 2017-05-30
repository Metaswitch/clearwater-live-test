# @file sipp-endpoint.rb
#
# Copyright (C) Metaswitch Networks 2014
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'rest_client'
require 'json'
require 'erubis'
require 'cgi'
require_relative 'endpoint'

class SIPpEndpoint < Endpoint

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
      if @transport == :tcp
        register_flow << recv("401", save_auth: true)
      elsif @transport == :udp
        # In some situations, bono will allow a message through if the IP, port
        # and username match a recent REGISTER.  Since ellis allocates numbers
        # pretty deterministically, this happens quite often.
        register_flow << recv("200", optional: true, next_label: label_id, save_nat_ip: true)
        register_flow << recv("401", save_auth: true)
      else
        throw "Unrecognized transport #{@transport}"
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
