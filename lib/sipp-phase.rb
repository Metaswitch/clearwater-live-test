# @file sipp-phase.rb
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

class SIPpPhase
  def initialize(template, sender, options={})
    @template = template
    @options = options.merge(sender: sender)
  end

  def to_s
    erb_src = File.read(File.join(File.dirname(__FILE__),
                                  "..",
                                  "templates",
                                  @template + ".erb"))
    erb = Erubis::Eruby.new(erb_src)
    erb.result(@options)
  end

  def sender
    @options[:sender]
  end
end
