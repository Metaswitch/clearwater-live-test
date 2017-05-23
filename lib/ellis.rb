# @file ellis-endpoint.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

require 'rest_client'
require 'json'
require 'erubis'
require 'cgi'

EMAIL = ENV['ELLIS_USER'] || "live.tests@example.com"

class EllisProvisionedLine
  attr_reader :username,
              :password,
              :sip_uri,
              :domain,
              :private_id,
              :pstn,
              :transport

  def self.destroy_leaked_numbers(domain)

    r = RestClient.post(ellis_url(domain, "session"),
                        email: EMAIL,
                        password: "Please enter your details")
    cookie = r.cookies
    begin
      r = RestClient::Request.execute(method: :get,
                                      url: ellis_url(domain, "accounts/#{EMAIL}/numbers"),
                                      cookies: cookie)
    rescue RestClient::Exception => e
      puts "Listing existing numbers failed with HTTP code #{e.http_code}"
      begin
        j = JSON.parse(e.http_body)
        puts "Detailed error output: #{j['detail']}"
      rescue
        # Just ignore errors here
      end
      return
    end
    j = JSON.parse(r)

    # Destroy default SIP URIs last
    default_numbers = j["numbers"].select { |n| is_default_public_id? n }
    ordered_numbers = (j["numbers"] - default_numbers) + default_numbers
    ordered_numbers.each do |n|
      begin
        puts "Deleting leaked number: #{n["sip_uri"]}"
        RestClient::Request.execute(method: :delete,
                                    url: ellis_url(domain, "accounts/#{EMAIL}/numbers/#{CGI.escape(n["sip_uri"])}/"),
                                    cookies: cookie)
      rescue
        puts "Failed to delete leaked number, check Ellis logs"
        next
      end
    end
  end

  def initialize(deployment, pstn = false, shared_identity = nil, specific_id = nil)
    @domain = deployment
    @pstn = pstn
    @@security_cookie ||= get_security_cookie
    if specific_id
      get_specific_number(specific_id)
    elsif shared_identity.nil?
      get_number(pstn, nil)
    else
      get_number(pstn, shared_identity.private_id)
      @password = shared_identity.password
    end
    verify!
  end

  def self.specific_line user_part, deployment
    EllisProvisionedLine.new deployment, false, nil, user_part
  end

  def self.new_pstn_line deployment
    EllisProvisionedLine.new deployment, true
  end

  def self.associated_public_identity ep
    EllisProvisionedLine.new ep.domain, ep.pstn, ep
  end

  def cleanup
    delete_number
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
      url: ellis_url("accounts/#{account_email}/numbers/#{CGI.escape(@sip_uri)}/simservs"),
      cookies: @@security_cookie,
      payload: simservs
    )
  end

  def set_ifc(options=[{}], template="ifcs.xml.erb")
    options.map! { |o| default_ifcs.merge(o) }
    erb_src = File.read(File.join(File.dirname(__FILE__),
                                  "..",
                                  "templates",
                                  template))
    erb = Erubis::Eruby.new(erb_src)
    ifcs = erb.result(ifcs: options)

    RestClient::Request.execute(
      method: :put,
      url: ellis_url("accounts/#{account_email}/numbers/#{CGI.escape(@sip_uri)}/ifcs"),
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

  def self.ellis_url domain, path
    if ENV['ELLIS']
      "http://#{ENV['ELLIS']}/#{path}"
    else
      "http://ellis.#{domain}/#{path}"
    end
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
                          email: account_email,
                          password: account_password)
      r.cookies
    rescue StandardError
      # This is most likely caused by the live test user not existing.  Create it now and retry.
      RestClient.post(ellis_url("accounts"),
                      password: account_password,
                      full_name: "clearwater-live-test user",
                      email: account_email,
                      signup_code: ENV['SIGNUP_CODE'] )
      get_security_cookie
    end
  end

  def setup_vars_from_json json
    @username = json["sip_username"]
    @password = json["sip_password"] unless json["sip_password"].nil?
    @sip_uri = json["sip_uri"]
    @private_id = json["private_id"]
  end

  def get_number(pstn, private_id)
    fail "Cannot create more than one number per SIP endpoint" if not @username.nil?

    payload = { pstn: pstn }
    payload.merge!(private_id: private_id) unless private_id.nil?
    begin
      r = RestClient::Request.execute(method: :post,
                                      url: ellis_url("accounts/#{account_email}/numbers/"),
                                      cookies: @@security_cookie,
                                      payload: payload)
    rescue RestClient::Exception => e
      fail "Account creation failed with HTTP code #{e.http_code}, body #{e.http_body}"
    end
    setup_vars_from_json JSON.parse(r.body)
  end

  def get_specific_number(public_id)
    fail "Cannot create more than one number per SIP endpoint" if not @username.nil?

    r = RestClient::Request.execute(method: :post,
                                    url: ellis_url("accounts/#{account_email}/numbers/sip:#{public_id}@#{@domain}"),
                                    cookies: @@security_cookie,
                                    payload: {},
                                    headers: {"NGV-API-Key" => ENV['ELLIS_API_KEY']})
    setup_vars_from_json JSON.parse(r.body)
  end

  def delete_number
    return if @sip_uri.nil?
    begin
      RestClient::Request.execute(
        method: :delete,
        url: ellis_url("accounts/#{account_email}/numbers/#{CGI.escape(@sip_uri)}"),
        cookies: @@security_cookie,
      ) do |rsp, req, result, &blk|
        puts "Leaked #{@sip_uri}, DELETE returned #{rsp.code}" if rsp.code != 200
      end
    rescue RestClient::Exception => e
      fail "Account deletion of #{@sip_uri} failed with HTTP code #{e.http_code}, body #{e.http_body}"
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
    EllisProvisionedLine.ellis_url @domain, path
  end

  def account_email
    EMAIL
  end

  def account_password
    "Please enter your details"
  end
end
