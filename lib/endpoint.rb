# @file endpoint.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'forwarder'

class Endpoint
  extend Forwarder
  forward_all :password, :username, :sip_uri, :domain, :private_id, :pstn, :transport, :set_simservs, :set_ifc, :domain, :instance_id, to: :line_info
  attr_reader :line_info, :transport

  def element_type
    :endpoint
  end

  def initialize(line_info, transport, endpoint_idx)
    @endpoint_idx = endpoint_idx
    @transport = transport
    @line_info = line_info
  end

  # Algorithmically determined from the public identity (using algorithm in RFC4122)
  def instance_id
    return @instance_id if @instance_id

    ary = Digest::SHA1.new.digest(@line_info.sip_uri + @endpoint_idx.to_s).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x5000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    @instance_id = "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end

  def cleanup
    @line_info.cleanup
  end

end
