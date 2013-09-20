#Imagezip client
#created by parent :frisbee_factory
#used in save command

module OmfRc::ResourceProxy::ImagezipClient #Imagezip client
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :imagezip_client, :create_by => :frisbee_factory

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/bin/imagezip'
  property :map_err_to_out, :default => false

  property :ip, :default => "#{$domain}200"
  property :port, :default => "9000"
  property :hardrive, :default => "/dev/sda"
  property :node_topic

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

    client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

    command = "#{client.property.binary_path} -o -z1 #{client.property.hardrive} - | /bin/nc -q 0 #{client.property.ip} #{client.property.port}"
    puts "########### running command is #{command}"

    host = Net::Telnet.new("Host" => node[:node_ip], "Timeout" => false)#, "Prompt" => /[\w().-]*[\$#>:.]\s?(?:\(enable\))?\s*$/)
    host.cmd(command.to_s) do |c|
      if c.to_s !=  "\n" && c[0,5] != "\n/usr" && c.to_s != "." && c.to_s != ".." && c.to_s != "..."
        #puts '__' + c.to_s + '__'
        client.inform(:status, {
          status_type: 'IMAGEZIP',
          event: "STDOUT",
          app: client.property.app_id,
          node: client.property.node_topic,
          msg: "#{c.to_s}"
        }, :ALL)
      end
    end

    client.inform(:status, {
      status_type: 'IMAGEZIP',
      event: "EXIT",
      app: client.property.app_id,
      node: client.property.node_topic,
      msg: 'imagezip client completed.'
    }, :ALL)
    host.close
  end
end
