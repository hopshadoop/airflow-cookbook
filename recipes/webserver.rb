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

deps = ""
if exists_local("ndb", "mysqld") 
  deps = "mysqld.service"
end  

service_target = "/usr/lib/systemd/system/airflow-webserver.service"
service_template = "init_system/systemd/airflow-webserver.service.erb"

image_name = "#{consul_helper.get_service_fqdn("registry")}:#{node['hops']['docker']['registry']['port']}/airflow:#{node['airflow']['version']}"

template service_target do
  source service_template
  owner "root"
  group "root"
  mode "0644"
  variables({
    :deps => deps,              
    :image_name => image_name,
  })
end

bash 'remove-old-airflow-exporter' do
  user 'root'
  group 'root'
  code <<-EOH
   rm -rf #{node['airflow']["config"]["core"]["plugins_folder"]}/airflow-exporter
  EOH
  only_if { conda_helpers.is_upgrade }
end

service "airflow-webserver" do
  action :enable
  only_if {node['services']['enabled'] == "true"}
end

service "airflow-webserver" do
  action [:start]
end

# Register Airflow with Consul
consul_service "Registering Airflow with Consul" do
  service_definition "consul/airflow-consul.hcl.erb"
  reload_consul false
  action :register
end

if node['kagent']['enabled'] == "true"
    kagent_config "airflow-webserver" do
      service "airflow"
      log_file "#{node["airflow"]["config"]["core"]["base_log_folder"]}/airflow-scheduler.log"
      config_file "#{node['airflow']['base_dir']}/airflow.cfg"
      restart_agent false
      action :add
    end
end

