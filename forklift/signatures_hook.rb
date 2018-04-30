#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'apipie-bindings'
require 'open-uri'
require 'gpgme'

@defaults = {
  :noop      => false,
  :uri       => 'https://devel.example.com/',
  :username  => 'admin',
  :password  => 'changeme'
}

@options = {
  :yamlfile  => 'hooks.yaml',
}

if File.exists? @options[:yamlfile]
  @yaml = YAML.load_file(@options[:yamlfile])

  if @yaml.has_key?(:settings) and @yaml[:settings].is_a?(Hash)
    @yaml[:settings].each do |key,val|
      if not @options.has_key?(key)
        @options[key] = val
      end
    end
  end
end

@defaults.each do |key,val|
  if not @options.has_key?(key)
    @options[key] = val
  end
end


def get_signature(image, digest)
  signature = nil

  image = 'rhel7/etcd'
  digest = 'sha256:35fdf949dd7698ab5def00c504293be5fb5a5af29066a6e1684cf81a80bd6ce2'

  url = "https://access.redhat.com/webassets/docker/content/sigstore/" +
        "#{image}@sha256=#{digest[7..-1]}/signature-1"
  uri = URI(url)
  nethttp = Net::HTTP.new(uri.host, uri.port)
  nethttp.use_ssl = uri.scheme == 'https'
  nethttp.verify_mode = OpenSSL::SSL::VERIFY_NONE
  nethttp.start do |http|
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    if response.kind_of? Net::HTTPNotFound
      signature = {}
    else
      signature = response.body
      # signature = Tempfile.new(digest)
      # signature.write(response.body)
      # signature.rewind
      puts "----------------"
      puts signature
      puts "----------------"
      # signature.rewind
    end
  end
  signature
end

def sign_repository(repository)
  return unless repository['content_type'] == 'docker'

  api = ApipieBindings::API.new({
    :uri => @options[:uri],
    :username => @options[:username],
    :password => @options[:password],
    :api_version => '2',
    :timeout => @options[:timeout]
  })

  manifests = api.resource(:docker_manifests).call(:index, {
    organization_id: repository['organization']['id'],
    per_page: 99999
  })['results']

  product = api.resource(:products).call(:show, {
    id: repository['product']['id']
  })
  #puts "XXXXXXXX #{JSON.pretty_generate(product)}"
  gpgkey = api.resource(:gpg_keys).call(:show, {
    id: product['gpg_key']['id']
  })
  #puts "XXXXXXXX #{JSON.pretty_generate(gpgkey)}"
  GPGME::Key.import(gpgkey['content'])
  crypto = GPGME::Crypto.new
  ctx = GPGME::Ctx.new

  imagename = repository['docker_upstream_name']
  manifests.each do |manifest|
    puts manifest['digest']
    digest = manifest['digest']
    raw_signature = get_signature(imagename, digest)
    x = GPGME::Data.from_str(raw_signature)
    #signature = crypto.decrypt(GPGME::Data.new(raw_signature))
    #signature = crypto.decrypt(raw_signature)
    #signature = ctx.decrypt(File.open("/home/vagrant/code/tmp/rhel7etcd@sha256\=61bd5317a92c3213cfe70e2b629098c51c50728ef48ff984ce929983889ed663"))
    signature = crypto.decrypt(x)
    puts "ZZZZZZZZZZZ #{signature}"
    return #?????
  end
end

puts "XXXXXXXX #{ARGV}"
#repository = JSON.parse(STDIN.read)['katello::repository']
repository = {
  'id' => 7,
  'content_type' => 'docker',
  'organization' => {'id' => 3},
  'product' => {'id' => 1},
  'docker_upstream_name' => 'rhscl/httpd-24-rhel7'
}
puts "XXXXXXXX #{JSON.pretty_generate(repository)}"

sign_repository(repository)
