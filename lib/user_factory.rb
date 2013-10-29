#This resource is related with user instance


module OmfRc::ResourceProxy::UserFactory
  include OmfRc::ResourceProxyDSL

  register_proxy :user_factory

  property :users, :default => []

  hook :before_ready do |resource|
    File.open('/etc/passwd', 'r') do |file|
      file.each do |line|
        tmp = line.chomp.split(':')[0]
        resource.property.users << tmp
      end
    end
  end

#   hook :before_create do |controller, new_resource_type, new_resource_opts|
#     controller.property.users.each do |user|
#       if user == new_resource_opts.username
#         raise "user '#{new_resource_opts.username}' already exists"
#       end
#     end
#   end

  hook :after_create do |controller, user|
    controller.property.users << user.property.username
  end

  request :users do |res|
    #puts "Returing #{res.property.users.to_s}"
    res.property.users
  end

  configure :deluser do |res, value|
    if res.property.users.include?(value[:username])
      cmd = 'userdel -r ' + value[:username]
      exec cmd
      res.property.users.delete(value[:username])
    end
  end
end
