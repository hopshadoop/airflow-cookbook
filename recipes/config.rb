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

hopsworks_port = "8182"
if node.attribute?("hopsworks")
  if node['hopsworks'].attribute?('internal') and node['hopsworks']['internal'].attribute?('port')
    hopsworks_port = node['hopsworks']['internal']['port']
  end
end

node.override['airflow']["config"]["webserver"]["hopsworks_host"] = consul_helper.get_service_fqdn("hopsworks.glassfish")
node.override['airflow']["config"]["webserver"]["hopsworks_port"] = hopsworks_port

template "#{node["airflow"]["base_dir"]}/airflow.cfg" do
  source "airflow.cfg.erb"
  owner node["airflow"]["user"]
  group node["airflow"]["group"]
  mode node["airflow"]["config_file_mode"]
  variables(
    lazy do
      {
        :config => node['airflow']['config']
      }
    end
  )
end

cookbook_file "#{node["airflow"]["base_dir"]}/log_config.py" do
  source 'log_config.py'
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0750
end