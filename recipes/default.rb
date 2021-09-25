# coding: utf-8
# Copyright 2015 Sergey Bahchissaraitsev

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "hops_airflow::db"
include_recipe "hops_airflow::packages"

hopsworksGroup = "glassfish"
if node.attribute? "hopsworks"
    if node["hopsworks"].attribute? "group"
       hopsworksGroup = node['hopsworks']['group']
    end
end

# Directory where Hopsworks will store JWT for projects
# Directory structure will be secrets/SECRET_PROJECT_ID/project_user.jwt
# secrets dir is not readable so someone must only guess the SECRET_PROJECT_ID
directory "#{node['airflow']['data_volume']['secrets_dir']}" do
  owner node['airflow']['user']
  group hopsworksGroup
  mode 0130
  action :create
end

bash 'Move airflow secrets to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{node['airflow']['secrets_dir']}/* #{node['airflow']['data_volume']['secrets_dir']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node['airflow']['secrets_dir'])}
  not_if { File.symlink?(node['airflow']['secrets_dir'])}
  not_if { Dir.empty?(node['airflow']['secrets_dir']) }
end

bash 'Delete airflow secrets' do
  user 'root'
  code <<-EOH
    set -e
    rm -rf #{node['airflow']['secrets_dir']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node['airflow']['secrets_dir'])}
  not_if { File.symlink?(node['airflow']['secrets_dir'])}
end

link node['airflow']['secrets_dir'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0130
  to node['airflow']['data_volume']['secrets_dir']
end

include_recipe "hops_airflow::config"
include_recipe "hops_airflow::services"

directory node['airflow']['base_dir'] + "/plugins"  do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode "770"
  action :create
end

template "airflow_services_env" do
  source "init_system/airflow-env.erb"
  path node["airflow"]["env_path"]
  owner node['airflow']['user']
  group "root"
  mode "0644"
  variables({
    :is_upstart => node["airflow"]["is_upstart"],
    :config => node["airflow"]["config"]
  })
end

#
# Run airflow db upgrade - not airflow db init. See:
# https://medium.com/datareply/airflow-lesser-known-tips-tricks-and-best-practises-cf4d4a90f8f
#
bash 'init_airflow_db' do
  user node['airflow']['user']
  retry_delay 20
  retries 1
  code <<-EOF
      set -e
      export AIRFLOW_HOME=#{node['airflow']['base_dir']}
      RES=$(#{node['airflow']['bin_path']}/airflow db check)
      if [ $RES -ne 0 ] ; then
         echo "Problem connecting to the Database by Airflow"
         exit 1
      fi
      #{node['airflow']['bin_path']}/airflow db init
    EOF
end

bash 'upgrade_airflow_db' do
  user node['airflow']['user']
  code <<-EOF
      set -e
      export AIRFLOW_HOME=#{node['airflow']['base_dir']}
      RES=$(#{node['airflow']['bin_path']}/airflow db check)
      if [ $RES -ne 0 ] ; then
         echo "Problem connecting to the Database by Airflow"
         exit 1
      fi
      #{node['airflow']['bin_path']}/airflow db upgrade
    EOF
end

bash 'create_owners_idx' do
  user "root"
  group "root"
  code <<-EOH
       set -e
       #{node['ndb']['scripts_dir']}/mysql-client.sh -e \"call airflow.create_idx('airflow', 'dag', 'owners', 'owners_idx')\"
       EOH
end

include_recipe "hops_airflow::webserver"
include_recipe "hops_airflow::scheduler"

template node['airflow']['base_dir'] + "/create-default-user.sh" do
  source "create-default-user.sh.erb"
  owner node['airflow']['user']
  group node['airflow']['group']
  mode "0774"
end

examples_dir = "#{node['conda']['base_dir']}/envs/airflow/lib/python#{node['airflow']['python_version']}/site-packages/airflow/example_dags"
if not node['airflow']['config']['core']['load_examples']
  bash 'remove_examples' do
    user "root"
    code <<-EOF
      rm -rf "#{examples_dir}/*"
    EOF
    only_if "test -d #{examples_dir}", :user => "root"
  end
end  

# Generate a certificate
instance_id = private_recipe_ips("hops_airflow", "default").sort.find_index(my_private_ip())
service_fqdn = consul_helper.get_service_fqdn("airflow-webserver")

crypto_dir = x509_helper.get_crypto_dir(node['airflow']['user'])
kagent_hopsify "Generate x.509" do
  user node['airflow']['user']
  crypto_directory crypto_dir
#  common_name "#{instance_id}.#{service_fqdn}"
  action :generate_x509
  not_if { node["kagent"]["enabled"] == "false" }
end

# # Register with consul
# if service_discovery_enabled()
#   # Register airflow webserver with Consul
#   consul_service "Registering Airflow Webserver with Consul" do
#     service_definition "airflow-webserver.hcl.erb"
#     action :register
#   end
#   # Register airflow scheduler with Consul
#   consul_service "Registering Airflow Scheduler with Consul" do
#     service_definition "airflow-scheduler.hcl.erb"
#     action :register
#   end
# end


# /srv/hops/airflow/dags is a private directory - each project will have its own
# directory owned by 'glassfish' with a secret key as a name. No read permissions for
# group on this directory, means the 'glassfish' user cannot perform 'ls' on this directory
# to find out other project's secret keys

hopsworksUser = "glassfish"
if node.attribute?("hopsworks")
  if node['hopsworks'].attribute?("user")
    hopsworksUser = node['hopsworks']['user']
  end
end


hops_hdfs_directory "/user/airflow" do
  action :create_as_superuser
  owner hopsworksUser
  group node["airflow"]["group"]
  mode "1775"
end

hops_hdfs_directory "/user/airflow/dags" do
  action :create_as_superuser
  owner hopsworksUser
  group node["airflow"]["group"]
  mode "1370"
end


# directory node['airflow']['data_volume']['dags_dir']
#  do
#   owner node["airflow"]["user"]
#   group node["airflow"]["group"]
#   mode "730"
#   recursive true
#   action :create
# end

link node["airflow"]["config"]["core"]["dags_folder"] do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode "730"
  to node['airflow']['data_volume']['dags_dir']
end

