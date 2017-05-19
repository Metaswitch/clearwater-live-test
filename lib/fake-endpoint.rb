# @file fake-endpoint.rb
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

class FakeEndpoint
  attr_accessor :username, :domain, :sip_uri

  def initialize(username, domain)
    @username = username
    @domain = domain
    @sip_uri = "sip:#{username}@#{domain}"
  end
  
  def element_type
    :endpoint
  end

  def register
    []
  end

  def unregister
    []
  end

  def cleanup
  end
end
