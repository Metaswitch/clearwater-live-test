# @file sipp-endpoint.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'rest_client'
require 'json'
require 'erubis'
require 'cgi'
require 'quaff'
require 'forwarder'
require_relative 'endpoint'
require_relative 'quaff-monkey-patches'

class QuaffEndpoint < Endpoint
  extend Forwarder
  forward_all :incoming_call, :outgoing_call, :terminate, :register, :unregister, :msg_trace, :uri, :sdp_port, :sdp_socket, :msg_log, :local_port, :contact_header, :contact_header=, :no_new_calls?, :add_contact_param, to: :quaff
  attr_reader :quaff

  def initialize(line_info, transport, endpoint_idx, use_instance_id=true)
    super line_info, transport, endpoint_idx
    registrar = ENV['PROXY'] || domain
    registrar_port = (ENV['PROXY_PORT'] || "5060").to_i
    if transport == :tcp then
      @quaff = Quaff::TCPSIPEndpoint.new(sip_uri,
                                         private_id,
                                         password,
                                         :anyport,
                                         registrar,
                                         registrar_port)
    else
      @quaff = Quaff::UDPSIPEndpoint.new(sip_uri,
                                         private_id,
                                         password,
                                         :anyport,
                                         registrar,
                                         registrar_port)
    end

    @quaff.instance_id = instance_id if use_instance_id
  end

  def cleanup
    @quaff.terminate
    super
  end

  def expected_pub_gruu
    "#{sip_uri};gr=urn:uuid:#{instance_id}"
  end

end
