#!/usr/bin/env ruby
# Emit CloudFormation parameter-overrides JSON array for network SSM paths.
# Usage: tenant-network-ssm-params.rb <tenant-registry.yaml> <tenant-id> <environment>
# Env: SSM_NETWORK_PREFIX — optional root path (default from tenant ssmNetworkPrefix or /accelerator/network)
require "json"
require "yaml"

registry_path = ARGV[0] or abort("usage: tenant-network-ssm-params.rb <registry.yaml> <tenant> <env>")
tenant_id = ARGV[1] or abort("missing tenant")
env_name = ARGV[2] or abort("missing env")

data = YAML.load_file(registry_path)
tenant = data.dig("tenants", tenant_id) or abort("unknown tenant: #{tenant_id}")
env = tenant.dig("environments", env_name) or abort("unknown environment #{env_name} for tenant #{tenant_id}")

raw_prefix = ENV["SSM_NETWORK_PREFIX"].to_s.strip
prefix =
  if !raw_prefix.empty?
    raw_prefix
  elsif tenant["ssmNetworkPrefix"].to_s.strip != ""
    tenant["ssmNetworkPrefix"].to_s.strip
  else
    "/accelerator/network"
  end

vpc = env["networkVpcName"] or abort("tenant-registry: missing networkVpcName for #{tenant_id}/#{env_name}")
pub = env["networkPublicSubnetNames"] or abort("tenant-registry: missing networkPublicSubnetNames")
priv = env["networkPrivateSubnetNames"] or abort("tenant-registry: missing networkPrivateSubnetNames")
abort("tenant-registry: need 2 public subnet names") unless pub.is_a?(Array) && pub.size >= 2
abort("tenant-registry: need 2 private subnet names") unless priv.is_a?(Array) && priv.size >= 2

def subnet_param(prefix, vpc, subnet_name)
  "#{prefix}/vpc/#{vpc}/subnet/#{subnet_name}/id"
end

params = [
  { "ParameterKey" => "VpcIdSsmPath", "ParameterValue" => "#{prefix}/vpc/#{vpc}/id" },
  { "ParameterKey" => "PublicSubnet1SsmPath", "ParameterValue" => subnet_param(prefix, vpc, pub[0]) },
  { "ParameterKey" => "PublicSubnet2SsmPath", "ParameterValue" => subnet_param(prefix, vpc, pub[1]) },
  { "ParameterKey" => "PrivateSubnet1SsmPath", "ParameterValue" => subnet_param(prefix, vpc, priv[0]) },
  { "ParameterKey" => "PrivateSubnet2SsmPath", "ParameterValue" => subnet_param(prefix, vpc, priv[1]) }
]

puts JSON.generate(params)
