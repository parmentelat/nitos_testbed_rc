#This resource is related with user instance


module OmfRc::ResourceProxy::UserFactory
  include OmfRc::ResourceProxyDSL

  register_proxy :user_factory

  configure :deluser do |res, value|
    cmd = 'userdel -r ' + value[:username]
    exec cmd
  end
end
