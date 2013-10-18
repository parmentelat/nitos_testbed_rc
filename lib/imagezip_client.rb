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
#     node = nil
#     $all_nodes.each do |n|
#       if n[:node_name] == client.property.node_topic.to_sym
#         node = n
#       end
#     end
#     puts "Node : #{node}"
#     if node.nil?
#       puts "error: Node nill"
#       client.inform(:status, {
#         event_type: "EXIT",
#         exit_code: "-1",
#         msg: "Wrong node name."
#       }, :ALL)
#       client.release
#       return
#     end

    OmfCommon.comm.subscribe("am_controller") do |am_con|
      acc = client.find_account_name(client)
      if acc.nil?
        puts "error: acc nill"
        client.inform(:status, {
          event_type: "EXIT",
          exit_code: "-1",
          node: client.property.node_topic,
          msg: "Wrong account name."
        }, :ALL)
        next
      end

      am_con.request([:nodes]) do |msg|
        nodes = msg.read_property("nodes")[:resources]
        node = nil
        nodes.each do |n|
          if n[:resource][:name] == client.property.node_topic
            node = n
            break
          end
        end

        if node.nil?
          puts "error: Node nill"
          client.inform(:status, {
            event_type: "EXIT",
            exit_code: "-1",
            node: client.property.node_topic,
            msg: "Wrong node name."
          }, :ALL)
          next
        else
          am_con.request([:leases]) do |msg|
            leases = msg.read_property("leases")
            lease = nil
            leases.each do |l|
              if Time.parse(l[:valid_from]) <= Time.now && Time.parse(l[:valid_until]) >= Time.now
                l[:component_names].each do |c|
                  if c[:component_name] == client.property.node_topic && l[:account] == acc
                    lease = l
                    break #found the correct lease
                  end
                end
              end
            end

            if lease.nil? #if lease is nil it means no matching lease is found
              puts "error: Lease nill"
              client.inform(:status, {
                event_type: "EXIT",
                exit_code: "-1",
                node: client.property.node_topic,
                msg: "Node is not leased by your account."
              }, :ALL)
              next
            else
              nod = {}
              nod[:node_name] = node[:resource][:name]
              node[:resource][:interfaces].each do |i|
                if i[:role] == "control_network"
                  nod[:node_ip] = i[:ip][:address]
                  nod[:node_mac] = i[:mac]
                elsif i[:role] == "cm_network"
                  nod[:node_cm_ip] = i[:ip][:address]
                end
              end
              client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

              command = "#{client.property.binary_path} -o -z1 #{client.property.hardrive} - | /bin/nc -q 0 #{client.property.ip} #{client.property.port}"
              puts "########### running command is #{command}"

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
      end
    end
  end

  work("find_account_name") do |res|#most likely another input will be required
    #TODO find the account from the authentication key that is used in the xmpp message
    #at the moment always return root as account, return nil if it fails
    acc_name = "root"
    acc_name
  end
end
