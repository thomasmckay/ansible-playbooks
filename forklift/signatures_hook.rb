#!/usr/bin/env ruby

# gem install apipie-bindings
# gem install gpgme

exit 0

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
  sigstores: [
    {
      registry: 'https://registry.access.redhat.com',
      signature: 'https://access.redhat.com/webassets/docker/content/sigstore/<%= image %>@sha256=<%= digest.split(":")[1] %>/signature-1'
    }
  ]
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
  sigstore = @options[:sigstores].detect {|s| s[:registry] == registry}
  return unless sigstore

  box = Safemode::Box.new(self)
  erb = ERB.new(sigstore[:signature])
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

_api = nil
def api
  _api ||= ApipieBindings::API.new({
    uri: @options[:url],
    username: @options[:username],
    password: @options[:password],
    api_version: '2',
    timeout: @options[:timeout]
  })
end

def import_repository_signature(repository)
  return unless repository['content_type'] == 'docker'

  manifests = api.resource(:docker_manifests).call(:index, {
    repository_id: repository['id'],
    per_page: 99999
  })['results']
  return true if manifests.empty?

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

  all_pass = true
  manifests.each do |manifest|
    puts "HOOK: #{manifest['digest']}"
    digest = manifest['digest']
    raw_signature = get_signature(registry, image, digest)
    if raw_signature.nil?
      puts "HOOK: NO SIGNATURE"
      all_pass = false
    else
      signature = nil
      sigstore = crypto.verify(raw_signature) do |sig|
        signature = sig
      end
      if signature.nil? || sigstore.nil?
        puts "HOOK: ERROR"
        all_pass = false
      else
        sigstore = JSON.parse(sigstore.read)
        puts "HOOK: SIGNATURE VALID #{signature.valid?}"
      end
    end
  end

  all_pass
end

puts "HOOK #{ARGV[0]}"
if ARGV[0] == 'after_sync'
  if ARGV.length < 2
    repository = {
      'id' => 52,
      'content_type' => 'docker',
      'organization' => {'id' => 3},
      'product' => {'id' => 1},
      'url' => 'https://registry.access.redhat.com',
      'docker_upstream_name' => 'rhel7/etcd'
    }
  else
    repository = JSON.parse(STDIN.read)['katello::repository']
  end

  result = import_repository_signature(repository)
  exit 1 unless result
elsif ARGV[0] == 'before_promote'
  if ARGV.length < 2
    content_view_version = {
      'id' => 17,
      'repositories' => [{'id' => 53,'name' => 'rhel7/etcd','label' => 'rhel7_etcd','content_type' => 'docker'}],
      'organization' => {'id' => 3}
    }
  else
    content_view_version = JSON.parse(STDIN.read)['katello::contentviewversion']
  end

  all_pass = true
  content_view_version['repositories'].each do |repository|
    next if repository['content_type'] != 'docker'
    repository = api.resource(:repositories).call(:show, {
      id: repository['id']
    })
    result = import_repository_signature(repository)
    all_pass = false unless result
  end
  exit 1 unless all_pass
end

exit 0
