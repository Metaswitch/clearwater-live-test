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

class SIPpEndpoint
  attr_accessor :username, :password, :sip_uri, :domain

  def initialize(pstn, deployment, transport)
    @domain = deployment
    @transport = transport
    @@security_cookie ||= get_security_cookie
    get_number(pstn)
  end
  
  def element_type
    :endpoint
  end

  def cleanup
    delete_number
    @sip_uri = nil
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

  def register
    label_id = TestDefinition.get_next_label_id
    register_flow = []
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
    register_flow << recv("200", save_nat_ip: true)
    register_flow << SIPpPhase.new("__label", self, label_value: label_id)
    register_flow
  end

  def unregister
    [
      send("REGISTER", expires: 0),
      recv("200")
    ]
  end

  def set_simservs(options={})
    options = default_simservs.merge(options)
    erb_src = File.read(File.join(File.dirname(__FILE__),
                                  "..",
                                  "templates",
                                  "simservs.xml.erb"))
    erb = Erubis::Eruby.new(erb_src)
    simservs = erb.result(options)

    RestClient::Request.execute(
      method: :put,
      url: ellis_url("accounts/#{account_username}/numbers/#{CGI.escape(@sip_uri)}/simservs"),
      cookies: @@security_cookie,
      payload: simservs
    )
  end

  def default_simservs
    { oip: { active: true },
      oir: { active: true,
             restricted: false },
      cdiv: { active: false,
              rules: [] },
      ocb: { active: false,
             rules: [] },
      icb: { active: false,
             rules: [] } }
  end

  def set_ifc(options={})
    options = default_ifcs.merge(options)
    erb_src = File.read(File.join(File.dirname(__FILE__),
                                  "..",
                                  "templates",
                                  "ifcs.xml.erb"))
    erb = Erubis::Eruby.new(erb_src)
    ifcs = erb.result(options)

    RestClient::Request.execute(
      method: :put,
      url: ellis_url("accounts/#{account_username}/numbers/#{CGI.escape(@sip_uri)}/ifcs"),
      cookies: @@security_cookie,
      payload: ifcs
    )
  end
  
  def default_ifcs
    {
    }
  end
    
private

  def get_security_cookie
    begin
      r = RestClient.post(ellis_url("session"),
                          username: account_username,
                          password: account_password)
      r.cookies
    rescue StandardError
      # This is most likely caused by the System Test user not existing.  Create it now and retry.
      RestClient.post(ellis_url("accounts"),
                      username: "System Test",
                      password: account_password,
                      full_name: "System Test",
                      email: account_username,
                      signup_code: ENV['SIGNUP_CODE'] )
      get_security_cookie
    end
  end

  def get_number(pstn)
    fail "Cannot create more than one number per SIP endpoint" if not @username.nil?

    r = RestClient::Request.execute(method: :post,
                                    url: ellis_url("accounts/#{account_username}/numbers/"),
                                    cookies: @@security_cookie,
                                    payload: { pstn: pstn } )
    r = JSON.parse(r.body)
    @username = r["sip_username"]
    @password = r["sip_password"]
    @sip_uri = r["sip_uri"]
  end

  def delete_number
    return if @sip_uri.nil?
    RestClient::Request.execute(
      method: :delete,
      url: ellis_url("accounts/#{account_username}/numbers/#{CGI.escape(@sip_uri)}"),
      cookies: @@security_cookie,
    ) do |rsp, req, result, &blk|
      puts "Leaked #{@sip_uri}, DELETE returned #{rsp.code}" if rsp.code != 200
    end
  end

  def ellis_url path
    "http://ellis.#{@domain}/#{path}"
  end

  def account_username
    "system.test@#{@domain}"
  end

  def account_password
    "Please enter your details"
  end
end
