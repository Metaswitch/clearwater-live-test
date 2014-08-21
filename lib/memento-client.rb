require 'rest_client'
require 'nokogiri'
require 'date'
require 'httpi'

module Memento

  EXPECTED_CONTENT_TYPE = "application/vnd.projectclearwater.call-list+xml"

  class Call
    attr_reader :to_uri, :to_name, :from_uri, :from_name, :answered, :outgoing, :start_time, :answered_time, :end_time

    def initialize xmlnode
      @to_uri = xmlnode.xpath('./to/uri').text
      @to_name = xmlnode.xpath('./to/name').text
      @from_uri = xmlnode.xpath('./from/uri').text
      @from_name = xmlnode.xpath('./from/name').text
      @answered = (xmlnode.xpath('./answered').text == "1") or (xmlnode.xpath('./answered').text == "true")
      @outgoing = (xmlnode.xpath('./outgoing').text == "0") or (xmlnode.xpath('./outgoing').text == "true")
      @start_string = DateTime.parse(xmlnode.xpath('./start-time').text)
      @start_time = DateTime.parse(xmlnode.xpath('./start-time').text).to_time
      @answered_time = DateTime.parse(xmlnode.xpath('./answer-time').text).to_time if @answered
      @end_time = DateTime.parse(xmlnode.xpath('./end-time').text).to_time if @answered
    end

    def ringing_time
      if @answered_time
        @answered_time - @start_time
      else
        0
      end
    end

    def duration
      if @end_time
        @end_time - @answered_time
      else
        0
      end
    end

    def to_s
      if @answered and @outgoing
        "Call to #{to_name} (#{to_uri}) made at #{@start_string} and lasting #{duration}"
      elsif @answered and not @outgoing
        "Call from #{from_name} (#{from_uri}) received at #{@start_string} and lasting #{duration}"
      elsif @outgoing
        "Unanswered call to #{to_name} (#{to_uri}) made at #{@start_string}"
      else
        "Unanswered call from #{from_name} (#{from_uri}) received at #{@start_string}"
      end
    end
  end

  class CallList < Array
    def self.from_xml xmlnode
      call_list = CallList.new
      xmlnode.xpath("//calls/call").each { |call_xml| call_list << Call.new(call_xml) }
      call_list
    end

    def to_s
      if self.empty?
        "No calls"
      else
        self.collect { |call| call.to_s }.join("\n")
      end
    end
  end


  class Client

    def initialize schema_path, memento_server, sip_uri, username, password
      @@schema = Nokogiri::XML::RelaxNG(File.open(schema_path))
      url = "https://#{memento_server}/org.projectclearwater.call-list/users/#{sip_uri}/call-list.xml"
      @request = HTTPI::Request.new(url)
      @request.auth.digest(username, password)
      @request.auth.ssl.verify_mode = :none
    end

    def get_call_list encoding="gzip", debug=false
      @request.headers["Accept-Encoding"] = encoding
      response = HTTPI.get(@request)
      puts response.headers if debug
      puts response.body if debug
      xml = Nokogiri.XML(response.body, nil, nil, Nokogiri::XML::ParseOptions::PEDANTIC)
      fail xml.errors.to_s unless xml.errors.empty?
      fail @@schema.validate(xml).to_s unless @@schema.valid? xml
      fail "Response is not encoded as #{encoding}!" if (response.headers["Content-Encoding"] != encoding)
      fail "Content-Type is #{response.headers["Content-Type"]}, not #{EXPECTED_CONTENT_TYPE}" unless (response.headers["Content-Type"] == EXPECTED_CONTENT_TYPE)
      CallList.from_xml xml
    end
  end
end
