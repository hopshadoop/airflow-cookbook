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

#python_runtime node["airflow"]["python_runtime"] do
#  version node["airflow"]["python_version"]
#  provider :system
#  pip_version node["airflow"]["pip_version"]
#end

# Obtain the current platform name
platform = node['platform_family'].to_s

if platform == 'rhel' and node['rhel']['epel'].downcase == "true"
  epel_release = { name: 'epel-release', version: ''}
  node.default['airflow']['dependencies'][platform][:default] << epel_release
end

#For maria DB 10
if platform == 'rhel' 
  ## Add maria db repo for new version 
  bash "add_mariadb_repo" do
    user 'root'
    group 'root'
    code <<-EOF
tee -a /etc/yum.repos.d/mariadb.repo << EOM
# MariaDB 10.1 CentOS repository list - created 2020-10-07 14:28 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOM
    EOF
  end
end

# epel for openssl11
if node['platform_family'].eql?("rhel") && node['rhel']['epel'].downcase == "true"
  package "epel-release"
end

# Default dependencies to install
dependencies_to_install = []
node['airflow']['dependencies'][platform][:default].each do |dependency|
  dependencies_to_install << dependency
end

# Install dependencies
dependencies_to_install.each do |value|
  package_to_install = ''
  version_to_install = ''
  value.each do |key, val|
    if key.to_s == 'name'
      package_to_install = val
    else
      version_to_install = val
    end
  end
  package package_to_install do
    action  :install
    version version_to_install
  end
end

## Remove Aiflow environment if it already exists
bash "remove_airflow_env" do
  user 'root'
  group 'root'
  code <<-EOF
    #{node['conda']['base_dir']}/bin/conda env remove -y -q -n airflow
  EOF
  only_if "test -d #{node['conda']['base_dir']}/envs/airflow", :user => node['conda']['user']  
end

## Create Aiflow anaconda environment.
bash "create_airflow_env" do
  umask "022"
  user node['conda']['user']
  group node['conda']['group']
  environment ({'HOME' => "/home/#{node['conda']['user']}"})
  cwd "/home/#{node['conda']['user']}"
  code <<-EOF
    #{node['conda']['base_dir']}/bin/conda create -q -y -n airflow python=#{node['airflow']['python_version']}
  EOF
  not_if "test -d #{node['conda']['base_dir']}/envs/airflow", :user => node['conda']['user']
end

# Install Airflow
bash 'install_airflow' do
  umask "022"
  user node['conda']['user']
  group node['conda']['group']
  environment ({'SLUGIFY_USES_TEXT_UNIDECODE' => 'yes',
                'AIRFLOW_HOME' => node['airflow']['base_dir'],
                'HOME' => "/home/#{node['conda']['user']}"})
  cwd "/home/#{node['conda']['user']}"
  code <<-EOF
      set -e
      #{node['conda']['base_dir']}/envs/airflow/bin/pip install --no-cache-dir apache-airflow==#{node['airflow']['version']} --constraint #{node['airflow']['constraints_url']}
    EOF
end

bash 'install_airflow_exporter' do
  umask "022"
  user node['conda']['user']
  group node['conda']['group']
  environment ({'SLUGIFY_USES_TEXT_UNIDECODE' => 'yes',
                'AIRFLOW_HOME' => node['airflow']['base_dir'],
                'HOME' => "/home/#{node['conda']['user']}"})
  cwd "/home/#{node['conda']['user']}"
  code <<-EOF
      set -e
      #{node['conda']['base_dir']}/envs/airflow/bin/pip install --no-cache-dir airflow-exporter==#{node['airflow']['exporter_version']}
    EOF
end


for operator in node['airflow']['operators'].split(",")
  bash 'install_airflow_' + operator do
    umask "022"
    user node['conda']['user']
    group node['conda']['group']
    environment ({'SLUGIFY_USES_TEXT_UNIDECODE' => 'yes',
                  'AIRFLOW_HOME' => node['airflow']['base_dir']})
    code <<-EOF
      set -e
      #{node['conda']['base_dir']}/envs/airflow/bin/pip install apache-airflow["#{operator}"]==#{node['airflow']['version']} --constraint #{node['airflow']['constraints_url']}
    EOF
  end
end

