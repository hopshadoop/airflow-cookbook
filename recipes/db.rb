exec = "#{node['ndb']['scripts_dir']}/mysql-client.sh"

bash 'create_airflow_db' do	
  user "root"	
  code <<-EOH
      set -e	
      #{exec} -e \"CREATE DATABASE IF NOT EXISTS airflow CHARACTER SET latin1\"	
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'localhost' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
    EOH
  not_if "#{exec} -e 'show databases' | grep airflow"	
end

airflow_user_home = conda_helpers.get_user_home(node['airflow']['user'])

cookbook_file "#{airflow_user_home}/create_db_idx_proc.sql" do
  source 'create_db_idx_proc.sql'
  owner node['airflow']['user']
  group node['airflow']['group']
  mode 0500
  notifies :run, 'bash[import_create_idx_proc]', :immediately
end

bash 'import_create_idx_proc' do
  user "root"
  group "root"
  code <<-EOH
       set -e
       #{exec} < #{airflow_user_home}/create_db_idx_proc.sql
       EOH
  only_if { ::File.exist?("#{airflow_user_home}/create_db_idx_proc.sql") }
end
