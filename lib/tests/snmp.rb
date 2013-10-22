require 'snmp'
require 'timeout'

def get_snmp host, community, oid
  snmp_map = {}
  SNMP::Manager.open(:host => host, :community => community) do |manager|
    manager.walk(oid) do |row|
      row.each { |vb| snmp_map[vb.name] = vb.value }
    end
  end
  snmp_map
end


servers_env = ENV['SNMP_AGENTS'] || ""
servers = servers_env.split(",")

servers.each do |s|
  # Test that the Clearwater-specific SNMP stats (e.g. latency) work
  # We can't be much moree specific about what we expect, because
  # stats can vary with IP address and (in some cases, like connected
  # Homesteads) based on how long we've been running
  NonCallTestDefinition.new("Clearwater SNMP - #{s}") do |domain, t|
    host = s
    snmp_map = get_snmp host, "clearwater", "1.2.826.0.1.1578918.9.2"
    if (snmp_map.empty?)
      raise "No results from SNMP for host #{host}"
    end
    true
  end

  # Test that the generic SNMP stats which we've made available work
  NonCallTestDefinition.new("CPU/Mem SNMP - #{s}") do |domain, t|
    host = s
    snmp_map = get_snmp host, "clearwater", "1.3.6.1.4.1.2021"
    if (snmp_map.empty?)
      raise "No results from SNMP for host #{host}"
    end
    true
  end

  # Test that the Clearwater SNMP code does not return stats for
  # nonexistent fields
  NonCallTestDefinition.new("Nonexistent SNMP - #{s}") do |domain, t|
    host = s
    oid = "1.2.826.0.1.1578918.9.2.99999"
    snmp_map = get_snmp host, "clearwater", oid
    if (not snmp_map.empty?)
      raise "Got unexpected result from SNMP #{oid} for host
                                #{host} - #{snmp_map.inspect}"
    end
    true
  end

  # Test that SNMPd does not respond when we authenticate incorrectly
  NonCallTestDefinition.new("SNMP with wrong community - #{s}") do |domain, t|
    host = s

    begin
      snmp_map = Timeout::timeout(2)  { get_snmp host, "public", "1.2.826.0.1.1578918.9.2" }
      raise "Got results from SNMP for host #{host} even with an incorrect community string"
    rescue TimeoutError
      true
    end
  end

end

