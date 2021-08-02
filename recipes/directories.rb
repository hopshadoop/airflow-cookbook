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

directory node["airflow"]["dir"]  do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode "755"
  recursive true
  action :create
  not_if { File.directory?("#{node["airflow"]["dir"]}") }
end

directory node["airflow"]["config"]["core"]["airflow_home"] do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode node["airflow"]["directories_mode"]
  action :create
end

directory node['data']['dir'] do
  owner 'root'
  group 'root'
  mode '0775'
  action :create
  not_if { ::File.directory?(node['data']['dir']) }
end

directory node['airflow']['data_volume']['root_dir'] do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode "755"
  action :create
end

# /srv/hops/airflow/dags is a private directory - each project will have its own
# directory owned by 'glassfish' with a secret key as a name. No read permissions for
# group on this directory, means the 'glassfish' user cannot perform 'ls' on this directory
# to find out other project's secret keys
directory node['airflow']['data_volume']['dags_dir'] do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode "710"
  recursive true
  action :create
end

bash 'Move airflow dags to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{node["airflow"]["config"]["core"]["dags_folder"]}/* #{node['airflow']['data_volume']['dags_dir']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["config"]["core"]["dags_folder"])}
  not_if { File.symlink?(node["airflow"]["config"]["core"]["dags_folder"])}
  not_if { Dir.empty?(node["airflow"]["config"]["core"]["dags_folder"])}
end

bash 'Delete old airflow dags directory' do
  user 'root'
  code <<-EOH
    set -e
    rm -rf #{node["airflow"]["config"]["core"]["dags_folder"]}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["config"]["core"]["dags_folder"])}
  not_if { File.symlink?(node["airflow"]["config"]["core"]["dags_folder"])}
end

link node["airflow"]["config"]["core"]["dags_folder"] do
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode "710"
  to node['airflow']['data_volume']['dags_dir']
end

directory node['airflow']['data_volume']['log_dir'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode '0750'
end

bash 'Move airflow logs to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{node["airflow"]["config"]["core"]["base_log_folder"]}/* #{node['airflow']['data_volume']['log_dir']}
    rm -rf #{node["airflow"]["config"]["core"]["base_log_folder"]}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["config"]["core"]["base_log_folder"])}
  not_if { File.symlink?(node["airflow"]["config"]["core"]["base_log_folder"])}
end

link node['airflow']["config"]["core"]["base_log_folder"] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode '0750'
  to node['airflow']['data_volume']['log_dir']
end

directory node['airflow']['config']['core']['plugins_folder'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode node['airflow']['directories_mode']
  action :create
end

directory node['airflow']['run_path'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode node['airflow']['directories_mode']
  action :create
end

# Directory where Hopsworks will store JWT for projects
# Directory structure will be secrets/SECRET_PROJECT_ID/project_user.jwt
# secrets dir is not readable so someone must only guess the SECRET_PROJECT_ID
directory "#{node['airflow']['data_volume']['secrets_dir']}" do
  owner node['airflow']['user']
  group node['airflow']['group']
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