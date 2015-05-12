#frisbee client
#created by parent :frisbee_factory
#used in load command
require 'net/telnet'
require 'socket'
require 'timeout'

####################
# the output of the frisbee client has no reason to come line by line
# so we reconstruct lines and parse them one line at a time
class FrisbeeParser

  def initialize(client)
    # keep a reference to the messaging entities that we notify of our progress or errors
    @client = client
    # overall result
    @output = nil
    ### local stuff
    # initialize current line
    @line = ""
    # total number of chunks
    @total_chunks = nil
  end

  def get_output
    @output
  end

  # parse one line of output from the frisbee client
  # support for old-style (2002) and new-style (2006) clients
  def parse_line
    # old-style frisbee plain percentage report
    if m = /^Progress:\s+([\d.]+%).*/.match(@line)
      percent = m[1]
      @client.inform(:status, {
                       status_type: 'FRISBEE',
                       event: "STDOUT",
                       app: @client.property.app_id,
                       node: @client.property.node_topic,
                       msg: "#{percent.to_s}"
                     }, :ALL)
    # final report on size
    elsif m = /^Wrote\s+(\d+)\s+byte.*/.match(@line)
      # xxx this is for reproducing the old behaviour
      # but it looks wrong as it repeats the entire line
      content = @line.split("\n")
      # should probably rather use this instead
      bytes = m[1]
      @output = "#{content.first}\n#{content.last}"
    # new-style output first reports total number of chunks
    elsif m = /.*File is ([0-9]+) chunks.*/.match(@line)
      # record this as an integer
      @total_chunks = m[1].to_i
    # and then a status line every now and again
    # we've always seen exactly 67 chars in a status line but well
    elsif m = /[.sz]{60,75}\s+\d+\s+(\d+)/.match(@line)
      if @total_chunks
        remaining_chunks = m[1].to_i
        i_percent = 100 * (@total_chunks - remaining_chunks) / @total_chunks
        percent = "#{i_percent}%"
        @client.inform(:status, {
                         status_type: 'FRISBEE',
                         event: "STDOUT",
                         app: @client.property.app_id,
                         node: @client.property.node_topic,
                         msg: "#{percent.to_s}"
                       }, :ALL)
        # else, this means we have not properly read the line that gives
        # the number of chunks, and there's nothing we can do..
      end
    # this happens when the whole thing goes south
    elsif @line =~ /.*Short write.*/
      @client.inform(:error,{
                       event_type: "ERROR",
                       exit_code: "-1",
                       node_name: @client.property.node_topic,
                       msg: "Load ended with 'Short write' error msg!"
                     }, :ALL)
    end
  end

  def new_input(chunk)
    chunk.each_char do |c|
      if c == "\n"
        parse_line()
        @line = ""
      else
        @line << c
      end
    end
  end
  
  def close
    if @line
      parse_line()
    end
  end
    
end

module OmfRc::ResourceProxy::Frisbee #frisbee client
  include OmfRc::ResourceProxyDSL
  require 'omf_common/exec_app'
  @config = YAML.load_file('/etc/nitos_testbed_rc/frisbee_proxy_conf.yaml')
  # @config = YAML.load_file(File.join(File.dirname(File.expand_path(__FILE__)), '../etc/frisbee_proxy_conf.yaml'))
  @fconf = @config[:frisbee]

  register_proxy :frisbee, :create_by => :frisbee_factory

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => @fconf[:frisbeeBin]      #'/usr/sbin/frisbee'
  property :map_err_to_out, :default => false

  property :multicast_interface                               #multicast interface, example 10.0.1.12 for node12 (-i arguement)
  property :multicast_address, :default => @fconf[:mcAddress] #multicast address, example 224.0.0.1 (-m arguement)
  property :port                                              #port, example 7000 (-p arguement)
  property :hardrive, :default => "/dev/sda"                  #hardrive to burn the image, example /dev/sda (nparguement)
  property :node_topic                                        #the node

  hook :after_initial_configured do |client|
    Thread.new do
      debug "Received message '#{client.opts.inspect}'"
      if error_msg = client.opts.error_msg
        client.inform(:error,{
          event_type: "AUTH",
          exit_code: "-1",
          node_name: client.property.node_topic,
          msg: error_msg
        }, :ALL)
        next
      end
      # if client.opts.ignore_msg
      #   #just ignore this message, another resource controller should take care of this message
      #   next
      # end
      # nod = {}
      # nod[:node_name] = client.opts.node.name
      # client.opts.node.interfaces.each do |i|
      #   if i[:role] == "control"
      #     nod[:node_ip] = i[:ip][:address]
      #     nod[:node_mac] = i[:mac]
      #   end
      # end
      # nod[:node_cm_ip] = client.opts.node.cmc.ip.address
      #nod = {node_name: "node1", node_ip: "10.0.0.1", node_mac: "00-03-1d-0d-4b-96", node_cm_ip: "10.0.0.101"}
      nod = client.opts.node
      client.property.multicast_interface = nod[:node_ip]
      client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

      command = "#{client.property.binary_path} -i #{client.property.multicast_interface} -m #{client.property.multicast_address} -p #{client.property.port} #{client.property.hardrive}"
      debug "Executing command #{command} on host #{client.property.multicast_interface.to_s}"
      
      # previous Prompt was way too extensive and caused early exits from cmd
      # of course using ssh would be much nicer, but for now let's keep it simple
      host = Net::Telnet.new("Host" => client.property.multicast_interface.to_s,
                             "Timeout" => 200,
#                             "Output_log" => "/tmp/telnet.log",
                            )
      parser = FrisbeeParser.new(client)

      host.cmd(command.to_s) do |chunk|
        parser.new_input(chunk)
      end
      parser.close()
      output = parser.get_output()

      client.inform(:status, {
        status_type: 'FRISBEE',
        event: "EXIT",
        app: client.property.app_id,
        node: client.property.node_topic,
        msg: output
      }, :ALL)
      host.close
    end
  end
end
