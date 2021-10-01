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

service_target = "/usr/lib/systemd/system/airflow-kerberos.service"
service_template = "init_system/systemd/airflow-kerberos.service.erb"

template service_target do
  source service_template
  owner "root"
  group "root"
  mode "0644"
  variables({
    :user => node["airflow"]["user"], 
    :group => node["airflow"]["group"],
    :run_path => node["airflow"]["run_path"],
    :bin_path => node["airflow"]["bin_path"],
    :env_path => node["airflow"]["env_path"],
    :base_path => node["airflow"]["base_dir"],
  })
end

service "airflow-kerberos" do
  action [:enable]
end


if node['kagent']['enabled'] == "true"
    kagent_config "airflow-kerberos" do
      service "airflow"
      log_file "#{node["airflow"]["config"]["logging"]["base_log_folder"]}/airflow.log"
      config_file "#{node['airflow']['base_dir']}/airflow.cfg"
      restart_agent false
      action :add
    end
end

