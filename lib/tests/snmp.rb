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


servers = ["bono-1", "sprout-1"]

servers.each do |s|
  NonCallTestDefinition.new("SNMP - #{s}") do |domain, t|
    host = "#{s}.#{domain}"
    snmp_map = get_snmp host, "clearwater", "1.2.826.0.1.1578918.9.2"
    if (snmp_map.empty?)
      raise "No results from SNMP for host #{s}.#{domain}"
    end
    true
  end

  NonCallTestDefinition.new("CPU/Mem SNMP - #{s}") do |domain, t|
    host = "#{s}.#{domain}"
    snmp_map = get_snmp host, "clearwater", "1.3.6.1.4.1.2021"
    if (snmp_map.empty?)
      raise "No results from SNMP for host #{s}.#{domain}"
    end
    true
  end

  NonCallTestDefinition.new("Nonexistent SNMP - #{s}") do |domain, t|
    host = "#{s}.#{domain}"
    oid = "1.2.826.0.1.1578918.9.2.99999"
    snmp_map = get_snmp host, "clearwater", oid
    if (not snmp_map.empty?)
      raise "Got unexpected result from SNMP #{oid} for host
                                #{s}.#{domain} - #{snmp_map.inspect}"
    end
    true
  end

  NonCallTestDefinition.new("SNMP with wrong community - #{s}") do |domain, t|
    host = "#{s}.#{domain}"
    begin
      snmp_map = Timeout::timeout(2)  { get_snmp host, "public", "1.2.826.0.1.1578918.9.2" }
      raise "Got results from SNMP for host #{s}.#{domain} even with an incorrect community string"
    rescue TimeoutError
      true
    end
  end

end

