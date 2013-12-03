#this resource is used to control applications frisbee/frisbeed and imagezip_server/imagezip_client.

$ports = []
module OmfRc::ResourceProxy::FrisbeeFactory
  include OmfRc::ResourceProxyDSL

  @config = YAML.load_file('../etc/frisbee_proxy_conf.yaml')
  @fconf = @config[:frisbee]

  register_proxy :frisbee_factory

  request :ports do |res|
    port = @fconf[:startPort]
    loop do
      if $ports.include?(port)
        port +=1
      elsif !res.port_open?(port)
        port +=1
      else
        $ports << port
        break
      end
    end
    debug "port chosen: '#{port}'"
    port
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
