exec = "#{node['ndb']['scripts_dir']}/mysql-client.sh"

# If we move to NDB, this fails. We need to decrease new length of password from 5000 to 2000 chars (at most).
# airflow/airflow/migrations/versions/fe461863935f_increase_length_for_connection_password.py

bash 'create_airflow_db' do	
  user "root"	
  code <<-EOH
      set -e	
      #{exec} -e \"CREATE DATABASE IF NOT EXISTS airflow CHARACTER SET latin1\"	
# This is airflow 2. It fails for airflow-1, because some rows are too large for NDB
#      #{exec} -e \"CREATE DATABASE IF NOT EXISTS airflow CHARACTER SET UTF8MB3 COLLATE utf8_general_ci\"
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'localhost' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"

      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
    EOH
  not_if "#{exec} -e 'show databases' | grep airflow"	
end

# NOTE: the above SQL code performs all the operations of 'airflow upgradedb'.
# 'airflow upgradedb' fails because it creates a column of length 5000 chars with utf8, and exceeds RonDB's max row size.
#
# Run airflow upgradedb - not airflow initdb. See:
# https://medium.com/datareply/airflow-lesser-known-tips-tricks-and-best-practises-cf4d4a90f8f
#
docker_registry = "#{consul_helper.get_service_fqdn("registry")}:#{node['hops']['docker']['registry']['port']}"
bash 'init_airflow_db' do
 user 'root'
 code <<-EOF
   docker run -v #{node['airflow']['base_dir']}/airflow.cfg:/airflow/airflow.cfg \
     --network=host \
     #{docker_registry}/airflow:#{node['airflow']['version']} \
     airflow upgradedb
   EOF
end


airflow_user_home = conda_helpers.get_user_home(node['airflow']['user'])
cookbook_file "#{airflow_user_home}/create_db_idx_proc.sql" do
  source 'create_db_idx_proc.sql'
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0500
end

bash 'create_owners_idx' do
  user "root"
  group "root"
  code <<-EOH
       set -e
       #{exec} < "#{airflow_user_home}/create_db_idx_proc.sql"
       #{exec} -e \"call airflow.create_idx('airflow', 'dag', 'owners', 'owners_idx')\"
  EOH
end

