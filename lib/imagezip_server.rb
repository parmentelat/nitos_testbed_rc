#Imagezip client
#created by parent :frisbee_factory
#used in save command

module OmfRc::ResourceProxy::ImagezipServer #Imagezip server
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :imagezip_server, :create_by => :frisbee_factory

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/bin/nc'
  property :map_err_to_out, :default => false

  property :ip, :default => "#{$domain}200"
  property :port, :default => "9000"
  property :image_name, :default => "/tmp/image.ndz"

  hook :after_initial_configured do |server|
    server.property.app_id = server.hrn.nil? ? server.uid : server.hrn
    server.property.multicast_interface = "#{$domain}200"

    @app = ExecApp.new(server.property.app_id, server.build_command_line, server.property.map_err_to_out) do |event_type, app_id, msg|
      server.process_event(server, event_type, app_id, msg)
    end
  end

  hook :before_release do |server|
    #not needed, stops by default
    #@app.signal(signal = 'KILL')
    $ports.delete_if {|x| x == server.property.port}
  end

  def process_event(res, event_type, app_id, msg)
      logger.info "Frisbeed: App Event from '#{app_id}' - #{event_type}: '#{msg}'"
      if event_type == 'EXIT' #maybe i should inform you for every event_type, we'll see.
        res.inform(:status, {
          status_type: 'IMAGEZIP',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      elsif event_type == 'STDOUT'
        res.inform(:status, {
          status_type: 'IMAGEZIP',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      end
  end

  work('build_command_line') do |res|
    cmd_line = "env -i " # Start with a 'clean' environment
    cmd_line += res.property.binary_path + " "
    cmd_line += "-d -l " +  res.property.ip + " " + res.property.port.to_s + " > " +  res.property.image_name
    cmd_line
  end
end
