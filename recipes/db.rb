exec = "#{node['ndb']['scripts_dir']}/mysql-client.sh"

bash 'create_airflow_db' do	
  user "root"	
  code <<-EOH
      set -e	
#      #{exec} -e \"CREATE DATABASE IF NOT EXISTS airflow CHARACTER SET latin1\"	
      #{exec} -e \"CREATE DATABASE IF NOT EXISTS airflow CHARACTER SET UTF8MB3 COLLATE utf8_general_ci\"
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'localhost' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"

      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON airflow.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
    EOH
  not_if "#{exec} -e 'show databases' | grep airflow"	
end

cookbook_file "#{::Dir.home(node['airflow']['user'])}/create_db_idx_proc.sql" do
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
       #{exec} < "#{::Dir.home(node['airflow']['user'])}/create_db_idx_proc.sql"
       EOH
  only_if { ::File.exist?("#{::Dir.home(node['airflow']['user'])}/create_db_idx_proc.sql") }
end
