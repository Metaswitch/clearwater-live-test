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
require 'quaff'

class QuaffEndpoint < EllisEndpoint
  attr_reader :quaff

  def initialize(pstn, deployment, transport, shared_identity = nil)
    @domain = deployment
    registrar = ENV['PROXY'] || deployment
    @transport = transport
    @pstn = pstn
    @@security_cookie ||= get_security_cookie
    if shared_identity.nil?
      get_number(pstn, nil)
    else
      get_number(pstn, shared_identity.private_id)
      @password = shared_identity.password
    end
    verify!
    listen_port = ENV['LISTENPORT'] || rand(60000) + 1024
    if transport == :tcp then
      @quaff = Quaff::TCPSIPEndpoint.new(@sip_uri,
                                         "#{@username}@#{@domain}",
                                         @password,
                                         listen_port,
                                         registrar)
    else
      @quaff = Quaff::UDPSIPEndpoint.new(@sip_uri,
                                         "#{@username}@#{@domain}",
                                         @password,
                                         listen_port,
                                         registrar)
    end
  end

  def element_type
    :endpoint
  end

  def cleanup
    delete_number
    @quaff.terminate
    @sip_uri = nil
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

  # Algorithmically determined from the public identity (using algorithm in RFC4122)
  def instance_id
    return @instance_id if @instance_id

    ary = Digest::SHA1.new.digest(@sip_uri).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x5000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    @instance_id = "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end

private

  def verify!
    fail "SIP endpoint has no username" if @username.nil?
    fail "SIP endpoint has no password" if @password.nil?
    fail "SIP endpoint has no private_id" if @private_id.nil?
    fail "SIP endpoint has no domain" if @domain.nil?
  end

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

  def get_number(pstn, private_id)
    fail "Cannot create more than one number per SIP endpoint" if not @username.nil?

    payload = { pstn: pstn }
    payload.merge!(private_id: private_id) unless private_id.nil?
    r = RestClient::Request.execute(method: :post,
                                    url: ellis_url("accounts/#{account_username}/numbers/"),
                                    cookies: @@security_cookie,
                                    payload: payload )
    r = JSON.parse(r.body)
    @username = r["sip_username"]
    @password = r["sip_password"] unless r["sip_password"].nil?
    @sip_uri = r["sip_uri"]
    @private_id = r["private_id"]
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

  def default_ifcs
    {}
  end

  def ellis_url path
    if ENV['ELLIS']
      "http://#{ENV['ELLIS']}/#{path}"
    else
      "http://ellis.#{@domain}/#{path}"
    end
  end

  def account_username
    "system.test@#{@domain}"
  end

  def account_password
    "Please enter your details"
  end
end
