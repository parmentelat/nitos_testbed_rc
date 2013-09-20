#frisbee client
#created by parent :frisbee_factory
#used in load command

module OmfRc::ResourceProxy::Frisbee #frisbee client
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :frisbee, :create_by => :frisbee_factory

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/sbin/frisbee'
  property :map_err_to_out, :default => false

  property :multicast_interface                           #multicast interface, example 10.0.1.200 (-i arguement)
  property :multicast_address, :default => "224.0.0.1"    #multicast address, example 224.0.0.1 (-m arguement)
  property :port                                          #port, example 7000 (-p arguement)
  property :hardrive, :default => "/dev/sda"              #hardrive to burn the image, example /dev/sda (nparguement)
  property :node_topic                                    #the node

   hook :after_initial_configured do |client|
    node = nil
    $all_nodes.each do |n|
      if n[:node_name] == client.property.node_topic.to_sym
        node = n
      end
    end
    puts "Node : #{node}"
    if node.nil?
      puts "error: Node nill"
      client.inform(:status, {
        event_type: "EXIT",
        exit_code: "-1",
        msg: "Wrong node name."
      }, :ALL)
      client.release
      return
    end

    client.property.multicast_interface = node[:node_ip]
    client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

    command = "#{client.property.binary_path} -i #{client.property.multicast_interface} -m #{client.property.multicast_address} "
    command += "-p #{client.property.port} #{client.property.hardrive}"

    host = Net::Telnet.new("Host" => client.property.multicast_interface.to_s, "Timeout" => 200, "Prompt" => /[\w().-]*[\$#>:.]\s?(?:\(enable\))?\s*$/)
    host.cmd(command.to_s) do |c|
      if c !=  "\n" && (c[0,8] == "Progress" || c[0,5] == "Wrote")
        c = c.sub("\n","\n#{client.property.node_topic}: ")
        client.inform(:status, {
          status_type: 'FRISBEE',
          event: "STDOUT",
          app: client.property.app_id,
          node: client.property.node_topic,
          msg: "#{c.to_s}"
        }, :ALL)
      end
    end

    client.inform(:status, {
      status_type: 'FRISBEE',
      event: "EXIT",
      app: client.property.app_id,
      node: client.property.node_topic,
      msg: 'frisbee client completed.'
    }, :ALL)
    host.close
  end
end
