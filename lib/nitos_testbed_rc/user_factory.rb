#This resource is related with user instance


module OmfRc::ResourceProxy::UserFactory
  include OmfRc::ResourceProxyDSL

  register_proxy :user_factory

  configure :deluser do |res, value|
    cmd = '/usr/sbin/userdel -r -f ' + value[:username]
    system cmd
  end
end
