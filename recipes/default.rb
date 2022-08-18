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

include_recipe "hops_airflow::config"
include_recipe "hops_airflow::image"
include_recipe "hops_airflow::db"
include_recipe "hops_airflow::webserver"
include_recipe "hops_airflow::scheduler"

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
    :config => node["airflow"]["config"]
  })
end

#
# Run airflow upgradedb - not airflow initdb. See:
# https://medium.com/datareply/airflow-lesser-known-tips-tricks-and-best-practises-cf4d4a90f8f
#
bash 'init_airflow_db' do
  user node['airflow']['user']
  retry_delay 20
  retries 1
  code <<-EOF
      set -e
      export AIRFLOW_HOME=#{node['airflow']['base_dir']}
      #{node['airflow']['bin_path']}/airflow upgradedb
    EOF
end

#
# This gives an error that the key length (3072 chars) is too long. Removing. Not needed for correctness.
#
# bash 'create_owners_idx' do
#   user "root"
#   group "root"
#   code <<-EOH
#        set -e
#        #{node['ndb']['scripts_dir']}/mysql-client.sh -e \"call airflow.create_idx('airflow', 'dag', 'owners', 'owners_idx')\"
#        EOH
# end
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

#link node["airflow"]["config"]["core"]["dags_folder"] do
#  owner node["airflow"]["user"]
#  group node["airflow"]["group"]
#  mode "730"
#  to node['airflow']['data_volume']['dags_dir']
#end

#link node["airflow"]["config"]["core"]["dags_folder"] do
#  owner node["airflow"]["user"]
#  group node["airflow"]["group"]
#  mode "770"
#  to node['airflow']['data_volume']['dags_dir']
#end


# Force reload of glassfish, so that secrets work
kagent_config "glassfish-domain1" do
  action :systemd_reload
end
