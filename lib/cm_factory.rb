#this resource is used to control chassis managers.
require 'yaml'
require 'open-uri'
require 'nokogiri'
require 'pp'


module OmfRc::ResourceProxy::CMFactory
  include OmfRc::ResourceProxyDSL
  @timeout = 120

  register_proxy :cm_factory

#   property :all_nodes, :default => []
  property :node_state

  hook :before_ready do |res|
    #@config = YAML.load_file('../etc/proxies_conf.yaml')
    #@domain = @config[:domain]
#   ->before integrating with Broker, this was the way we took ip's for the nodes
#     @nodes = @config[:nodes]
#     puts "### nodes: #{@nodes}"
#     @nodes.each do |node|
#       tmp = {node_name: node[0], node_ip: node[1][:ip], node_mac: node[1][:mac], node_cm_ip: node[1][:cm_ip]}
#       res.property.all_nodes << tmp
#     end
  end

#   request :node_state do |res|
#     node = nil
#     puts "#### value is #{res.property.node_state}"
#     res.property.all_nodes.each do |n|
#       if n[:node_name] == res.property.node_state
#         node = n
#       end
#     end
#     puts "Node : #{node}"
#     ret = false
#     if node.nil?
#       puts "error: Node nill"
#       res.inform(:status, {
#         event_type: "EXIT",
#         exit_code: "-1",
#         node_name: value[:node],
#         msg: "Wrong node name."
#       }, :ALL)
#     else
#       ret = res.get_status(node)
#     end
#     ret
#   end

  configure :state do |res, value|

    OmfCommon.comm.subscribe("am_controller") do |am_con|
      acc = res.find_account_name(res)
      if acc.nil?
        puts "error: acc nill"
        res.inform(:error, {
          event_type: "ACCOUNT",
          exit_code: "-1",
          node_name: value[:node],
          msg: "Wrong account name."
        }, :ALL)
        next
      end

      am_con.request([:nodes]) do |msg|
        nodes = msg.read_property("nodes")[:resources]
        node = nil
        nodes.each do |n|
          if n[:resource][:name] == value[:node].to_s
            node = n
            break
          end
        end

        if node.nil?
          puts "error: Node nill"
          res.inform(:error, {
            event_type: "NODE",
            exit_code: "-1",
            node_name: value[:node],
            msg: "Wrong node name."
          }, :ALL)
          next
        else
          am_con.request([:leases]) do |msg|
            leases = msg.read_property("leases")
            lease = nil
            leases[:resources].each do |l|
              if Time.parse(l[:resource][:valid_from]) <= Time.now && Time.parse(l[:resource][:valid_until]) >= Time.now
                l[:resource][:components].each do |c|
                  if c[:component][:name] == value[:node].to_s && l[:resource][:account][:name] == acc
                    lease = l
                    break #found the correct lease
                  end
                end
              end
            end

            if lease.nil? #if lease is nil it means no matching lease is found
              puts "error: Lease nill"
              res.inform(:error, {
                event_type: "LEASE",
                exit_code: "-1",
                node_name: value[:node],
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

              case value[:status].to_sym
              when :on then res.start_node(nod, value[:wait])
              when :off then res.stop_node(nod, value[:wait])
              when :reset then res.reset_node(nod, value[:wait])
              when :start_on_pxe then res.start_node_pxe(nod)
              when :start_without_pxe then res.start_node_pxe_off(nod, value[:last_action])
              when :get_status then res.status(nod)
              else
                res.log_inform_warn "Cannot switch node to unknown state '#{value[:status].to_s}'!"
              end
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

#   work("get_node") do |res, node_name|
#     OmfCommon.comm.subscribe("am_controller") do |res|
#       res.request([:nodes]) do |msg|
#         node = msg.read_property("node")
#         puts "+++++++++++++ #{node}"
#       end
#     end
#   end
#
#   work("check_lease") do |res, node, account|
#
#   end

  work("wait_until_ping") do |res, ip|
    t = 0
    resp = false
    loop do
      sleep 2
      status = system("ping #{ip} -c 2 -w 2")
      if t < @timeout
        if status == true
          resp = true
          break
        end
      else
        resp = false
        break
      end
      t += 2
    end
    resp
  end

  work("wait_until_no_ping") do |res, ip|
    t = 0
    resp = false
    loop do
      sleep 2
      status = system("ping #{ip} -c 2 -w 2")
      if t < @timeout
        if status == false
          resp = true
          break
        end
      else
        resp = false
        break
      end
      t += 2
    end
    resp
  end

  work("get_status") do |res, node|
    puts "http://#{node[:node_cm_ip].to_s}/state"
    doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/state"))
    resp = doc.xpath("//Measurement//type//value").text.strip

    if resp == 'on'
      symlink_name = "/tftpboot/pxelinux.cfg/01-#{node[:node_mac]}"
      if File.exists?("#{symlink_name}")
        :on_pxe
      else
        :on
      end
    elsif resp == 'off'
      :off
    end
  end

  work("status") do |res, node|
    puts "http://#{node[:node_cm_ip].to_s}/state"
    begin
      doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/state"))
    rescue
      res.inform(:error, {
        event_type: "HTTP",
        exit_code: "-1",
        node_name: "#{node[:node_name].to_s}",
        msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
      }, :ALL)
      next
    end
    puts doc

    res.inform(:status, {
      event_type: "NODE_STATUS",
      exit_code: "0",
      node_name: "#{node[:node_name].to_s}",
      msg: "#{doc.xpath("//Measurement//type//value").text}"
    }, :ALL)
  end

  work("start_node") do |res, node, wait|
    puts "http://#{node[:node_cm_ip].to_s}/on"
    begin
      doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/on"))
    rescue
      res.inform(:error, {
        event_type: "HTTP",
        exit_code: "-1",
        node_name: "#{node[:node_name].to_s}",
        msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
      }, :ALL)
      next
    end
    puts doc
    res.inform(:status, {
      event_type: "START_NODE",
      exit_code: "0",
      node_name: "#{node[:node_name].to_s}",
      msg: "#{doc.xpath("//Response").text}"
    }, :ALL)

    if wait
      if res.wait_until_ping(node[:node_ip])
        res.inform(:status, {
          event_type: "EXIT",
          exit_code: "0",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' is up."
        }, :ALL)
      else
        res.inform(:error, {
          event_type: "EXIT",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' timed out while booting."
        }, :ALL)
      end
    end
  end

  work("stop_node") do |res, node, wait|
    puts "http://#{node[:node_cm_ip].to_s}/off"
    begin
      doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/off"))
    rescue
      res.inform(:error, {
        event_type: "HTTP",
        exit_code: "-1",
        node_name: "#{node[:node_name].to_s}",
        msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
      }, :ALL)
      next
    end
    puts doc
    res.inform(:status, {
      event_type: "STOP_NODE",
      exit_code: "0",
      node_name: "#{node[:node_name].to_s}",
      msg: "#{doc.xpath("//Response").text}"
    }, :ALL)

    if wait
      if res.wait_until_no_ping(node[:node_ip])
        res.inform(:status, {
          event_type: "EXIT",
          exit_code: "0",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' is down."
        }, :ALL)
      else
        res.inform(:error, {
          event_type: "EXIT",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' timed out while shutting down."
        }, :ALL)
      end
    end
  end

  work("reset_node") do |res, node, wait|
    puts "http://#{node[:node_cm_ip].to_s}/reset"
    begin
      doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/reset"))
    rescue
      res.inform(:error, {
        event_type: "HTTP",
        exit_code: "-1",
        node_name: "#{node[:node_name].to_s}",
        msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
      }, :ALL)
      next
    end
    puts doc
    res.inform(:status, {
      event_type: "RESET_NODE",
      exit_code: "0",
      node_name: "#{node[:node_name].to_s}",
      msg: "#{doc.xpath("//Response").text}"
    }, :ALL)
    
    if wait
      if res.wait_until_ping(node[:node_ip])
        res.inform(:status, {
          event_type: "EXIT",
          exit_code: "0",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' is up after reset."
        }, :ALL)
      else
        res.inform(:error, {
          event_type: "EXIT",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' timed out while reseting."
        }, :ALL)
      end
    end
  end

  work("start_node_pxe") do |res, node|
    resp = res.get_status(node)
    if resp == :on
      symlink_name = "/tftpboot/pxelinux.cfg/01-#{node[:node_mac]}"
      if !File.exists?("#{symlink_name}")
        File.symlink("/tftpboot/pxelinux.cfg/omf-5.4", "#{symlink_name}")
      end
      puts "http://#{node[:node_cm_ip].to_s}/reset"
      begin
        doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/reset"))
      rescue
        res.inform(:error, {
          event_type: "HTTP",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
        }, :ALL)
        next
      end
    elsif resp == :off
      symlink_name = "/tftpboot/pxelinux.cfg/01-#{node[:node_mac]}"
      if !File.exists?("#{symlink_name}")
        File.symlink("/tftpboot/pxelinux.cfg/omf-5.4", "#{symlink_name}")
      end
      puts "http://#{node[:node_cm_ip].to_s}/on"
      begin
        doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/on"))
      rescue
        res.inform(:error, {
          event_type: "HTTP",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
        }, :ALL)
        next
      end
    elsif resp == :started_on_pxe
      puts "http://#{node[:node_cm_ip].to_s}/reset"
      begin
        doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/reset"))
      rescue
        res.inform(:error, {
          event_type: "HTTP",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
        }, :ALL)
        next
      end
    end

    if res.wait_until_ping(node[:node_ip])
      res.inform(:status, {
        event_type: "PXE",
        exit_code: "0",
        node_name: "#{node[:node_name].to_s}",
        msg: "Node '#{node[:node_name].to_s}' is up on PXE."
      }, :ALL)
    else
      res.inform(:error, {
        event_type: "PXE",
        exit_code: "-1",
        node_name: "#{node[:node_name].to_s}",
        msg: "Node '#{node[:node_name].to_s}' timed out while trying to boot on PXE."
      }, :ALL)
    end
  end

  work("start_node_pxe_off") do |res, node, action|
    symlink_name = "/tftpboot/pxelinux.cfg/01-#{node[:node_mac]}"
    if File.exists?(symlink_name)
      File.delete(symlink_name)
    end
    if action == "reset"
      puts "http://#{node[:node_cm_ip].to_s}/reset"
      begin
        doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/reset"))
      rescue
        res.inform(:error, {
          event_type: "HTTP",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
        }, :ALL)
        next
      end
      puts doc
      t = 0
      if res.wait_until_ping(node[:node_ip])
        res.inform(:status, {
          event_type: "PXE_OFF",
          exit_code: "0",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' is up."
        }, :ALL)
      else
        res.inform(:error, {
          event_type: "PXE_OFF",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' timed out while booting."
        }, :ALL)
      end
    elsif action == "shutdown"
      puts "http://#{node[:node_cm_ip].to_s}/off"
      begin
        doc = Nokogiri::XML(open("http://#{node[:node_cm_ip].to_s}/off"))
      rescue
        res.inform(:error, {
          event_type: "HTTP",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "failed to reach cm, ip: #{node[:node_cm_ip].to_s}."
        }, :ALL)
        next
      end
      puts doc
      if res.wait_until_no_ping(node[:node_ip])
        res.inform(:status, {
          event_type: "EXIT",
          exit_code: "0",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' is down."
        }, :ALL)
      else
        res.inform(:error, {
          event_type: "EXIT",
          exit_code: "-1",
          node_name: "#{node[:node_name].to_s}",
          msg: "Node '#{node[:node_name].to_s}' timed out while shutting down."
        }, :ALL)
      end
    end
  end
end
#
#
# entity_cert = File.expand_path(@auth[:entity_cert])
# entity_key = File.expand_path(@auth[:entity_key])
# entity = OmfCommon::Auth::Certificate.create_from_x509(File.read(entity_cert), File.read(entity_key))
#
# trusted_roots = File.expand_path(@auth[:root_cert_dir])
#
# OmfCommon.init(:development, communication: { url: "xmpp://#{@xmpp[:username]}:#{@xmpp[:password]}@#{@xmpp[:server]}", auth: {} }) do
#   OmfCommon.comm.on_connected do |comm|
#     OmfCommon::Auth::CertificateStore.instance.register_default_certs(trusted_roots)
#     OmfCommon::Auth::CertificateStore.instance.register(entity, OmfCommon.comm.local_topic.address)
#     OmfCommon::Auth::CertificateStore.instance.register(entity)
#
#     info "CMController >> Connected to XMPP server"
#     cmContr = OmfRc::ResourceFactory.create(:cmController, { uid: 'cmController', certificate: entity })
#     comm.on_interrupted { cmContr.disconnect }
#   end
# end
