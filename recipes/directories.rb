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

directory node["airflow"]["base_dir"] do
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
  mode "730"
  recursive true
  action :create
end

bash 'Move airflow dags to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{node["airflow"]["dags_link"]}/* #{node['airflow']['data_volume']['dags_dir']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["dags_link"])}
  not_if { File.symlink?(node["airflow"]["dags_link"])}
  not_if { Dir.empty?(node["airflow"]["dags_link"])}
end

bash 'Delete old airflow dags directory' do
  user 'root'
  code <<-EOH
    set -e
    rm -rf #{node["airflow"]["dags_link"]}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["dags_link"])}
  not_if { File.symlink?(node["airflow"]["dags_link"])}
end

link node['airflow']['dags_link'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0130
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
    mv -f #{node["airflow"]["log_link"]}/* #{node['airflow']['data_volume']['log_dir']}
    rm -rf #{node["airflow"]["log_link"]}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node["airflow"]["log_link"])}
  not_if { File.symlink?(node["airflow"]["log_link"])}
end

link node['airflow']['log_link'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0130
  to node['airflow']['data_volume']['log_dir']
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
    mv -f #{node['airflow']['secrets_link']}/* #{node['airflow']['data_volume']['secrets_dir']}
    rm -rf #{node['airflow']['secrets_link']}
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(node['airflow']['secrets_link'])}
  not_if { File.symlink?(node['airflow']['secrets_link'])}
  not_if { Dir.empty?(node['airflow']['secrets_link']) }
end

link node['airflow']['secrets_link'] do
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0130
  to node['airflow']['data_volume']['secrets_dir']
end
