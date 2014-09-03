# @file endpoint.rb
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2013 Metaswitch Networks Ltd
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
