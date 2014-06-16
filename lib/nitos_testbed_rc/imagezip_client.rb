#Imagezip client
#created by parent :frisbee_factory
#used in save command

#$domain = @config[:domain][:ip]

module OmfRc::ResourceProxy::ImagezipClient #Imagezip client
  include OmfRc::ResourceProxyDSL
  require 'omf_common/exec_app'

  @config = YAML.load_file('/etc/nitos_testbed_rc/frisbee_proxy_conf.yaml')
  # @config = YAML.load_file(File.join(File.dirname(File.expand_path(__FILE__)), '../etc/frisbee_proxy_conf.yaml'))
  @fconf = @config[:frisbee]

  register_proxy :imagezip_client, :create_by => :frisbee_factory

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => @fconf[:imagezipClientBin] #usually '/usr/bin/imagezip'
  property :map_err_to_out, :default => false

  property :ip, :default => @fconf[:multicastIF]
  property :port
  property :hardrive, :default => "/dev/sda"
  property :node_topic

  hook :after_initial_configured do |client|
    Thread.new do
      debug "Received message '#{client.opts.inspect}'"
      if error_msg = client.opts.error_msg
        res.inform(:error,{
          event_type: "AUTH",
          exit_code: "-1",
          node_name: client.property.node_topic,
          msg: error_msg
        }, :ALL)
        next
      end

      nod = {}
      nod[:node_name] = client.opts.node.resource.name
      client.opts.node.resource.interfaces.each do |i|
        if i[:role] == "control"
          nod[:node_ip] = i[:ip][:address]
          nod[:node_mac] = i[:mac]
        elsif i[:role] == "cm_network"
          nod[:node_cm_ip] = i[:ip][:address]
        end
      end
      nod[:node_cm_ip] = client.opts.node.resource.cmc.ip.address

      client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

      command = "#{client.property.binary_path} -o -z1 #{client.property.hardrive} - | /bin/nc -q 0 #{client.property.ip} #{client.property.port}"
      debug "Executing command #{command}"
  #     nod = {node_name: "node1", node_ip: "10.0.0.1", node_mac: "00-03-1d-0d-4b-96", node_cm_ip: "10.0.0.101"}

      host = Net::Telnet.new("Host" => nod[:node_ip], "Timeout" => false)#, "Prompt" => /[\w().-]*[\$#>:.]\s?(?:\(enable\))?\s*$/)
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
end
