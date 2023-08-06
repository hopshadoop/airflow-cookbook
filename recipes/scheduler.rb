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

Chef::Recipe.send(:include, Hops::Helpers)

deps = ""
if exists_local("ndb", "mysqld") 
  deps = "mysqld.service"
end  

if node["platform"] == "ubuntu"
  service_target = "/lib/systemd/system/airflow-scheduler.service"
  service_template = "airflow-scheduler.service.erb"
else
  service_target = "/usr/lib/systemd/system/airflow-scheduler.service"
  service_template = "airflow-scheduler.service.erb"
end

namenode_fdqn = consul_helper.get_service_fqdn("rpc.namenode")
apparmor_security_opt=""
apparmor_enabled = is_apparmor_enabled()
if apparmor_enabled
  apparmor_security_opt="--security-opt apparmor:#{node['hops']['docker']['hopsfsmount-apparmor-profile']}"
end

docker_fuse_args = "--device /dev/fuse #{apparmor_security_opt} --security-opt seccomp=#{node['hops']['docker']['hopsfsmount-seccomp-profile']}"

image_name = "#{consul_helper.get_service_fqdn("registry")}:#{node['hops']['docker']['registry']['port']}/airflow:#{node['airflow']['version']}"

template service_target do
  source service_template
  owner "root"
  group "root"
  mode "0644"
  variables({
    :deps => deps,
    :image_name => image_name,
    :docker_fuse_args => docker_fuse_args,
    :namenode_fdqn => namenode_fdqn
  })
end

service "airflow-scheduler" do
  action :enable
  only_if {node['services']['enabled'] == "true"}
end

service "airflow-scheduler" do
  action :start
end

if node['kagent']['enabled'] == "true"
    kagent_config "airflow-scheduler" do
      service "airflow"
      log_file "#{node["airflow"]["config"]["core"]["base_log_folder"]}/airflow-scheduler.log"
      config_file "#{node['airflow']['base_dir']}/airflow.cfg"
      fail_attempts 10
      restart_agent false
      action :add
    end
end

