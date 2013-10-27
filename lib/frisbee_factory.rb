


#$all_nodes = []
$ports = []
module OmfRc::ResourceProxy::FrisbeeFactory
  include OmfRc::ResourceProxyDSL

  property :ports, :default => nil
  register_proxy :frisbee_factory

  def is_port_open?(port)
    begin
      TCPSocket.new("127.0.0.1", port)
    rescue Errno::ECONNREFUSED
      return false
    end
    return true
  end

  hook :before_ready do |res|
    #@config = YAML.load_file('../etc/proxies_conf.yaml')
#     @nodes = @config[:nodes]
#
#     @nodes.each do |node|
#       tmp = {node_name: node[0], node_ip: node[1][:ip], node_mac: node[1][:mac], node_cm_ip: node[1][:cm_ip]}
#       $all_nodes << tmp
#     end
  end

#   def port_open?(port, seconds=1)
#     Timeout::timeout(seconds) do
#       begin
#         TCPSocket.new("127.0.0.1", port).close
#         return true
#       rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
#         return false
#       end
#     end
#   rescue Timeout::Error
#     return false
#   end

  request :ports do |res|
    p = 7000
    puts "port '#{p}'"
    loop do
      if $ports.include?(p)
        puts "included"
        p +=1
      elsif !res.port_open?(p)
        puts "taken"
        p +=1
      else
        $ports << p
        res.property.ports = p
        break
      end
    end
    res.property.ports.to_s
  end

  def port_open?(port, seconds=1)
    Timeout::timeout(seconds) do
      begin
        TCPServer.new('localhost', port) rescue return false
        return true
      end
    end
  rescue Timeout::Error
    return false
  end
end
