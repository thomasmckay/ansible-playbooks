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


def sigstore_url(registry, image, digest)
  sigstore = @options[:sigstores].detect {|s| s['registry'] == registry}
  return unless sigstore

  box = Safemode::Box.new(self)
  erb = ERB.new(sigstore['signature'])
  box.eval(erb.src, {}, {image: image, digest: digest})
end


def get_signature(registry, image, digest)
  signature = nil
  url = sigstore_url(registry, image, digest)
  return unless url

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

  registry = repository['url']
  image = repository['docker_upstream_name']
  manifests.each do |manifest|
    puts manifest['digest']
    digest = manifest['digest']
    raw_signature = get_signature(registry, image, digest)
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
    return
  end
end

if ARGV[0] == 'after_sync'
  if ARGV.length < 2
    repository = {
      'id' => 71,
      'content_type' => 'docker',
      'organization' => {'id' => 3},
      'product' => {'id' => 1},
      'url' => 'https://registry.access.redhat.com',
      'docker_upstream_name' => 'rhscl/python-36-rhel7'
    }
  else
    repository = JSON.parse(STDIN.read)['katello::repository']
  end

  import_repository_signature(repository)
else
  # ????
end
