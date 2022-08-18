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

include_recipe "hops_airflow::user"
include_recipe "hops_airflow::directories"
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

include_recipe "hops_airflow::webserver"
include_recipe "hops_airflow::scheduler"

# Force reload of glassfish, so that secrets work
kagent_config "glassfish-domain1" do
  action :systemd_reload
end
