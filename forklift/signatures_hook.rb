#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'apipie-bindings'
require 'open-uri'
require 'gpgme'
require 'safemode'
require 'erb'

@defaults = {
  url:       'https://devel.example.com/',
  username:  'admin',
  password:  'changeme',
  sigstores: []
}

@options = {
  #yamlfile: 'config/settings.plugins.d/signatures.yaml',
  yamlfile: 'config/signatures.yaml'
}


if File.exists? @options[:yamlfile]
  @yaml = YAML.load_file(@options[:yamlfile])

  if @yaml.has_key?('settings') and @yaml['settings'].is_a?(Hash)
    @yaml['settings'].each do |key,val|
      if not @options.has_key?(key.to_sym)
        @options[key.to_sym] = val
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
      signature = nil
    else
      signature = response.body
    end
  end
  signature
end

def import_repository_signature(repository)
  return unless repository['content_type'] == 'docker'

  api = ApipieBindings::API.new({
    uri: @options[:url],
    username: @options[:username],
    password: @options[:password],
    api_version: '2',
    timeout: @options[:timeout]
  })

  manifests = api.resource(:docker_manifests).call(:index, {
    organization_id: repository['organization']['id'],
    per_page: 99999
  })['results']

  product = api.resource(:products).call(:show, {
    id: repository['product']['id']
  })
  gpgkey = api.resource(:gpg_keys).call(:show, {
    id: product['gpg_key']['id']
  })
  GPGME::Key.import(gpgkey['content'])
  crypto = GPGME::Crypto.new

  imagename = repository['docker_upstream_name']
  manifests.each do |manifest|
    puts manifest['digest']
    digest = manifest['digest']
    raw_signature = get_signature(imagename, digest)
    if raw_signature.nil?
      puts "NO SIGNATURE"
    else
      signature = nil
      sigstore = crypto.verify(raw_signature) do |sig|
        signature = sig
      end
      if signature.nil? || sigstore.nil?
        puts "ERROR"
      else
        sigstore = JSON.parse(sigstore.read)
        puts "SIGNATURE VALID #{signature.valid?}"
      end
      puts sigstore
    end
  end
end

puts @options[:sigstores]

sigstore = @options[:sigstores].detect {|s| s['registry'] == 'https://registry.access.redhat.com'}
require 'pry'; binding.pry ########################################################
box = Safemode::Box.new(sigstore)
erb = ERB.new(sigstore['signature'])
url = box.eval(erb.src, {}, {image: 'imagename', digest: 'sha256:123456'})
puts "url"

if ARGV[0] == 'after_sync'
  if ARGV.length < 2
    repository = {
      'id' => 7,
      'content_type' => 'docker',
      'organization' => {'id' => 3},
      'product' => {'id' => 1},
      'docker_upstream_name' => 'rhscl/httpd-24-rhel7'
    }
  else
    repository = JSON.parse(STDIN.read)['katello::repository']
  end

  import_repository_signature(repository)
else
  # ????
end
