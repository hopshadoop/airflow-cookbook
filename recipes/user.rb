group node['airflow']['group'] do
  gid node['airflow']['group_id']
  action :create
  not_if "getent group #{node['airflow']['group']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

user node['airflow']['user'] do
  comment "Airflow user"
  home node["airflow"]["user_home_directory"]
  uid node['airflow']['user_id']
  gid node['airflow']['group']
  system true
  shell "/bin/bash"
  manage_home true
  action :create
  not_if "getent passwd #{node['airflow']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

hopsworksUser = "glassfish"
if node.attribute? "hopsworks" and node["hopsworks"].attribute? "user"
   hopsworksUser = node['hopsworks']['user']
end

group node['airflow']['group'] do
  action :modify
  members [hopsworksUser]  
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end
